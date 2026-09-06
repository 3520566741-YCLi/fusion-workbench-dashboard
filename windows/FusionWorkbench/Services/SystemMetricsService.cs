using System.IO;
using System.Runtime.InteropServices;
using System.Runtime.Versioning;
using FusionWorkbench.Models;

namespace FusionWorkbench.Services;

/// <summary>One Windows system-metrics sample, mirroring the macOS SystemMetrics type.</summary>
public sealed class SystemMetricsSnapshot : ModuleSnapshot
{
    public SystemMetricsSnapshot(
        DateTime sampledAt,
        double? cpuPercent,
        ulong memoryTotalBytes,
        ulong memoryUsedBytes,
        ulong diskTotalBytes,
        ulong diskFreeBytes,
        int processorCount,
        string osDescription,
        string? reasonKey = null,
        string? reasonDetail = null)
        : base(sampledAt, isAvailable: cpuPercent.HasValue || memoryTotalBytes > 0 || diskTotalBytes > 0, reasonKey, reasonDetail)
    {
        CpuPercent = cpuPercent;
        MemoryTotalBytes = memoryTotalBytes;
        MemoryUsedBytes = memoryUsedBytes;
        DiskTotalBytes = diskTotalBytes;
        DiskFreeBytes = diskFreeBytes;
        ProcessorCount = processorCount;
        OsDescription = osDescription;
    }

    /// <summary>Overall CPU usage in 0..1; null until a second sample exists (30 s cadence).</summary>
    public double? CpuPercent { get; }

    public ulong MemoryTotalBytes { get; }

    public ulong MemoryUsedBytes { get; }

    /// <summary>Used memory as a 0..1 fraction; null when total memory is unknown.</summary>
    public double? MemoryFraction =>
        MemoryTotalBytes > 0 ? Math.Min(1.0, (double)MemoryUsedBytes / MemoryTotalBytes) : null;

    public ulong DiskTotalBytes { get; }

    public ulong DiskFreeBytes { get; }

    public double? DiskFraction =>
        DiskTotalBytes > 0 ? Math.Min(1.0, 1.0 - (double)DiskFreeBytes / DiskTotalBytes) : null;

    public int ProcessorCount { get; }

    public string OsDescription { get; }
}

/// <summary>
/// Windows implementation of the macOS SystemMetricsSampler:
///   - CPU: kernel32 GetSystemTimes, idle/kernel/user deltas between samples (same idea as the
///     macOS host_statistics delta approach). The first sample only records a baseline and
///     returns null for CPU.
///   - RAM: kernel32 GlobalMemoryStatusEx (dwMemoryLoad + ullTotalPhys/ullAvailPhys).
///   - Disk: DriveInfo over fixed drives (Windows equivalent of the macOS "/" volume query).
/// Each native call is wrapped so a failed subsystem only nulls that metric; only when nothing
/// at all could be read does the service report Unavailable.
/// </summary>
[SupportedOSPlatform("windows")]
public sealed class SystemMetricsService
{
    private readonly object _baselineLock = new();
    private ulong? _previousIdleTicks;
    private ulong? _previousKernelTicks;
    private ulong? _previousUserTicks;

    public SystemMetricsSnapshot Sample()
    {
        DateTime sampledAt = DateTime.Now;

        ulong memoryTotal = 0;
        ulong memoryUsed = 0;
        bool memoryRead = false;

        try
        {
            var status = new MemoryStatusEx { dwLength = (uint)Marshal.SizeOf<MemoryStatusEx>() };
            if (GlobalMemoryStatusEx(ref status))
            {
                memoryTotal = status.ullTotalPhys;
                memoryUsed = status.ullTotalPhys > status.ullAvailPhys ? status.ullTotalPhys - status.ullAvailPhys : 0;
                memoryRead = status.ullTotalPhys > 0;
            }
        }
        catch (Exception)
        {
            // P/Invoke failure: leave memory metrics null.
        }

        double? cpuPercent = ReadCpuPercent();

        ulong diskTotal = 0;
        ulong diskFree = 0;
        try
        {
            foreach (DriveInfo drive in DriveInfo.GetDrives())
            {
                if (drive.DriveType == DriveType.Fixed && drive.IsReady && drive.TotalSize > 0)
                {
                    checked
                    {
                        diskTotal += (ulong)drive.TotalSize;
                        diskFree += (ulong)drive.AvailableFreeSpace;
                    }
                }
            }
        }
        catch (Exception)
        {
            // Unreadable drive list: disk metric stays at zero.
        }

        if (!memoryRead && !cpuPercent.HasValue && diskTotal == 0)
        {
            return new SystemMetricsSnapshot(
                sampledAt,
                cpuPercent: null,
                memoryTotalBytes: 0,
                memoryUsedBytes: 0,
                diskTotalBytes: 0,
                diskFreeBytes: 0,
                processorCount: Environment.ProcessorCount,
                osDescription: DescribeOs(),
                reasonKey: "Msg_SystemUnavailable");
        }

        return new SystemMetricsSnapshot(
            sampledAt,
            cpuPercent,
            memoryTotal,
            memoryUsed,
            diskTotal,
            diskFree,
            Environment.ProcessorCount,
            DescribeOs());
    }

    private double? ReadCpuPercent()
    {
        try
        {
            if (!GetSystemTimes(out FileTime idleTime, out FileTime kernelTime, out FileTime userTime))
            {
                return null;
            }

            ulong idleTicks = idleTime.ToUInt64();
            ulong kernelTicks = kernelTime.ToUInt64();
            ulong userTicks = userTime.ToUInt64();

            lock (_baselineLock)
            {
                if (!_previousIdleTicks.HasValue || !_previousKernelTicks.HasValue || !_previousUserTicks.HasValue)
                {
                    // First sample: only establish the baseline (mirrors macOS returning nil once).
                    _previousIdleTicks = idleTicks;
                    _previousKernelTicks = kernelTicks;
                    _previousUserTicks = userTicks;
                    return null;
                }

                // kernelTicks already includes idle time, so "busy" == kernel + user - idle.
                ulong idleDelta = idleTicks - Math.Min(idleTicks, _previousIdleTicks.Value);
                ulong busyDelta = (kernelTicks + userTicks) - Math.Min(kernelTicks + userTicks, _previousKernelTicks.Value + _previousUserTicks.Value);
                ulong totalDelta = idleDelta + busyDelta;

                _previousIdleTicks = idleTicks;
                _previousKernelTicks = kernelTicks;
                _previousUserTicks = userTicks;

                if (totalDelta == 0)
                {
                    return null;
                }

                return Math.Clamp((double)busyDelta / totalDelta, 0.0, 1.0);
            }
        }
        catch (Exception)
        {
            return null;
        }
    }

    private static string DescribeOs()
    {
        try
        {
            string description = System.Runtime.InteropServices.RuntimeInformation.OSDescription.Trim();
            return string.IsNullOrEmpty(description) ? "Windows" : description;
        }
        catch (Exception)
        {
            return "Windows";
        }
    }

    // ---- Native interop (kernel32) ---------------------------------------------------------

    [StructLayout(LayoutKind.Sequential)]
    private struct FileTime
    {
        public uint LowDateTime;
        public uint HighDateTime;

        public ulong ToUInt64() => ((ulong)HighDateTime << 32) | LowDateTime;
    }

    [DllImport("kernel32.dll", SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool GetSystemTimes(
        out FileTime lpIdleTime,
        out FileTime lpKernelTime,
        out FileTime lpUserTime);

    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Auto)]
    private struct MemoryStatusEx
    {
        public uint dwLength;
        public uint dwMemoryLoad;
        public ulong ullTotalPhys;
        public ulong ullAvailPhys;
        public ulong ullTotalPageFile;
        public ulong ullAvailPageFile;
        public ulong ullTotalVirtual;
        public ulong ullAvailVirtual;
        public ulong ullAvailExtendedVirtual;
    }

    [DllImport("kernel32.dll", CharSet = CharSet.Auto, SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool GlobalMemoryStatusEx(ref MemoryStatusEx lpBuffer);
}
