import Foundation

// MARK: - Plugin Error Codes

/// All error codes returned by the mail plugin, matching the spec.
enum MailPluginError: String {
  case mailNotRunning = "mail_not_running"
  case permissionDenied = "permission_denied"
  case mailboxNotFound = "mailbox_not_found"
  case messageNotFound = "message_not_found"
  case invalidDestination = "invalid_destination"
  case sendFailed = "send_failed"
  case missingBody = "missing_body"
  case invalidParameter = "invalid_parameter"

  /// The canonical Osaurus host error kind for this code.
  ///
  /// The host only classifies a tool result as a failure when the result is the
  /// canonical envelope (`ok`/`kind`/`retryable`) or the legacy `{error, retryable}`
  /// shape. Mapping each code to a valid kind ensures errors are not silently
  /// auto-wrapped as successes.
  var kind: String {
    switch self {
    case .mailNotRunning, .permissionDenied:
      return "unavailable"
    case .mailboxNotFound, .messageNotFound:
      return "not_found"
    case .invalidDestination, .missingBody, .invalidParameter:
      return "invalid_args"
    case .sendFailed:
      return "execution_error"
    }
  }

  /// Whether the host should treat this error as retryable.
  var retryable: Bool {
    switch self {
    case .mailNotRunning, .permissionDenied, .mailboxNotFound, .messageNotFound:
      return false
    case .invalidDestination, .missingBody, .invalidParameter, .sendFailed:
      return true
    }
  }

  /// Build a canonical Osaurus error envelope the host recognizes as a failure.
  ///
  /// Shape: `{"ok":false,"kind":"<kind>","message":"<msg>","retryable":<bool>,"code":"<rawValue>"}`
  /// The original code string is preserved under `code` for backward debugging.
  func json(message: String) -> String {
    canonicalErrorEnvelope(
      kind: self.kind, message: message, retryable: self.retryable, code: self.rawValue)
  }
}

/// Build a canonical Osaurus error envelope the host recognizes as a failure.
///
/// Shape: `{"ok":false,"kind":"<kind>","message":"<msg>","retryable":<bool>[,"code":"<code>"]}`.
/// Use this for failure paths that don't map to a `MailPluginError` case (e.g. the
/// plugin entry point's unknown-capability / unknown-tool fallbacks) so they emit the
/// same shape and are not silently auto-wrapped as a success by the host.
func canonicalErrorEnvelope(
  kind: String, message: String, retryable: Bool, code: String? = nil
) -> String {
  let escapedMessage = jsonEscapeString(message)
  var json = "{\"ok\":false,\"kind\":\"\(kind)\",\"message\":\"\(escapedMessage)\",\"retryable\":\(retryable)"
  if let code = code {
    json += ",\"code\":\"\(jsonEscapeString(code))\""
  }
  json += "}"
  return json
}

// MARK: - JSON Helpers

/// Escape a string for safe embedding in a JSON string value.
func jsonEscapeString(_ s: String) -> String {
  var result = ""
  result.reserveCapacity(s.count)
  for ch in s {
    switch ch {
    case "\"": result += "\\\""
    case "\\": result += "\\\\"
    case "\n": result += "\\n"
    case "\r": result += "\\r"
    case "\t": result += "\\t"
    default:
      if let ascii = ch.asciiValue, ascii < 0x20 {
        result += String(format: "\\u%04x", ascii)
      } else {
        result.append(ch)
      }
    }
  }
  return result
}

/// Encode a value as a JSON string using JSONSerialization.
func jsonEncode(_ value: Any) -> String {
  guard let data = try? JSONSerialization.data(withJSONObject: value, options: []),
    let str = String(data: data, encoding: .utf8)
  else {
    return "{\"error\":\"json_encoding_failed\",\"message\":\"Failed to encode response\"}"
  }
  return str
}
