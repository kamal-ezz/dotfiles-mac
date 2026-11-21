# Configs

Personal terminal and editor configuration for macOS.

## Install

Install the tools with `brew bundle`, then preview and link the configs.

```sh
bash setup.sh --dry-run
bash setup.sh
```

The installer moves conflicting files into adjacent
`*.dotfiles-backup.*/original` paths, adds a theme hook to `~/.zshrc`, and
installs missing mpv plugins. Open a new Zsh session to load the hook.

## Neovim shortcuts

In normal mode, press Space and pause for 250 ms to show the shortcut menu.
Press the next key to run a command or open a group (Space `g` for Git).
Space `?` opens the menu immediately; Esc dismisses it. The menu uses the
descriptions on the existing keymaps and follows the active theme.

## Themes

Kitty, Ghostty, tmux, Starship, Neovim, mpv, btop, Lazygit, Delta, fzf and bat
share a theme. The installer links `theme` into `~/.local/bin`. Run it from
there or directly from this repo.

```sh
bin/theme catppuccin-mocha
```

- `theme` lists the themes and marks the active one.
- `theme NAME` switches every app. Running kitty, Ghostty, tmux and Neovim
  reload at once. mpv, btop, Lazygit, Delta, fzf and bat pick up the theme the
  next time they start.
- `theme rose-pine` selects Rosé Pine.
- fastfetch uses only the terminal's 16 colors, so it follows any theme.

Each folder in `themes/` defines one theme.

| File | Contents |
| --- | --- |
| `kitty.conf` | Terminal colors. Ghostty's theme is generated from this file. |
| `nvim.lua` | Adds the colorscheme plugin with `dotfiles_colorscheme_plugin()` and selects it. |
| `palette` | Color roles (`bg`, `fg`, `accent`, ...) for tmux, starship, mpv and btop. |
| `syntax-theme` | Optional theme name for bat and Delta. The default is `ansi`, which uses terminal colors. |

To add a theme, copy a folder, then replace its colors and colorscheme.
`theme` stops with an error if a palette role is missing or is not `#rrggbb`.

`theme` writes its output to `~/.config/dotfiles-theme`. The app configs
include those files. Starship cannot include files, so `~/.config/starship.toml`
is generated from `starship.toml` in this repo. After you edit
`starship.toml`, run `theme NAME` again.

## mpv

Each file in `mpv/` is symlinked to the same path under `~/.config/mpv`
(`mpv/tests/` stays in the repo; run it with `lua mpv/tests/playlist.lua`).

`mpv.conf` uses uosc for on-screen controls and thumbfast for seek-bar
previews. `setup.sh` installs missing plugins from pinned, SHA-256-verified
downloads.

uosc's clipboard helper (`ziggy-darwin`) is an Intel build, so pasting paths
into the playlist needs Rosetta on Apple Silicon.
