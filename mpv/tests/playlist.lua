-- Run from the repository root: lua mpv/tests/playlist.lua
local properties, commands, messages, warnings, errors, events, bindings
local pending, requests, aborted, rejected

package.loaded["mp"] = {
  get_property = function(name, default)
    if properties[name] == nil then return default end
    return properties[name]
  end,
  command_native_async = function(request, callback)
    requests[#requests + 1] = request
    pending = callback
    return #requests
  end,
  commandv = function(...)
    local command = {...}
    commands[#commands + 1] = command
    if rejected[command[2]] then return nil, "rejected" end
    return true
  end,
  osd_message = function(text) messages[#messages + 1] = text end,
  msg = {
    warn = function(text) warnings[#warnings + 1] = text end,
    error = function(text) errors[#errors + 1] = text end,
  },
  add_key_binding = function(_, name, callback) bindings[name] = callback end,
  register_event = function(name, callback) events[name] = callback end,
  abort_async_command = function(token) aborted[#aborted + 1] = token end,
}
package.loaded["mp.utils"] = {
  split_path = function(path) return path:match("^(.-)[^/]*$") end,
  join_path = function(directory, path)
    if path:sub(1, 1) == "/" then return path end
    return directory .. "/" .. path
  end,
}

local function reset()
  properties = {["working-directory"] = "/media"}
  commands, messages, warnings, errors = {}, {}, {}, {}
  events, bindings, requests, aborted, rejected = {}, {}, {}, {}, {}
  pending = nil
  dofile("mpv/scripts/playlist.lua")
end

local function equal(actual, expected)
  assert(actual == expected, string.format("expected %q, got %q", tostring(expected), tostring(actual)))
end

local function finish(status, stdout)
  pending(true, {status = status, stdout = stdout or ""})
end

local tests = {
  {"opens one non-blocking multi-select dialog", function()
    bindings["add-files"]()
    bindings["add-files"]()
    equal(#requests, 1)
    equal(requests[1].args[1], "kdialog")
    equal(requests[1].args[5], "/media")
    equal(requests[1].args[7], "--multiple")
    equal(requests[1].args[8], "--separate-output")
    equal(requests[1].playback_only, false)
    equal(requests[1].capture_stdout, true)
  end},
  {"uses the macOS open panel on darwin, passing the folder as an argument", function()
    properties.platform = "darwin"
    properties.path = "/shows/it's \"Season 1\"/Episode 01.mkv"
    bindings["add-files"]()
    equal(#requests, 1)
    equal(requests[1].args[1], "osascript")
    equal(requests[1].args[2], "-e")
    assert(requests[1].args[3]:find("with multiple selections allowed", 1, true))
    -- The folder is never spliced into the AppleScript source.
    assert(not requests[1].args[3]:find("Season 1", 1, true))
    equal(requests[1].args[4], "/shows/it's \"Season 1\"/")
    equal(#requests[1].args, 4)
  end},
  {"macOS cancel leaves the queue untouched and selections append", function()
    properties.platform = "darwin"
    bindings["add-files"]()
    finish(1)
    equal(#commands, 0)
    bindings["add-files"]()
    finish(0, "/media/Episode 01.mkv\n/media/Episode 02.mkv\n")
    equal(#commands, 2)
    equal(messages[1], "Added 2 items to playlist")
  end},
  {"starts in the current file's directory", function()
    properties.path = "/shows/Season 1/Episode 01.mkv"
    bindings["add-files"]()
    equal(requests[1].args[5], "/shows/Season 1/")
  end},
  {"resolves relative directories and ignores stream URLs", function()
    properties.path = "album/track.flac"
    bindings["add-files"]()
    equal(requests[1].args[5], "/media/album/")
    finish(1)
    properties.path = "https://example.com/video"
    bindings["add-files"]()
    equal(requests[2].args[5], "/media")
  end},
  {"appends multiple files in order without splitting spaces or punctuation", function()
    bindings["add-files"]()
    finish(0, "/media/Episode 01.mkv\n/media/it's [02]; $title.mkv\n/media/أغنية.flac\n")
    equal(#commands, 3)
    equal(commands[1][1], "loadfile")
    equal(commands[1][2], "/media/Episode 01.mkv")
    equal(commands[2][2], "/media/it's [02]; $title.mkv")
    equal(commands[3][2], "/media/أغنية.flac")
    for _, command in ipairs(commands) do equal(command[3], "append-play") end
    equal(messages[1], "Added 3 items to playlist")
    bindings["add-files"]()
    equal(#requests, 2)
  end},
  {"cancel and empty selection leave the queue untouched", function()
    bindings["add-files"]()
    finish(1)
    bindings["add-files"]()
    finish(0)
    equal(#commands, 0)
    equal(#messages, 0)
  end},
  {"falls back to the uosc browser if kdialog is missing", function()
    bindings["add-files"]()
    finish(-2)
    equal(commands[1][1], "script-binding")
    equal(commands[1][2], "uosc/open-file")
    equal(#warnings, 1)
    assert(messages[1]:find("Shift+Enter", 1, true))
  end},
  {"handles async failures without a result", function()
    bindings["add-files"]()
    pending(false, nil, "subprocess failed")
    equal(commands[1][2], "uosc/open-file")
    equal(#warnings, 1)
  end},
  {"reports dialog errors instead of treating them as file selections", function()
    bindings["add-files"]()
    pending(true, {status = 2, stdout = "/not/a/selection", stderr = "dialog failed"})
    equal(#commands, 0)
    equal(#errors, 1)
    equal(#messages, 1)
  end},
  {"continues after an append failure and counts successful additions", function()
    rejected["/bad.mkv"] = true
    bindings["add-files"]()
    finish(0, "/bad.mkv\n/good.mkv\n")
    equal(#commands, 2)
    equal(#errors, 1)
    equal(messages[1], "Added 1 item to playlist")
  end},
  {"closes an outstanding dialog on shutdown", function()
    bindings["add-files"]()
    events.shutdown()
    equal(aborted[1], 1)
    events.shutdown()
    equal(#aborted, 1)
  end},
}

for _, test in ipairs(tests) do
  reset()
  test[2]()
  print("ok - " .. test[1])
end
print(string.format("%d playlist tests passed", #tests))
