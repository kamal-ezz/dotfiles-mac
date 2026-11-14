-- Render a spectrum from the selected audio track using mpv's libavfilter.
-- Only the visualization branch is downmixed; playback keeps the original audio.
local mp = require("mp")

-- RGB hex colors, overridden by the active theme through script-opts
-- (audio-visualizer-bars=...) in ~/.config/dotfiles-theme/mpv.conf.
local colors = { bars = "d37918", backdrop = "0e0e0e" }
require("mp.options").read_options(colors, "audio-visualizer")
local backdrop = {
  tonumber(colors.backdrop:sub(1, 2), 16),
  tonumber(colors.backdrop:sub(3, 4), 16),
  tonumber(colors.backdrop:sub(5, 6), 16),
}

local enabled = true
local ready = false
local owned_graph

local function clear_graph()
  if owned_graph and mp.get_property("lavfi-complex", "") == owned_graph then
    mp.set_property("lavfi-complex", "")
  end
  owned_graph = nil
end

local function update()
  if not ready then
    return
  end
  local current_graph = mp.get_property("lavfi-complex", "")
  -- Do not replace a graph supplied by the user or another script.
  if current_graph ~= "" and current_graph ~= owned_graph then
    owned_graph = nil
    return
  end
  -- The aid property becomes "no" while a graph owns audio output; the option
  -- retains the user's requested selection, including an explicit disable.
  local selected_id = mp.get_property("options/aid", "auto")
  if not enabled or selected_id == "no" then
    clear_graph()
    return
  end

  local audio
  for _, track in ipairs(mp.get_property_native("track-list", {})) do
    if track.type == "video" and not track.albumart and not track.image then
      clear_graph()
      return
    end
    if track.type == "audio" then
      if not audio or tostring(track.id) == selected_id or
          (not tonumber(selected_id) and track.selected) then
        audio = track
      end
    end
  end
  if not audio then
    clear_graph()
    return
  end

  local graph = string.format(
    "[aid%d]asplit[ao][spectrum];" ..
    "[spectrum]aformat=channel_layouts=mono," ..
    "showfreqs=s=960x240:rate=30:mode=bar:ascale=sqrt:fscale=log:" ..
    "win_size=2048:averaging=4:colors=0x%s," ..
    -- showfreqs draws on black: paint only the black channels with the backdrop
    "format=rgb24,lutrgb=r='if(val,val,%d)':g='if(val,val,%d)':b='if(val,val,%d)'," ..
    "pad=1280:720:(ow-iw)/2:(oh-ih)/2:color=0x%s,format=yuv420p[vo]",
    audio.id, colors.bars, backdrop[1], backdrop[2], backdrop[3], colors.backdrop
  )
  if graph == current_graph then
    return
  end
  local ok, error = mp.set_property("lavfi-complex", graph)
  if ok then
    owned_graph = graph
  else
    mp.msg.error("Could not enable audio visualizer: " .. tostring(error))
  end
end

mp.add_hook("on_preloaded", 50, function()
  ready = true
  update()
end)
mp.observe_property("options/aid", "native", update)
mp.observe_property("track-list", "native", update)
mp.register_event("end-file", function()
  ready = false
  clear_graph()
end)
mp.add_key_binding(nil, "toggle", function()
  enabled = not enabled
  update()
  mp.osd_message("Audio visualizer: " .. (enabled and "on" or "off"))
end)
