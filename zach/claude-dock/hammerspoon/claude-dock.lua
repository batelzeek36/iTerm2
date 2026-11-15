-- claude-dock: Ctrl-Opt-Cmd-C starts Claude Dock (the Claude panel inside World of Warcraft, its own
-- app since 2026-11-15) when it is not running. While Claude Dock runs, the key belongs to Claude
-- Dock (its panel's hotkey: focus the panel / give the keyboard back to the game), so this binding
-- steps aside from the moment Claude Dock launches until it quits. Started in the background
-- (`open -g`), so the game stays the active app and the panel comes up on its window.
-- Source: ~/Documents/iTerm2/zach/claude-dock/hammerspoon (zach/claude-dock/install.sh copies it here).
local M = {}

local BUNDLE_ID = "com.zakkbates.claudedock"
local APP_NAME = "Claude Dock"
local MODS, KEY = { "ctrl", "alt", "cmd" }, "c"

local hotkey, watcher, retryTimer, pollTimer
local hotkeyOn = false
local lastError = nil

local function running()
  return #hs.application.applicationsForBundleID(BUNDLE_ID) > 0
end

local function setHotkey(on)
  if not hotkey or hotkeyOn == on then return end
  if on then
    -- nil = the key could not be registered (another app holds it, e.g. a running Claude Dock).
    hotkeyOn = hotkey:enable() ~= nil
    if hotkeyOn then
      lastError = nil
    else
      lastError = "could not register Ctrl-Opt-Cmd-C"
    end
  else
    hotkey:disable()
    hotkeyOn = false
  end
end

-- The key is ours exactly while Claude Dock is not running.
local function sync()
  setHotkey(not running())
end

local function launch()
  -- Step aside first, so Claude Dock can register the same key as it starts.
  setHotkey(false)
  hs.task.new("/usr/bin/open", function(code, _, err)
    if code ~= 0 then
      lastError = "open exited " .. tostring(code) .. ": " .. tostring(err)
      hs.alert.show(APP_NAME .. " did not start: " .. tostring(err))
      sync()
    end
  end, { "-g", "-b", BUNDLE_ID }):start()
  -- If it never shows up (moved out of /Applications), take the key back.
  if retryTimer then retryTimer:stop() end
  retryTimer = hs.timer.doAfter(15, sync)
end

function M.start()
  M.stop()
  hotkey = hs.hotkey.new(MODS, KEY, launch)
  watcher = hs.application.watcher.new(function(name, event, app)
    local id = app and app:bundleID()
    if event == hs.application.watcher.launching or event == hs.application.watcher.launched then
      if id == BUNDLE_ID or name == APP_NAME then setHotkey(false) end
    elseif event == hs.application.watcher.terminated then
      -- A terminated app may no longer report its bundle id; checking is cheap.
      if id == BUNDLE_ID or name == APP_NAME or id == nil then
        hs.timer.doAfter(0.5, sync)
      end
    end
  end)
  watcher:start()
  -- While the key is not ours although Claude Dock is not running (another app held it when this
  -- loaded, e.g. the main iTerm2 before it dropped the old panel profile), keep trying.
  pollTimer = hs.timer.doEvery(30, function()
    if not hotkeyOn then sync() end
  end)
  sync()
end

function M.stop()
  if retryTimer then retryTimer:stop(); retryTimer = nil end
  if pollTimer then pollTimer:stop(); pollTimer = nil end
  if watcher then watcher:stop(); watcher = nil end
  if hotkey then hotkey:delete(); hotkey = nil end
  hotkeyOn = false
end

-- One line for install.sh: whether the launcher key is live and why.
function M.selftest()
  return string.format("claude-dock running=%s launcher-key=%s%s", tostring(running()),
    hotkeyOn and "on" or "off", lastError and (" (" .. lastError .. ")") or "")
end

return M
