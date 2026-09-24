---
name: magenta-archive
description: How to find and read archived magenta threads (conversation logs and tool output) under /tmp/magenta/threads. Use when the user refers to a previous thread, asks to "continue where we left off" on a thread id, or wants to search past conversations.
---

# Layout

The archive root is `$MAGENTA_TEMP_DIR` (default `/tmp/magenta`). Each thread is a directory `threads/<thread-id>/`:

- `meta.json` — `{ title, threadType, cwd, scriptName? }`. `threadType` is `root`, `docker_root`, `subagent` or `compact`.
- `conversation.jsonl` — one JSON object per line, in order.
- `tools/<tool_use_id>/` — full untrimmed tool output (e.g. `bashCommand.log`), keyed by the `tool_use` id in the conversation.

Thread ids are uuidv7, so directory names sort by creation time (newest last with `ls`). Users sometimes paste an id without dashes (`01a0caaad329…`); re-insert dashes as 8-4-4-4-12, or just `ls threads | grep` a prefix.

# Finding a conversation

Live threads in the current nvim: each open thread has a display buffer named `<title> [Magenta <id>]` (and an input buffer `[Magenta Input <id>]`), with the id undashed. List them with the `nvim_lua` tool:

```lua
local r = {}
for _, b in ipairs(vim.api.nvim_list_bufs()) do
  local name = vim.api.nvim_buf_get_name(b)
  local id = name:match("%[Magenta (%x+)%]$")
  if id then table.insert(r, { id = id, name = name }) end
end
return r
```

Recent archived threads for a directory: `meta.json` records the thread's `cwd`, so filter by it (newest first; stops after `want` matches or `max` threads examined):

```sh
cd /tmp/magenta/threads
want=5 max=500 cwd="$HOME/src/glean" found=0
for d in $(ls -r | head -n "$max"); do
  line=$(jq -r --arg d "$d" --arg cwd "$cwd" \
    'select(.cwd==$cwd and (.threadType=="root" or .threadType=="docker_root")) | "\($d) \(.title // "untitled")"' \
    "$d/meta.json" 2>/dev/null) || continue
  [ -n "$line" ] || continue
  echo "$line"; found=$((found+1)); [ "$found" -ge "$want" ] && break
done
```

Subagent and compact threads share the directory but are usually noise; filter them out as above unless debugging a subagent.

# conversation.jsonl entries

- `{type:"thread_start", threadId, threadType, timestamp}`
- `{type:"title", title, timestamp}`
- `{type:"message", timestamp, message:{role, content:[...], stopReason?, usage?}}`

Content block types: `text`, `thinking`, `tool_use` (`id`, `name`, `request.value.input`), `tool_result` (`id`, `result.value[]`), `context_update`, `system_reminder`, `system_info`.

# Recipes

Don't read `conversation.jsonl` whole; it's often hundreds of KB. Use `jq`:

```sh
cd /tmp/magenta/threads
# recent top-level threads with titles
for d in $(ls | tail -n 20); do echo "$d $(jq -r '[.threadType,.title]|join(" ")' $d/meta.json)"; done
# find threads by title / cwd
grep -l '"title":"[^"]*glean' */meta.json
# user text messages
jq -r 'select(.type=="message" and .message.role=="user") | .message.content[] | select(.type=="text") | .text' <id>/conversation.jsonl
# the last assistant reply (usually what "continue where we left off" needs)
jq -r 'select(.type=="message" and .message.role=="assistant") | .message.content[] | select(.type=="text") | .text' <id>/conversation.jsonl | tail -n 40
# tool calls made, in order
jq -c 'select(.type=="message") | .message.content[] | select(.type=="tool_use") | [.name, .request.value.input]' <id>/conversation.jsonl
```

To continue a thread: read the last assistant text and the last few user texts, check any open question it ended on, then verify current repo state (`git status`, `git log`) before acting, since work may have happened since.
