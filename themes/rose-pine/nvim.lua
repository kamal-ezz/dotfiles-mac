dotfiles_colorscheme_plugin({ src = "https://github.com/rose-pine/neovim", name = "rose-pine" })
vim.o.background = "dark"
require("rose-pine").setup({ variant = "main" })
vim.cmd.colorscheme("rose-pine")
