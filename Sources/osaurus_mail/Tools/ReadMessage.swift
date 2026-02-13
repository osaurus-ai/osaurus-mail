import Foundation

// MARK: - Read Message Tool

struct ReadMessageTool {
  let name = "read_message"

  struct Args: Decodable {
    let message_id: String
    let max_length: Int?
    let include_headers: Bool?
  }

  func run(args: String, cache: MessageCache) -> String {
    guard let data = args.data(using: .utf8),
      let input = try? JSONDecoder().decode(Args.self, from: data)
    else {
      return MailPluginError.invalidParameter.json(message: "Invalid arguments for read_message.")
    }

    let maxLength = input.max_length ?? 10000
    let includeHeaders = input.include_headers ?? false
    let messageID = input.message_id
    let resolveScript = buildResolveScript(messageID: messageID, cache: cache)

    let headersLine =
      includeHeaders
      ? "set hdrs to all headers of m"
      : "set hdrs to \"\""

    let script = """
      tell application "Mail"
          \(resolveScript)
          set subj to subject of m
          set sndr to sender of m
          set dr to date received of m
          set rs to read status of m
          set fs to flagged status of m
          set bodyContent to content of m
          \(headersLine)
          set mid to message id of m
          set iid to id of m
          -- Recipients
          set toList to ""
          repeat with r in (every to recipient of m)
              if toList is not "" then set toList to toList & "|||"
              set toList to toList & (address of r as text)
          end repeat
          set ccList to ""
          repeat with r in (every cc recipient of m)
              if ccList is not "" then set ccList to ccList & "|||"
              set ccList to ccList & (address of r as text)
          end repeat
          -- Attachments
          set attList to ""
          repeat with att in (every mail attachment of m)
              if attList is not "" then set attList to attList & "|||"
              set attName to name of att
              try
                  set attBytes to file size of att
              on error
                  set attBytes to 0
              end try
              set attList to attList & attName & ":::" & attBytes
          end repeat
          -- Mailbox path
          set mbox to mailbox of m
          set mboxName to name of mbox
          set acctName to name of account of mbox
          set mboxPath to acctName & "/" & mboxName
          return mid & "\\t" & subj & "\\t" & sndr & "\\t" & (dr as «class isot» as string) & "\\t" & rs & "\\t" & fs & "\\t" & bodyContent & "\\t" & hdrs & "\\t" & toList & "\\t" & ccList & "\\t" & attList & "\\t" & mboxPath & "\\t" & iid
      end tell
      """

    switch runAppleScript(script) {
    case .success(let output):
      let parts = output.split(separator: "\t", maxSplits: 12, omittingEmptySubsequences: false)
        .map(String.init)
      guard parts.count >= 13 else {
        return MailPluginError.messageNotFound.json(
          message: "Message '\(messageID)' not found. It may have been deleted or moved.")
      }

      let msgID = parts[0]
      let internalID = Int(parts[12]) ?? 0
      cache.set(msgID, internalID: internalID)

      // Truncate body
      var body = parts[6]
      var bodyTruncated = false
      if body.count > maxLength {
        body = String(body.prefix(maxLength))
        bodyTruncated = true
      }

      let toList = parts[8].isEmpty ? [String]() : parts[8].split(separator: "|||").map(String.init)
      let ccList = parts[9].isEmpty ? [String]() : parts[9].split(separator: "|||").map(String.init)

      // Parse attachments
      var attachments: [[String: Any]] = []
      if !parts[10].isEmpty {
        for att in parts[10].split(separator: "|||").map(String.init) {
          let info = att.split(separator: ":::", maxSplits: 1).map(String.init)
          attachments.append([
            "name": info[0],
            "size_bytes": info.count >= 2 ? (Int(info[1]) ?? 0) : 0,
          ])
        }
      }

      var response: [String: Any] = [
        "message_id": msgID,
        "subject": parts[1],
        "from": parts[2],
        "to": toList,
        "cc": ccList,
        "date": formatISO8601(parts[3]),
        "body": body,
        "body_truncated": bodyTruncated,
        "is_read": parts[4] == "true",
        "is_flagged": parts[5] == "true",
        "attachments": attachments,
        "mailbox_path": parts[11],
      ]

      if includeHeaders && !parts[7].isEmpty {
        response["headers"] = parts[7]
      }

      return jsonEncode(response)

    case .error(let code, let message):
      return code.json(message: message)
    }
  }
}
