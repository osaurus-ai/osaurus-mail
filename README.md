# Osaurus Mail

An Osaurus plugin that gives agents the ability to read, search, compose, and manage emails in Apple Mail via AppleScript. Combined with Osaurus's local models, agents can summarize threads, draft replies, triage inboxes, and more — all on-device.

**Plugin ID:** `osaurus.mail`
**Requirement:** macOS 15.0+, Automation permission for Mail.app

## Tools

| Tool | Description | Permission |
|------|-------------|------------|
| `list_mailboxes` | List all mailboxes across all accounts | auto |
| `list_messages` | List message summaries in a mailbox with filters and pagination | auto |
| `read_message` | Read the full content of a specific email | ask |
| `search_messages` | Search messages by keyword across subject and sender summaries only | auto |
| `compose_message` | Compose a new email (draft or send) | ask |
| `reply_to_message` | Reply to an existing email (draft or send) | ask |
| `move_message` | Move a message to a different mailbox | ask |
| `set_message_status` | Update read/flagged/junk status of a message | auto |
| `get_thread` | Get all messages in a conversation thread | ask |

## Setup

### 1. Grant Automation Permission

The first time the plugin runs, macOS will prompt you to allow Osaurus to control Mail.app. You can also pre-authorize this in:

**System Settings → Privacy & Security → Automation → Osaurus → Mail**

### 2. Build

```bash
swift build -c release
```

### 3. Verify Manifest

```bash
osaurus manifest extract .build/release/libosaurus-mail.dylib
```

### 4. Package & Install Locally

```bash
osaurus tools package osaurus.mail 0.1.0
osaurus tools install ./osaurus.mail-0.1.0.zip
osaurus tools verify
```

### 5. Test in Osaurus

Open Osaurus, go to Tools settings (Cmd+Shift+M → Tools), and verify the plugin appears. Try asking the agent to list your mailboxes or summarize unread emails.

## How It Works

All tools communicate with Apple Mail via AppleScript. The plugin:

- **Identifies mailboxes** using qualified paths like `iCloud/INBOX` or `Gmail/Work/Projects`
- **Identifies messages** using RFC 2822 Message-ID headers, which are globally unique and survive Mail.app restarts
- **Caches** message ID → internal ID mappings in an LRU cache (10K entries) to keep lookups fast
- **Paginates** list and search results with `limit`/`offset`/`has_more`/`next_offset`
- **Returns structured JSON** for all responses and errors

## Agent Workflow Examples

**"Summarize my unread emails"**
1. Agent calls `list_mailboxes` → discovers `iCloud/INBOX`
2. Agent calls `list_messages(mailbox_path: "iCloud/INBOX", unread_only: true)`
3. For each message, calls `read_message(message_id: "...")`
4. Agent summarizes all messages

**"Reply to Sarah's latest email"**
1. Agent calls `search_messages(query: "Sarah", limit: 5)`
2. Identifies the right message from summaries
3. Calls `read_message(message_id: "...")` for full context
4. Drafts reply, calls `reply_to_message(message_id: "...", body: "...", send: false)` → draft opens for user review

`search_messages` does not search message bodies. Use it to find likely messages by
subject or sender, then call `read_message` on selected results when body context is needed.

**"Archive everything from GitHub older than a week"**
1. Agent calls `list_messages(mailbox_path: "iCloud/INBOX", from_contains: "github.com", before: "2026-02-06T00:00:00Z")`
2. For each message, calls `move_message(message_id: "...", destination_mailbox_path: "iCloud/Archive")`
3. Paginates if needed using `next_offset`

## Publishing

This project includes a GitHub Actions workflow that automatically builds and releases the plugin when you push a version tag.

```bash
git tag v0.1.0
git push origin v0.1.0
```

## License

MIT
