---
name: osaurus-mail
description: Read, search, compose, and manage Apple Mail emails using the Osaurus Mail plugin. Use when the user asks to check email, read messages, send replies, search their inbox, triage mail, summarize threads, or manage mailboxes.
metadata:
  author: osaurus
  version: "0.1.0"
---

# Osaurus Mail

Read, search, compose, and manage emails in Apple Mail. All operations happen locally via AppleScript — no data leaves the device.

## Workflow

Always follow this sequence when working with email:

1. **Discover mailboxes.** Call `list_mailboxes` first to get the available `mailbox_path` values. Never guess mailbox names.
2. **Browse or search.** Use `list_messages` to browse a specific mailbox, or `search_messages` to find messages by keyword. Both return summaries without bodies.
3. **Read full content.** Call `read_message` with a `message_id` to get the body text. Only read messages the user actually needs — don't bulk-read unnecessarily.
4. **Act.** Use `compose_message`, `reply_to_message`, `move_message`, or `set_message_status` to take action. Default to drafts (`send: false`) for compose and reply so the user can review.
5. **Paginate.** When `has_more` is `true`, call again with `offset: next_offset` to get the next page. Don't assume all results fit in one call.

Never skip `list_mailboxes`. Never guess a `mailbox_path` or `message_id`. Always use values returned by a previous tool call.

## Identifiers

Two identifier types are used across all tools. Always pass them verbatim — never construct or modify them.

### Mailbox Path

Format: `<account>/<mailbox>[/<child>]*`

```
iCloud/INBOX
iCloud/Sent
iCloud/Archive
Gmail/INBOX
Gmail/Work/Projects
Gmail/[Gmail]/All Mail
```

Returned by `list_mailboxes`. Used as the `mailbox_path` parameter in `list_messages`, `search_messages`, and `move_message`.

### Message ID

RFC 2822 Message-ID header. Globally unique, survives Mail.app restarts.

```
<CABx+XYZ123@mail.gmail.com>
<abc-def-456@icloud.com>
```

Returned in every message summary by `list_messages`, `search_messages`, and `get_thread`. Used as the `message_id` parameter in `read_message`, `reply_to_message`, `move_message`, `set_message_status`, and `get_thread`.

## Pagination

`list_messages` and `search_messages` return paginated results:

```json
{
  "messages": [...],
  "total": 342,
  "has_more": true,
  "next_offset": 20
}
```

- `total` is the count of all messages matching the current filters.
- When `has_more` is `true`, call again with `offset` set to `next_offset`.
- Default limit is 20 for `list_messages`, 10 for `search_messages`. Max is 50.
- Messages are returned newest-first.

## Drafts vs Sending

`compose_message` and `reply_to_message` both default to `send: false`, which opens a draft in Mail's compose window for the user to review before sending.

- **Always default to drafts** unless the user explicitly asks to send immediately.
- When drafting, tell the user: "I've opened a draft in Mail for your review."
- Only set `send: true` when the user says something like "send it" or "send immediately."

## Tool Reference

### `list_mailboxes`

- No parameters. Returns all mailboxes across all configured accounts.
- Call this first in every email session to discover available mailbox paths.
- Returns `mailbox_path`, `unread_count`, and `message_count` for each mailbox.

### `list_messages`

- Requires `mailbox_path`. Browse a specific mailbox with optional filters.
- Filters: `unread_only`, `since`, `before`, `from_contains`. All are optional.
- Returns summaries: subject, sender, date, flags. **No body** — use `read_message` for that.
- Dates use ISO 8601 format: `"2026-02-01T00:00:00Z"`.
- `from_contains` is case-insensitive and matches against both sender name and email address.

### `read_message`

- Requires `message_id`. Returns the full message body, recipients, attachments, and mailbox path.
- `max_length` (default 10000) truncates long bodies. If `body_truncated` is `true`, call again with a higher `max_length`.
- Set `include_headers: true` only when the user needs raw email headers.

### `search_messages`

- Requires `query`. Searches subject, sender, and body text.
- Optionally scope to a single mailbox with `mailbox_path`.
- Returns the same summary format as `list_messages` — no bodies.
- Use this instead of `list_messages` when looking for specific content rather than browsing.

### `compose_message`

- Requires `to` (array) and `subject`.
- Provide `body` (plain text) or `html_body` (HTML). At least one is required. If both are given, `html_body` takes precedence.
- Optional: `cc`, `bcc`, `from_account` (account name like `"iCloud"` or `"Gmail"`).
- `send: false` (default) opens a draft. `send: true` sends immediately.

### `reply_to_message`

- Requires `message_id`. Provide `body` or `html_body` for the reply content. At least one is required.
- `reply_all: true` replies to all recipients. Default is `false` (reply to sender only).
- Mail automatically quotes the original message.
- `send: false` (default) opens a draft.

### `move_message`

- Requires `message_id` and `destination_mailbox_path`.
- **Source and destination must be in the same account.** You cannot move from `iCloud/INBOX` to `Gmail/Archive`. Use `list_mailboxes` to find valid destinations.
- Common patterns: move to `Account/Archive`, `Account/Trash`, or a custom folder.

### `set_message_status`

- Requires `message_id`. Provide any combination of `is_read`, `is_flagged`, `is_junk`.
- Only provided fields are changed. Omitted fields are left as-is.
- Returns the full current status after applying changes.

### `get_thread`

- Requires `message_id` (any message in the thread). Returns all related messages sorted oldest-first.
- `include_bodies: false` (default) returns summaries only. Set `true` to include bodies (truncated to `max_body_length`, default 5000).
- Thread detection is best-effort based on subject matching. It strips Re:/Fwd: prefixes and searches the same account.

## Common Patterns

### Summarize unread emails

```
1. list_mailboxes()
2. list_messages(mailbox_path="iCloud/INBOX", unread_only=true, limit=10)
3. read_message(message_id=...) for each message
4. Summarize all messages for the user
```

### Reply to a specific person's email

```
1. search_messages(query="Sarah", limit=5)
2. Show summaries to user, confirm which message
3. read_message(message_id=...) for full context
4. Draft reply text
5. reply_to_message(message_id=..., body="...", send=false)
6. Tell user: "Draft opened in Mail for review."
```

### Archive old messages from a sender

```
1. list_mailboxes() → find archive mailbox
2. list_messages(mailbox_path="iCloud/INBOX", from_contains="notifications@github.com", before="2026-02-06T00:00:00Z", limit=50)
3. move_message(message_id=..., destination_mailbox_path="iCloud/Archive") for each
4. If has_more, paginate with next_offset and repeat
```

### Summarize a conversation thread

```
1. search_messages(query="Q4 budget", limit=1)
2. get_thread(message_id=..., include_bodies=true)
3. Summarize the full thread for the user
```

### Triage inbox (mark read, flag important, archive noise)

```
1. list_mailboxes()
2. list_messages(mailbox_path="iCloud/INBOX", unread_only=true, limit=20)
3. For each message, read the summary and decide:
   - Important → set_message_status(message_id=..., is_flagged=true, is_read=true)
   - Noise → move_message(message_id=..., destination_mailbox_path="iCloud/Archive")
   - Needs reply → leave unread, tell user
```

## Limitations

- **Apple Mail must be running.** If Mail is closed, all tools return a `mail_not_running` error.
- **Automation permission required.** The user must grant Osaurus access to control Mail in System Settings → Privacy & Security → Automation.
- **No attachment content.** `read_message` returns attachment names and sizes, but cannot read attachment file contents.
- **Thread detection is best-effort.** Based on subject matching, not server-side thread IDs. Threads with heavily modified subjects may not group perfectly.
- **Cross-account moves fail.** A message in iCloud cannot be moved to a Gmail mailbox. The error message will suggest the correct account.
- **Rate limits on large mailboxes.** `whose` clauses in AppleScript can be slow on mailboxes with thousands of messages. Use filters (`since`, `before`, `from_contains`, `unread_only`) to narrow results.
