import Testing

@testable import osaurus_mail

@Suite("MailboxPath")
struct MailboxPathTests {

  @Test("simple path: iCloud/INBOX")
  func simplePath() {
    let result = parseMailboxPath("iCloud/INBOX")
    #expect(result != nil)
    #expect(result?.account == "iCloud")
    #expect(result?.applescriptRef == "mailbox \"INBOX\" of account \"iCloud\"")
  }

  @Test("nested path: Gmail/Work/Projects")
  func nestedPath() {
    let result = parseMailboxPath("Gmail/Work/Projects")
    #expect(result != nil)
    #expect(result?.account == "Gmail")
    #expect(
      result?.applescriptRef == "mailbox \"Projects\" of mailbox \"Work\" of account \"Gmail\"")
  }

  @Test("deeply nested path: Account/A/B/C")
  func deeplyNestedPath() {
    let result = parseMailboxPath("Account/A/B/C")
    #expect(result != nil)
    #expect(result?.account == "Account")
    #expect(
      result?.applescriptRef
        == "mailbox \"C\" of mailbox \"B\" of mailbox \"A\" of account \"Account\"")
  }

  @Test("path with special chars: Gmail/[Gmail]/All Mail")
  func pathWithBrackets() {
    let result = parseMailboxPath("Gmail/[Gmail]/All Mail")
    #expect(result != nil)
    #expect(result?.account == "Gmail")
    #expect(
      result?.applescriptRef == "mailbox \"All Mail\" of mailbox \"[Gmail]\" of account \"Gmail\"")
  }

  @Test("no slash returns nil")
  func noSlash() {
    #expect(parseMailboxPath("INBOX") == nil)
  }

  @Test("empty account returns nil")
  func emptyAccount() {
    #expect(parseMailboxPath("/INBOX") == nil)
  }

  @Test("empty mailbox returns nil")
  func emptyMailbox() {
    #expect(parseMailboxPath("iCloud/") == nil)
  }

  @Test("empty string returns nil")
  func emptyString() {
    #expect(parseMailboxPath("") == nil)
  }

  // MARK: - escapeAppleScriptString

  @Test("escapes quotes in AppleScript strings")
  func escapeQuotes() {
    #expect(escapeAppleScriptString("hello \"world\"") == "hello \\\"world\\\"")
  }

  @Test("escapes backslashes in AppleScript strings")
  func escapeBackslashes() {
    #expect(escapeAppleScriptString("path\\to\\file") == "path\\\\to\\\\file")
  }

  @Test("leaves plain strings unchanged")
  func plainString() {
    #expect(escapeAppleScriptString("hello world") == "hello world")
  }
}
