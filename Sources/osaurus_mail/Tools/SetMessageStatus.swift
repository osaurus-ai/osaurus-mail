import Foundation

// MARK: - Set Message Status Tool

struct SetMessageStatusTool {
  let name = "set_message_status"

  struct Args: Decodable {
    let message_id: String
    let is_read: Bool?
    let is_flagged: Bool?
    let is_junk: Bool?
  }

  func run(args: String, cache: MessageCache) -> String {
    guard let data = args.data(using: .utf8),
      let input = try? JSONDecoder().decode(Args.self, from: data)
    else {
      return MailPluginError.invalidParameter.json(
        message: "Invalid arguments for set_message_status.")
    }

    let messageID = input.message_id
    let resolveScript = buildResolveScript(messageID: messageID, cache: cache)

    // Build set commands for only the provided fields
    var setLines = ""
    if let isRead = input.is_read {
      setLines += "set read status of m to \(isRead)\n"
    }
    if let isFlagged = input.is_flagged {
      setLines += "set flagged status of m to \(isFlagged)\n"
    }
    if let isJunk = input.is_junk {
      setLines += "set junk mail status of m to \(isJunk)\n"
    }

    let script = """
      tell application "Mail"
          \(resolveScript)
          \(setLines)
          set rs to read status of m
          set fs to flagged status of m
          set js to junk mail status of m
          set mid to message id of m
          return mid & "\\t" & rs & "\\t" & fs & "\\t" & js
      end tell
      """

    switch runAppleScript(script) {
    case .success(let output):
      let parts = output.split(separator: "\t", omittingEmptySubsequences: false).map(String.init)
      guard parts.count >= 4 else {
        return MailPluginError.messageNotFound.json(message: "Failed to update message status.")
      }

      return jsonEncode([
        "message_id": parts[0],
        "is_read": parts[1] == "true",
        "is_flagged": parts[2] == "true",
        "is_junk": parts[3] == "true",
      ])

    case .error(let code, let message):
      return code.json(message: message)
    }
  }
}
