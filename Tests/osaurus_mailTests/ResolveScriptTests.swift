import Testing

@testable import osaurus_mail

@Suite("buildResolveScript")
struct ResolveScriptTests {

  @Test("uses cached internal ID when available")
  func cacheHit() {
    let cache = MessageCache(capacity: 100)
    cache.set("<abc@example.com>", internalID: 12345)

    let script = buildResolveScript(messageID: "<abc@example.com>", cache: cache)
    #expect(script.contains("12345"))
    #expect(script.contains("whose id is"))
    // Should NOT contain the fallback search logic
    #expect(!script.contains("missing value"))
  }

  @Test("generates search script on cache miss")
  func cacheMiss() {
    let cache = MessageCache(capacity: 100)

    let script = buildResolveScript(messageID: "<unknown@example.com>", cache: cache)
    #expect(script.contains("missing value"))
    #expect(script.contains("whose message id is"))
    #expect(script.contains("unknown@example.com"))
  }

  @Test("escapes quotes in message ID")
  func escapesMessageID() {
    let cache = MessageCache(capacity: 100)

    let script = buildResolveScript(messageID: "<test\"quote@x>", cache: cache)
    #expect(script.contains("\\\""))
  }
}
