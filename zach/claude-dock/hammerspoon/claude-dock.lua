-- claude-dock: Ctrl-Opt-Cmd-C starts Claude Dock (the Claude panel inside World of Warcraft, its own
-- app since 2026-11-15) when it is not running. While Claude Dock runs, the key belongs to Claude
-- Dock (its panel's hotkey: focus the panel / give the keyboard back to the game).
-- Started in the background (`open -g`), so the game stays the active app and the panel comes up
-- on its window.
--
-- Why a key watcher and not hs.hotkey (2026-11-15): a registered hotkey held the key system-wide,
-- and Claude Dock registers the same key once, as it starts. Opened from Finder, Claude Dock
-- registered it before this module saw the launch and stepped aside (7:35:31 PM start, key let go
-- 7:35:33 PM), its registration failed, and the panel had no hotkey until it was restarted. A key
-- watcher registers nothing, so Claude Dock always gets the key; the watcher runs only while
-- Claude Dock is not running and lets every other key through untouched.
-- Source: ~/Documents/iTerm2/zach/claude-dock/hammerspoon (zach/claude-dock/install.sh copies it here).
local M = {}

local BUNDLE_ID = "com.zakkbates.claudedock"
local APP_NAME = "Claude Dock"
local MODS, KEY = { "ctrl", "alt", "cmd" }, "c"
local LAUNCH_GRACE = 15   -- seconds a launch may take before the key starts Claude Dock again

local tap, watcher, pollTimer
local tapOn = false
local lastError = nil
local launchedAt = nil

local function running()
  return #hs.application.applicationsForBundleID(BUNDLE_ID) > 0
end

local function setTap(on)
  if not tap then return end
  if on then
    if not tap:isEnabled() then tap:start() end
    tapOn = tap:isEnabled()
    if not tapOn then lastError = "could not watch Ctrl-Opt-Cmd-C" end
  else
    if tap:isEnabled() then tap:stop() end
    tapOn = false
  end
end

-- The key is watched exactly while Claude Dock is not running.
local function sync()
  if running() then
    launchedAt = nil
    setTap(false)
  else
    setTap(true)
  end
end

local function launch()
  local now = hs.timer.secondsSinceEpoch()
  if launchedAt and now - launchedAt < LAUNCH_GRACE then return end
  launchedAt = now
  lastError = nil
  hs.task.new("/usr/bin/open", function(code, _, err)
    if code ~= 0 then
      launchedAt = nil
      lastError = "open exited " .. tostring(code) .. ": " .. tostring(err)
      hs.alert.show(APP_NAME .. " did not start: " .. tostring(err))
    end
  end, { "-g", "-b", BUNDLE_ID }):start()
end

-- Exactly Ctrl-Opt-Cmd-C (Shift-Ctrl-Opt-Cmd-C is Claude Dock's hide key, not this one).
function M.matches(event)
  return event:getKeyCode() == hs.keycodes.map[KEY] and event:getFlags():containExactly(MODS)
end

-- true = the key press is ours (swallowed), false = it goes on to the active app.
function M.handle(event)
  if not M.matches(event) then return false end
  if running() then
    -- Claude Dock's own hotkey takes it from here; the watcher should already be off.
    setTap(false)
    return false
  end
  if event:getProperty(hs.eventtap.event.properties.keyboardEventAutorepeat) == 0 then
    launch()
  end
  return true
end

function M.start()
  M.stop()
  tap = hs.eventtap.new({ hs.eventtap.event.types.keyDown }, M.handle)
  watcher = hs.application.watcher.new(function(name, event, app)
    local id = app and app:bundleID()
    if event == hs.application.watcher.launching or event == hs.application.watcher.launched then
      if id == BUNDLE_ID or name == APP_NAME then setTap(false) end
    elseif event == hs.application.watcher.terminated then
      -- A terminated app may no longer report its bundle id; checking is cheap.
      if id == BUNDLE_ID or name == APP_NAME or id == nil then
        hs.timer.doAfter(0.5, sync)
      end
    end
  end)
  watcher:start()
  -- macOS turns off a key watcher it judges slow; this puts it back, and catches a launch or quit
  -- the app watcher missed.
  pollTimer = hs.timer.doEvery(30, sync)
  sync()
end

function M.stop()
  if pollTimer then pollTimer:stop(); pollTimer = nil end
  if watcher then watcher:stop(); watcher = nil end
  if tap then tap:stop(); tap = nil end
  tapOn = false
  launchedAt = nil
end

-- One line for install.sh: whether the launcher key is live and why. It never holds the key
-- itself; "launcher-key=on" means it is watching for it.
function M.selftest()
  return string.format("claude-dock running=%s launcher-key=%s%s", tostring(running()),
    tapOn and "on" or "off", lastError and (" (" .. lastError .. ")") or "")
end

return M
