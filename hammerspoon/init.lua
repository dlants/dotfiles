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


-- Window management
hs.hotkey.bind({ "cmd", "alt" }, "h", function()
  local win = hs.window.focusedWindow()
  if win then
    local screen = win:screen():frame()
    win:setFrame({ x = screen.x, y = screen.y, w = screen.w / 2, h = screen.h })
  end
end)

hs.hotkey.bind({ "cmd", "alt" }, "l", function()
  local win = hs.window.focusedWindow()
  if win then
    local screen = win:screen():frame()
    win:setFrame({ x = screen.x + screen.w / 2, y = screen.y, w = screen.w / 2, h = screen.h })
  end
end)

hs.hotkey.bind({ "cmd", "alt" }, "k", function()
  local win = hs.window.focusedWindow()
  if win then
    local screen = win:screen():frame()
    win:setFrame({ x = screen.x, y = screen.y, w = screen.w, h = screen.h })
  end
end)
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
