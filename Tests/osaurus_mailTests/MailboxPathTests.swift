import Testing

@testable import osaurus_mail

@Suite("MailboxPath")
struct MailboxPathTests {

  @Test("simple path: you@gmail.com/INBOX")
  func simplePath() {
    let result = parseMailboxPath("you@gmail.com/INBOX")
    #expect(result != nil)
    #expect(result?.accountKey == "you@gmail.com")
    #expect(result?.mailboxRef == "mailbox \"INBOX\" of targetAccount")
    // the account is resolved by a loop binding `targetAccount`, matching name or email
    #expect(result?.resolveAccountScript.contains("set acctKey to \"you@gmail.com\"") == true)
    #expect(result?.resolveAccountScript.contains("email addresses of a contains acctKey") == true)
  }

  @Test("name-based path still parses (backward compatible)")
  func namePath() {
    let result = parseMailboxPath("iCloud/INBOX")
    #expect(result != nil)
    #expect(result?.accountKey == "iCloud")
    #expect(result?.mailboxRef == "mailbox \"INBOX\" of targetAccount")
  }

  @Test("nested path: you@work.com/Work/Projects")
  func nestedPath() {
    let result = parseMailboxPath("you@work.com/Work/Projects")
    #expect(result != nil)
    #expect(result?.accountKey == "you@work.com")
    #expect(
      result?.mailboxRef == "mailbox \"Projects\" of mailbox \"Work\" of targetAccount")
  }

  @Test("deeply nested path: Account/A/B/C")
  func deeplyNestedPath() {
    let result = parseMailboxPath("Account/A/B/C")
    #expect(result != nil)
    #expect(result?.accountKey == "Account")
    #expect(
      result?.mailboxRef
        == "mailbox \"C\" of mailbox \"B\" of mailbox \"A\" of targetAccount")
  }

  @Test("path with special chars: you@gmail.com/[Gmail]/All Mail")
  func pathWithBrackets() {
    let result = parseMailboxPath("you@gmail.com/[Gmail]/All Mail")
    #expect(result != nil)
    #expect(result?.accountKey == "you@gmail.com")
    #expect(
      result?.mailboxRef == "mailbox \"All Mail\" of mailbox \"[Gmail]\" of targetAccount")
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
