dotfiles_colorscheme_plugin("https://github.com/folke/tokyonight.nvim")
vim.o.background = "dark"
require("tokyonight").setup({ style = "night" })
vim.cmd.colorscheme("tokyonight-night")
