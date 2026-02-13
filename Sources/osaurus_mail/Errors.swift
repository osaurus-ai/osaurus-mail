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

  /// Build a JSON error response with the error code and a human-readable message.
  func json(message: String) -> String {
    let escaped = jsonEscapeString(message)
    return "{\"error\":\"\(self.rawValue)\",\"message\":\"\(escaped)\"}"
  }
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
