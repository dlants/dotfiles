-- glean.provenance: per-line ownership for the combined (base...target) view.
--
-- Every surviving new line in the net diff was last written by exactly one
-- commit. `git blame -p` on the target post-image gives, for each final line,
-- the owning commit sha and that line's number *in the owning commit's
-- post-image* (the immutable addressing basis used by the ReviewStore). Pure
-- parsing lives here; the git invocation is injected by the caller.
local M = {}

-- Parse `git blame -p` porcelain output into a map
--   final_lnum -> { sha = <40hex>, orig_lnum = <int> }
-- where final_lnum is the line number in the blamed (target) file and orig_lnum
-- is its line number in the owning commit. Metadata and TAB-prefixed content
-- lines are ignored; only the `<sha> <orig> <final> [<count>]` headers match.
function M.parse_blame(text)
  local map = {}
  for line in (text .. "\n"):gmatch("(.-)\n") do
    local sha, orig, final = line:match("^(%x+) (%d+) (%d+)")
    if sha and #sha >= 7 then
      map[tonumber(final)] = { sha = sha, orig_lnum = tonumber(orig) }
    end
  end
  return map
end

-- The all-zero sha `git blame` assigns to working-tree lines that are "Not
-- Committed Yet". The combined work-tree overlay rewrites this to the floating
-- commit id so uncommitted lines route to the content-hash adapter.
M.ZERO_SHA = "0000000000000000000000000000000000000000"

-- Rewrite every all-zero (uncommitted) sha in a parsed blame map to `id`.
function M.map_zero_sha(map, id)
  for _, p in pairs(map) do
    if p.sha:match("^0+$") then p.sha = id end
  end
  return map
end

return M
