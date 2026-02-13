import Foundation

// MARK: - Get Thread Tool

struct GetThreadTool {
  let name = "get_thread"

  struct Args: Decodable {
    let message_id: String
    let include_bodies: Bool?
    let max_body_length: Int?
  }

  func run(args: String, cache: MessageCache) -> String {
    guard let data = args.data(using: .utf8),
      let input = try? JSONDecoder().decode(Args.self, from: data)
    else {
      return MailPluginError.invalidParameter.json(message: "Invalid arguments for get_thread.")
    }

    let messageID = input.message_id
    let includeBodies = input.include_bodies ?? false
    let maxBodyLength = input.max_body_length ?? 5000

    let resolveScript = buildResolveScript(messageID: messageID, cache: cache)

    // Step 1: Get the seed message's subject and account
    let seedScript = """
      tell application "Mail"
          \(resolveScript)
          set subj to subject of m
          set acctName to name of account of mailbox of m
          return subj & "\\t" & acctName
      end tell
      """

    var seedSubject = ""
    var accountName = ""

    switch runAppleScript(seedScript) {
    case .success(let output):
      let parts = output.split(separator: "\t", maxSplits: 1, omittingEmptySubsequences: false).map(
        String.init)
      if parts.count >= 2 {
        seedSubject = parts[0]
        accountName = parts[1]
      } else {
        seedSubject = output.trimmingCharacters(in: .whitespacesAndNewlines)
      }
    case .error(let code, let message):
      return code.json(message: message)
    }

    // Normalize subject: strip Re:/Fwd: prefixes
    let normalizedSubject = normalizeSubject(seedSubject)
    let escapedSubject = escapeAppleScriptString(normalizedSubject)
    let escapedAccount = escapeAppleScriptString(accountName)

    // Step 2: Search for all messages with matching normalized subject in the same account
    let bodyFetchLine =
      includeBodies
      ? "set bodyContent to content of m"
      : "set bodyContent to \"\""

    let searchScript = """
      tell application "Mail"
          set output to ""
          set acct to account "\(escapedAccount)"
          repeat with mbox in every mailbox of acct
              try
                  set msgs to (every message of mbox whose subject contains "\(escapedSubject)")
                  repeat with m in msgs
                      set subj to subject of m
                      -- Verify normalized subject matches
                      set mid to message id of m
                      set sndr to sender of m
                      set dr to date received of m
                      set rs to read status of m
                      set fs to flagged status of m
                      set iid to id of m
                      set hasAtt to (count of mail attachments of m) > 0
                      \(bodyFetchLine)
                      set recipList to ""
                      repeat with r in (every to recipient of m)
                          if recipList is not "" then set recipList to recipList & "|||"
                          set recipList to recipList & (address of r as text)
                      end repeat
                      set output to output & mid & "\\t" & subj & "\\t" & sndr & "\\t" & (dr as «class isot» as string) & "\\t" & rs & "\\t" & fs & "\\t" & hasAtt & "\\t" & iid & "\\t" & recipList & "\\t" & bodyContent & linefeed
                  end repeat
              end try
          end repeat
          return output
      end tell
      """

    switch runAppleScript(searchScript) {
    case .success(let output):
      var threadMessages: [[String: Any]] = []
      var cacheEntries: [(messageID: String, internalID: Int)] = []
      let lines = output.split(separator: "\n", omittingEmptySubsequences: true)

      for line in lines {
        let parts = line.split(separator: "\t", maxSplits: 9, omittingEmptySubsequences: false).map(
          String.init)
        guard parts.count >= 10 else { continue }

        let msgSubject = parts[1]
        // Verify the normalized subject matches
        guard normalizeSubject(msgSubject) == normalizedSubject else { continue }

        let msgID = parts[0]
        let internalID = Int(parts[7]) ?? 0
        let toStr = parts[8]
        let toList = toStr.isEmpty ? [String]() : toStr.split(separator: "|||").map(String.init)

        var msgDict: [String: Any] = [
          "message_id": msgID,
          "subject": msgSubject,
          "from": parts[2],
          "to": toList,
          "date": formatISO8601(parts[3]),
          "is_read": parts[4] == "true",
          "is_flagged": parts[5] == "true",
          "has_attachments": parts[6] == "true",
        ]

        if includeBodies {
          var body = parts[9]
          var bodyTruncated = false
          if body.count > maxBodyLength {
            body = String(body.prefix(maxBodyLength))
            bodyTruncated = true
          }
          msgDict["body"] = body
          msgDict["body_truncated"] = bodyTruncated
        }

        threadMessages.append(msgDict)
        cacheEntries.append((messageID: msgID, internalID: internalID))
      }

      cache.populateFromMessages(cacheEntries)

      // Sort chronologically (oldest first) by date string
      threadMessages.sort { a, b in
        let dateA = a["date"] as? String ?? ""
        let dateB = b["date"] as? String ?? ""
        return dateA < dateB
      }

      let response: [String: Any] = [
        "thread_subject": seedSubject,
        "message_count": threadMessages.count,
        "messages": threadMessages,
      ]
      return jsonEncode(response)

    case .error(let code, let message):
      return code.json(message: message)
    }
  }
}

// MARK: - Subject Normalization

/// Strip common reply/forward prefixes from a subject line for thread matching.
/// Handles: Re:, Fwd:, Fw:, and their variations with brackets like [Re]:
func normalizeSubject(_ subject: String) -> String {
  var s = subject.trimmingCharacters(in: .whitespacesAndNewlines)
  let prefixPattern = "^(?i)(re|fwd|fw)(\\[\\d+\\])?:\\s*"

  while true {
    guard let range = s.range(of: prefixPattern, options: .regularExpression) else {
      break
    }
    s = String(s[range.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
  }
  return s
}
