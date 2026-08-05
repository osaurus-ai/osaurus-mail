import Foundation
import Testing

@testable import osaurus_mail

@Suite("Mailbox List Rendering")
struct MailboxListRenderTests {

  private func parse(_ json: String) -> [[String: Any]]? {
    guard let data = json.data(using: .utf8),
      let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    else { return nil }
    return obj["mailboxes"] as? [[String: Any]]
  }

  @Test("three-column rows produce path, unread count, and account email")
  func basicRows() {
    let output = [
      "\(encodeAppleScriptField("you@gmail.com/INBOX"))\t3\t\(encodeAppleScriptField("you@gmail.com"))",
      "\(encodeAppleScriptField("you@gmail.com/[Gmail]/All Mail"))\t0\t\(encodeAppleScriptField("you@gmail.com"))",
    ].joined(separator: "\n") + "\n"

    let mailboxes = parse(renderMailboxListJSON(output))
    #expect(mailboxes?.count == 2)
    #expect(mailboxes?[0]["mailbox_path"] as? String == "you@gmail.com/INBOX")
    #expect(mailboxes?[0]["unread_count"] as? Int == 3)
    #expect(mailboxes?[0]["account_email"] as? String == "you@gmail.com")
    #expect(mailboxes?[1]["mailbox_path"] as? String == "you@gmail.com/[Gmail]/All Mail")
    #expect(mailboxes?[1]["unread_count"] as? Int == 0)
  }

  @Test("encoded field characters in mailbox names round-trip")
  func encodedFields() {
    let path = "Local/Folders\twith\ntabs"
    let output = "\(encodeAppleScriptField(path))\t7\t\(encodeAppleScriptField(""))\n"
    let mailboxes = parse(renderMailboxListJSON(output))
    #expect(mailboxes?.count == 1)
    #expect(mailboxes?[0]["mailbox_path"] as? String == path)
    #expect(mailboxes?[0]["account_email"] as? String == "")
  }

  @Test("malformed rows are skipped, non-numeric unread counts become zero")
  func malformedRows() {
    let output = [
      "only-one-column",
      "two\tcolumns",
      "good\tmissing value\temail",
    ].joined(separator: "\n") + "\n"
    let mailboxes = parse(renderMailboxListJSON(output))
    #expect(mailboxes?.count == 1)
    #expect(mailboxes?[0]["unread_count"] as? Int == 0)
  }

  @Test("empty script output yields an empty mailbox list")
  func emptyOutput() {
    let mailboxes = parse(renderMailboxListJSON(""))
    #expect(mailboxes?.isEmpty == true)
  }
}

@Suite("Message Row Emitter Contract")
struct MessageRowEmitterTests {

  /// renderMessageListJSON and the search parser require >= 9 tab-separated
  /// columns per row (message id, subject, sender, date, read, flagged,
  /// has_attachments, internal id, recipients). Pin that the shared emitter's
  /// append statement still produces exactly that shape.
  @Test("emitter row has nine columns in the parser's expected order")
  func columnContract() {
    let appendLine = appleScriptEmitMessageRow
      .split(separator: "\n")
      .first { $0.contains("set output to output &") }
    #expect(appendLine != nil)
    let tabCount = appendLine?.components(separatedBy: "\\t").count ?? 0
    #expect(tabCount == 9, "expected 8 tab separators (9 columns), got \(tabCount - 1)")
    // Scalar properties must arrive via ONE multi-property get - the whole
    // point of the emitter is a single Apple event for these seven fields.
    #expect(
      appleScriptEmitMessageRow.contains(
        "{message id, subject, sender, date received, read status, flagged status, id} of m"))
  }

  /// The emitter's rows must remain parseable by renderMessageListJSON.
  @Test("a row shaped like the emitter's output parses end to end")
  func rowParsesEndToEnd() {
    let cache = MessageCache(capacity: 10)
    let row = [
      encodeAppleScriptField("<msg-1@example.com>"),
      encodeAppleScriptField("Hello"),
      encodeAppleScriptField("Sender <s@example.com>"),
      "2026-02-01T10:00:00Z",
      "true",
      "false",
      "true",
      "12345",
      encodeAppleScriptField("a@example.com") + "|||" + encodeAppleScriptField("b@example.com"),
    ].joined(separator: "\t")

    let json = renderMessageListJSON(row + "\n", total: 1, offset: 0, endIdx: 1, cache: cache)
    guard let data = json.data(using: .utf8),
      let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
      let messages = obj["messages"] as? [[String: Any]]
    else {
      Issue.record("response was not valid JSON: \(json)")
      return
    }
    #expect(messages.count == 1)
    #expect(messages[0]["message_id"] as? String == "<msg-1@example.com>")
    #expect(messages[0]["is_read"] as? Bool == true)
    #expect(messages[0]["has_attachments"] as? Bool == true)
    #expect((messages[0]["to"] as? [String]) == ["a@example.com", "b@example.com"])
    #expect(cache.get("<msg-1@example.com>") == 12345)
  }
}
