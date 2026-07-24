import Foundation

// MARK: - AppleScript Output Field Coding

/// AppleScript handlers that escape a text field before it is embedded in the
/// tab/linefeed-delimited script output. Escapes backslash, tab, linefeed,
/// carriage return, `|` (item separator `|||`) and `:` (attachment separator
/// `:::`), so real message content can never collide with the delimiters.
///
/// Append these handlers after the `end tell` of any script that calls
/// `my encodeField(...)`, and decode each field on the Swift side with
/// `decodeAppleScriptField(_:)`.
let appleScriptFieldEncoderHandlers = """
  on encodeField(t)
      set t to t as text
      set t to my replaceAll(t, "\\\\", "\\\\\\\\")
      set t to my replaceAll(t, tab, "\\\\t")
      set t to my replaceAll(t, linefeed, "\\\\n")
      set t to my replaceAll(t, return, "\\\\r")
      set t to my replaceAll(t, "|", "\\\\p")
      set t to my replaceAll(t, ":", "\\\\c")
      return t
  end encodeField
  on replaceAll(t, f, r)
      set AppleScript's text item delimiters to f
      set itemList to text items of t
      set AppleScript's text item delimiters to r
      set t to itemList as text
      set AppleScript's text item delimiters to ""
      return t
  end replaceAll
  """

/// Swift mirror of the AppleScript `encodeField` handler. Used by tests to
/// verify that any string round-trips through `decodeAppleScriptField`.
func encodeAppleScriptField(_ s: String) -> String {
  var result = ""
  result.reserveCapacity(s.count)
  for ch in s {
    switch ch {
    case "\\": result += "\\\\"
    case "\t": result += "\\t"
    case "\n": result += "\\n"
    case "\r": result += "\\r"
    case "|": result += "\\p"
    case ":": result += "\\c"
    default: result.append(ch)
    }
  }
  return result
}

/// Reverse the AppleScript `encodeField` escaping applied to a single field.
func decodeAppleScriptField(_ s: String) -> String {
  var result = ""
  result.reserveCapacity(s.count)
  var escaped = false
  for ch in s {
    if escaped {
      switch ch {
      case "t": result.append("\t")
      case "n": result.append("\n")
      case "r": result.append("\r")
      case "p": result.append("|")
      case "c": result.append(":")
      case "\\": result.append("\\")
      default:
        result.append("\\")
        result.append(ch)
      }
      escaped = false
    } else if ch == "\\" {
      escaped = true
    } else {
      result.append(ch)
    }
  }
  if escaped { result.append("\\") }
  return result
}
