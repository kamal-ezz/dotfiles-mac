# Load theme settings for tools that accept a second config through the environment.
# Starship ignores XDG_CONFIG_HOME unless STARSHIP_CONFIG is set.
if [[ -z "${STARSHIP_CONFIG:-}" && -n "${XDG_CONFIG_HOME:-}" ]]; then
  export STARSHIP_CONFIG="$XDG_CONFIG_HOME/starship.toml"
fi

() {
  local config=${XDG_CONFIG_HOME:-$HOME/.config}
  if [[ -r $config/dotfiles-theme/fzf.opts ]]; then
    export FZF_DEFAULT_OPTS_FILE=$config/dotfiles-theme/fzf.opts
  fi
  if [[ -r $config/lazygit/config.yml && -r $config/dotfiles-theme/lazygit.yml ]]; then
    export LG_CONFIG_FILE=$config/lazygit/config.yml,$config/dotfiles-theme/lazygit.yml
  fi
}
