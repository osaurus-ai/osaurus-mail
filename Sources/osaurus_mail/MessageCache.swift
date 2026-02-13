import Foundation

// MARK: - LRU Message Cache

/// Thread-safe LRU cache mapping RFC 2822 Message-ID strings to Mail.app internal IDs.
///
/// Bounded to a configurable capacity (default 10,000). When the cache is full,
/// the least-recently-used entry is evicted.
final class MessageCache: @unchecked Sendable {
  private let lock = NSLock()
  private let capacity: Int

  // Dictionary for O(1) lookup
  private var map: [String: Node] = [:]

  // Doubly-linked list for LRU ordering
  private var head: Node?  // Most recently used
  private var tail: Node?  // Least recently used

  private class Node {
    let messageID: String
    var internalID: Int
    var prev: Node?
    var next: Node?

    init(messageID: String, internalID: Int) {
      self.messageID = messageID
      self.internalID = internalID
    }
  }

  init(capacity: Int = 10_000) {
    self.capacity = capacity
  }

  /// Look up the Mail.app internal ID for a given RFC Message-ID.
  /// Returns `nil` on cache miss. Promotes the entry to most-recently-used on hit.
  func get(_ messageID: String) -> Int? {
    lock.lock()
    defer { lock.unlock() }

    guard let node = map[messageID] else {
      return nil
    }
    moveToHead(node)
    return node.internalID
  }

  /// Insert or update a mapping from RFC Message-ID to Mail.app internal ID.
  func set(_ messageID: String, internalID: Int) {
    lock.lock()
    defer { lock.unlock() }

    if let existing = map[messageID] {
      existing.internalID = internalID
      moveToHead(existing)
      return
    }

    let node = Node(messageID: messageID, internalID: internalID)
    map[messageID] = node
    addToHead(node)

    if map.count > capacity {
      if let evicted = removeTail() {
        map.removeValue(forKey: evicted.messageID)
      }
    }
  }

  /// Batch-populate the cache with message ID mappings.
  func populateFromMessages(_ messages: [(messageID: String, internalID: Int)]) {
    lock.lock()
    defer { lock.unlock() }

    for entry in messages {
      if let existing = map[entry.messageID] {
        existing.internalID = entry.internalID
        moveToHead(existing)
      } else {
        let node = Node(messageID: entry.messageID, internalID: entry.internalID)
        map[entry.messageID] = node
        addToHead(node)

        if map.count > capacity {
          if let evicted = removeTail() {
            map.removeValue(forKey: evicted.messageID)
          }
        }
      }
    }
  }

  // MARK: - Linked List Operations

  private func addToHead(_ node: Node) {
    node.prev = nil
    node.next = head
    head?.prev = node
    head = node
    if tail == nil {
      tail = node
    }
  }

  private func removeNode(_ node: Node) {
    let prev = node.prev
    let next = node.next
    prev?.next = next
    next?.prev = prev
    if node === head { head = next }
    if node === tail { tail = prev }
    node.prev = nil
    node.next = nil
  }

  private func moveToHead(_ node: Node) {
    guard node !== head else { return }
    removeNode(node)
    addToHead(node)
  }

  private func removeTail() -> Node? {
    guard let tailNode = tail else { return nil }
    removeNode(tailNode)
    return tailNode
  }
}
