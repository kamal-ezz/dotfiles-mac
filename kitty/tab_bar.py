"""Custom slanted powerline tab bar for Kitty.

Draws symmetric parallel-slanted ribbons ( … ) on the theme's dark bar:
  - Active tab: slanted accent index cap interlocked with an elevated overlay body
  - Inactive tabs: calm surface ribbons with a diagonal hairline (╱), colored
    activity/bell indicators, and clean app icons
  - Right edge: active keyboard mode badge (when active), else a quiet layout
    and tab-position counter when space allows

Reads ~/.config/dotfiles-theme/kitty-palette.json (written by bin/theme) and
reloads colors automatically on file modification (live theme switches).
"""
import json
import os
import re
import unicodedata

from kitty.fast_data_types import Screen, get_boss
from kitty.tab_bar import DrawData, ExtraData, TabBarData, as_rgb

SLANT_LEFT = "\ue0ba"   #   fg=right_color, bg=left_color
SLANT_RIGHT = "\ue0bc"  #   fg=left_color,  bg=right_color
SLANT_HAIR = "\u2571"   # ╱  matching diagonal hairline

BELL_ICON = "\U000f009a"     # 󰂚
ACTIVITY_ICON = "\u25cf"     # ●
ZOOM_ICON = "\U000f0293"     # 󰊓
FOLDER_ICON = "\U000f024b"   # 󰉋
TERM_ICON = "\ue795"         # 

APP_ICONS = {
    "nvim": "\ue6ae", "vim": "\ue6ae", "vi": "\ue6ae",
    "lazygit": "\ue702", "git": "\ue725", "gh": "\ue725",
    "yazi": "\U000f01e5", "ranger": "\U000f01e5", "lf": "\U000f01e5",
    "btop": "\U000f035b", "htop": "\U000f035b", "top": "\U000f035b",
    "tmux": "\uebc8",
    "ssh": "\U000f08c0", "mosh": "\U000f08c0",
    "python": "\ue73c", "python3": "\ue73c", "ipython": "\ue73c", "uv": "\ue73c",
    "node": "\ue718", "npm": "\ue718", "pnpm": "\ue718", "bun": "\ue718", "deno": "\ue718",
    "cargo": "\ue7a8", "rustc": "\ue7a8",
    "go": "\ue627",
    "docker": "\uf308",
    "claude": "\U000f06a9", "codex": "\U000f06a9", "agy": "\U000f06a9",
    "man": "\U000f0219", "less": "\U000f0219", "bat": "\U000f0219",
    "zsh": TERM_ICON, "bash": TERM_ICON, "fish": TERM_ICON, "sh": TERM_ICON,
}

LAYOUT_ICONS = {
    "tall": "\U000f0574",        # 󰕴
    "fat": "\U000f0574",
    "stack": ZOOM_ICON,          # 󰊓
    "grid": "\U000f0570",        # 󰕰
    "splits": "\U000f0574",
    "horizontal": "\U000f0574",
    "vertical": "\U000f0574",
}

SPINNER_RE = re.compile(r"^(?:[✳✶✻✽✢·◐◓◑◒⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏*]\s*)+")
USER_HOST_RE = re.compile(r"^[A-Za-z0-9._-]+@[A-Za-z0-9._-]+:\s*")

FALLBACK_HEX = {
    "bg": "#1e1e2e", "bg_dim": "#11111b", "surface": "#181825",
    "overlay": "#313244", "border": "#45475a", "fg": "#cdd6f4",
    "muted": "#7f849c", "accent": "#89b4fa", "accent2": "#cba6f7",
    "warn": "#f9e2af", "error": "#f38ba8", "success": "#a6e3a1",
}

_palette_cache = {"mtime": -1, "colors": None}


def _hex_to_rgb(value: str, fallback: str) -> int:
    s = value if isinstance(value, str) and re.fullmatch(r"#[0-9a-fA-F]{6}", value) else fallback
    return as_rgb(int(s[1:], 16))


def _load_palette() -> dict[str, int]:
    config = os.environ.get("XDG_CONFIG_HOME") or os.path.expanduser("~/.config")
    path = os.path.join(config, "dotfiles-theme", "kitty-palette.json")
    try:
        mtime = os.stat(path).st_mtime_ns
    except OSError:
        mtime = 0
    if _palette_cache["colors"] is not None and _palette_cache["mtime"] == mtime:
        return _palette_cache["colors"]
    raw = {}
    if mtime:
        try:
            with open(path, encoding="utf-8") as handle:
                raw = json.load(handle)
        except (OSError, json.JSONDecodeError):
            raw = {}
    colors = {k: _hex_to_rgb(raw.get(k, v), v) for k, v in FALLBACK_HEX.items()}
    _palette_cache["mtime"] = mtime
    _palette_cache["colors"] = colors
    return colors


def _cell_width(text: str) -> int:
    return sum(2 if unicodedata.east_asian_width(c) in "WF" else 1 for c in text)


def _truncate(text: str, limit: int) -> str:
    if limit <= 0:
        return ""
    if _cell_width(text) <= limit:
        return text
    if limit == 1:
        return "…"
    out = []
    used = 0
    for ch in text:
        w = 2 if unicodedata.east_asian_width(ch) in "WF" else 1
        if used + w > limit - 1:
            break
        out.append(ch)
        used += w
    return "".join(out).rstrip() + "…"


def _has_leading_icon(text: str) -> bool:
    if not text:
        return False
    cp = ord(text[0])
    return 0xE000 <= cp <= 0xF8FF or 0xF0000 <= cp <= 0xFFFFD


def _shorten_path(text: str) -> str:
    stripped = text.rstrip("/")
    if not stripped:
        return "/"
    if stripped == "~":
        return "~"
    parts = [p for p in stripped.split("/") if p]
    if len(parts) <= 1:
        return stripped
    return parts[-1]


def _format_title(raw_title: str) -> tuple[str, str]:
    """Return (icon, clean_title) from a raw tab title."""
    title = SPINNER_RE.sub("", (raw_title or "").strip())
    title = USER_HOST_RE.sub("", title).strip()
    if not title:
        return TERM_ICON, "shell"

    if _has_leading_icon(title):
        return "", title

    first, _, rest = title.partition(" ")
    base = os.path.basename(first).lower()
    if base in APP_ICONS:
        icon = APP_ICONS[base]
        if rest:
            arg = rest.strip()
            if arg.startswith(("~/", "/")) or "/" in arg:
                return icon, _shorten_path(arg)
            return icon, f"{base} {arg}" if base in ("git", "ssh", "docker", "man") else arg
        return icon, base

    if title.startswith(("~", "/", "./", "../")):
        return FOLDER_ICON, _shorten_path(title)

    return TERM_ICON, title


def _draw(screen: Screen, text: str, fg: int, bg: int, bold: bool = False) -> None:
    if not text:
        return
    screen.cursor.fg = fg
    screen.cursor.bg = bg
    screen.cursor.bold = bold
    screen.cursor.italic = False
    screen.draw(text)


def _draw_right_status(screen: Screen, colors: dict[str, int], min_x: int) -> None:
    try:
        boss = get_boss()
        mode = boss.mappings.current_keyboard_mode_name if boss else ""
        tm = boss.active_tab_manager if boss else None
        active_tab = tm.active_tab if tm else None
        tabs = list(tm.tabs) if tm else []
    except Exception:
        mode, active_tab, tabs = "", None, []

    bar_bg = colors["bg_dim"]
    if mode:
        label = f" {mode.upper()} "
        width = _cell_width(label) + 2
        start = screen.columns - width
        if start < min_x + 2:
            return
        screen.cursor.x = start
        _draw(screen, SLANT_LEFT, colors["warn"], bar_bg)
        _draw(screen, label, bar_bg, colors["warn"], bold=True)
        _draw(screen, SLANT_RIGHT, colors["warn"], bar_bg)
        return

    if not tabs or active_tab is None:
        return
    try:
        pos = tabs.index(active_tab) + 1
    except ValueError:
        return
    layout_name = getattr(getattr(active_tab, "current_layout", None), "name", "")
    layout_icon = LAYOUT_ICONS.get(layout_name, LAYOUT_ICONS["tall"])
    status = f"{layout_icon} {pos}/{len(tabs)}"
    width = _cell_width(status) + 2
    start = screen.columns - width
    if start < min_x + 4:
        return
    screen.cursor.x = start
    _draw(screen, f" {status} ", colors["muted"], bar_bg)


def draw_tab(
    draw_data: DrawData,
    screen: Screen,
    tab: TabBarData,
    before: int,
    max_tab_length: int,
    index: int,
    is_last: bool,
    extra_data: ExtraData,
) -> int:
    colors = _load_palette()
    bar_bg = colors["bg_dim"]
    idx_text = str(index)
    icon, title = _format_title(tab.title)

    has_bell = bool(tab.needs_attention)
    has_activity = bool(tab.has_activity_since_last_focus) and not tab.is_active
    is_stacked = tab.layout_name == "stack"
    splits = f" ·{tab.num_windows}" if tab.num_windows > 1 else ""

    if tab.is_active:
        #  {idx}  [bell ][icon ]{title}[ 󰊓][ ·N] 
        fixed = (
            1 + 1 + len(idx_text) + 1 + 1  #  + " idx " + 
            + 1                             # leading space in body
            + (2 if has_bell else 0)
            + (_cell_width(icon) + 1 if icon else 0)
            + (2 if is_stacked else 0)
            + _cell_width(splits)
            + 1 + 1                         # trailing space + 
        )
        title_budget = max(4, min(draw_data.max_tab_title_length or 24, max_tab_length - fixed))
        shown = _truncate(title, title_budget)

        _draw(screen, SLANT_LEFT, colors["accent"], bar_bg)
        _draw(screen, f" {idx_text} ", bar_bg, colors["accent"], bold=True)
        _draw(screen, SLANT_RIGHT, colors["accent"], colors["overlay"])
        _draw(screen, " ", colors["fg"], colors["overlay"])
        if has_bell:
            _draw(screen, f"{BELL_ICON} ", colors["error"], colors["overlay"], bold=True)
        if icon:
            _draw(screen, f"{icon} ", colors["accent"], colors["overlay"])
        _draw(screen, shown, colors["fg"], colors["overlay"], bold=True)
        if is_stacked:
            _draw(screen, f" {ZOOM_ICON}", colors["accent2"], colors["overlay"])
        if splits:
            _draw(screen, splits, colors["muted"], colors["overlay"])
        _draw(screen, " ", colors["fg"], colors["overlay"])
        _draw(screen, SLANT_RIGHT, colors["overlay"], bar_bg)
    else:
        #  {idx} ╱ [bell ][act ][icon ]{title}[ ·N] 
        fixed = (
            1 + 1 + len(idx_text) + 1 + 1 + 1  #  + " idx " + ╱ + " "
            + (2 if has_bell else 0)
            + (2 if has_activity else 0)
            + (_cell_width(icon) + 1 if icon else 0)
            + _cell_width(splits)
            + 1 + 1                             # trailing space + 
        )
        title_budget = max(4, min(draw_data.max_tab_title_length or 24, max_tab_length - fixed))
        shown = _truncate(title, title_budget)

        _draw(screen, SLANT_LEFT, colors["surface"], bar_bg)
        _draw(screen, f" {idx_text} ", colors["muted"], colors["surface"])
        _draw(screen, SLANT_HAIR, colors["border"], colors["surface"])
        _draw(screen, " ", colors["muted"], colors["surface"])
        if has_bell:
            _draw(screen, f"{BELL_ICON} ", colors["error"], colors["surface"])
        if has_activity:
            _draw(screen, f"{ACTIVITY_ICON} ", colors["accent2"], colors["surface"])
        if icon:
            _draw(screen, f"{icon} ", colors["muted"], colors["surface"])
        _draw(screen, shown, colors["muted"], colors["surface"])
        if splits:
            _draw(screen, splits, colors["border"], colors["surface"])
        _draw(screen, " ", colors["muted"], colors["surface"])
        _draw(screen, SLANT_RIGHT, colors["surface"], bar_bg)

    end = screen.cursor.x
    if not is_last and screen.cursor.x < screen.columns:
        _draw(screen, " ", colors["fg"], bar_bg)
    elif is_last:
        _draw_right_status(screen, colors, end)
    screen.cursor.bold = False
    screen.cursor.italic = False
    return end
