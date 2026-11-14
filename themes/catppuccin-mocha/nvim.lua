dotfiles_colorscheme_plugin({ src = "https://github.com/catppuccin/nvim", name = "catppuccin" })
vim.o.background = "dark"
require("catppuccin").setup({ flavour = "mocha" })
vim.cmd.colorscheme("catppuccin")
