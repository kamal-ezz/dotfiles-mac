-- Native multi-select picker: add files without replacing the current queue.
-- macOS uses the system open panel, Linux uses kdialog to match KDE; uosc's
-- browser is the fallback when neither is available.
local mp = require("mp")
local utils = require("mp.utils")

local picker

-- Prints one POSIX path per line; exits 1 on cancel, like kdialog.
local MACOS_PICKER = [[
on run argv
  activate
  set promptText to "Add to mpv playlist"
  try
    set picked to choose file with prompt promptText default location (POSIX file (item 1 of argv) as alias) with multiple selections allowed
  on error errorText number errorNumber
    if errorNumber is -128 then error errorText number errorNumber
    -- The start folder may not exist (e.g. a stream); open without it.
    set picked to choose file with prompt promptText with multiple selections allowed
  end try
  set output to ""
  repeat with chosen in picked
    set output to output & POSIX path of chosen & linefeed
  end repeat
  return output
end run
]]

local function picker_args(directory)
  if mp.get_property("platform") == "darwin" then
    return { "osascript", "-e", MACOS_PICKER, directory }
  end
  return {
    "kdialog", "--title", "Add to mpv playlist",
    "--getopenfilename", directory, "",
    "--multiple", "--separate-output",
  }
end

local function start_directory()
  local directory = mp.get_property("working-directory", ".")
  local path = mp.get_property("path")
  if path and not path:match("^[%w+.-]+://") then
    local parent = utils.split_path(path)
    if parent ~= "" then
      directory = utils.join_path(directory, parent)
    end
  end
  return directory
end

local function add_files()
  -- Repeated clicks must not open several dialogs at once.
  if picker then
    return
  end

  picker = mp.command_native_async({
    name = "subprocess",
    args = picker_args(start_directory()),
    playback_only = false,
    capture_stdout = true,
    capture_stderr = true,
  }, function(success, result, error)
    picker = nil
    if not success or not result or result.status < 0 then
      mp.msg.warn("File picker unavailable: " .. tostring(error or (result and result.error_string)))
      mp.commandv("script-binding", "uosc/open-file")
      mp.osd_message("Use Shift+Enter or Shift+click to add files in the browser.", 5)
      return
    end
    if result.status == 1 then
      return -- Cancelled; leave playback and the queue untouched.
    end
    if result.status ~= 0 then
      mp.msg.error("File picker failed: " .. (result.stderr or ""))
      mp.osd_message("Could not open the file picker. Try Ctrl+Shift+O.", 5)
      return
    end

    local added = 0
    for path in (result.stdout or ""):gmatch("[^\n]+") do
      -- append-play starts playback only if the player is idle.
      local ok, err = mp.commandv("loadfile", path, "append-play")
      if ok then
        added = added + 1
      else
        mp.msg.error("Could not add " .. path .. ": " .. tostring(err))
      end
    end
    if added > 0 then
      mp.osd_message(string.format("Added %d item%s to playlist", added, added == 1 and "" or "s"))
    end
  end)
end

mp.add_key_binding(nil, "add-files", add_files)
mp.register_event("shutdown", function()
  if picker then
    mp.abort_async_command(picker)
    picker = nil
  end
end)
