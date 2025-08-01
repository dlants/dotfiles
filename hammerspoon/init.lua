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



-- Interactive tab switcher using fzf
function interactiveGhosttyTabSwitcher()
  local ghostty = hs.application.find("Ghostty")
  if not ghostty then
    hs.alert.show("Ghostty not found")
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

# Use fzf to select a tab, only matching against window/tab names (exclude the bracketed part)
SELECTED=$(echo "$TABS" | fzf --delimiter="###" --nth=1 --header="Select Ghostty Tab" --height=~50% --border)

if [ -n "$SELECTED" ]; then
    # Switch to the selected tab
    hs -c "cliSelectGhosttyTab('$SELECTED')" > /dev/null
    echo "Switched to tab"
else
    echo "No tab selected"
fi
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

  ghostty:activate()

  hs.timer.doAfter(0.01, function() -- wiat for focus
    hs.eventtap.keyStroke({ "cmd" }, "n")

    hs.timer.doAfter(0.01, function() -- wait for new window
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
    -- Skip the tab switcher window
    if window:title():match("ghostty_tab_switcher") or window:title():match("/tmp/ghostty_tab_swi") then
      goto continue
    end

    local windowTabs = {}
    local success, result = pcall(function()
      local axWindow = hs.axuielement.windowElement(window)
      if axWindow then
        local children = axWindow:attributeValue("AXChildren")
        local foundTabGroup = false

        if children then
          for _, child in ipairs(children) do
            local role = child:attributeValue("AXRole")
            if role == "AXTabGroup" then
              foundTabGroup = true
              local tabs = child:attributeValue("AXChildren")
              if tabs then
                for j, tab in ipairs(tabs) do
                  local tabTitle = tab:attributeValue("AXTitle")
                  local tabSelected = tab:attributeValue("AXSelected")
                  -- Skip tabs that contain the switcher script
                  if tabTitle and not tabTitle:match("ghostty_tab_switcher") and not tabTitle:match("/tmp/ghostty_tab_swi") then
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

        -- If no tab group found, treat the window as a single tab
        if not foundTabGroup then
          table.insert(windowTabs, {
            index = 1,
            title = window:title(),
            selected = true
          })
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

    ::continue::
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
      -- Format: "WindowName | TabName [tabIndex] ###[windowId:tabIndex]"
      local line = string.format("%s | %s [%d] ###[%d:%d]",
        windowData.windowTitle,
        tab.title or "",
        tab.index,
        windowData.windowId,
        tab.index
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

  -- Parse the line: extract [windowId:tabIndex] from the end after ###
  local windowId, tabIndex = line:match("###%[(%d+):(%d+)%]%s*$")

  if not windowId or not tabIndex then
    print("Invalid line format - missing [windowId:tabIndex]")
    return ""
  end

  windowId = tonumber(windowId)
  tabIndex = tonumber(tabIndex)

  if not windowId or not tabIndex then
    print("Invalid window ID or tab index")
    return ""
  end

  selectGhosttyTab(windowId, tabIndex)
  return ""
end
