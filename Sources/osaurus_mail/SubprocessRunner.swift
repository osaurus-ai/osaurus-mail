import Foundation

// MARK: - Shared Subprocess Runner

/// Result of running a subprocess to completion.
struct SubprocessResult {
  let terminationStatus: Int32
  let stdout: String
  let stderr: String
  let timedOut: Bool
}

enum SubprocessError: Error {
  case launchFailed(String)
}

/// Maximum bytes captured per stream before further output is dropped.
let subprocessOutputCapBytes = 5 * 1024 * 1024

/// Thread-safe accumulator for pipe output, capped at a byte limit.
private final class PipeBuffer: @unchecked Sendable {
  private let lock = NSLock()
  private var data = Data()
  private var truncated = false

  func append(_ chunk: Data, cap: Int) {
    lock.lock()
    defer { lock.unlock() }
    guard !truncated else { return }
    let remaining = cap - data.count
    if chunk.count <= remaining {
      data.append(chunk)
    } else {
      data.append(chunk.prefix(max(remaining, 0)))
      truncated = true
    }
  }

  var string: String {
    lock.lock()
    defer { lock.unlock() }
    return String(data: data, encoding: .utf8) ?? ""
  }
}

private final class AtomicFlag: @unchecked Sendable {
  private let lock = NSLock()
  private var value = false
  func set() {
    lock.lock()
    value = true
    lock.unlock()
  }
  var isSet: Bool {
    lock.lock()
    defer { lock.unlock() }
    return value
  }
}

/// Run a subprocess to completion.
///
/// - Drains stdout/stderr concurrently while the process runs, so output larger
///   than the pipe buffer cannot deadlock `waitUntilExit`.
/// - Kills the process (SIGTERM, then SIGKILL after a grace period) if it does
///   not finish within `timeout`; the result reports `timedOut == true`.
/// - Caps captured output at `outputCap` bytes per stream.
func runSubprocess(
  executable: String, arguments: [String],
  timeout: TimeInterval, outputCap: Int = subprocessOutputCapBytes
) throws -> SubprocessResult {
  let process = Process()
  process.executableURL = URL(fileURLWithPath: executable)
  process.arguments = arguments

  let stdoutPipe = Pipe()
  let stderrPipe = Pipe()
  process.standardOutput = stdoutPipe
  process.standardError = stderrPipe

  let stdoutBuf = PipeBuffer()
  let stderrBuf = PipeBuffer()
  let drainGroup = DispatchGroup()

  drainGroup.enter()
  stdoutPipe.fileHandleForReading.readabilityHandler = { handle in
    let chunk = handle.availableData
    if chunk.isEmpty {
      handle.readabilityHandler = nil
      drainGroup.leave()
    } else {
      stdoutBuf.append(chunk, cap: outputCap)
    }
  }
  drainGroup.enter()
  stderrPipe.fileHandleForReading.readabilityHandler = { handle in
    let chunk = handle.availableData
    if chunk.isEmpty {
      handle.readabilityHandler = nil
      drainGroup.leave()
    } else {
      stderrBuf.append(chunk, cap: outputCap)
    }
  }

  do {
    try process.run()
  } catch {
    stdoutPipe.fileHandleForReading.readabilityHandler = nil
    stderrPipe.fileHandleForReading.readabilityHandler = nil
    throw SubprocessError.launchFailed(error.localizedDescription)
  }

  let timedOut = AtomicFlag()
  let killItem = DispatchWorkItem {
    guard process.isRunning else { return }
    timedOut.set()
    let pid = process.processIdentifier
    process.terminate()
    DispatchQueue.global().asyncAfter(deadline: .now() + 2) {
      kill(pid, SIGKILL)
    }
  }
  DispatchQueue.global().asyncAfter(deadline: .now() + timeout, execute: killItem)

  process.waitUntilExit()
  killItem.cancel()
  _ = drainGroup.wait(timeout: .now() + 5)

  return SubprocessResult(
    terminationStatus: process.terminationStatus,
    stdout: stdoutBuf.string,
    stderr: stderrBuf.string,
    timedOut: timedOut.isSet)
}
