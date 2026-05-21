-- Load the IPC module for command line tool support
require("hs.ipc")

-- Install the CLI tool
hs.ipc.cliInstall()

-- Basic configuration
hs.window.animationDuration = 0

-- Reload configuration hotkey
hs.hotkey.bind({ "cmd", "alt", "ctrl" }, "R", function()
  hs.reload()
end)

hs.alert.show("Config loaded")


-- Window management helpers
local TOLERANCE = 20

local function isApprox(a, b)
  return math.abs(a - b) <= TOLERANCE
end

local function isLeftHalf(win, screen)
  local f = win:frame()
  local s = screen:frame()
  return isApprox(f.x, s.x) and isApprox(f.y, s.y) and isApprox(f.w, s.w / 2) and isApprox(f.h, s.h)
end

local function isRightHalf(win, screen)
  local f = win:frame()
  local s = screen:frame()
  return isApprox(f.x, s.x + s.w / 2) and isApprox(f.y, s.y) and isApprox(f.w, s.w / 2) and isApprox(f.h, s.h)
end

local function moveToLeftHalf(win, screen)
  win:moveToScreen(screen)
  local s = screen:frame()
  win:setFrame({ x = s.x, y = s.y, w = s.w / 2, h = s.h })
end

local function moveToRightHalf(win, screen)
  win:moveToScreen(screen)
  local s = screen:frame()
  win:setFrame({ x = s.x + s.w / 2, y = s.y, w = s.w / 2, h = s.h })
end

hs.hotkey.bind({ "cmd", "alt" }, "h", function()
  local win = hs.window.focusedWindow()
  if not win then return end

  local currentScreen = win:screen()
  local westScreen = currentScreen:toWest()

  if isLeftHalf(win, currentScreen) and westScreen then
    moveToRightHalf(win, westScreen)
  else
    moveToLeftHalf(win, currentScreen)
  end
end)

hs.hotkey.bind({ "cmd", "alt" }, "l", function()
  local win = hs.window.focusedWindow()
  if not win then return end

  local currentScreen = win:screen()
  local eastScreen = currentScreen:toEast()

  if isRightHalf(win, currentScreen) and eastScreen then
    moveToLeftHalf(win, eastScreen)
  else
    moveToRightHalf(win, currentScreen)
  end
end)

hs.hotkey.bind({ "cmd", "alt" }, "k", function()
  local win = hs.window.focusedWindow()
  if win then
    local screen = win:screen():frame()
    win:setFrame({ x = screen.x, y = screen.y, w = screen.w, h = screen.h })
  end
end)

-- Move focused window to a specific Mission Control space (and follow it).
-- hs.spaces.moveWindowToSpace is broken on macOS Sequoia, so we simulate a
-- title-bar drag while switching spaces — macOS carries the window with us.
local function moveCurrentWindowToSpace(n)
  local win = hs.window.focusedWindow()
  if not win then return end
  local screen = win:screen()
  local spaces = hs.spaces.spacesForScreen(screen)
  if not (spaces and spaces[n]) then
    hs.alert.show("No desktop " .. n)
    return
  end

  local zoom = win:zoomButtonRect()
  if not zoom then return end
  local clickPoint = {
    x = zoom.x + zoom.w + 40,
    y = zoom.y + zoom.h / 2,
  }

  local mouseOrigin = hs.mouse.absolutePosition()
  hs.eventtap.event.newMouseEvent(hs.eventtap.event.types.leftMouseDown, clickPoint):post()
  hs.timer.usleep(50000)
  hs.spaces.gotoSpace(spaces[n])
  hs.timer.doAfter(0.6, function()
    hs.eventtap.event.newMouseEvent(hs.eventtap.event.types.leftMouseUp, clickPoint):post()
    hs.mouse.absolutePosition(mouseOrigin)
  end)
end

hs.hotkey.bind({ "cmd", "shift" }, "1", function() moveCurrentWindowToSpace(1) end)
hs.hotkey.bind({ "cmd", "shift" }, "2", function() moveCurrentWindowToSpace(2) end)
-- Fuzzy matching function
local function fuzzyMatch(str, pattern)
  if pattern == "" then return true end

  local strLower = string.lower(str)
  local patternLower = string.lower(pattern)

  local strIdx = 1
  local patternIdx = 1

  while strIdx <= #strLower and patternIdx <= #patternLower do
    if string.sub(strLower, strIdx, strIdx) == string.sub(patternLower, patternIdx, patternIdx) then
      patternIdx = patternIdx + 1
    end
    strIdx = strIdx + 1
  end

  return patternIdx > #patternLower
end

-- Track tab focus times for sorting
local tabFocusTimes = {}

local function makeTabKey(windowId, tabIndex)
  return string.format("%d:%d", windowId, tabIndex)
end

-- Create window filter once for better performance
local ghosttyWindowFilter = hs.window.filter.new(false):setAppFilter("Ghostty")

-- Chooser-based Ghostty tab switcher
local allGhosttyTabs = {}

local ghosttyChooser = hs.chooser.new(function(choice)
  if not choice then return end
  local tabKey = makeTabKey(choice.windowId, choice.tabIndex)
  tabFocusTimes[tabKey] = os.time()
  selectGhosttyTab(choice.windowId, choice.tabIndex)
end)

ghosttyChooser:queryChangedCallback(function(query)
  if query == "" then
    ghosttyChooser:choices(allGhosttyTabs)
    return
  end

  local filtered = {}
  for _, choice in ipairs(allGhosttyTabs) do
    local searchText = choice.text .. " " .. choice.subText
    if fuzzyMatch(searchText, query) then
      table.insert(filtered, choice)
    end
  end

  ghosttyChooser:choices(filtered)
end)

function showGhosttyChooser()
  local now = os.time()

  -- Get Ghostty app
  local ghostty = hs.application.find("Ghostty")
  if not ghostty then
    hs.alert.show("Ghostty not running")
    return
  end

  -- Get all Ghostty windows (including minimized)
  local allGhosttyWindows = ghostty:allWindows()

  -- Create a map of window IDs to their focus order
  local focusOrder = {}
  for i, window in ipairs(hs.window.orderedWindows()) do
    focusOrder[window:id()] = i
  end

  -- Sort Ghostty windows by focus order (minimized windows will have no order, so put them last)
  table.sort(allGhosttyWindows, function(a, b)
    local orderA = focusOrder[a:id()] or math.huge
    local orderB = focusOrder[b:id()] or math.huge
    return orderA < orderB
  end)

  local sortedWindows = allGhosttyWindows

  if #sortedWindows == 0 then
    hs.alert.show("No Ghostty windows found")
    return
  end

  allGhosttyTabs = {}

  -- First pass: collect all windows and their tabs
  local windowsToShow = {}     -- Array of {windowId, tabs=[...]}
  local childWindowTitles = {} -- Set of window titles that are children/tabs
  local parentWindows = {}     -- Set of window IDs that have tab groups

  -- Iterate through windows in focus order
  for _, window in ipairs(sortedWindows) do
    local windowId = window:id()
    local windowTitle = window:title()

    -- Get tabs for this window
    local success, windowTabs = pcall(function()
      local tabs = {}
      local axWindow = hs.axuielement.windowElement(window)

      if axWindow then
        local children = axWindow:attributeValue("AXChildren")
        local foundTabGroup = false

        if children then
          for _, child in ipairs(children) do
            if child:attributeValue("AXRole") == "AXTabGroup" then
              foundTabGroup = true
              local axTabs = child:attributeValue("AXChildren")

              if axTabs then
                parentWindows[windowId] = true

                for j, tab in ipairs(axTabs) do
                  local tabTitle = tab:attributeValue("AXTitle")
                  local tabSelected = tab:attributeValue("AXSelected")

                  if tabTitle then
                    -- Mark this tab title as a child so we can filter out matching windows
                    childWindowTitles[tabTitle] = true
                    local tabKey = makeTabKey(windowId, j)
                    local focusTime = tabFocusTimes[tabKey] or 0

                    -- Currently selected tabs get a recent time boost
                    if tabSelected then
                      tabFocusTimes[tabKey] = now
                      focusTime = now
                    end

                    table.insert(tabs, {
                      text = tabTitle,
                      subText = string.format("Window: %s | Tab %d", windowTitle, j),
                      windowId = windowId,
                      tabIndex = j,
                      focusTime = focusTime,
                    })
                  end
                end
              end
              break
            end
          end
        end

        -- If no tab group found, treat the window as a single tab
        if not foundTabGroup then
          local tabKey = makeTabKey(windowId, 1)
          tabFocusTimes[tabKey] = now

          table.insert(tabs, {
            text = windowTitle,
            subText = string.format("Window: %s | Tab 1", windowTitle),
            windowId = windowId,
            tabIndex = 1,
            focusTime = now,
          })
        end
      end

      return tabs
    end)

    -- Store window info for second pass
    if success and windowTabs and #windowTabs > 0 then
      -- Sort tabs within this window by focus time
      table.sort(windowTabs, function(a, b)
        return a.focusTime > b.focusTime
      end)

      table.insert(windowsToShow, {
        windowId = windowId,
        windowTitle = windowTitle,
        tabs = windowTabs,
      })
    end
  end

  -- Second pass: filter out child windows and build final list
  for _, windowInfo in ipairs(windowsToShow) do
    -- Skip if this window is a parent (has tab group) but all its tabs are also individual windows
    -- OR if this window's title matches a child tab title
    local isParent = parentWindows[windowInfo.windowId]
    local titleIsChild = false

    -- Check if any tab in this window has a title that's marked as a child
    for _, tab in ipairs(windowInfo.tabs) do
      if childWindowTitles[tab.text] then
        titleIsChild = true
        break
      end
    end

    if isParent then
      -- This is a parent window with tab group - include it
      for _, tab in ipairs(windowInfo.tabs) do
        table.insert(allGhosttyTabs, tab)
      end
    elseif not titleIsChild then
      -- This is a standalone window that isn't a child tab - include it
      for _, tab in ipairs(windowInfo.tabs) do
        table.insert(allGhosttyTabs, tab)
      end
    end
  end

  if #allGhosttyTabs == 0 then
    hs.alert.show("No Ghostty tabs found")
    return
  end

  ghosttyChooser:choices(allGhosttyTabs)
  ghosttyChooser:show()
end

-- Bind hotkey for chooser-based tab switcher
hs.hotkey.bind({ "cmd" }, "p", function()
  showGhosttyChooser()
end)

-- Select a specific Ghostty tab
function selectGhosttyTab(windowId, tabIndex)
  local ghostty = hs.application.find("Ghostty")
  if not ghostty then
    return false
  end

  -- Find the window by ID
  local targetWindow = nil
  for _, window in ipairs(ghostty:allWindows()) do
    if window:id() == windowId then
      targetWindow = window
      break
    end
  end

  if not targetWindow then
    return false
  end

  -- Focus the window first
  targetWindow:focus()

  -- Find and click the tab (if there's a tab group)
  local success, result = pcall(function()
    local axWindow = hs.axuielement.windowElement(targetWindow)
    if axWindow then
      local children = axWindow:attributeValue("AXChildren")
      local foundTabGroup = false

      if children then
        for _, child in ipairs(children) do
          local role = child:attributeValue("AXRole")
          if role == "AXTabGroup" then
            foundTabGroup = true
            local tabs = child:attributeValue("AXChildren")
            if tabs and tabs[tabIndex] then
              -- Click the tab
              tabs[tabIndex]:performAction("AXPress")
              return true
            end
            break
          end
        end
      end

      -- If no tab group found, this is a single-tab window
      -- Just focusing the window is sufficient
      if not foundTabGroup then
        return true
      end
    end
    return false
  end)

  if success and result then
    return true
  else
    return false
  end
end

-- Window switching across visible (and minimized) windows on the current space.
-- Called from scripts/pane-nav via `hs -c "switchWindow('left'|'right')"`.
-- Cycles through visible windows sorted by their left x-coord; when at the edge,
-- starts unminimizing windows on the same space so they re-enter the cycle.

local function windowSortKey(a, b)
  local fa, fb = a:frame(), b:frame()
  if math.abs(fa.x - fb.x) > 1 then return fa.x < fb.x end
  return fa.y < fb.y
end

function switchWindow(direction)
  local currentSpace = hs.spaces.focusedSpace()
  if not currentSpace then return end

  -- One fast call instead of hs.spaces.windowSpaces(win) per window.
  local idsOnSpace = {}
  for _, id in ipairs(hs.spaces.windowsForSpace(currentSpace) or {}) do
    idsOnSpace[id] = true
  end

  -- Single pass through allWindows. Categorize by visible vs minimized,
  -- and track which apps have a visible window on this space (used to
  -- claim minimized windows whose space membership is unreliable).
  local visible = {}
  local minimizedOnSpace = {}
  local minimizedMaybe = {}
  local appsOnSpace = {}
  for _, win in ipairs(hs.window.allWindows()) do
    if win:isStandard() then
      local onSpace = idsOnSpace[win:id()]
      if win:isMinimized() then
        if onSpace then
          table.insert(minimizedOnSpace, win)
        else
          table.insert(minimizedMaybe, win)
        end
      elseif onSpace then
        table.insert(visible, win)
        local app = win:application()
        if app then appsOnSpace[app:pid()] = true end
      end
    end
  end

  local minimized = minimizedOnSpace
  for _, win in ipairs(minimizedMaybe) do
    local app = win:application()
    if app and appsOnSpace[app:pid()] then
      table.insert(minimized, win)
    end
  end

  table.sort(visible, windowSortKey)
  table.sort(minimized, windowSortKey)

  local focused = hs.window.focusedWindow()
  local currentIdx = nil
  if focused then
    for i, w in ipairs(visible) do
      if w:id() == focused:id() then currentIdx = i; break end
    end
  end

  local function restoreMinimized(pickLast)
    if #minimized == 0 then return false end
    local target = pickLast and minimized[#minimized] or minimized[1]
    target:unminimize()
    target:focus()
    return true
  end

  if direction == "left" then
    if currentIdx and currentIdx > 1 then
      visible[currentIdx - 1]:focus()
    elseif not currentIdx and #visible > 0 then
      visible[#visible]:focus()
    else
      restoreMinimized(true)
    end
  elseif direction == "right" then
    if currentIdx and currentIdx < #visible then
      visible[currentIdx + 1]:focus()
    elseif not currentIdx and #visible > 0 then
      visible[1]:focus()
    else
      restoreMinimized(false)
    end
  end
end

-- Global C-h / C-l for switching between macOS windows.
-- Skips Ghostty so tmux/nvim can handle it locally and escalate back
-- via pane-nav when at the edge.
local paneNavKeyTap
paneNavKeyTap = hs.eventtap.new({ hs.eventtap.event.types.keyDown }, function(e)
  local flags = e:getFlags()
  if not flags.ctrl or flags.cmd or flags.alt or flags.shift or flags.fn then
    return false
  end
  local key = hs.keycodes.map[e:getKeyCode()]
  if key ~= "h" and key ~= "l" then
    return false
  end
  local app = hs.application.frontmostApplication()
  if app and app:name() == "Ghostty" then
    return false
  end
  -- Defer so the callback returns immediately; macOS kills slow taps.
  hs.timer.doAfter(0, function()
    switchWindow(key == "h" and "left" or "right")
  end)
  return true
end)
paneNavKeyTap:start()

-- If macOS disables the tap (slow callback, sleep, etc.), re-enable it.
hs.timer.doEvery(5, function()
  if paneNavKeyTap and not paneNavKeyTap:isEnabled() then
    paneNavKeyTap:start()
  end
end)
-- Pane-nav signal bridge for dev containers. The container's pane-nav script
-- can't call the `hs` CLI, so it appends tokens ("left"/"right") to a file
-- under the shared mount. We track the last byte we read so reloads don't
-- replay history, and reset to 0 if the file shrinks (was truncated).
local paneNavSignalFile = os.getenv("HOME") .. "/dev-in-docker-shared-files/pane-nav-signal"
local paneNavLastPos = 0
do
  local attrs = hs.fs.attributes(paneNavSignalFile)
  if attrs then paneNavLastPos = attrs.size end
end

local function processPaneNavSignal()
  local attrs = hs.fs.attributes(paneNavSignalFile)
  if not attrs then return end
  if attrs.size < paneNavLastPos then paneNavLastPos = 0 end
  local f = io.open(paneNavSignalFile, "r")
  if not f then return end
  f:seek("set", paneNavLastPos)
  for line in f:lines() do
    local token = line:match("(%S+)")
    if token == "left" or token == "right" then
      switchWindow(token)
    end
  end
  paneNavLastPos = f:seek()
  f:close()
end

local paneNavWatcher
do
  local dir = os.getenv("HOME") .. "/dev-in-docker-shared-files"
  if hs.fs.attributes(dir) then
    paneNavWatcher = hs.pathwatcher.new(dir, function(paths)
      for _, p in ipairs(paths) do
        if p:match("pane%-nav%-signal$") then
          processPaneNavSignal()
          return
        end
      end
    end):start()
  end
end

-- Command palette
local function handleApp(name)
  local app = hs.application.find(name)
  if not app then
    hs.application.launchOrFocus(name)
    return
  end
  for _, win in ipairs(app:allWindows()) do
    if win:isMinimized() then
      win:unminimize()
    end
  end
  app:activate()
end

local function handleAppOnCurrentDesktop(name)
  local app = hs.application.find(name)

  if app then
    local currentSpace = hs.spaces.focusedSpace()
    for _, win in ipairs(app:allWindows()) do
      local winSpaces = hs.spaces.windowSpaces(win) or {}
      for _, sp in ipairs(winSpaces) do
        if sp == currentSpace then
          if win:isMinimized() then
            win:unminimize()
          end
          win:focus()
          return
        end
      end
    end
  end

  hs.application.launchOrFocus(name)
end

local function handleGhostty()
  handleAppOnCurrentDesktop("Ghostty")
end

local function openSpotlight()
  hs.application.launchOrFocus("/System/Library/CoreServices/Spotlight.app")
end

local function openInChrome(url)
  hs.task.new("/usr/bin/open", nil, { "-a", "Google Chrome", url }):start()
end

local commandPaletteItems = {
  {
    text = "ghostty",
    subText = "Ghostty on current desktop",
    handler = handleGhostty,
  },
  {
    text = "slack",
    subText = "Switch to Slack",
    handler = function() handleApp("Slack") end,
  },
  {
    text = "chrome",
    subText = "Switch to Chrome",
    handler = function() handleApp("Google Chrome") end,
  },
  {
    text = "firefox",
    subText = "Switch to Firefox",
    handler = function() handleApp("Firefox") end,
  },
  {
    text = "1password",
    subText = "Switch to 1Password",
    handler = function() handleAppOnCurrentDesktop("1Password") end,
  },
  {
    text = "activity monitor",
    subText = "Switch to Activity Monitor",
    handler = function() handleAppOnCurrentDesktop("Activity Monitor") end,
  },
  {
    text = "spotlight",
    subText = "Open Spotlight",
    handler = openSpotlight,
  },
  {
    text = "aurelia",
    subText = "github.com/benchling/aurelia/pulls",
    handler = function() openInChrome("https://github.com/benchling/aurelia/pulls") end,
  },
  {
    text = "infra",
    subText = "github.com/benchling/infra/pulls",
    handler = function() openInChrome("https://github.com/benchling/infra/pulls") end,
  },
  {
    text = "confluence",
    subText = "Search Confluence",
    handler = function() openInChrome("https://benchling.atlassian.net/wiki/search?text=") end,
  },
  {
    text = "jira",
    subText = "Jira For You",
    handler = function() openInChrome("https://benchling.atlassian.net/jira/for-you") end,
  },
}

local function buildCommandPaletteChoices()
  local choices = {}
  for i, item in ipairs(commandPaletteItems) do
    table.insert(choices, {
      text = item.text,
      subText = item.subText,
      itemIndex = i,
    })
  end
  return choices
end

local commandPaletteChooser = hs.chooser.new(function(choice)
  if not choice then return end
  local item = commandPaletteItems[choice.itemIndex]
  if item then
    item.handler()
  end
end)

commandPaletteChooser:queryChangedCallback(function(query)
  local allChoices = buildCommandPaletteChoices()
  if query == "" then
    commandPaletteChooser:choices(allChoices)
    return
  end

  local filtered = {}
  for _, choice in ipairs(allChoices) do
    if fuzzyMatch(choice.text .. " " .. choice.subText, query) then
      table.insert(filtered, choice)
    end
  end
  commandPaletteChooser:choices(filtered)
end)

hs.hotkey.bind({ "cmd" }, "space", function()
  commandPaletteChooser:choices(buildCommandPaletteChoices())
  commandPaletteChooser:show()
end)

-- Drag lock: F19 toggles left mouse button held state.
-- ESC or right/middle click also releases.
local dragLocked = false
local dragTap = nil
local dragKillTap = nil

local function stopDragLock()
  if not dragLocked then return end
  local types = hs.eventtap.event.types
  local pos = hs.mouse.absolutePosition()
  hs.eventtap.event.newMouseEvent(types.leftMouseUp, pos):post()
  dragLocked = false
  if dragTap then dragTap:stop(); dragTap = nil end
  if dragKillTap then dragKillTap:stop(); dragKillTap = nil end
  hs.alert.show("drag lock off", 0.5)
end

local function startDragLock()
  if dragLocked then return end
  local types = hs.eventtap.event.types
  local pos = hs.mouse.absolutePosition()
  hs.eventtap.event.newMouseEvent(types.leftMouseDown, pos):post()
  dragLocked = true
  hs.alert.show("drag lock on", 0.5)

  -- Rewrite subsequent mouse moves as drags so apps see a real drag gesture
  dragTap = hs.eventtap.new({ types.mouseMoved }, function(e)
    e:setType(types.leftMouseDragged)
    return false
  end)
  dragTap:start()

  dragKillTap = hs.eventtap.new({
    types.keyDown,
    types.rightMouseDown,
    types.otherMouseDown,
  }, function(e)
    if e:getType() == types.keyDown and e:getKeyCode() ~= hs.keycodes.map.escape then
      return false
    end
    stopDragLock()
    return false
  end)
  dragKillTap:start()
end

local function toggleDragLock()
  if dragLocked then stopDragLock() else startDragLock() end
end

hs.hotkey.bind({}, "F19", toggleDragLock)

-- Scroll lock: F20 toggles 2D scroll mode (trackball motion → scroll wheel events)
local SCROLL_GAIN = 1.0  -- linear scroll per delta unit; controls low-end speed
local SCROLL_ACCEL = 0.05 -- multiplier on the accel term; controls high-end boost
local SCROLL_EXP = 2.0   -- accel exponent; >1 = larger sweeps amplify proportionally

local function accel(d)
  if d == 0 then return 0 end
  local sign = d > 0 and 1 or -1
  local abs_d = math.abs(d)
  return sign * (abs_d * SCROLL_GAIN + abs_d ^ SCROLL_EXP * SCROLL_ACCEL)
end

local scrollLocked = false
local scrollTap = nil
local scrollKillTap = nil
local accX, accY = 0, 0  -- accumulators for fractional deltas

local function stopScrollLock()
  if not scrollLocked then return end
  scrollLocked = false
  if scrollTap then scrollTap:stop(); scrollTap = nil end
  if scrollKillTap then scrollKillTap:stop(); scrollKillTap = nil end
  hs.alert.show("scroll lock off", 0.5)
end

local function startScrollLock()
  if scrollLocked then return end
  local types = hs.eventtap.event.types
  local props = hs.eventtap.event.properties

  scrollLocked = true
  accX, accY = 0, 0
  hs.alert.show("scroll lock on", 0.5)

  scrollTap = hs.eventtap.new({ types.mouseMoved }, function(e)
    local dx = e:getProperty(props.mouseEventDeltaX)
    local dy = e:getProperty(props.mouseEventDeltaY)
    -- Accumulate, then emit only the integer part (keeps fractions for next tick)
    accX = accX + accel(dx)
    accY = accY + accel(dy)
    local intX, fracX = math.modf(accX)
    local intY, fracY = math.modf(accY)
    accX, accY = fracX, fracY
    if intX ~= 0 or intY ~= 0 then
      -- Negate so direction matches natural scrolling. Flip signs if backwards.
      hs.eventtap.event.newScrollEvent({ -intX, -intY }, {}, "pixel"):post()
    end
    return true -- consume the mouseMoved so the cursor doesn't drift while scrolling
  end)
  scrollTap:start()

  -- ESC or any mouse button click cancels scroll lock (event still passes through)
  scrollKillTap = hs.eventtap.new({
    types.keyDown,
    types.leftMouseDown,
    types.rightMouseDown,
    types.otherMouseDown,
  }, function(e)
    if e:getType() == types.keyDown and e:getKeyCode() ~= hs.keycodes.map.escape then
      return false
    end
    stopScrollLock()
    return false
  end)
  scrollKillTap:start()
end

local function toggleScrollLock()
  if scrollLocked then stopScrollLock() else startScrollLock() end
end

hs.hotkey.bind({}, "F20", toggleScrollLock)
