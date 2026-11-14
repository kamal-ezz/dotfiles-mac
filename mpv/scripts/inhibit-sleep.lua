-- Block system sleep while anything is playing, and block screen dimming only
-- for real video (mpv's stop-screensaver), not audio or cover art.

-- Each holds an idle-sleep assertion until it is killed.
local SLEEP_BLOCKER = {
  darwin = { "caffeinate", "-i" },
  linux = { "systemd-inhibit", "--what=sleep", "--who=mpv", "--why=Playing media", "sleep", "infinity" },
}

local inhibitor

local function release()
  if inhibitor then
    mp.abort_async_command(inhibitor)
    inhibitor = nil
  end
end

local function acquire()
  local args = SLEEP_BLOCKER[mp.get_property("platform")]
  if inhibitor or not args then
    return
  end
  local token
  token = mp.command_native_async({
    name = "subprocess",
    args = args,
    playback_only = false,
  }, function()
    if inhibitor == token then
      inhibitor = nil
    end
  end)
  inhibitor = token
end

local function update_sleep()
  if mp.get_property_bool("pause") or mp.get_property_bool("idle-active") then
    release()
  else
    acquire()
  end
end

local function update_screensaver(_, video)
  local is_video = video ~= nil and not video.image
  mp.set_property("stop-screensaver", is_video and "yes" or "no")
end

mp.observe_property("pause", "bool", update_sleep)
mp.observe_property("idle-active", "bool", update_sleep)
mp.observe_property("current-tracks/video", "native", update_screensaver)
mp.register_event("shutdown", release)
