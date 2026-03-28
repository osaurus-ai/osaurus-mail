import Foundation

// MARK: - Search Messages Tool

struct SearchMessagesTool {
  let name = "search_messages"

  struct Args: Decodable {
    let query: String
    let mailbox_path: String?
    let limit: Int?
    let offset: Int?
    let since: String?
    let before: String?
  }

  func run(args: String, cache: MessageCache) -> String {
    guard let data = args.data(using: .utf8),
      let input = try? JSONDecoder().decode(Args.self, from: data)
    else {
      return MailPluginError.invalidParameter.json(
        message: "Invalid arguments for search_messages.")
    }

    let limit = min(max(input.limit ?? 10, 1), 50)
    let offset = max(input.offset ?? 0, 0)
    let escapedQuery = escapeAppleScriptString(input.query)

    // only match against subject and sender — content contains forces Mail to load every
    // message body, which freezes Mail.app and causes apple event timeouts (-1712)
    var whoseClauses: [String] = [
      "(subject contains \"\(escapedQuery)\" or sender contains \"\(escapedQuery)\")"
    ]
    if let since = input.since {
      let dateStr = escapeAppleScriptString(formatDateForAppleScript(since))
      whoseClauses.append("date received > date \"\(dateStr)\"")
    }
    if let before = input.before {
      let dateStr = escapeAppleScriptString(formatDateForAppleScript(before))
      whoseClauses.append("date received < date \"\(dateStr)\"")
    }

    let whoseStr = whoseClauses.joined(separator: " and ")

    if let mailboxPath = input.mailbox_path {
      guard let parsed = parseMailboxPath(mailboxPath) else {
        return MailPluginError.mailboxNotFound.json(
          message:
            "Invalid mailbox path format: '\(mailboxPath)'. Expected format: 'Account/Mailbox'.")
      }
      let searchScope = "every message of \(parsed.applescriptRef)"
      return searchInMailbox(
        searchScope: searchScope, whoseStr: whoseStr,
        limit: limit, offset: offset, cache: cache)
    } else {
      return searchAllMailboxes(
        whoseStr: whoseStr,
        limit: limit, offset: offset, cache: cache)
    }
  }

  private func searchInMailbox(
    searchScope: String, whoseStr: String,
    limit: Int, offset: Int, cache: MessageCache
  ) -> String {
    let countScript = """
      tell application "Mail"
          return count of (\(searchScope) whose \(whoseStr))
      end tell
      """

    var total = 0
    switch runAppleScript(countScript) {
    case .success(let output):
      total = Int(output.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0
    case .error(let code, let message):
      return code.json(message: message)
    }

    if total == 0 || offset >= total {
      return jsonEncode([
        "messages": [] as [Any],
        "total": total,
        "has_more": false,
        "next_offset": offset,
      ])
    }

    let startIdx = offset + 1
    let endIdx = min(offset + limit, total)

    let fetchScript = """
      tell application "Mail"
          set msgs to (\(searchScope) whose \(whoseStr))
          set output to ""
          repeat with i from \(startIdx) to \(endIdx)
              set m to item i of msgs
              set mid to message id of m
              set subj to subject of m
              set sndr to sender of m
              set dr to date received of m
              set rs to read status of m
              set fs to flagged status of m
              set iid to id of m
              set hasAtt to (count of mail attachments of m) > 0
              set recipList to ""
              repeat with r in (every to recipient of m)
                  if recipList is not "" then set recipList to recipList & "|||"
                  set recipList to recipList & (address of r as text)
              end repeat
              set output to output & mid & "\\t" & subj & "\\t" & sndr & "\\t" & (dr as «class isot» as string) & "\\t" & rs & "\\t" & fs & "\\t" & hasAtt & "\\t" & iid & "\\t" & recipList & linefeed
          end repeat
          return output
      end tell
      """

    return parseMessageListOutput(
      fetchScript, total: total, offset: offset, endIdx: endIdx, cache: cache)
  }

  private func searchAllMailboxes(
    whoseStr: String,
    limit: Int, offset: Int, cache: MessageCache
  ) -> String {
    let script = """
      tell application "Mail"
          set output to ""
          set totalFound to 0
          set collected to 0
          set skipped to 0
          repeat with acct in every account
              repeat with mbox in every mailbox of acct
                  try
                      set foundMsgs to (every message of mbox whose \(whoseStr))
                      repeat with m in foundMsgs
                          set totalFound to totalFound + 1
                          if skipped < \(offset) then
                              set skipped to skipped + 1
                          else if collected < \(limit) then
                              set mid to message id of m
                              set subj to subject of m
                              set sndr to sender of m
                              set dr to date received of m
                              set rs to read status of m
                              set fs to flagged status of m
                              set iid to id of m
                              set hasAtt to (count of mail attachments of m) > 0
                              set recipList to ""
                              repeat with r in (every to recipient of m)
                                  if recipList is not "" then set recipList to recipList & "|||"
                                  set recipList to recipList & (address of r as text)
                              end repeat
                              set output to output & mid & "\\t" & subj & "\\t" & sndr & "\\t" & (dr as «class isot» as string) & "\\t" & rs & "\\t" & fs & "\\t" & hasAtt & "\\t" & iid & "\\t" & recipList & linefeed
                              set collected to collected + 1
                          end if
                      end repeat
                  end try
              end repeat
          end repeat
          return (totalFound as text) & "\\n" & output
      end tell
      """

    switch runAppleScript(script) {
    case .success(let output):
      let lines = output.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
      guard !lines.isEmpty else {
        return jsonEncode([
          "messages": [] as [Any],
          "total": 0,
          "has_more": false,
          "next_offset": offset,
        ])
      }

      let total = Int(lines[0].trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0
      var messages: [[String: Any]] = []
      var cacheEntries: [(messageID: String, internalID: Int)] = []

      for i in 1..<lines.count {
        let line = lines[i]
        guard !line.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { continue }
        let parts = line.split(separator: "\t", omittingEmptySubsequences: false).map(String.init)
        guard parts.count >= 9 else { continue }

        let messageID = parts[0]
        let internalID = Int(parts[7]) ?? 0
        let toStr = parts[8]
        let toList = toStr.isEmpty ? [String]() : toStr.split(separator: "|||").map(String.init)

        messages.append([
          "message_id": messageID,
          "subject": parts[1],
          "from": parts[2],
          "to": toList,
          "date": formatISO8601(parts[3]),
          "is_read": parts[4] == "true",
          "is_flagged": parts[5] == "true",
          "has_attachments": parts[6] == "true",
        ])
        cacheEntries.append((messageID: messageID, internalID: internalID))
      }

      cache.populateFromMessages(cacheEntries)

      let hasMore = offset + messages.count < total
      let nextOffset = hasMore ? offset + messages.count : offset

      return jsonEncode([
        "messages": messages,
        "total": total,
        "has_more": hasMore,
        "next_offset": nextOffset,
      ])

    case .error(let code, let message):
      return code.json(message: message)
    }
  }
}
