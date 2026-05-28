# context

Replace the existing window management system with a linear left-to-right ordering model.

Currently `shift-cmd-h`, `shift-cmd-l`, `shift-cmd-k` move windows by setting absolute screen frames (left half, right half, full screen). Multiple windows end up with identical corner coordinates, producing unexpected focus and visibility behavior.

In the new model, each macOS Space has a linear ordered list of windows, each marked as `half` (1 unit) or `full` (2 units). The display is a contiguous "slice" of this list, rendered across the available physical monitors. The slice always contains the focused window. Windows outside the slice are moved off-screen.

## Concepts

- **Order**: per-space ordered list of window IDs.
- **Size**: `half` (occupies one side of a monitor) or `full` (occupies a whole monitor).
- **Virtual monitor**: a conceptual unit = 1 full window OR 2 halves. Windows pack greedily into virtual monitors.
- **Slice**: range of virtual monitors actually rendered. Slice length = number of physical monitors.
- **Hidden window**: a window outside the slice. Moved off-screen (negative coordinates) so it doesn't cover other windows. Stays "open" and reachable via cmd-tab / dock click.

## Layout algorithm

Pack windows greedily into virtual monitors. Maintain `cursor = {monitorIdx, side}` starting at `{0, "left"}`:

- half at `left`: place at left of `monitorIdx`. Cursor → `{monitorIdx, "right"}`.
- half at `right`: place at right of `monitorIdx`. Cursor → `{monitorIdx+1, "left"}`.
- full at `left`: place as full of `monitorIdx`. Cursor → `{monitorIdx+1, "left"}`.
- full at `right`: leave right slot empty; place full at `monitorIdx+1`. Cursor → `{monitorIdx+2, "left"}`.

Each window gets a position record `{monitorIdx, side}` where side ∈ {"left", "right", "full"}.

The slice is **sticky**: it only scrolls when focus moves off the currently-shown page. Per-space we cache `shownMonitors = {minIdx, maxIdx}` (an inclusive range).

On each `applyLayout`:

1. Compute `positions` and `totalMonitors`. Slice size `S = min(N_physical, totalMonitors)`.
2. If no cached slice (first run, or window count changed so that the cached range is now invalid): seed by left-bias — `minIdx = max(0, F - S + 1)`, `maxIdx = minIdx + S - 1`, then clamp `maxIdx` to `totalMonitors - 1` and adjust `minIdx` so the slice has length `S`.
3. Otherwise:
   - If `F > maxIdx`: shift slice right so `maxIdx = F`, `minIdx = F - S + 1`.
   - If `F < minIdx`: shift slice left so `minIdx = F`, `maxIdx = F + S - 1`.
   - Otherwise: keep cached slice unchanged.
4. Clamp the final range against `[0, totalMonitors - 1]` (in case total shrank).
5. Cache the resulting `{minIdx, maxIdx}` back into state.

Map shown virtual monitors to physical monitors left-to-right: smallest virtual-monitor index → leftmost physical screen.

For each window:
- If its monitorIdx is in slice: unminimize if minimized; set frame on the mapped physical monitor (left half / right half / full).
- Otherwise: unminimize if minimized; set frame to off-screen position (e.g. `{x = -10000, y = -10000, w = 800, h = 600}`).

## Bindings

- `cmd-h` / `cmd-l`: move focus to previous / next window in the order. Re-layout.
- `shift-cmd-h` / `shift-cmd-l`: swap focused window with previous / next neighbor; set focused window's size to half. Re-layout.
- `shift-cmd-k`: toggle focused window's size (half ↔ full). Re-layout.

At order boundaries, focus and swap operations are no-ops on the move (but shift-cmd-h/l still set size to half).

## Events

- Space change → re-layout for the new focused space.
- Window created → insert after focused window in current space's order (size = half); re-layout.
- Window destroyed → remove from all stored space states.
- Window focused (e.g. via mouse, cmd-tab) → if focused window not in slice, re-layout.

Suppress event-driven re-layout while `applyLayout` is mutating frames (otherwise we get feedback loops).

## State initialization

State is in-memory only. On hammerspoon reload it's empty. The first time `applyLayout` runs for a space:

- Collect all standard windows on the space.
- Sort by current `frame.x`.
- Infer size: `full` if `frame.w > screen.w * 0.75`, else `half`.

After that the order is sticky and only mutated by user actions and window create/destroy.

## Relevant files

- `/Users/denis.lantsman/src/dotfiles/hammerspoon/init.lua`: single hammerspoon config.
  - `TOLERANCE`, `isApprox`, `isLeftHalf`, `isRightHalf`, `moveToLeftHalf`, `moveToRightHalf`: geometry helpers to **delete**.
  - existing `shift-cmd-h/l/k` bindings: **delete**.
  - `windowSortKey`, `switchWindow`, existing `cmd-h/cmd-l` bindings: **delete**.
  - Command palette, ghostty chooser, drag-lock, scroll-lock: leave untouched.

## Hammerspoon API notes

- `hs.spaces.focusedSpace()` → integer space ID.
- `hs.spaces.windowsForSpace(spaceId)` → list of window IDs on that space.
- `hs.spaces.watcher.new(cb):start()` → fires when active space changes.
- `hs.window.filter.new()` → all standard windows; supports `:subscribe(events, cb)`.
- `hs.screen.allScreens()` → sort by `frame.x` to get physical left-to-right order.
- `hs.window:setFrame`, `:focus`, `:minimize`, `:unminimize`, `:isMinimized`, `:isStandard`, `:id`, `:frame`, `:screen`.

# implementation

- [ ] Add data model and helpers at the top of the window management section
  - `windowState = {}` (map: spaceId → `{order = {winId, ...}, sizes = {[winId] = "half"|"full"}}`)
  - `suppressEvents = false`
  - `getStandardWindowsOnSpace(spaceId)`: return list of `hs.window` objects on the space that are standard.
  - `initSpaceState(spaceId)`: sort windows by `frame().x`, infer size from current width vs screen width, build the table.
  - `ensureSpaceState(spaceId)`: lazy init.
  - `getOrderIndex(state, winId)`: return index of `winId` in `state.order` or nil.
  - `insertAfterFocused(state, winId, focusedId)`: insert `winId` immediately after `focusedId` (or at end if not found).
  - `removeFromState(state, winId)`: drop from order and sizes.

- [ ] Implement layout computation as a pure function
  - `computePositions(order, sizes)` → list of `{monitorIdx, side}` parallel to `order`. Implements the greedy packer described above. Also returns `totalMonitors` (max monitorIdx + 1 reached).
  - `computeSlice(focusedMonIdx, totalMonitors, numPhysicalMonitors)` → set of monitor indices to display. Uses the left-then-right extension loop.
  - Both are unit-testable; sanity check by running in `hs.console`:
    - Behavior: 3 halves packs into monitors `[0,0,1]` with sides `[left, right, left]`.
    - Setup: `order = {1,2,3}`, `sizes = {[1]="half",[2]="half",[3]="half"}`.
    - Actions: call `computePositions`.
    - Expected output: `{{0,"left"},{0,"right"},{1,"left"}}`, totalMonitors = 2.
    - Behavior: half-then-full advances past the right slot.
    - Setup: `order = {1,2}`, `sizes = {[1]="half",[2]="full"}`.
    - Actions: call `computePositions`.
    - Expected output: `{{0,"left"},{1,"full"}}` — second monitor's right slot is implicitly empty.
    - Behavior: slice with focused on left edge prefers extending right.
    - Setup: focused monitor = 0, total = 3, physical = 2.
    - Actions: call `computeSlice`.
    - Expected output: `{0, 1}`.
    - Behavior: slice with focused at right edge extends left.
    - Setup: focused monitor = 2, total = 3, physical = 2.
    - Actions: call `computeSlice`.
    - Expected output: `{1, 2}`.

- [ ] Implement `applyLayout(spaceId)`
  - Set `suppressEvents = true` for the duration.
  - Ensure space state exists.
  - Determine focused window. If focused window's space is the target space but the window isn't in `state.order`, append it (size = half).
  - Run `computePositions` → positions array.
  - Determine `focusedMonIdx` from focused window's position. If no focused window in this space, default to 0.
  - Compute `slice` and sort it ascending.
  - Get physical screens sorted by `frame().x`. Map each slice element to one physical screen, by index.
  - For each window in `order`:
    - If its `monitorIdx` ∈ slice: compute target frame from the mapped screen and side (`left` / `right` / `full`); unminimize if minimized; setFrame.
    - Otherwise: unminimize if minimized; setFrame to off-screen `{x = -10000, y = -10000, w = 800, h = 600}`.
  - Restore `suppressEvents = false`.
  - Manual verification:
    - Behavior: 3 half windows with 1 physical monitor, focused on first → first two windows visible, third off-screen.
    - Setup: spin up 3 ghostty windows, mark all as half in the inferred state, ensure they live on the same space.
    - Actions: focus window 1, call `applyLayout`.
    - Expected output: window 1 occupies left half, window 2 occupies right half, window 3 is off-screen.
    - Behavior: focusing window 3 scrolls the slice right.
    - Setup: same starting state.
    - Actions: focus window 3 (via order index 2), call `applyLayout`.
    - Expected output: window 2 left half, window 3 right half, window 1 off-screen.

- [ ] Implement user-facing operations
  - `moveFocus(direction)`:
    1. Get current space + state + focused window.
    2. Find focused index in order; compute target index = idx ± 1.
    3. If out of range: no-op.
    4. Get target window; if minimized, unminimize.
    5. Focus target.
    6. Call `applyLayout`.
  - `swapWindow(direction)`:
    1. Get current state + focused index `i`.
    2. Compute target index `j = i ± 1`.
    3. Always set `sizes[focusedId] = "half"`.
    4. If `j` is in range: swap `order[i]` and `order[j]`.
    5. Call `applyLayout`.
  - `toggleSize()`:
    1. Get current state + focused window id.
    2. Flip `sizes[id]` between `"half"` and `"full"`.
    3. Call `applyLayout`.

- [ ] Delete the old code and bind the new operations
  - Remove `TOLERANCE`, `isApprox`, `isLeftHalf`, `isRightHalf`, `moveToLeftHalf`, `moveToRightHalf`, the old `shift-cmd-h/l/k` bindings, `windowSortKey`, `switchWindow`, the old `cmd-h/cmd-l` bindings.
  - Bind:
    - `cmd-h` → `moveFocus("left")`
    - `cmd-l` → `moveFocus("right")`
    - `shift-cmd-h` → `swapWindow("left")`
    - `shift-cmd-l` → `swapWindow("right")`
    - `shift-cmd-k` → `toggleSize()`

- [ ] Wire up events (with `suppressEvents` guard)
  - `hs.spaces.watcher.new(function() if not suppressEvents then applyLayout(hs.spaces.focusedSpace()) end end):start()`
  - One `hs.window.filter.new()` subscribed to:
    - `windowCreated`: ensure state for current space; insert new window id after focused id in order (size = half); applyLayout.
    - `windowDestroyed`: iterate all stored space states and remove the window id from each.
    - `windowFocused`: if focused window's monitorIdx not in current slice (i.e. would be hidden, currently off-screen), applyLayout. Skip if it's already on-screen to avoid thrash.
  - All callbacks early-return when `suppressEvents` is true.

- [ ] Manual end-to-end verification
  - Behavior: focus cycling across linear order on a single monitor.
    - Setup: open 3 windows; cmd-h until you reach the leftmost.
    - Actions: press cmd-l twice.
    - Expected output: focus walks W1 → W2 → W3; at each step the displayed pair updates so the focused window is always visible.
  - Behavior: shift-cmd-l reorders and halves.
    - Setup: 3 half windows on 1 monitor, focused on W1.
    - Actions: shift-cmd-l once.
    - Expected output: order becomes `[W2, W1, W3]`; W1 still focused; layout updates.
  - Behavior: shift-cmd-k toggles size.
    - Setup: 3 half windows, focused on W2.
    - Actions: shift-cmd-k.
    - Expected output: W2 becomes full; W1 and W3 are off-screen (single monitor) or one of them is visible on the second monitor (dual monitor).
  - Behavior: dual-monitor shows three half windows simultaneously.
    - Setup: 3 half windows, 2 physical monitors.
    - Actions: focus any of the three.
    - Expected output: monitor 0 shows W1 left + W2 right; monitor 1 shows W3 left + empty right.
  - Behavior: newly opened app inserts after focused.
    - Setup: order `[W1, W2, W3]`, focused W2.
    - Actions: open a new app.
    - Expected output: new window inserted at index 3 (after W2), focused, slice updated.
