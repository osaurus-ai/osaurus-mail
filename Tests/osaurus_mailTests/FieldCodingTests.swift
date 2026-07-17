import Foundation
import Testing

@testable import osaurus_mail

@Suite("AppleScript Field Coding")
struct FieldCodingTests {

  static let hostileCorpus: [String] = [
    "plain subject",
    "tab\there",
    "newline\nhere",
    "crlf\r\nhere",
    "pipes ||| in subject",
    "colons ::: in name",
    "back\\slash",
    "mix\t|||\n:::\\end",
    "trailing backslash\\",
    "unicode — émojis 🦖 ok",
    "quote \" and 'single'",
    "|||leading and trailing|||",
    ":::",
    "\t\t\t",
  ]

  @Test("every hostile string round-trips through encode/decode")
  func roundTrip() {
    for s in Self.hostileCorpus {
      let encoded = encodeAppleScriptField(s)
      #expect(!encoded.contains("\t"))
      #expect(!encoded.contains("\n"))
      #expect(!encoded.contains("\r"))
      #expect(!encoded.contains("|"))
      #expect(!encoded.contains(":"))
      #expect(decodeAppleScriptField(encoded) == s, "round-trip failed for \(s.debugDescription)")
    }
  }

  @Test("decode tolerates unknown escapes and dangling backslash")
  func decodeLenient() {
    #expect(decodeAppleScriptField("a\\zb") == "a\\zb")
    #expect(decodeAppleScriptField("end\\") == "end\\")
  }

  @Test("AppleScript encodeField handler matches the Swift encoder")
  func appleScriptHandlerMatchesSwiftEncoder() throws {
    // Pure string manipulation via osascript: no app automation, no TCC.
    let script = """
      set s to "evil" & tab & "subject|||x" & linefeed & "b\\\\c:d" & return & "end"
      return my encodeField(s)
      \(appleScriptFieldEncoderHandlers)
      """
    let result = try runSubprocess(
      executable: "/usr/bin/osascript", arguments: ["-e", script], timeout: 20)
    #expect(result.terminationStatus == 0, "osascript failed: \(result.stderr)")

    let expectedInput = "evil\tsubject|||x\nb\\c:d\rend"
    let expected = encodeAppleScriptField(expectedInput)
    #expect(result.stdout.trimmingCharacters(in: .newlines) == expected)
    #expect(decodeAppleScriptField(expected) == expectedInput)
  }

  @Test("message list parsing survives hostile subjects, senders, and recipients")
  func messageListHostileFields() throws {
    let cache = MessageCache(capacity: 10)
    let subject = "Q3 report\t|||\ndraft:::final\\v2"
    let sender = "Team | Reports <a\tb@example.com>"
    let recipients = ["x|y@example.com", "tab\t@example.com"]

    let line = [
      encodeAppleScriptField("<msg1@example.com>"),
      encodeAppleScriptField(subject),
      encodeAppleScriptField(sender),
      "2026-02-13T09:30:00",
      "true", "false", "true", "42",
      recipients.map(encodeAppleScriptField).joined(separator: "|||"),
    ].joined(separator: "\t")

    let json = renderMessageListJSON(line + "\n", total: 1, offset: 0, endIdx: 1, cache: cache)
    let obj =
      try JSONSerialization.jsonObject(with: json.data(using: .utf8)!) as! [String: Any]
    let messages = obj["messages"] as! [[String: Any]]
    #expect(messages.count == 1)
    #expect(messages[0]["message_id"] as? String == "<msg1@example.com>")
    #expect(messages[0]["subject"] as? String == subject)
    #expect(messages[0]["from"] as? String == sender)
    #expect(messages[0]["to"] as? [String] == recipients)
    #expect(cache.get("<msg1@example.com>") == 42)
  }

  @Test("read_message parsing survives hostile bodies and attachment names")
  func readMessageHostileFields() throws {
    let cache = MessageCache(capacity: 10)
    let body = "line1\nline2\ttabbed\n|||weird:::stuff\\done"
    let attachmentName = "report:final|draft\t2026.pdf"

    let parts = [
      encodeAppleScriptField("<msg2@example.com>"),
      encodeAppleScriptField("subject\twith tab"),
      encodeAppleScriptField("sender@example.com"),
      "2026-02-13T09:30:00",
      "true", "false",
      encodeAppleScriptField(body),
      "",
      encodeAppleScriptField("to@example.com"),
      "",
      encodeAppleScriptField(attachmentName) + ":::2048",
      encodeAppleScriptField("Work/IN:BOX"),
      "77",
    ].joined(separator: "\t")

    let tool = ReadMessageTool()
    let json = tool.parseOutput(
      parts, messageID: "<msg2@example.com>", maxLength: 10000, includeHeaders: false,
      cache: cache)
    let obj =
      try JSONSerialization.jsonObject(with: json.data(using: .utf8)!) as! [String: Any]
    #expect(obj["body"] as? String == body)
    #expect(obj["subject"] as? String == "subject\twith tab")
    #expect(obj["mailbox_path"] as? String == "Work/IN:BOX")
    let attachments = obj["attachments"] as! [[String: Any]]
    #expect(attachments.count == 1)
    #expect(attachments[0]["name"] as? String == attachmentName)
    #expect(attachments[0]["size_bytes"] as? Int == 2048)
    #expect(cache.get("<msg2@example.com>") == 77)
  }

  @Test("get_thread parsing matches normalized hostile subjects and preserves bodies")
  func threadHostileFields() throws {
    let cache = MessageCache(capacity: 10)
    let subject = "Plan: rollout ||| phase\t2"
    let body = "see attachment\nname:::x"

    let line = [
      encodeAppleScriptField("<t1@example.com>"),
      encodeAppleScriptField("Re: " + subject),
      encodeAppleScriptField("sender@example.com"),
      "2026-02-13T09:30:00",
      "true", "false", "false", "9",
      encodeAppleScriptField("to@example.com"),
      encodeAppleScriptField(body),
    ].joined(separator: "\t")

    let tool = GetThreadTool()
    let json = tool.renderThreadJSON(
      line + "\n", seedSubject: "Re: " + subject, normalizedSubject: normalizeSubject(subject),
      includeBodies: true, maxBodyLength: 5000, cache: cache)
    let obj =
      try JSONSerialization.jsonObject(with: json.data(using: .utf8)!) as! [String: Any]
    #expect(obj["message_count"] as? Int == 1)
    let messages = obj["messages"] as! [[String: Any]]
    #expect(messages[0]["subject"] as? String == "Re: " + subject)
    #expect(messages[0]["body"] as? String == body)
  }
}
