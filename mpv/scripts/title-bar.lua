-- Title bar for the borderless window: title, chapter, queue position and
-- window buttons on one fixed-height charcoal panel. uosc's own top bar is off
-- (see uosc.conf): it has no panel while revealed over playing video, and its
-- buttons can't be restyled.
local mp = require("mp")
local assdraw = require("mp.assdraw")

-- Logical pixels, multiplied by the display scale like uosc's sizes.
local BAR_HEIGHT = 32
local BUTTON_WIDTH = 40
local GLYPH_SIZE = 10
local FONT_SIZE = 14
local PADDING = 12
local CHIP_INSET = 6
local CHIP_PADDING = 8
local MIN_TITLE_WIDTH = 120
-- Same reveal distances and fade as uosc.conf, so both bars appear together.
local PROXIMITY_IN = 16
local PROXIMITY_OUT = 60
local FADE_SECONDS = 0.14
local FLASH_SECONDS = 1
local FRAME_SECONDS = 1 / 60

-- RGB hex colors. Window buttons stay neutral; the accent is reserved for
-- playback controls. The active theme overrides these through script-opts
-- (title-bar-panel=...) in ~/.config/dotfiles-theme/mpv.conf.
local COLORS = {
  panel = "1B1B1B",
  edge = "222222",
  text = "EEEEEE",
  muted = "9A9A9A",
  glyph = "BDBDBD",
  raised = "262626",
  hover = "303030",
  pressed = "3A3A3A",
  close_hover = "C42B1C",
  close_pressed = "A32417",
  on_close = "FFFFFF",
}
require("mp.options").read_options(COLORS, "title-bar")
local BUTTONS = { "minimize", "maximize", "close" }
local BUTTON_SECTION = "title-bar-buttons"
local DRAG_SECTION = "title-bar-drag"
local RELEASE_SECTION = "title-bar-release"

-- Default z keeps the bar above player-chrome's backdrop and below uosc's menus.
local overlay = mp.create_osd_overlay("ass-events")
overlay.data = ""
local measure = mp.create_osd_overlay("ass-events")
measure.compute_bounds = true
measure.hidden = true

local original_top = mp.get_property_number("video-margin-ratio-top", 0)
local original_osd_margin = mp.get_property_number("osd-margin-y", 0)

local window = { width = 0, height = 0, scale = 1, restored = true }
local pointer = { x = 0, y = 0, inside = false, idle = false }
local media = { title = nil, chapter = nil, position = nil, count = 0, idle = false }
local bar = { pinned = false, flashing = false, menu_open = false, visibility = 0 }
local layout = nil
local hovered = nil
local pressed = nil
local active_areas = nil
local width_cache = {}
local width_cache_size = 0

local function px(value)
  return math.floor(value * window.scale + 0.5)
end

local function escape(text)
  return mp.command_native({ "escape-ass", (text:gsub("%s+", " ")) })
end

local function text_width(text, font_size)
  local key = font_size .. "\n" .. text
  if width_cache[key] then
    return width_cache[key]
  end
  measure.res_x = window.width
  measure.res_y = window.height
  measure.data = string.format("{\\an7\\pos(0,0)\\q2\\bord0\\shad0\\fs%d}%s", font_size, escape(text))
  local bounds = measure:update()
  local width = bounds and bounds.x1 or 0
  if width <= 0 and text ~= "" then
    -- VO/libass may not be initialized yet; do not poison the cache with 0.
    return 0
  end
  if width >= window.width then
    -- Measurements are clipped to the window, so the real width is unknown
    -- and must not be reused once the window grows.
    return math.huge
  end
  if width_cache_size >= 256 then
    width_cache = {}
    width_cache_size = 0
  end
  width_cache[key] = width
  width_cache_size = width_cache_size + 1
  return width
end

-- Longest prefix that fits, ending in an ellipsis; nil when nothing fits.
local function fit(text, font_size, max_width)
  if text_width(text, font_size) <= max_width then
    return text
  end
  local starts = {}
  for position in text:gmatch("()[%z\1-\127\194-\244][\128-\191]*") do
    starts[#starts + 1] = position
  end
  local best = nil
  local low = 1
  local high = #starts - 1
  while low <= high do
    local kept = math.floor((low + high) / 2)
    local candidate = text:sub(1, starts[kept + 1] - 1):gsub("%s+$", "") .. "…"
    if text_width(candidate, font_size) <= max_width then
      best = candidate
      low = kept + 1
    else
      high = kept - 1
    end
  end
  return best
end

local function compute_layout()
  local height = px(BAR_HEIGHT)
  local button_width = px(BUTTON_WIDTH)
  local buttons_left = window.width - button_width * #BUTTONS
  local result = {
    height = height,
    font_size = px(FONT_SIZE),
    button_width = button_width,
    buttons_left = buttons_left,
    interactive_left = buttons_left,
    title_left = px(PADDING),
    title_right = buttons_left - px(PADDING),
  }

  if media.idle or not media.position or media.count < 2 then
    return result
  end
  local position = tostring(media.position)
  local total = "/" .. media.count
  local chip_right = buttons_left - px(CHIP_INSET)
  local chip_left = chip_right - text_width(position .. total, result.font_size) - px(CHIP_PADDING) * 2
  local title_right = chip_left - px(PADDING)
  if title_right - result.title_left < px(MIN_TITLE_WIDTH) then
    return result
  end
  result.chip = {
    x0 = chip_left,
    y0 = px(CHIP_INSET),
    x1 = chip_right,
    y1 = height - px(CHIP_INSET),
    position = position,
    total = total,
  }
  result.interactive_left = chip_left
  result.title_right = title_right
  return result
end

local function zone_at(x, y)
  if not layout or y < 0 or y >= layout.height then
    return nil
  end
  if x >= layout.buttons_left and x < window.width then
    local index = math.floor((x - layout.buttons_left) / layout.button_width) + 1
    return BUTTONS[math.min(index, #BUTTONS)]
  end
  local chip = layout.chip
  if chip and x >= chip.x0 and x < chip.x1 then
    return "playlist"
  end
  return nil
end

local function target_visibility()
  if bar.pinned or bar.flashing then
    return 1
  end
  if not pointer.inside then
    return 0
  end
  if hovered then
    return 1
  end
  if pointer.idle or not layout then
    return 0
  end
  local distance = math.max(0, pointer.y - layout.height)
  local prox_in = px(PROXIMITY_IN)
  local prox_out = px(PROXIMITY_OUT)
  local range = math.max(1, prox_out - prox_in)
  return 1 - math.min(math.max(distance - prox_in, 0), range) / range
end

local function style(color, opacity)
  local bgr = color:sub(5, 6) .. color:sub(3, 4) .. color:sub(1, 2)
  local alpha = math.floor((1 - bar.visibility * (opacity or 1)) * 255 + 0.5)
  return string.format("\\bord0\\shad0\\1c&H%s&\\alpha&H%02X&", bgr, alpha)
end

local function begin_shape(ass, color)
  ass:new_event()
  ass:pos(0, 0)
  ass:append("{\\an7" .. style(color) .. "}")
  ass:draw_start()
end

local function fill(ass, x0, y0, x1, y1, color, radius)
  begin_shape(ass, color)
  if radius then
    ass:round_rect_cw(x0, y0, x1, y1, radius)
  else
    ass:rect_cw(x0, y0, x1, y1)
  end
  ass:draw_stop()
end

local function square_outline(ass, x0, y0, x1, y1, stroke)
  ass:rect_cw(x0, y0, x1, y1)
  ass:rect_ccw(x0 + stroke, y0 + stroke, x1 - stroke, y1 - stroke)
end

local function diagonal(ass, x0, y0, x1, y1, stroke)
  local length = math.sqrt((x1 - x0) ^ 2 + (y1 - y0) ^ 2)
  local nx = -(y1 - y0) / length * stroke / 2
  local ny = (x1 - x0) / length * stroke / 2
  ass:move_to(x0 + nx, y0 + ny)
  ass:line_to(x1 + nx, y1 + ny)
  ass:line_to(x1 - nx, y1 - ny)
  ass:line_to(x0 - nx, y0 - ny)
end

local function draw_glyph(ass, name, center_x, center_y, color)
  local size = px(GLYPH_SIZE)
  local stroke = math.max(1, px(1))
  local x0 = center_x - math.floor(size / 2)
  local y0 = center_y - math.floor(size / 2)
  local x1 = x0 + size
  local y1 = y0 + size

  begin_shape(ass, color)
  if name == "minimize" then
    local line_y = center_y - math.floor(stroke / 2)
    ass:rect_cw(x0, line_y, x1, line_y + stroke)
  elseif name == "maximize" and window.restored then
    square_outline(ass, x0, y0, x1, y1, stroke)
  elseif name == "maximize" then
    -- Restore: a front square with the top and right edges of one behind it.
    local offset = math.max(2, px(2))
    square_outline(ass, x0, y0 + offset, x1 - offset, y1, stroke)
    ass:rect_cw(x0 + offset, y0, x1, y0 + stroke)
    ass:rect_cw(x1 - stroke, y0, x1, y1 - offset)
  else
    local diagonal_stroke = stroke * 1.3
    diagonal(ass, x0, y0, x1, y1, diagonal_stroke)
    diagonal(ass, x0, y1, x1, y0, diagonal_stroke)
  end
  ass:draw_stop()
end

local function draw_buttons(ass)
  for index, name in ipairs(BUTTONS) do
    local x0 = layout.buttons_left + (index - 1) * layout.button_width
    local is_close = name == "close"
    local glyph_color = COLORS.glyph
    local background = nil
    if pressed == name and hovered == name then
      background = is_close and COLORS.close_pressed or COLORS.pressed
    elseif hovered == name and not pressed then
      background = is_close and COLORS.close_hover or COLORS.hover
    end
    if background then
      fill(ass, x0, 0, x0 + layout.button_width, layout.height, background)
      glyph_color = is_close and COLORS.on_close or COLORS.text
    end
    local center_x = x0 + math.floor(layout.button_width / 2)
    draw_glyph(ass, name, center_x, math.floor(layout.height / 2), glyph_color)
  end
end

local function draw_chip(ass)
  local chip = layout.chip
  local background = COLORS.raised
  if pressed == "playlist" and hovered == "playlist" then
    background = COLORS.pressed
  elseif hovered == "playlist" and not pressed then
    background = COLORS.hover
  end
  fill(ass, chip.x0, chip.y0, chip.x1, chip.y1, background, (chip.y1 - chip.y0) / 2)
  ass:new_event()
  ass:pos((chip.x0 + chip.x1) / 2, layout.height / 2)
  ass:append(string.format(
    "{\\an5\\q2\\fs%d%s}%s{%s}%s",
    layout.font_size, style(COLORS.text), chip.position, style(COLORS.muted), chip.total
  ))
end

local function draw_title(ass)
  local primary = media.title
  local secondary = media.chapter
  if media.idle then
    primary = "mpv"
    secondary = "Drop files to play"
  end
  if not primary or primary == "" then
    return
  end

  local available = layout.title_right - layout.title_left
  local gap = px(PADDING)
  local shown = fit(primary, layout.font_size, available)
  if not shown then
    return
  end
  local detail = nil
  if secondary and secondary ~= "" and shown == primary then
    local remaining = available - text_width(primary, layout.font_size) - gap
    if remaining > 0 then
      detail = fit(secondary, layout.font_size, remaining)
    end
  end

  ass:new_event()
  ass:pos(layout.title_left, layout.height / 2)
  ass:append(string.format("{\\an4\\q2\\fs%d%s}%s", layout.font_size, style(COLORS.text), escape(shown)))
  if detail then
    ass:new_event()
    ass:pos(layout.title_left + text_width(primary, layout.font_size) + gap, layout.height / 2)
    ass:append(string.format("{\\an4\\q2\\fs%d%s}%s", layout.font_size, style(COLORS.muted), escape(detail)))
  end
end

local function render()
  if bar.visibility <= 0 or not layout then
    if overlay.data ~= "" then
      overlay.data = ""
      overlay:remove()
    end
    return
  end
  local ass = assdraw.ass_new()
  fill(ass, 0, 0, window.width, layout.height, COLORS.panel)
  fill(ass, 0, layout.height - 1, window.width, layout.height, COLORS.edge)
  draw_title(ass)
  if layout.chip then
    draw_chip(ass)
  end
  draw_buttons(ass)
  -- Pointer movement refreshes constantly; only redraw when something changed.
  if overlay.data == ass.text and overlay.res_x == window.width and overlay.res_y == window.height then
    return
  end
  overlay.res_x = window.width
  overlay.res_y = window.height
  overlay.data = ass.text
  overlay:update()
end

-- Pinned bars sit above the picture and OSD messages instead of covering them.
local function reserve_space()
  local ratio = 0
  if bar.pinned and layout and window.height > 0 then
    ratio = layout.height / window.height
  end
  local top = math.max(original_top, ratio)
  if math.abs(mp.get_property_number("video-margin-ratio-top", 0) - top) > 0.000001 then
    mp.set_property_number("video-margin-ratio-top", top)
  end
  -- osd-margin-y is measured against a 720 pixel tall window.
  local osd_margin = original_osd_margin + math.floor(ratio * 720 + 0.5)
  if mp.get_property_number("osd-margin-y", 0) ~= osd_margin then
    mp.set_property_number("osd-margin-y", osd_margin)
  end
end

-- Buttons take clicks themselves; the rest of the bar still drags the window.
local function sync_input()
  local areas = nil
  if bar.visibility > 0 and not bar.menu_open and layout then
    areas = string.format("%d,%d,%d", layout.interactive_left, window.width, layout.height)
  end
  if areas == active_areas then
    return
  end
  active_areas = areas
  if not areas then
    mp.disable_key_bindings(BUTTON_SECTION)
    mp.disable_key_bindings(DRAG_SECTION)
    return
  end
  mp.set_mouse_area(layout.interactive_left, 0, window.width, layout.height, BUTTON_SECTION)
  mp.set_mouse_area(0, 0, layout.interactive_left, layout.height, DRAG_SECTION)
  mp.enable_key_bindings(BUTTON_SECTION)
  mp.enable_key_bindings(DRAG_SECTION, "allow-vo-dragging+allow-hide-cursor")
end

local fade_timer

local function refresh()
  layout = nil
  if window.width > 0 and window.height > 0 then
    layout = compute_layout()
  end
  hovered = nil
  if pointer.inside and not bar.menu_open and bar.visibility > 0 then
    hovered = zone_at(pointer.x, pointer.y)
  end

  local target = target_visibility()
  if bar.pinned then
    -- The picture moves under a pinned bar at once, so the panel must too.
    bar.visibility = target
  elseif bar.visibility ~= target then
    fade_timer:resume()
  end
  reserve_space()
  sync_input()
  render()
end

fade_timer = mp.add_periodic_timer(FRAME_SECONDS, function()
  local target = target_visibility()
  local step = FRAME_SECONDS / FADE_SECONDS
  if bar.visibility < target then
    bar.visibility = math.min(target, bar.visibility + step)
  else
    bar.visibility = math.max(target, bar.visibility - step)
  end
  if bar.visibility == target then
    fade_timer:kill()
  end
  refresh()
end)
fade_timer:kill()

local idle_timer = mp.add_timeout(1, function()
  pointer.idle = true
  refresh()
end)
idle_timer:kill()

local flash_timer = mp.add_timeout(FLASH_SECONDS, function()
  bar.flashing = false
  refresh()
end)
flash_timer:kill()

local function toggle_maximized()
  if window.restored then
    mp.set_property_bool("window-maximized", true)
  else
    mp.set_property_bool("fullscreen", false)
    mp.set_property_bool("window-maximized", false)
  end
end

local actions = {
  minimize = function()
    mp.commandv("cycle", "window-minimized")
  end,
  maximize = toggle_maximized,
  close = function()
    mp.command("quit")
  end,
  playlist = function()
    mp.commandv("script-binding", "uosc/playlist")
  end,
}

local function press()
  pressed = hovered
  if pressed then
    mp.enable_key_bindings(RELEASE_SECTION)
  end
  render()
end

-- Act on release so a press can be cancelled by moving off the button.
local function release()
  local action = pressed and pressed == hovered and actions[pressed]
  pressed = nil
  mp.disable_key_bindings(RELEASE_SECTION)
  render()
  if action then
    action()
  end
end

mp.set_key_bindings({
  { "mbtn_left", release, press },
  { "mbtn_left_dbl", "ignore" },
}, BUTTON_SECTION, "force")
mp.set_key_bindings({
  { "mbtn_left", release },
}, RELEASE_SECTION, "force")
mp.set_key_bindings({
  { "mbtn_left_dbl", toggle_maximized },
}, DRAG_SECTION, "force")

mp.observe_property("osd-dimensions", "native", function(_, dimensions)
  window.width = dimensions and dimensions.w or 0
  window.height = dimensions and dimensions.h or 0
  refresh()
end)
mp.observe_property("display-hidpi-scale", "number", function(_, scale)
  window.scale = scale or 1
  refresh()
end)
mp.observe_property("mouse-pos", "native", function(_, position)
  if not position then
    return
  end
  local moved = position.x ~= pointer.x or position.y ~= pointer.y
  local inside_changed = position.hover ~= pointer.inside
  pointer.x = position.x
  pointer.y = position.y
  pointer.inside = position.hover
  if not pointer.inside and pressed then
    pressed = nil
    mp.disable_key_bindings(RELEASE_SECTION)
  end
  if moved then
    pointer.idle = false
    idle_timer:kill()
    local autohide = mp.get_property_number("cursor-autohide")
    if autohide then
      idle_timer.timeout = autohide / 1000
      idle_timer:resume()
    end
  end
  if not moved and not inside_changed then
    return
  end
  -- Skip full layout/ASS rebuild when the bar is hidden and stays hidden.
  if bar.visibility == 0 and not bar.pinned and not bar.flashing and target_visibility() == 0 then
    return
  end
  refresh()
end)
-- uosc reports a bottom margin exactly while its controls are pinned (paused,
-- audio, idle), so the title bar pins and unpins together with them.
mp.observe_property("user-data/osc/margins", "native", function(_, margins)
  bar.pinned = margins ~= nil and (margins.b or 0) > 0
  refresh()
end)
mp.observe_property("user-data/uosc/menu/type", "native", function(_, menu)
  bar.menu_open = menu ~= nil
  refresh()
end)
mp.observe_property("media-title", "string", function(_, title)
  media.title = title
  refresh()
end)
mp.observe_property("idle-active", "bool", function(_, idle)
  media.idle = idle or false
  refresh()
end)
mp.observe_property("playlist-pos-1", "number", function(_, position)
  media.position = position
  refresh()
end)
mp.observe_property("playlist-count", "number", function(_, count)
  media.count = count or 0
  refresh()
end)

local function update_chapter()
  local index = mp.get_property_number("chapter")
  local chapters = mp.get_property_native("chapter-list")
  local chapter = index and chapters and chapters[index + 1]
  media.chapter = chapter and chapter.title or nil
  refresh()
end
mp.observe_property("chapter", "number", update_chapter)
mp.observe_property("chapter-list", "native", update_chapter)

local function update_window_state()
  local fullscreen = mp.get_property_bool("fullscreen", false)
  local maximized = mp.get_property_bool("window-maximized", false)
  window.restored = not fullscreen and not maximized
  refresh()
end
mp.observe_property("fullscreen", "bool", update_window_state)
mp.observe_property("window-maximized", "bool", update_window_state)

-- Show the new title briefly when playback moves on to another file.
mp.register_event("file-loaded", function()
  bar.flashing = true
  flash_timer:kill()
  flash_timer:resume()
  refresh()
end)
mp.register_event("shutdown", function()
  overlay:remove()
  mp.set_property_number("video-margin-ratio-top", original_top)
  mp.set_property_number("osd-margin-y", original_osd_margin)
end)
