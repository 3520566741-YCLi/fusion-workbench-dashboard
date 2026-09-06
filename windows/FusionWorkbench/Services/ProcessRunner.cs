using System.ComponentModel;
using System.Diagnostics;
using System.Text;

namespace FusionWorkbench.Services;

/// <summary>
/// Minimal, dependency-free helper that runs an external executable and captures its output.
/// Used to shell out to the GitHub CLI (gh), exactly like the macOS sampler does with Process.
/// </summary>
public static class ProcessRunner
{
    /// <summary>
    /// Runs <paramref name="fileName"/> with <paramref name="arguments"/> and returns its exit
    /// code plus captured stdout/stderr. Never throws for a non-zero exit code; throws
    /// <see cref="Win32Exception"/> (error 2) when the executable does not exist.
    /// </summary>
    public static async Task<(int ExitCode, string StdOut, string StdErr)> RunAsync(
        string fileName,
        IReadOnlyList<string> arguments,
        TimeSpan timeout,
        CancellationToken cancellationToken)
    {
        var psi = new ProcessStartInfo
        {
            FileName = fileName,
            UseShellExecute = false,
            RedirectStandardOutput = true,
            RedirectStandardError = true,
            CreateNoWindow = true,
            StandardOutputEncoding = Encoding.UTF8,
            StandardErrorEncoding = Encoding.UTF8,
        };

        foreach (string argument in arguments)
        {
            psi.ArgumentList.Add(argument);
        }

        using var process = Process.Start(psi) ?? throw new InvalidOperationException($"Could not start process '{fileName}'.");

        Task<string> stdoutTask = process.StandardOutput.ReadToEndAsync();
        Task<string> stderrTask = process.StandardError.ReadToEndAsync();

        using var timeoutCts = CancellationTokenSource.CreateLinkedTokenSource(cancellationToken);
        timeoutCts.CancelAfter(timeout);

        try
        {
            await process.WaitForExitAsync(timeoutCts.Token).ConfigureAwait(false);
        }
        catch (OperationCanceledException) when (!cancellationToken.IsCancellationRequested)
        {
            // Timed out.
            try
            {
                process.Kill(entireProcessTree: true);
            }
            catch (InvalidOperationException)
            {
                // Process already exited.
            }

            throw new TimeoutException($"Process '{fileName}' did not finish within {timeout.TotalSeconds:0} seconds.");
        }

        string stdout = await stdoutTask.ConfigureAwait(false);
        string stderr = await stderrTask.ConfigureAwait(false);
        return (process.ExitCode, stdout, stderr);
    }
}
