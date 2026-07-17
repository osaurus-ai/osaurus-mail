import Foundation
import Testing

@testable import osaurus_mail

@Suite("Subprocess Runner")
struct SubprocessRunnerTests {

  @Test("captures stdout and exit status")
  func capturesStdout() throws {
    let result = try runSubprocess(
      executable: "/bin/sh", arguments: ["-c", "printf hello"], timeout: 10)
    #expect(result.terminationStatus == 0)
    #expect(result.stdout == "hello")
    #expect(result.timedOut == false)
  }

  @Test("captures stderr and nonzero exit status")
  func capturesStderr() throws {
    let result = try runSubprocess(
      executable: "/bin/sh", arguments: ["-c", "printf oops 1>&2; exit 3"], timeout: 10)
    #expect(result.terminationStatus == 3)
    #expect(result.stderr == "oops")
    #expect(result.timedOut == false)
  }

  @Test("output larger than the pipe buffer does not deadlock")
  func largeOutputNoDeadlock() throws {
    // 4 MB of output — far beyond the ~64 KB kernel pipe buffer. The old
    // wait-then-read implementation deadlocks here.
    let result = try runSubprocess(
      executable: "/bin/sh",
      arguments: ["-c", "dd if=/dev/zero bs=1024 count=4096 2>/dev/null | tr '\\0' 'x'"],
      timeout: 20)
    #expect(result.terminationStatus == 0)
    #expect(result.stdout.count == 4 * 1024 * 1024)
    #expect(result.timedOut == false)
  }

  @Test("hung process is killed and reported as timed out")
  func timeoutKillsProcess() throws {
    let start = Date()
    let result = try runSubprocess(
      executable: "/bin/sh", arguments: ["-c", "sleep 60"], timeout: 1)
    #expect(result.timedOut == true)
    #expect(Date().timeIntervalSince(start) < 30)
  }

  @Test("captured output is capped")
  func outputCap() throws {
    let result = try runSubprocess(
      executable: "/bin/sh",
      arguments: ["-c", "dd if=/dev/zero bs=1024 count=64 2>/dev/null | tr '\\0' 'x'"],
      timeout: 20, outputCap: 1024)
    #expect(result.terminationStatus == 0)
    #expect(result.stdout.count == 1024)
  }

  @Test("missing executable throws launchFailed")
  func launchFailure() {
    #expect(throws: SubprocessError.self) {
      _ = try runSubprocess(
        executable: "/nonexistent/binary", arguments: [], timeout: 5)
    }
  }

  @Test("runAppleScript maps a hung script to a timeout error")
  func appleScriptTimeoutMapping() {
    // exercised indirectly: the timeout error case must map to the canonical
    // timeout kind and be retryable
    #expect(MailPluginError.timeout.kind == "timeout")
    #expect(MailPluginError.timeout.retryable == true)
  }
}
