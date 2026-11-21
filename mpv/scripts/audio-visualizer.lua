-- Render a spectrum from the selected audio track using mpv's libavfilter.
-- Only the visualization branch is downmixed; playback keeps the original audio.
local mp = require("mp")

-- RGB hex colors, overridden by the active theme through script-opts
-- (audio-visualizer-bars=...) in ~/.config/dotfiles-theme/mpv.conf.
local colors = { bars = "d37918", backdrop = "0e0e0e" }
require("mp.options").read_options(colors, "audio-visualizer")
local function parse_hex(value, fallback)
  local hex = type(value) == "string" and value:match("^#?(%x%x%x%x%x%x)$") or fallback
  return hex, {
    tonumber(hex:sub(1, 2), 16),
    tonumber(hex:sub(3, 4), 16),
    tonumber(hex:sub(5, 6), 16),
  }
end
local _, bar_rgb = parse_hex(colors.bars, "d37918")
-- Keep each bar channel >= 0x01 so lutrgb's val==0 test matches only the black backdrop.
local bars_hex = string.format("%02x%02x%02x",
  math.max(1, bar_rgb[1]), math.max(1, bar_rgb[2]), math.max(1, bar_rgb[3]))
local backdrop_hex, backdrop = parse_hex(colors.backdrop, "0e0e0e")

local enabled = true
local ready = false
local owned_graph
local active_audio_id

local function clear_graph()
  if owned_graph and mp.get_property("lavfi-complex", "") == owned_graph then
    mp.set_property("lavfi-complex", "")
  end
  owned_graph = nil
  active_audio_id = nil
end

local function update()
  if not ready then
    return
  end
  local current_graph = mp.get_property("lavfi-complex", "")
  -- Do not replace a graph supplied by the user or another script.
  if current_graph ~= "" and current_graph ~= owned_graph then
    owned_graph = nil
    active_audio_id = nil
    return
  end
  -- The aid property becomes "no" while a graph owns audio output; the option
  -- retains the user's requested selection, including an explicit disable.
  local selected_id = mp.get_property("options/aid", "auto")
  if not enabled or selected_id == "no" then
    clear_graph()
    return
  end

  local audio, selected, previous
  for _, track in ipairs(mp.get_property_native("track-list", {})) do
    if track.type == "video" and not track.albumart and not track.image then
      clear_graph()
      return
    end
    if track.type == "audio" then
      if tostring(track.id) == selected_id then
        audio = track
      end
      if track.selected then
        selected = track
      end
      if track.id == active_audio_id then
        previous = track
      end
    end
  end
  audio = audio or selected or previous
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
    audio.id, bars_hex, backdrop[1], backdrop[2], backdrop[3], backdrop_hex
  )
  if graph == current_graph then
    active_audio_id = audio.id
    return
  end
  local ok, error = mp.set_property("lavfi-complex", graph)
  if ok then
    owned_graph = graph
    active_audio_id = audio.id
  else
    mp.msg.error("Could not enable audio visualizer: " .. tostring(error))
  end
end

-- mpv selects its default track after on_preloaded. Wait for that decision
-- before attaching a filter graph, which takes over audio selection.
mp.register_event("file-loaded", function()
  ready = true
  active_audio_id = nil
  update()
end)
mp.observe_property("options/aid", "native", function()
  active_audio_id = nil
  update()
end)
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
