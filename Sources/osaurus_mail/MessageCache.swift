import Foundation

// MARK: - LRU Message Cache

/// Thread-safe LRU cache mapping RFC 2822 Message-ID strings to Mail.app internal IDs,
/// plus (when known) the `Account/Mailbox` path the message was last seen in.
///
/// The mailbox path lets `buildResolveScript` address the message directly
/// (`message id N of <mailbox>`) instead of going through the front message viewer,
/// which only knows the messages it currently displays (issue #5).
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

  /// A cached mapping: Mail.app internal ID plus the mailbox path it was last listed in
  /// (`nil` when the message was found without a mailbox context, e.g. by get_thread).
  struct Entry: Equatable {
    let internalID: Int
    let mailboxPath: String?
  }

  private class Node {
    let messageID: String
    var internalID: Int
    var mailboxPath: String?
    var prev: Node?
    var next: Node?

    init(messageID: String, internalID: Int, mailboxPath: String?) {
      self.messageID = messageID
      self.internalID = internalID
      self.mailboxPath = mailboxPath
    }
  }

  init(capacity: Int = 10_000) {
    self.capacity = capacity
  }

  /// Look up the Mail.app internal ID for a given RFC Message-ID.
  /// Returns `nil` on cache miss. Promotes the entry to most-recently-used on hit.
  func get(_ messageID: String) -> Int? {
    entry(for: messageID)?.internalID
  }

  /// Look up the full cached entry (internal ID and last-known mailbox path) for a
  /// given RFC Message-ID. Returns `nil` on cache miss. Promotes the entry to
  /// most-recently-used on hit.
  func entry(for messageID: String) -> Entry? {
    lock.lock()
    defer { lock.unlock() }

    guard let node = map[messageID] else {
      return nil
    }
    moveToHead(node)
    return Entry(internalID: node.internalID, mailboxPath: node.mailboxPath)
  }

  /// Insert or update a mapping from RFC Message-ID to Mail.app internal ID.
  ///
  /// Pass `mailboxPath` (`Account/Mailbox`) when the caller knows where the message
  /// was listed; `nil` keeps a previously cached path, since a message that has not
  /// been moved is still where it was last seen.
  func set(_ messageID: String, internalID: Int, mailboxPath: String? = nil) {
    lock.lock()
    defer { lock.unlock() }
    insert(messageID: messageID, internalID: internalID, mailboxPath: mailboxPath)
  }

  /// Batch-populate the cache with message ID mappings.
  func populateFromMessages(_ messages: [(messageID: String, internalID: Int)]) {
    populateFromMessages(messages.map { ($0.messageID, $0.internalID, nil) })
  }

  /// Batch-populate the cache with message ID mappings that carry the mailbox path
  /// the messages were listed in.
  func populateFromMessages(
    _ messages: [(messageID: String, internalID: Int, mailboxPath: String?)]
  ) {
    lock.lock()
    defer { lock.unlock() }

    for entry in messages {
      insert(messageID: entry.messageID, internalID: entry.internalID, mailboxPath: entry.mailboxPath)
    }
  }

  /// Caller must hold `lock`.
  private func insert(messageID: String, internalID: Int, mailboxPath: String?) {
    if let existing = map[messageID] {
      existing.internalID = internalID
      if let mailboxPath { existing.mailboxPath = mailboxPath }
      moveToHead(existing)
      return
    }

    let node = Node(messageID: messageID, internalID: internalID, mailboxPath: mailboxPath)
    map[messageID] = node
    addToHead(node)

    if map.count > capacity {
      if let evicted = removeTail() {
        map.removeValue(forKey: evicted.messageID)
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
