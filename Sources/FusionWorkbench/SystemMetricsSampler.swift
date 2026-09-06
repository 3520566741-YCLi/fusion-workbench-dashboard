import Foundation
import Darwin

struct SystemMetricsSampler {
    private var previousCPUTicks: [UInt32]?

    mutating func sample() -> SystemMetrics {
        let cpuPercent = currentCPUPercent()
        let memory = currentMemory()
        let disk = currentDisk()

        return SystemMetrics(
            cpuPercent: cpuPercent,
            cpuPerformanceCores: systemInteger("hw.perflevel0.physicalcpu"),
            cpuEfficiencyCores: systemInteger("hw.perflevel1.physicalcpu"),
            memoryUsedBytes: memory.used,
            memoryTotalBytes: ProcessInfo.processInfo.physicalMemory,
            gpu: currentGPU(),
            diskAvailableBytes: disk.available,
            diskTotalBytes: disk.total,
            thermalState: ProcessInfo.processInfo.thermalState,
            sampledAt: .now
        )
    }

    private mutating func currentCPUPercent() -> Double? {
        var cpuLoad = host_cpu_load_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<host_cpu_load_info_data_t>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &cpuLoad) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics(mach_host_self(), HOST_CPU_LOAD_INFO, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return nil }

        let ticks = [cpuLoad.cpu_ticks.0, cpuLoad.cpu_ticks.1, cpuLoad.cpu_ticks.2, cpuLoad.cpu_ticks.3]
        defer { previousCPUTicks = ticks }
        guard let previousCPUTicks else { return nil }

        let deltas = zip(ticks, previousCPUTicks).map { Int64($0.0) - Int64($0.1) }
        let total = deltas.reduce(0, +)
        guard total > 0 else { return nil }
        let idle = deltas[2] // CPU_STATE_IDLE; index 3 is CPU_STATE_NICE.
        return max(0, min(1, Double(total - idle) / Double(total)))
    }

    private func currentMemory() -> (used: UInt64, free: UInt64) {
        var stats = vm_statistics64_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64_data_t>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &stats) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }
        let total = ProcessInfo.processInfo.physicalMemory
        guard result == KERN_SUCCESS else { return (0, total) }
        let pageSize = UInt64(getpagesize())
        let free = (UInt64(stats.free_count) + UInt64(stats.inactive_count)) * pageSize
        return (total > free ? total - free : 0, free)
    }

    private func currentDisk() -> (available: Int64, total: Int64) {
        let values = try? URL(fileURLWithPath: "/").resourceValues(forKeys: [
            .volumeAvailableCapacityForImportantUsageKey,
            .volumeTotalCapacityKey
        ])
        return (
            values?.volumeAvailableCapacityForImportantUsage ?? 0,
            Int64(values?.volumeTotalCapacity ?? 0)
        )
    }

    private func systemInteger(_ name: String) -> Int? {
        var value: Int32 = 0
        var size = MemoryLayout<Int32>.size
        guard sysctlbyname(name, &value, &size, nil, 0) == 0 else { return nil }
        return Int(value)
    }

    private func currentGPU() -> GPUMetrics? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/ioreg")
        process.arguments = ["-r", "-c", "AGXAccelerator", "-l"]
        let output = Pipe()
        process.standardOutput = output
        process.standardError = Pipe()

        do {
            try process.run()
            let data = output.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            guard process.terminationStatus == 0,
                  let text = String(data: data, encoding: .utf8) else { return nil }

            let device = percent("Device Utilization %", in: text)
            let renderer = percent("Renderer Utilization %", in: text)
            let tiler = percent("Tiler Utilization %", in: text)
            let cores = integer("gpu-core-count", in: text)
            let allocated = integer("Alloc system memory", in: text).map(Int64.init)
            let used = integer("In use system memory", in: text).map(Int64.init)

            guard device != nil || renderer != nil || tiler != nil || cores != nil else { return nil }
            return GPUMetrics(
                coreCount: cores,
                deviceUtilization: device,
                rendererUtilization: renderer,
                tilerUtilization: tiler,
                allocatedMemoryBytes: allocated,
                usedMemoryBytes: used
            )
        } catch {
            return nil
        }
    }

    private func percent(_ key: String, in text: String) -> Double? {
        integer(key, in: text).map { Double($0) / 100 }
    }

    private func integer(_ key: String, in text: String) -> Int? {
        let pattern = "\\\"" + NSRegularExpression.escapedPattern(for: key) + "\\\"\\s*=\\s*(\\d+)"
        guard let expression = try? NSRegularExpression(pattern: pattern),
              let match = expression.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let range = Range(match.range(at: 1), in: text) else { return nil }
        return Int(text[range])
    }
}
