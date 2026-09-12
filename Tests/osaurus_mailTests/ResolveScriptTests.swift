import Testing

@testable import osaurus_mail

@Suite("buildResolveScript")
struct ResolveScriptTests {

  @Test("cache hit with mailbox path addresses the message in that mailbox first")
  func cacheHitWithMailbox() {
    let cache = MessageCache(capacity: 100)
    cache.set("<abc@example.com>", internalID: 12345, mailboxPath: "you@example.com/INBOX")

    let script = buildResolveScript(messageID: "<abc@example.com>", cache: cache)
    #expect(script.contains("set m to first message of targetMailbox whose id is 12345"))
    // the mailbox resolver for the cached path is emitted
    #expect(script.contains("you@example.com"))
    #expect(script.contains("if name of _mb is \"INBOX\""))
    // never through the front viewer (issue #5)
    #expect(!script.contains("message viewer"))
    // still falls back to the RFC Message-ID search if the id lookups miss
    #expect(script.contains("whose message id is \"<abc@example.com>\""))
    #expect(script.contains("error \"Message not found\""))
  }

  @Test("cache hit without mailbox path scans every mailbox by internal id")
  func cacheHitWithoutMailbox() {
    let cache = MessageCache(capacity: 100)
    cache.set("<abc@example.com>", internalID: 12345)

    let script = buildResolveScript(messageID: "<abc@example.com>", cache: cache)
    #expect(script.contains("set m to first message of mbox whose id is 12345"))
    #expect(!script.contains("of targetMailbox"))
    #expect(!script.contains("message viewer"))
    #expect(script.contains("whose message id is"))
  }

  @Test("id lookups are wrapped in try so a miss falls through")
  func idLookupsAreGuarded() {
    let cache = MessageCache(capacity: 100)
    cache.set("<abc@example.com>", internalID: 7, mailboxPath: "acct/Box")

    let script = buildResolveScript(messageID: "<abc@example.com>", cache: cache)
    let lines = script.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }
    let direct = lines.firstIndex(of: "set m to first message of targetMailbox whose id is 7")!
    #expect(lines[..<direct].contains("try"))
    #expect(lines[direct...].contains("end try"))
    #expect(script.contains("if m is missing value then"))
  }

  @Test("generates search script on cache miss")
  func cacheMiss() {
    let cache = MessageCache(capacity: 100)

    let script = buildResolveScript(messageID: "<unknown@example.com>", cache: cache)
    #expect(script.contains("set m to missing value"))
    #expect(script.contains("whose message id is"))
    #expect(script.contains("unknown@example.com"))
    #expect(!script.contains("whose id is 0"))
    #expect(!script.contains("message viewer"))
  }

  @Test("escapes quotes in message ID")
  func escapesMessageID() {
    let cache = MessageCache(capacity: 100)

    let script = buildResolveScript(messageID: "<test\"quote@x>", cache: cache)
    #expect(script.contains("\\\""))
  }
}
