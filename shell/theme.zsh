# Load theme settings for tools that accept a second config through the environment.
() {
  local config=$HOME/.config
  if [[ -r $config/dotfiles-theme/fzf.opts ]]; then
    export FZF_DEFAULT_OPTS_FILE=$config/dotfiles-theme/fzf.opts
  fi
  if [[ -r $config/lazygit/config.yml && -r $config/dotfiles-theme/lazygit.yml ]]; then
    export LG_CONFIG_FILE=$config/lazygit/config.yml,$config/dotfiles-theme/lazygit.yml
  fi
}
