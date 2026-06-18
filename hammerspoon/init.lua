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



-- Stateless window management.
--
-- Move keys (cmd-shift-h / cmd-shift-l) reposition the focused window
-- through half-slots across all monitors (mon0-left, mon0-right,
-- mon1-left, ...). Full windows step between whole monitors.
--
-- Focus keys (cmd-h / cmd-l) walk all windows on the current space
-- sorted by on-screen position (top-left, then bottom-right).
--
-- Size toggle (cmd-shift-k) flips between half and full on whichever
-- monitor the window currently occupies.

local function physicalScreensLeftToRight()
  local screens = {}
  for _, s in ipairs(hs.screen.allScreens()) do table.insert(screens, s) end
  table.sort(screens, function(a, b) return a:frame().x < b:frame().x end)
  return screens
end

local function halfSlots(physScreens)
  local slots = {}
  for _, ps in ipairs(physScreens) do
    local sf = ps:frame()
    table.insert(slots, { x = sf.x, y = sf.y, w = sf.w / 2, h = sf.h })
    table.insert(slots, { x = sf.x + sf.w / 2, y = sf.y, w = sf.w / 2, h = sf.h })
  end
  return slots
end

local function windowMonitorIndex(win, physScreens)
  local f = win:frame()
  local cx = f.x + f.w / 2
  local cy = f.y + f.h / 2
  for i, ps in ipairs(physScreens) do
    local sf = ps:frame()
    if cx >= sf.x and cx < sf.x + sf.w and cy >= sf.y and cy < sf.y + sf.h then
      return i
    end
  end
  return 1
end

local function classifyWindow(win, physScreens)
  local f = win:frame()
  local idx = windowMonitorIndex(win, physScreens)
  local sf = physScreens[idx]:frame()
  if f.w > sf.w * 0.75 then return "full", idx end
  if (f.x + f.w / 2) > (sf.x + sf.w / 2) then return "right", idx end
  return "left", idx
end

local function setWindowFrame(win, frame)
  if win:isMinimized() then return end
  win:setFrame(frame)
end

local function moveFocusedWindow(direction)
  local win = hs.window.focusedWindow()
  if not win or not win:isStandard() then return end
  local physScreens = physicalScreensLeftToRight()
  local N = #physScreens
  if N == 0 then return end
  local kind, monIdx = classifyWindow(win, physScreens)

  if kind == "full" then
    local sf = physScreens[monIdx]:frame()
    if direction == "left" then
      setWindowFrame(win, { x = sf.x, y = sf.y, w = sf.w / 2, h = sf.h })
    else
      setWindowFrame(win, { x = sf.x + sf.w / 2, y = sf.y, w = sf.w / 2, h = sf.h })
    end
    return
  end

  local slots = halfSlots(physScreens)
  local curSlotIdx = (monIdx - 1) * 2 + (kind == "left" and 1 or 2)
  local target = curSlotIdx + (direction == "right" and 1 or -1)
  if target < 1 or target > #slots then return end
  setWindowFrame(win, slots[target])
end

local function toggleSize()
  local win = hs.window.focusedWindow()
  if not win or not win:isStandard() then return end
  local physScreens = physicalScreensLeftToRight()
  local kind, monIdx = classifyWindow(win, physScreens)
  local sf = physScreens[monIdx]:frame()
  if kind == "full" then
    setWindowFrame(win, { x = sf.x, y = sf.y, w = sf.w / 2, h = sf.h })
  else
    setWindowFrame(win, { x = sf.x, y = sf.y, w = sf.w, h = sf.h })
  end
end

local function slotRect(physScreen, side)
  local sf = physScreen:frame()
  if side == "left" then
    return { x = sf.x, y = sf.y, w = sf.w / 2, h = sf.h }
  end
  return { x = sf.x + sf.w / 2, y = sf.y, w = sf.w / 2, h = sf.h }
end

local function frameOverlapsRect(f, r)
  local x1 = math.max(f.x, r.x)
  local y1 = math.max(f.y, r.y)
  local x2 = math.min(f.x + f.w, r.x + r.w)
  local y2 = math.min(f.y + f.h, r.y + r.h)
  if x2 <= x1 or y2 <= y1 then return false end
  return (x2 - x1) * (y2 - y1) > (r.w * r.h * 0.4)
end

local function windowsInSlot(physScreens, monIdx, side, onSpace)
  local rect = slotRect(physScreens[monIdx], side)
  local result = {}
  for _, w in ipairs(hs.window.orderedWindows()) do
    if onSpace[w:id()] and w:isStandard() and not w:isMinimized()
        and frameOverlapsRect(w:frame(), rect) then
      table.insert(result, w)
    end
  end
  return result
end

-- Focus model: each slot is (monitor, side). Moving in a direction
-- advances through slots left-to-right (or right-to-left), skipping
-- empty slots, until we find a window. Past the outermost edge we cycle
-- through stacked windows on the current side.
local function focusNeighbor(direction)
  local win = hs.window.focusedWindow()
  if not win or not win:isStandard() then return end
  local physScreens = physicalScreensLeftToRight()
  local N = #physScreens
  if N == 0 then return end

  local spaceId = hs.spaces.focusedSpace()
  if not spaceId then return end
  local onSpace = {}
  for _, id in ipairs(hs.spaces.windowsForSpace(spaceId) or {}) do onSpace[id] = true end

  local kind, monIdx = classifyWindow(win, physScreens)
  local curSide
  if kind == "full" then
    curSide = (direction == "right") and "right" or "left"
  else
    curSide = kind
  end
  local curSlotIdx = (monIdx - 1) * 2 + (curSide == "left" and 1 or 2)

  local step = (direction == "right") and 1 or -1
  local total = 2 * N
  local t = curSlotIdx + step
  while t >= 1 and t <= total do
    local m = math.floor((t - 1) / 2) + 1
    local s = (((t - 1) % 2) == 0) and "left" or "right"
    local cands = windowsInSlot(physScreens, m, s, onSpace)
    for _, w in ipairs(cands) do
      if w:id() ~= win:id() then
        w:focus()
        return
      end
    end
    t = t + step
  end

  local cands = windowsInSlot(physScreens, monIdx, curSide, onSpace)
  if #cands == 0 then return end
  for i, w in ipairs(cands) do
    if w:id() == win:id() then
      cands[(i % #cands) + 1]:focus()
      return
    end
  end
  cands[1]:focus()
end

hs.hotkey.bind({ "cmd" }, "h", function() focusNeighbor("left") end)
hs.hotkey.bind({ "cmd" }, "l", function() focusNeighbor("right") end)
hs.hotkey.bind({ "cmd", "shift" }, "h", function() moveFocusedWindow("left") end)
hs.hotkey.bind({ "cmd", "shift" }, "l", function() moveFocusedWindow("right") end)
hs.hotkey.bind({ "cmd", "shift" }, "k", toggleSize)
hs.hotkey.bind({ "cmd", "shift" }, "1", function() moveFocusedWindowToDesktop(1) end)
hs.hotkey.bind({ "cmd", "shift" }, "2", function() moveFocusedWindowToDesktop(2) end)

-- Fuzzy scoring (Forrest Smith-style). Returns a numeric score, or nil if
-- the pattern's chars don't all appear in `target` in order.
local FUZZY_FIRST_LETTER = 15
local FUZZY_SEPARATOR = 30
local FUZZY_CAMEL = 30
local FUZZY_SEQUENTIAL = 15
local FUZZY_LEADING = -5
local FUZZY_LEADING_MAX = -15
local FUZZY_UNMATCHED = -1

local function isFuzzySeparator(c)
  return c == " " or c == "_" or c == "-" or c == "." or c == "/"
end

local function fuzzyScore(target, pattern)
  if pattern == nil or pattern == "" then return 0 end
  if target == nil or target == "" then return nil end
  local tLen = #target
  local pLen = #pattern
  if pLen > tLen then return nil end

  local tLower = target:lower()
  local pLower = pattern:lower()

  local score = 0
  local pIdx = 1
  local prevMatched = false
  local prevLower = false
  local prevSeparator = true
  local firstMatchIdx = nil

  for tIdx = 1, tLen do
    local rawT = target:sub(tIdx, tIdx)
    local tChar = tLower:sub(tIdx, tIdx)
    local matched = false

    if pIdx <= pLen and tChar == pLower:sub(pIdx, pIdx) then
      matched = true
      if not firstMatchIdx then
        firstMatchIdx = tIdx
        score = score + math.max(FUZZY_LEADING_MAX, FUZZY_LEADING * (tIdx - 1))
      end
      if tIdx == 1 then score = score + FUZZY_FIRST_LETTER end
      if prevSeparator then score = score + FUZZY_SEPARATOR end
      if prevLower and rawT >= "A" and rawT <= "Z" then score = score + FUZZY_CAMEL end
      if prevMatched then score = score + FUZZY_SEQUENTIAL end
      pIdx = pIdx + 1
    elseif firstMatchIdx then
      score = score + FUZZY_UNMATCHED
    end

    prevMatched = matched
    prevLower = rawT >= "a" and rawT <= "z"
    prevSeparator = isFuzzySeparator(tChar)
  end

  if pIdx <= pLen then return nil end
  return score
end

local function fuzzyScoreFields(text, subText, query)
  local s = fuzzyScore(text, query)
  if s ~= nil then return s end
  local sub = fuzzyScore(subText, query)
  if sub ~= nil then return sub - 20 end
  return nil
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

  local scored = {}
  for _, choice in ipairs(allGhosttyTabs) do
    local s = fuzzyScoreFields(choice.text, choice.subText, query)
    if s then
      table.insert(scored, { choice = choice, score = s })
    end
  end
  table.sort(scored, function(a, b)
    if a.score ~= b.score then return a.score > b.score end
    return (a.choice.focusTime or 0) > (b.choice.focusTime or 0)
  end)

  local filtered = {}
  for _, item in ipairs(scored) do
    table.insert(filtered, item.choice)
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

local function userSpacesOnPrimary()
  local primary = hs.screen.primaryScreen()
  if not primary then return {} end
  local all = hs.spaces.allSpaces() or {}
  local list = all[primary:getUUID()] or {}
  local result = {}
  for _, sid in ipairs(list) do
    if hs.spaces.spaceType(sid) == "user" then table.insert(result, sid) end
  end
  return result
end

local function handleGhosttyOnDesktop(index)
  local spaces = userSpacesOnPrimary()
  local target = spaces[index]
  local ghostty = hs.application.find("Ghostty")

  if target and ghostty then
    for _, win in ipairs(ghostty:allWindows()) do
      for _, sp in ipairs(hs.spaces.windowSpaces(win) or {}) do
        if sp == target then
          hs.spaces.gotoSpace(target)
          if win:isMinimized() then win:unminimize() end
          win:focus()
          return
        end
      end
    end
  end

  if target then hs.spaces.gotoSpace(target) end
  hs.timer.doAfter(target and 0.3 or 0, function()
    hs.application.launchOrFocus("Ghostty")
  end)
end

-- hs.spaces.moveWindowToSpace is broken on macOS 15+, so we drag the window
-- by its titlebar and switch desktops with the cmd+<n> shortcut, which
-- carries the in-flight drag along. This requires "Mission Control > Switch
-- to Desktop N" keyboard shortcuts (bound to cmd+1/cmd+2) in System Settings.
function moveFocusedWindowToDesktop(index)
  local win = hs.window.focusedWindow()
  if not win or not win:isStandard() then return end
  local types = hs.eventtap.event.types
  local f = win:frame()
  local grab = hs.geometry.point(f.x + f.w / 2, f.y + 8)

  hs.eventtap.event.newMouseEvent(types.leftMouseDown, grab):post()
  hs.timer.usleep(40000)
  hs.eventtap.event.newMouseEvent(types.leftMouseDragged, grab):post()
  hs.timer.usleep(40000)
  hs.eventtap.keyStroke({ "cmd" }, tostring(index), 0)
  hs.timer.usleep(300000)
  hs.eventtap.event.newMouseEvent(types.leftMouseUp, hs.mouse.absolutePosition()):post()
end

local function openSpotlight()
  hs.application.launchOrFocus("/System/Library/CoreServices/Spotlight.app")
end

local function openInChrome(url)
  hs.task.new("/usr/bin/open", nil, { "-a", "Google Chrome", url }):start()
end

local function plusEncode(s)
  if not s then return "" end
  s = s:gsub("([^%w%-%._~ ])", function(c) return string.format("%%%02X", string.byte(c)) end)
  s = s:gsub(" ", "+")
  return s
end

-- Preset window layouts. Each layout is a list of placements mapping an app to
-- a region. Regions are expressed against "logical monitors" (left/right) which
-- map to physical monitors when two are present, or to the left/right halves of
-- a single monitor otherwise. `frac` ("full"/"left"/"right") subdivides a
-- logical monitor. Layouts always target the second desktop.
local LAYOUT_DESKTOP = 2

local LAYOUT_APP_NAMES = {
  zoom = "zoom.us",
  slack = "Slack",
  chrome = "Google Chrome",
  term = "Ghostty",
}

local LAYOUTS = {
  zt = {
    { app = "zoom", region = { mon = "left", frac = "full" } },
    { app = "term", region = { mon = "right", frac = "full" } },
  },
  st = {
    { app = "slack", region = { mon = "left", frac = "full" } },
    { app = "term", region = { mon = "right", frac = "full" } },
  },
  zct = {
    { app = "zoom", region = { mon = "left", frac = "full" } },
    { app = "chrome", region = { mon = "right", frac = "left" } },
    { app = "term", region = { mon = "right", frac = "right" } },
  },
  ct = {
    { app = "chrome", region = { mon = "left", frac = "full" } },
    { app = "term", region = { mon = "right", frac = "full" } },
  },
  cst = {
    { app = "chrome", region = { mon = "left", frac = "left" } },
    { app = "slack", region = { mon = "left", frac = "right" } },
    { app = "term", region = { mon = "right", frac = "full" } },
  },
  sct = {
    { app = "slack", region = { mon = "left", frac = "left" } },
    { app = "chrome", region = { mon = "left", frac = "right" } },
    { app = "term", region = { mon = "right", frac = "full" } },
  },
}

local function logicalMonitors()
  local screens = physicalScreensLeftToRight()
  if #screens == 0 then return nil end
  if #screens >= 2 then
    return { left = screens[1]:frame(), right = screens[2]:frame() }
  end
  local sf = screens[1]:frame()
  return {
    left = { x = sf.x, y = sf.y, w = sf.w / 2, h = sf.h },
    right = { x = sf.x + sf.w / 2, y = sf.y, w = sf.w / 2, h = sf.h },
  }
end

local function regionFrame(region)
  local mons = logicalMonitors()
  if not mons then return nil end
  local base = mons[region.mon]
  if not base then return nil end
  if region.frac == "left" then
    return { x = base.x, y = base.y, w = base.w / 2, h = base.h }
  elseif region.frac == "right" then
    return { x = base.x + base.w / 2, y = base.y, w = base.w / 2, h = base.h }
  end
  return { x = base.x, y = base.y, w = base.w, h = base.h }
end

local function layoutTargetSpace()
  local spaces = userSpacesOnPrimary()
  return spaces[LAYOUT_DESKTOP]
end

local function appStandardWindow(name)
  local app = hs.application.find(name)
  if not app then return nil end
  local win = app:mainWindow()
  if win and win:isStandard() then return win end
  for _, w in ipairs(app:allWindows()) do
    if w:isStandard() then return w end
  end
  return nil
end

local function windowOnSpace(win, target)
  for _, sp in ipairs(hs.spaces.windowSpaces(win) or {}) do
    if sp == target then return true end
  end
  return false
end

-- Walk the placements one at a time (waiting for each app's window to appear,
-- dragging it onto the target desktop if needed, then framing it). Sequential
-- processing keeps the desktop-drag hack in moveFocusedWindowToDesktop from
-- racing against itself.
local function applyLayout(placements)
  local target = layoutTargetSpace()
  if target and hs.spaces.focusedSpace() ~= target then
    hs.spaces.gotoSpace(target)
  end

  for _, p in ipairs(placements) do
    local name = LAYOUT_APP_NAMES[p.app]
    if not hs.application.find(name) then
      hs.application.launchOrFocus(name)
    end
  end

  local idx = 0
  local function placeNext()
    idx = idx + 1
    if idx > #placements then return end
    local p = placements[idx]
    local name = LAYOUT_APP_NAMES[p.app]
    local frame = regionFrame(p.region)

    local attempts = 0
    local function tryPlace()
      attempts = attempts + 1
      local win = appStandardWindow(name)
      if not win then
        if attempts < 24 then
          hs.timer.doAfter(0.25, tryPlace)
        else
          placeNext()
        end
        return
      end
      if target and not windowOnSpace(win, target) then
        win:focus()
        hs.timer.doAfter(0.2, function()
          moveFocusedWindowToDesktop(LAYOUT_DESKTOP)
          hs.timer.doAfter(0.5, function()
            if frame then win:setFrame(frame) end
            placeNext()
          end)
        end)
        return
      end
      if frame then win:setFrame(frame) end
      placeNext()
    end
    tryPlace()
  end
  placeNext()
end

local commandPaletteItems = {
  {
    text = "zt",
    subText = "zoomterm — zoom left, terminal right",
    handler = function() applyLayout(LAYOUTS.zt) end,
  },
  {
    text = "st",
    subText = "slackterm — slack left, terminal right",
    handler = function() applyLayout(LAYOUTS.st) end,
  },
  {
    text = "zct",
    subText = "zoomchrometerm — zoom left, chrome half-left, terminal half-right",
    handler = function() applyLayout(LAYOUTS.zct) end,
  },
  {
    text = "ct",
    subText = "chrometerm — chrome left, terminal right",
    handler = function() applyLayout(LAYOUTS.ct) end,
  },
  {
    text = "cst",
    subText = "chromeslackterm — chrome+slack share left, terminal right",
    handler = function() applyLayout(LAYOUTS.cst) end,
  },
  {
    text = "sct",
    subText = "slackchrometerm — slack+chrome share left, terminal right",
    handler = function() applyLayout(LAYOUTS.sct) end,
  },
  {
    text = "ghostty1",
    subText = "Ghostty on Desktop 1",
    handler = function() handleGhosttyOnDesktop(1) end,
  },
  {
    text = "ghostty2",
    subText = "Ghostty on Desktop 2",
    handler = function() handleGhosttyOnDesktop(2) end,
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
    subText = "github.com/benchling/aurelia/pulls/dlants",
    handler = function() openInChrome("https://github.com/benchling/aurelia/pulls/dlants") end,
  },
  {
    text = "infra",
    subText = "github.com/benchling/infra/pulls/dlants",
    handler = function() openInChrome("https://github.com/benchling/infra/pulls/dlants") end,
  },
  {
    text = "conf",
    subText = "Search Confluence (space + query)",
    handler = function(arg)
      local url = "https://benchling.atlassian.net/wiki/search?text="
      if arg and arg ~= "" then url = url .. plusEncode(arg) end
      openInChrome(url)
    end,
  },
  {
    text = "jira",
    subText = "Jira For You",
    handler = function() openInChrome("https://benchling.atlassian.net/jira/for-you") end,
  },
}

-- Scan for installed applications via mdfind (Spotlight backend)
local function scanApps()
  local apps = {}
  local handle = io.popen("mdfind -onlyin /Applications -onlyin /System/Applications \"kMDItemKind == 'Application'\"")
  if not handle then return apps end
  for line in handle:lines() do
    local name = line:match("([^/]+)%.app$")
    if name then
      table.insert(apps, {
        text = name,
        subText = "App: " .. line,
        appPath = line,
      })
    end
  end
  handle:close()
  table.sort(apps, function(a, b) return a.text:lower() < b.text:lower() end)
  return apps
end

local appChoices = scanApps()

local function openAppPath(path)
  hs.task.new("/usr/bin/open", nil, { path }):start()
end

-- Running-app set, refreshed when the command palette is shown.
local runningAppNames = {}
local function refreshRunningApps()
  runningAppNames = {}
  for _, app in ipairs(hs.application.runningApplications()) do
    local title = app:title()
    if title then runningAppNames[title:lower()] = true end
  end
end

-- Persisted recency (item text -> unix timestamp of last selection).
local COMMAND_PALETTE_RECENCY_KEY = "commandPaletteRecency"
local recencyData = hs.settings.get(COMMAND_PALETTE_RECENCY_KEY) or {}

local function recordCommandPaletteSelection(text)
  if not text then return end
  recencyData[text:lower()] = os.time()
  hs.settings.set(COMMAND_PALETTE_RECENCY_KEY, recencyData)
end

local RECENCY_BOOST_MAX = 60
local RECENCY_HALF_LIFE = 60 * 60 * 24 -- 1 day
local RUNNING_BOOST = 25

local function recencyBoost(text)
  local ts = recencyData[text:lower()]
  if not ts then return 0 end
  local age = os.time() - ts
  if age < 0 then age = 0 end
  return RECENCY_BOOST_MAX * math.exp(-age * math.log(2) / RECENCY_HALF_LIFE)
end

local function commandPaletteBoosts(choice)
  local boost = recencyBoost(choice.text)
  if runningAppNames[choice.text:lower()] then
    boost = boost + RUNNING_BOOST
  end
  return boost
end

local function buildCommandPaletteChoices()
  local choices = {}
  local seen = {}
  for i, item in ipairs(commandPaletteItems) do
    seen[item.text:lower()] = true
    table.insert(choices, {
      text = item.text,
      subText = item.subText,
      itemIndex = i,
    })
  end
  for _, app in ipairs(appChoices) do
    if not seen[app.text:lower()] then
      table.insert(choices, {
        text = app.text,
        subText = app.subText,
        appPath = app.appPath,
      })
    end
  end
  return choices
end

local commandPaletteChooser = hs.chooser.new(function(choice)
  if not choice then return end
  recordCommandPaletteSelection(choice.text)
  if choice.appPath then
    openAppPath(choice.appPath)
    return
  end
  local item = commandPaletteItems[choice.itemIndex]
  if item then
    item.handler(choice.arg)
  end
end)

-- When the user types a space, lock the chooser to the currently-selected
-- item so the rest of the query is passed as an argument to that item's
-- handler instead of re-filtering. Cleared on palette reopen.
local commandPaletteLocked = nil

local function refreshCommandPaletteChoices(query)
  local spaceIdx = query and query:find(" ", 1, true)
  if spaceIdx then
    if not commandPaletteLocked then
      local current = commandPaletteChooser:selectedRowContents()
      if current and next(current) ~= nil then
        commandPaletteLocked = current
      end
    end
    if commandPaletteLocked then
      local arg = query:sub(spaceIdx + 1)
      local origSub = commandPaletteLocked.subText or ""
      local preview = {
        text = commandPaletteLocked.text,
        subText = arg == "" and origSub or (origSub .. " — " .. arg),
        itemIndex = commandPaletteLocked.itemIndex,
        appPath = commandPaletteLocked.appPath,
        arg = arg,
      }
      commandPaletteChooser:choices({ preview })
    else
      commandPaletteChooser:choices({})
    end
    return
  end

  commandPaletteLocked = nil
  local allChoices = buildCommandPaletteChoices()
  if query == nil or query == "" then
    local sorted = {}
    for i, c in ipairs(allChoices) do
      table.insert(sorted, { choice = c, boost = commandPaletteBoosts(c), origIdx = i })
    end
    table.sort(sorted, function(a, b)
      if a.boost ~= b.boost then return a.boost > b.boost end
      return a.origIdx < b.origIdx
    end)
    local out = {}
    for _, item in ipairs(sorted) do table.insert(out, item.choice) end
    commandPaletteChooser:choices(out)
    return
  end

  local scored = {}
  for i, choice in ipairs(allChoices) do
    local s = fuzzyScoreFields(choice.text, choice.subText, query)
    if s then
      table.insert(scored, {
        choice = choice,
        score = s + commandPaletteBoosts(choice),
        origIdx = i,
      })
    end
  end
  table.sort(scored, function(a, b)
    if a.score ~= b.score then return a.score > b.score end
    return a.origIdx < b.origIdx
  end)
  local filtered = {}
  for _, item in ipairs(scored) do table.insert(filtered, item.choice) end
  commandPaletteChooser:choices(filtered)
end

commandPaletteChooser:queryChangedCallback(refreshCommandPaletteChoices)

hs.hotkey.bind({ "cmd" }, "space", function()
  refreshRunningApps()
  commandPaletteLocked = nil
  refreshCommandPaletteChoices("")
  commandPaletteChooser:show()
end)

-- ctrl-j / ctrl-k navigate any open chooser; pass through otherwise.
local function visibleChooser()
  if commandPaletteChooser and commandPaletteChooser:isVisible() then
    return commandPaletteChooser
  end
  if ghosttyChooser and ghosttyChooser:isVisible() then
    return ghosttyChooser
  end
  return nil
end

local function chooserMove(chooser, delta)
  local current = chooser:selectedRow() or 1
  local target = current + delta
  if target < 1 then return end
  local contents = chooser:selectedRowContents(target)
  if not contents or next(contents) == nil then return end
  chooser:selectedRow(target)
end

local chooserNavTap = hs.eventtap.new({ hs.eventtap.event.types.keyDown }, function(e)
  local flags = e:getFlags()
  if not flags.ctrl or flags.cmd or flags.alt or flags.shift then return false end
  local key = hs.keycodes.map[e:getKeyCode()]
  if key ~= "j" and key ~= "k" then return false end
  local chooser = visibleChooser()
  if not chooser then return false end
  chooserMove(chooser, key == "j" and 1 or -1)
  return true
end)
chooserNavTap:start()

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

local browserBundleIDs = {
  ["com.google.Chrome"] = true,
  ["org.mozilla.firefox"] = true,
  ["org.mozilla.firefoxdeveloperedition"] = true,
}

local function postToApp(mods, key, app)
  if not app then return end
  hs.eventtap.event.newKeyEvent(mods, key, true):post(app)
  hs.eventtap.event.newKeyEvent(mods, key, false):post(app)
end

local function frontmostIsBrowser()
  local app = hs.application.frontmostApplication()
  return app and browserBundleIDs[app:bundleID()] or false
end

-- cmd+k focuses the address bar (re-emitted as native cmd+L) and cmd+j returns
-- focus to the page (Escape blurs the address bar). We use an eventtap rather
-- than hs.hotkey so the keys pass through untouched in non-browser apps.
local browserKeyTap = hs.eventtap.new({ hs.eventtap.event.types.keyDown }, function(e)
  local flags = e:getFlags()
  if not flags.cmd or flags.ctrl or flags.alt or flags.shift then return false end
  local key = hs.keycodes.map[e:getKeyCode()]
  if key ~= "k" and key ~= "j" then return false end
  if not frontmostIsBrowser() then return false end

  if key == "k" then
    local app = hs.application.frontmostApplication()
    hs.timer.doAfter(0.02, function() postToApp({ "cmd" }, "l", app) end)
  else
    hs.eventtap.keyStroke({}, "escape", 0)
  end
  return true
end)
browserKeyTap:start()
