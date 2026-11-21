#!/usr/bin/env bash
set -euo pipefail

repo_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
target_dir="$HOME"
dry_run=false

while (( $# )); do
  case "$1" in
    --dry-run)
      dry_run=true
      shift
      ;;
    --target-dir)
      if (( $# < 2 )) || [[ "$2" != /* ]]; then
        printf '%s\n' '--target-dir requires an absolute path' >&2
        exit 1
      fi
      target_dir="$2"
      shift 2
      ;;
    --help)
      printf '%s\n' 'Usage: bash setup.sh [--dry-run] [--target-dir /absolute/path]' \
        'Links the Mac configs, backing up files already at those paths.'
      exit 0
      ;;
    *)
      printf 'Unknown option: %s\n' "$1" >&2
      exit 1
      ;;
  esac
done

if [[ $(uname -s) != Darwin ]]; then
  printf '%s\n' 'Use dotfiles-linux for a Linux installation.' >&2
  exit 1
fi

config_dir="$target_dir/.config"

link_config() {
  local source="$repo_dir/$1" target="$2" backup_dir=
  if [[ -L $target && $source -ef $target ]]; then
    return
  fi
  if "$dry_run"; then
    if [[ -e $target || -L $target ]]; then
      printf 'Would back up: %s\n' "$target"
    fi
    printf 'Would link: %s -> %s\n' "$target" "$source"
    return
  fi
  mkdir -p -- "$(dirname -- "$target")"
  if [[ -e $target || -L $target ]]; then
    backup_dir=$(mktemp -d "$target.dotfiles-backup.XXXXXX")
    mv -- "$target" "$backup_dir/original"
    printf 'Backed up: %s -> %s/original\n' "$target" "$backup_dir"
  fi
  if ! ln -sh -- "$source" "$target"; then
    if [[ -n $backup_dir && ! -e $target && ! -L $target ]]; then
      mv -- "$backup_dir/original" "$target"
      rmdir -- "$backup_dir"
    fi
    return 1
  fi
  printf 'Linked: %s -> %s\n' "$target" "$source"
}

install_shell_hook() {
  local zshrc="$target_dir/.zshrc"
  local hook='[[ -r "$HOME/.config/dotfiles/theme.zsh" ]] && source "$HOME/.config/dotfiles/theme.zsh"'
  if [[ -f $zshrc ]] && grep -Fqx -- "$hook" "$zshrc"; then
    return
  fi
  if "$dry_run"; then
    printf 'Would add theme hook to: %s\n' "$zshrc"
    return
  fi
  printf '\n# Terminal theme settings from dotfiles.\n%s\n' "$hook" >> "$zshrc"
}

download_verified() {
  local url="$1" file="$2" sha="$3"
  curl --fail --location --proto '=https' --silent --show-error -o "$file" "$url"
  printf '%s  %s\n' "$sha" "$file" | shasum -a 256 -c
}

install_mpv_plugins() (
  local mpv_dir="$config_dir/mpv" stage
  local thumbfast_revision=0f711de3138c9bd6718209d819ac54022c23ded2
  local missing_uosc=false missing_thumbfast=false
  if [[ ! -f $mpv_dir/scripts/uosc/main.lua || ! -f $mpv_dir/fonts/uosc_icons.otf ||
        ! -f $mpv_dir/fonts/uosc_textures.ttf ]]; then
    missing_uosc=true
  fi
  if [[ ! -f $mpv_dir/scripts/thumbfast.lua ]]; then
    missing_thumbfast=true
  fi
  if ! "$missing_uosc" && ! "$missing_thumbfast"; then
    return
  fi
  if "$dry_run"; then
    if "$missing_uosc"; then printf 'Would install uosc 5.13.0\n'; fi
    if "$missing_thumbfast"; then printf 'Would install thumbfast %s\n' "$thumbfast_revision"; fi
    return
  fi
  stage=$(mktemp -d)
  trap 'find "$stage" -depth -delete' EXIT
  mkdir -p -- "$mpv_dir/scripts"
  if "$missing_uosc"; then
    download_verified https://github.com/tomasklaen/uosc/releases/download/5.13.0/uosc.zip \
      "$stage/uosc.zip" 4be9da3289285300fa374496c3f1bfd7bb20ac08e890d25bd5a06b28eebe4882
    unzip -nq "$stage/uosc.zip" -d "$mpv_dir"
  fi
  if "$missing_thumbfast"; then
    download_verified "https://codeload.github.com/po5/thumbfast/tar.gz/$thumbfast_revision" \
      "$stage/thumbfast.tar.gz" 2d16e9172750c222f7357e3523e41ee9da8fc148fb1e4c0d5f6ac8a317c3a96e
    tar -xOf "$stage/thumbfast.tar.gz" "thumbfast-$thumbfast_revision/thumbfast.lua" > "$stage/thumbfast.lua"
    mv -n -- "$stage/thumbfast.lua" "$mpv_dir/scripts/thumbfast.lua"
  fi
)

link_config .tmux.conf "$target_dir/.tmux.conf"
link_config bin/theme "$target_dir/.local/bin/theme"
link_config shell/theme.zsh "$config_dir/dotfiles/theme.zsh"
link_config ghostty.conf "$config_dir/ghostty/config"
link_config kitty/kitty.conf "$config_dir/kitty/kitty.conf"
link_config kitty/tab_bar.py "$config_dir/kitty/tab_bar.py"
link_config nvim/init.lua "$config_dir/nvim/init.lua"
link_config btop/btop.conf "$config_dir/btop/btop.conf"
link_config fastfetch/config.jsonc "$config_dir/fastfetch/config.jsonc"
link_config git/config "$config_dir/git/config"
link_config karabiner/karabiner.json "$config_dir/karabiner/karabiner.json"
link_config lazygit.yml "$config_dir/lazygit/config.yml"
link_config yazi.toml "$config_dir/yazi/yazi.toml"
for file in "$repo_dir"/mpv/*.conf "$repo_dir"/mpv/script-opts/*.conf "$repo_dir"/mpv/scripts/*.lua; do
  link_config "${file#"$repo_dir"/}" "$config_dir/${file#"$repo_dir"/}"
done
install_shell_hook

theme_name=catppuccin-mocha
if [[ -f $config_dir/dotfiles-theme/name ]]; then
  installed_theme=$(cat "$config_dir/dotfiles-theme/name")
  if [[ -n $installed_theme && -f $repo_dir/themes/$installed_theme/palette ]]; then
    theme_name=$installed_theme
  fi
fi
if "$dry_run"; then
  printf 'Would apply theme: %s\n' "$theme_name"
else
  DOTFILES_CONFIG_DIR="$config_dir" "$repo_dir/bin/theme" --no-reload "$theme_name"
fi
install_mpv_plugins
