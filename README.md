# Configs

Personal terminal and editor configuration for macOS. 

## Neovim shortcuts

In normal mode, press Space and pause for 250 ms to show the shortcut menu.
Press the next key to run a command or open a group (Space `g` for Git).
Space `?` opens the menu immediately; Esc dismisses it. The menu uses the
descriptions on the existing keymaps and follows the active theme.

## Themes

kitty, Ghostty, tmux, starship, Neovim, mpv and btop share one color theme,
switched with `bin/theme`. Link it onto your PATH, then apply a theme once:

```sh
ln -s ~/dotfiles/bin/theme ~/.local/bin/theme
theme catppuccin-mocha
```

- `theme` lists the themes and marks the active one.
- `theme NAME` switches every app. Running kitty, Ghostty, tmux and Neovim
  reload at once. Open mpv and btop windows change when they restart.
- fastfetch uses only the terminal's 16 colors, so it follows any theme.

Each folder in `themes/` is one theme with three files:

| File | Contents |
| --- | --- |
| `kitty.conf` | Terminal colors. Ghostty's theme is generated from this file. |
| `nvim.lua` | Adds the colorscheme plugin with `dotfiles_colorscheme_plugin()` and selects it. |
| `palette` | Color roles (`bg`, `fg`, `accent`, ...) for tmux, starship, mpv and btop. |

To add a theme, copy a folder, then replace its colors and colorscheme.
`theme` stops with an error if a palette role is missing or is not `#rrggbb`.

`theme` writes its output to `~/.config/dotfiles-theme`. The app configs
include those files. Starship cannot include files, so `~/.config/starship.toml`
is generated from `starship.toml` in this repo. After you edit
`starship.toml`, run `theme NAME` again.

## mpv

Each file in `mpv/` is symlinked to the same path under `~/.config/mpv`
(`mpv/tests/` stays in the repo; run it with `lua mpv/tests/playlist.lua`).

`mpv.conf` turns off the built-in controls in favour of uosc, so install uosc
and thumbfast (seek-bar previews) alongside the symlinks:

```sh
curl -fsSL -o /tmp/uosc.zip https://github.com/tomasklaen/uosc/releases/latest/download/uosc.zip
unzip -oq /tmp/uosc.zip -d ~/.config/mpv && rm /tmp/uosc.zip
curl -fsSL -o ~/.config/mpv/scripts/thumbfast.lua \
  https://raw.githubusercontent.com/po5/thumbfast/master/thumbfast.lua
```

uosc's clipboard helper (`ziggy-darwin`) is an Intel build, so pasting paths
into the playlist needs Rosetta on Apple Silicon.
