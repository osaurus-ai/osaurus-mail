import Testing

@testable import osaurus_mail

@Suite("MessageCache")
struct MessageCacheTests {

  @Test("get returns nil on cache miss")
  func getMiss() {
    let cache = MessageCache(capacity: 10)
    #expect(cache.get("<unknown@example.com>") == nil)
  }

  @Test("set and get round-trip")
  func setAndGet() {
    let cache = MessageCache(capacity: 10)
    cache.set("<abc@example.com>", internalID: 42)
    #expect(cache.get("<abc@example.com>") == 42)
  }

  @Test("set overwrites existing entry")
  func setOverwrite() {
    let cache = MessageCache(capacity: 10)
    cache.set("<abc@example.com>", internalID: 1)
    cache.set("<abc@example.com>", internalID: 99)
    #expect(cache.get("<abc@example.com>") == 99)
  }

  @Test("LRU eviction when capacity exceeded")
  func eviction() {
    let cache = MessageCache(capacity: 3)
    cache.set("<a@x>", internalID: 1)
    cache.set("<b@x>", internalID: 2)
    cache.set("<c@x>", internalID: 3)
    // Cache is full: [c, b, a] (head to tail)
    // Adding a 4th should evict <a@x> (LRU)
    cache.set("<d@x>", internalID: 4)

    #expect(cache.get("<a@x>") == nil)
    #expect(cache.get("<b@x>") == 2)
    #expect(cache.get("<c@x>") == 3)
    #expect(cache.get("<d@x>") == 4)
  }

  @Test("get promotes entry to MRU, preventing eviction")
  func getPromotesMRU() {
    let cache = MessageCache(capacity: 3)
    cache.set("<a@x>", internalID: 1)
    cache.set("<b@x>", internalID: 2)
    cache.set("<c@x>", internalID: 3)

    // Access <a@x> to promote it to MRU
    _ = cache.get("<a@x>")

    // Now <b@x> is LRU. Adding a new entry should evict <b@x>.
    cache.set("<d@x>", internalID: 4)

    #expect(cache.get("<a@x>") == 1)
    #expect(cache.get("<b@x>") == nil)
    #expect(cache.get("<c@x>") == 3)
    #expect(cache.get("<d@x>") == 4)
  }

  @Test("populateFromMessages batch insert")
  func populateBatch() {
    let cache = MessageCache(capacity: 100)
    let entries = [
      (messageID: "<m1@x>", internalID: 10),
      (messageID: "<m2@x>", internalID: 20),
      (messageID: "<m3@x>", internalID: 30),
    ]
    cache.populateFromMessages(entries)

    #expect(cache.get("<m1@x>") == 10)
    #expect(cache.get("<m2@x>") == 20)
    #expect(cache.get("<m3@x>") == 30)
  }

  @Test("populateFromMessages updates existing entries")
  func populateUpdates() {
    let cache = MessageCache(capacity: 100)
    cache.set("<m1@x>", internalID: 1)
    cache.populateFromMessages([(messageID: "<m1@x>", internalID: 999)])
    #expect(cache.get("<m1@x>") == 999)
  }

  @Test("populateFromMessages respects capacity")
  func populateEvicts() {
    let cache = MessageCache(capacity: 2)
    let entries = [
      (messageID: "<a@x>", internalID: 1),
      (messageID: "<b@x>", internalID: 2),
      (messageID: "<c@x>", internalID: 3),
    ]
    cache.populateFromMessages(entries)

    // Only last 2 should survive (capacity = 2)
    #expect(cache.get("<a@x>") == nil)
    #expect(cache.get("<b@x>") == 2)
    #expect(cache.get("<c@x>") == 3)
  }
}
