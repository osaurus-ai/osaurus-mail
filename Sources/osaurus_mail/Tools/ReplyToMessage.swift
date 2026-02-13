import Foundation

// MARK: - Reply To Message Tool

struct ReplyToMessageTool {
  let name = "reply_to_message"

  struct Args: Decodable {
    let message_id: String
    let body: String?
    let html_body: String?
    let reply_all: Bool?
    let send: Bool?
  }

  func run(args: String, cache: MessageCache) -> String {
    guard let data = args.data(using: .utf8),
      let input = try? JSONDecoder().decode(Args.self, from: data)
    else {
      return MailPluginError.invalidParameter.json(
        message: "Invalid arguments for reply_to_message.")
    }

    // Validate that at least one body is provided
    if input.body == nil && input.html_body == nil {
      return MailPluginError.missingBody.json(message: "Either body or html_body must be provided.")
    }

    let messageID = input.message_id
    let shouldSend = input.send ?? false
    let replyAll = input.reply_all ?? false
    let resolveScript = buildResolveScript(messageID: messageID, cache: cache)

    let bodyLine: String
    if let htmlBody = input.html_body {
      let escaped = escapeAppleScriptString(htmlBody)
      bodyLine = "set html content of replyMsg to \"\(escaped)\""
    } else if let body = input.body {
      let escaped = escapeAppleScriptString(body)
      bodyLine = "set content of replyMsg to \"\(escaped)\""
    } else {
      bodyLine = ""
    }

    let replyCommand = replyAll ? "reply m with reply to all" : "reply m"
    let sendOrShow = shouldSend ? "send replyMsg" : "set visible of replyMsg to true"

    let script = """
      tell application "Mail"
          \(resolveScript)
          set replyMsg to \(replyCommand)
          \(bodyLine)
          \(sendOrShow)
      end tell
      """

    switch runAppleScript(script) {
    case .success:
      if shouldSend {
        return jsonEncode([
          "status": "sent",
          "message": "Reply sent.",
        ])
      } else {
        return jsonEncode([
          "status": "drafted",
          "message": "Reply draft opened in Mail compose window for user review.",
        ])
      }

    case .error(let code, let message):
      if shouldSend {
        return MailPluginError.sendFailed.json(message: "Failed to send reply: \(message)")
      }
      return code.json(message: message)
    }
  }
}
