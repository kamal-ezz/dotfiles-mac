# Configs

Personal terminal and editor configuration for macOS. 

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
