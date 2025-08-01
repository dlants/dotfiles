-- Load the IPC module for command line tool support
require("hs.ipc")

-- Install the CLI tool
hs.ipc.cliInstall()

-- Basic configuration
hs.window.animationDuration = 0

-- Reload configuration hotkey
hs.hotkey.bind({ "cmd", "alt", "ctrl" }, "R", function()
  hs.reload()
end-- Deep inspection of tab children and other elements that might have PID info
function inspectTabChildrenForPids()
  local ghostty = hs.application.find("Ghostty")
  if not ghostty then
    print("Ghostty not found")
    return
  end

  local windows = ghostty:allWindows()
  for i, window in ipairs(windows) do
    print("=== Window " .. i .. ": " .. window:title() .. " ===")

    local success, result = pcall(function()
      local axWindow = hs.axuielement.windowElement(window)
      if axWindow then
        -- Check window-level attributes for PID info
        print("Window attributes:")
        local windowAttrs = axWindow:attributeNames()
        for _, attr in ipairs(windowAttrs) do
          if attr:lower():match("pid") or attr:lower():match("process") then
            local value = axWindow:attributeValue(attr)
            print("  " .. attr .. ": " .. tostring(value))
          end
        end

        local children = axWindow:attributeValue("AXChildren")
        if children then
          for _, child in ipairs(children) do
            local role = child:attributeValue("AXRole")
            if role == "AXTabGroup" then
              local tabs = child:attributeValue("AXChildren")
              if tabs then
                for j, tab in ipairs(tabs) do
                  if j <= 3 then -- Only check first 3 tabs to avoid spam
                    print("\n--- Tab " .. j .. " Children ---")

                    local tabChildren = tab:attributeValue("AXChildren")
                    if tabChildren and #tabChildren > 0 then
                      print("  Tab has " .. #tabChildren .. " children")
                      for k, tabChild in ipairs(tabChildren) do
                        local childRole = tabChild:attributeValue("AXRole")
                        local childTitle = tabChild:attributeValue("AXTitle")
                        print("    Child " .. k .. ": " .. (childRole or "unknown") ..
                              (childTitle and (" - " .. childTitle) or ""))

                        -- Check if this child has PID-related attributes
                        local childAttrs = tabChild:attributeNames()
                        for _, attr in ipairs(childAttrs) do
                          if attr:lower():match("pid") or attr:lower():match("process") then
                            local value = tabChild:attributeValue(attr)
                            print("      " .. attr .. ": " .. tostring(value))
                          end
                        end
                      end
                    else
                      print("  Tab has no children")
                    end
                  end
                end
              end
              break
            end
          end
        end
      end
    end)

    if not success then
      print("Error: " .. tostring(result))
    end
  end
end

-- CLI wrapper
function cliInspectTabChildrenForPids()
  inspectTabChildrenForPids()
  return ""
end-- Try to correlate tabs with their working directories
function getGhosttyTabsWithCwds()
  local tabData = getGhosttyTabs()
  local cwdData = getGhosttyTabCwds()

  if not next(tabData) or not next(cwdData) then
    return {}
  end

  -- Simple approach: try to match tab titles with directory names in CWDs
  for windowIndex, windowData in pairs(tabData) do
    for _, tab in ipairs(windowData.tabs) do
      -- Try to find a matching CWD based on tab title
      local bestMatch = nil
      local bestScore = -1

      for _, cwdInfo in ipairs(cwdData) do
        local score = 0

        -- Check if tab title contains part of the CWD path
        if tab.title and cwdInfo.cwd then
          local tabTitle = tab.title:lower()
          local cwd = cwdInfo.cwd:lower()

          -- Extract directory name from CWD
          local dirName = cwd:match("([^/]+)$") or ""

          -- Score based on matches
          if tabTitle:find(dirName, 1, true) then
            score = score + 10
          end

          -- Check for partial path matches
          for pathPart in cwd:gmatch("([^/]+)") do
            if tabTitle:find(pathPart, 1, true) then
              score = score + 1
            end
          end
        end

        if score > bestScore then
          bestScore = score
          bestMatch = cwdInfo
        end
      end

      -- Assign the best matching CWD
      if bestMatch and bestScore > 0 then
        tab.cwd = bestMatch.cwd
        tab.pid = bestMatch.pid
        print(string.format("Tab '%s' -> CWD: %s (score: %d)",
          tab.title or "unknown", bestMatch.cwd, bestScore))
      else
        tab.cwd = nil
        print(string.format("Tab '%s' -> No CWD match found", tab.title or "unknown"))
      end
    end
  end

  return tabData
end

-- Set a Ghostty window title based on tab information
function setGhosttyWindowTitle(windowId, newTitle)
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
    print("Window not found: " .. windowId)
    return false
  end

  -- Try to set the window title (this might not work with all apps)
  local success, result = pcall(function()
    local axWindow = hs.axuielement.windowElement(targetWindow)
    if axWindow then
      axWindow:setAttributeValue("AXTitle", newTitle)
      return true
    end
    return false
  end)

  if success and result then
    print("Set window title to: " .. newTitle)
    return true
  else
    print("Failed to set window title")
    return false
  end
end

-- CLI wrapper for tab-CWD correlation
function cliGetGhosttyTabsWithCwds()
  getGhosttyTabsWithCwds()
  return ""
end)

hs.alert.show("Config loaded")

-- Get working directories for Ghostty tabs
function getGhosttyTabCwds()
  local ghostty = hs.application.find("Ghostty")
  if not ghostty then
    print("Ghostty not found")
    return {}
  end

  local ghosttyPid = ghostty:pid()

  -- Get all processes in tree format to follow process hierarchy
  local handle = io.popen("ps -A -o pid,ppid,command")
  local result = handle:read("*a")
  handle:close()

  -- Build process tree
  local processes = {}
  local children = {}

  for line in result:gmatch("[^\r\n]+") do
    local processPid, parentPid, command = line:match("%s*(%d+)%s+(%d+)%s+(.+)")
    if processPid and parentPid and command then
      local pid = tonumber(processPid)
      local ppid = tonumber(parentPid)

      processes[pid] = {
        pid = pid,
        ppid = ppid,
        command = command
      }

      if not children[ppid] then
        children[ppid] = {}
      end
      table.insert(children[ppid], pid)
    end
  end

  -- Find all descendants of Ghostty process
  local function findDescendants(pid, depth)
    local descendants = {}
    if depth > 4 then return descendants end -- Prevent infinite recursion

    if children[pid] then
      for _, childPid in ipairs(children[pid]) do
        table.insert(descendants, childPid)
        local childDescendants = findDescendants(childPid, depth + 1)
        for _, desc in ipairs(childDescendants) do
          table.insert(descendants, desc)
        end
      end
    end
    return descendants
  end

  local allDescendants = findDescendants(ghosttyPid, 0)

  -- Find shell processes and get their CWDs
  local tabCwds = {}
  for _, pid in ipairs(allDescendants) do
    local proc = processes[pid]
    if proc and (proc.command:match("zsh") or proc.command:match("bash") or proc.command:match("fish")) then
      -- Get working directory for this shell process
      local cwdHandle = io.popen("lsof -p " .. pid .. " 2>/dev/null | grep cwd")
      local cwdResult = cwdHandle:read("*a")
      cwdHandle:close()

      if cwdResult and cwdResult ~= "" then
        for cwdLine in cwdResult:gmatch("[^\r\n]+") do
          local cwd = cwdLine:match("cwd%s+.*%s+(.+)")
          if cwd then
            table.insert(tabCwds, {
              pid = pid,
              command = proc.command,
              cwd = cwd
            })
            print(string.format("PID: %d, CMD: %s, CWD: %s", pid, proc.command, cwd))
          end
        end
      end
    end
  end

  return tabCwds
end

-- CLI wrapper
function cliGetGhosttyTabCwds()
  getGhosttyTabCwds()
  return ""
end

-- Debug function to inspect all available tab attributes
function inspectTabAttributes()
  local ghostty = hs.application.find("Ghostty")
  if not ghostty then
    print("Ghostty not found")
    return
  end

  local windows = ghostty:allWindows()
  for i, window in ipairs(windows) do
    print("=== Window " .. i .. ": " .. window:title() .. " ===")

    local success, result = pcall(function()
      local axWindow = hs.axuielement.windowElement(window)
      if axWindow then
        local children = axWindow:attributeValue("AXChildren")
        if children then
          for _, child in ipairs(children) do
            local role = child:attributeValue("AXRole")
            if role == "AXTabGroup" then
              local tabs = child:attributeValue("AXChildren")
              if tabs then
                for j, tab in ipairs(tabs) do
                  print("\n--- Tab " .. j .. " ---")

                  -- Get all available attributes
                  local attributes = tab:attributeNames()
                  for _, attr in ipairs(attributes) do
                    local value = tab:attributeValue(attr)
                    print("  " .. attr .. ": " .. tostring(value))
                  end

                  -- Also check for parameterized attributes
                  local paramAttrs = tab:parameterizedAttributeNames()
                  if #paramAttrs > 0 then
                    print("  Parameterized attributes:")
                    for _, pattr in ipairs(paramAttrs) do
                      print("    " .. pattr)
                    end
                  end
                end
              end
              break
            end
          end
        end
      end
    end)

    if not success then
      print("Error: " .. tostring(result))
    end
  end
end

-- CLI wrapper for tab attribute inspection
function cliInspectTabAttributes()
  inspectTabAttributes()
  return ""
end

function interactiveGhosttyTabSwitcher()
  local ghostty = hs.application.find("Ghostty")
  if not ghostty then
    hs.alert.show("Ghostty not found")
    return
  end

  -- Get current working directory from the focused window
  local currentWindow = ghostty:focusedWindow()
  if not currentWindow then
    hs.alert.show("No Ghostty window focused")
    return
  end

  -- Create a temporary script that will run fzf and return the selection
  local tempScript = "/tmp/ghostty_tab_switcher.sh"
  local scriptContent = [[#!/bin/bash
# Get tab list from Hammerspoon
TABS=$(hs -c "cliFormatGhosttyTabs()")

if [ -z "$TABS" ]; then
    echo "No Ghostty tabs found"
    exit 1
fi

# Use fzf to select a tab, showing the full line
SELECTED=$(echo "$TABS" | fzf --header="Select Ghostty Tab (WindowID Window TabIndex TabName)" --height=~50% --border)

if [ -n "$SELECTED" ]; then
    # Switch to the selected tab
    hs -c "cliSelectGhosttyTab('$SELECTED')" > /dev/null
    echo "Switched to tab"
else
    echo "No tab selected"
fi

# Small delay before closing
sleep 0.5
]]

  -- Write the script
  local file = io.open(tempScript, "w")
  if file then
    file:write(scriptContent)
    file:close()
    os.execute("chmod +x " .. tempScript)
  else
    hs.alert.show("Failed to create temporary script")
    return
  end

  -- Open a new window and run the script
  -- We'll use Cmd+N to open a new window, then run our script
  ghostty:activate()

  -- Small delay to ensure focus
  hs.timer.doAfter(0.1, function()
    -- Open new window
    hs.eventtap.keyStroke({ "cmd" }, "n")

    -- Wait a bit for window to open, then run the script
    hs.timer.doAfter(0.5, function()
      -- Type the command to run our script
      hs.eventtap.keyStrokes(tempScript .. " && exit")
      hs.eventtap.keyStroke({}, "return")
    end)
  end)
end

-- Bind hotkey for interactive tab switcher
hs.hotkey.bind({ "cmd", "shift" }, "t", function()
  interactiveGhosttyTabSwitcher()
end)
-- Get tabs from Ghostty window
function getGhosttyTabs()
  local ghostty = hs.application.find("Ghostty")
  if not ghostty then
    print("Ghostty not found")
    return {}
  end

  local windows = ghostty:allWindows()
  local allTabs = {}

  for i, window in ipairs(windows) do
    local windowTabs = {}
    local success, result = pcall(function()
      local axWindow = hs.axuielement.windowElement(window)
      if axWindow then
        local children = axWindow:attributeValue("AXChildren")
        if children then
          for _, child in ipairs(children) do
            local role = child:attributeValue("AXRole")
            if role == "AXTabGroup" then
              local tabs = child:attributeValue("AXChildren")
              if tabs then
                for j, tab in ipairs(tabs) do
                  local tabTitle = tab:attributeValue("AXTitle")
                  local tabSelected = tab:attributeValue("AXSelected")
                  if tabTitle then
                    table.insert(windowTabs, {
                      index = j,
                      title = tabTitle,
                      selected = tabSelected or false
                    })
                  end
                end
              end
              break
            end
          end
        end
      end
    end)

    if success and #windowTabs > 0 then
      allTabs[i] = {
        windowTitle = window:title(),
        windowId = window:id(),
        tabs = windowTabs
      }
    end
  end

  return allTabs
end

-- Format tabs for fzf selection
function formatGhosttyTabsForFzf()
  local tabData = getGhosttyTabs()

  if not next(tabData) then
    return ""
  end

  local lines = {}
  for windowIndex, windowData in pairs(tabData) do
    for _, tab in ipairs(windowData.tabs) do
      -- Format: windowId windowName tabIndex tabName
      local line = string.format("%d %s %d %s",
        windowData.windowId,
        windowData.windowTitle,
        tab.index,
        tab.title or ""
      )
      table.insert(lines, line)
    end
  end

  return table.concat(lines, "\n")
end

-- CLI function for fzf integration
function cliFormatGhosttyTabs()
  print(formatGhosttyTabsForFzf())
  return ""
end

-- Select a specific Ghostty tab
function selectGhosttyTab(windowId, tabIndex)
  local ghostty = hs.application.find("Ghostty")
  if not ghostty then
    print("Ghostty not found")
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
    print("Window not found: " .. windowId)
    return false
  end

  -- Focus the window first
  targetWindow:focus()

  -- Find and click the tab
  local success, result = pcall(function()
    local axWindow = hs.axuielement.windowElement(targetWindow)
    if axWindow then
      local children = axWindow:attributeValue("AXChildren")
      if children then
        for _, child in ipairs(children) do
          local role = child:attributeValue("AXRole")
          if role == "AXTabGroup" then
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
    end
    return false
  end)

  if success and result then
    print("Selected tab " .. tabIndex .. " in window " .. windowId)
    return true
  else
    print("Failed to select tab: " .. tostring(result))
    return false
  end
end

-- CLI function to select tab from fzf formatted line
function cliSelectGhosttyTab(line)
  if not line or line == "" then
    print("No line provided")
    return ""
  end

  -- Parse the line: windowId windowName tabIndex tabName
  local parts = {}
  for part in string.gmatch(line, "(%S+)") do
    table.insert(parts, part)
  end

  if #parts < 3 then
    print("Invalid line format")
    return ""
  end

  local windowId = tonumber(parts[1])
  local tabIndex = tonumber(parts[3])

  if not windowId or not tabIndex then
    print("Invalid window ID or tab index")
    return ""
  end

  selectGhosttyTab(windowId, tabIndex)
  return ""
end
