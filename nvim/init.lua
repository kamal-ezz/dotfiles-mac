-- Options ------------------------------------------------------------------

vim.g.mapleader = " "
-- nvim-tree replaces netrw
vim.g.loaded_netrw = 1
vim.g.loaded_netrwPlugin = 1

vim.o.number = true
vim.o.signcolumn = "yes"
vim.o.tabstop = 2
vim.o.shiftwidth = 2
vim.o.softtabstop = 2
vim.o.expandtab = true
vim.o.ignorecase = true
vim.o.smartcase = true
vim.o.undofile = true
vim.o.clipboard = "unnamedplus"
vim.o.background = "dark"
vim.o.updatetime = 300
vim.o.completeopt = "menu,menuone,noselect,popup"

vim.diagnostic.config({
  virtual_text = false,
  virtual_lines = { current_line = true },
  signs = {
    text = {
      [vim.diagnostic.severity.ERROR] = "✘",
      [vim.diagnostic.severity.WARN] = "▲",
      [vim.diagnostic.severity.INFO] = "●",
      [vim.diagnostic.severity.HINT] = "◆",
    },
  },
  severity_sort = true,
  float = { border = "rounded", source = "if_many" },
})

-- Plugins ------------------------------------------------------------------

-- Build hooks must be registered before vim.pack.add() to run on first install
vim.api.nvim_create_autocmd("PackChanged", {
  callback = function(ev)
    local name, kind = ev.data.spec.name, ev.data.kind
    if name == "nvim-treesitter" and kind == "update" then
      if not ev.data.active then
        vim.cmd.packadd("nvim-treesitter")
      end
      vim.cmd("TSUpdate")
    end
  end,
})

vim.pack.add({
  { src = "https://github.com/catppuccin/nvim", name = "catppuccin" },
  "https://github.com/nvim-treesitter/nvim-treesitter",
  "https://github.com/neovim/nvim-lspconfig",
  "https://github.com/mason-org/mason.nvim",
  "https://github.com/mason-org/mason-lspconfig.nvim",
  "https://github.com/ibhagwan/fzf-lua",
  "https://github.com/nvim-tree/nvim-tree.lua",
  "https://github.com/nvim-tree/nvim-web-devicons",
  "https://github.com/akinsho/bufferline.nvim",
})

vim.cmd.colorscheme("catppuccin")

-- Treesitter: install parsers, then highlight any filetype that has one
require("nvim-treesitter").install({
  "bash", "css", "go", "gomod", "gosum", "html", "java", "javascript",
  "json", "kotlin", "lua", "markdown", "python", "rust", "tsx", "typescript",
})
vim.api.nvim_create_autocmd("FileType", {
  callback = function()
    pcall(vim.treesitter.start)
  end,
})

-- LSP: mason installs servers, mason-lspconfig enables every installed one
local servers = { "lua_ls", "pyright", "ts_ls", "jdtls", "kotlin_lsp" }
if vim.fn.executable("go") == 1 then
  table.insert(servers, "gopls")
end
if vim.fn.executable("cargo") == 1 then
  table.insert(servers, "rust_analyzer")
end
require("mason").setup()

-- Import the whole build, even when Neovim opens a file inside a submodule.
local function jvm_root(bufnr, on_dir)
  local file = vim.api.nvim_buf_get_name(bufnr)
  local git_root = vim.fs.root(file, ".git")
  local maven_root, gradle_root
  for dir in vim.fs.parents(file) do
    for _, marker in ipairs({ "settings.gradle", "settings.gradle.kts", "gradlew", "mvnw" }) do
      if vim.uv.fs_stat(dir .. "/" .. marker) then
        on_dir(dir)
        return
      end
    end
    -- Maven projects without a wrapper can have a pom.xml in every submodule.
    if vim.uv.fs_stat(dir .. "/pom.xml") then
      maven_root = dir
    end
    if not gradle_root and (vim.uv.fs_stat(dir .. "/build.gradle")
        or vim.uv.fs_stat(dir .. "/build.gradle.kts")) then
      gradle_root = dir
    end
    if dir == git_root then
      break
    end
  end
  local root = maven_root or gradle_root
  if root then
    on_dir(root)
  end
end

vim.lsp.config("jdtls", {
  root_dir = jvm_root,
  workspace_required = true,
  cmd = function(dispatchers, config)
    -- Hash the full path so equally named projects cannot share an Eclipse cache.
    local root = vim.uv.fs_realpath(config.root_dir) or config.root_dir
    local workspace = vim.fn.stdpath("cache") .. "/jdtls/" .. vim.fn.sha256(root)
    local cmd = { "jdtls", "-data", workspace, "--jvm-arg=-Xmx2G" }
    for arg in (vim.env.JDTLS_JVM_ARGS or ""):gmatch("%S+") do
      table.insert(cmd, "--jvm-arg=" .. arg)
    end
    return vim.lsp.rpc.start(cmd, dispatchers, {
      cwd = config.cmd_cwd,
      env = config.cmd_env,
      detached = config.detached,
    })
  end,
  settings = {
    java = {
      configuration = { updateBuildConfiguration = "automatic" },
      import = {
        maven = { enabled = true },
        gradle = { enabled = true, wrapper = { enabled = true } },
      },
    },
  },
  handlers = {
    ["language/status"] = function(_, result)
      if result and result.type == "Error" then
        vim.notify("Java import: " .. (result.message or "Unknown error; see :LspLog"), vim.log.levels.ERROR)
      end
    end,
  },
})
vim.lsp.config("kotlin_lsp", {
  root_dir = jvm_root,
  workspace_required = true,
})
-- Use JetBrains' server even if the older community server is installed.
vim.lsp.enable("kotlin_language_server", false)
require("mason-lspconfig").setup({
  ensure_installed = servers,
  automatic_enable = { exclude = { "kotlin_language_server" } },
})

-- Make lua_ls aware of the Neovim API when editing this config
vim.lsp.config("lua_ls", {
  settings = {
    Lua = {
      runtime = { version = "LuaJIT" },
      workspace = { library = { vim.env.VIMRUNTIME }, checkThirdParty = false },
    },
  },
})

-- Point rust_analyzer at the std sources so jumping into std reuses the project's
-- server; lspconfig's own lookup needs nightly cargo and fails on stable
if vim.fn.executable("rustc") == 1 then
  local sysroot = vim.trim(vim.fn.system({ "rustc", "--print", "sysroot" }))
  if vim.v.shell_error == 0 then
    vim.lsp.config("rust_analyzer", {
      settings = {
        ["rust-analyzer"] = {
          cargo = { sysrootSrc = sysroot .. "/lib/rustlib/src/rust/library" },
        },
      },
    })
  end
end

-- Built-in completion: popup appears as you type; <C-n>/<C-p> move, <C-y> accepts
vim.api.nvim_create_autocmd("LspAttach", {
  callback = function(ev)
    local client = vim.lsp.get_client_by_id(ev.data.client_id)
    if client and client:supports_method("textDocument/completion") then
      vim.lsp.completion.enable(true, client.id, ev.buf, { autotrigger = true })
    end
  end,
})

-- Fuzzy finder
local fzf = require("fzf-lua")
fzf.setup({
  files = { hidden = true },
  -- Search dotfiles too, but never inside .git (the default rg_opts plus a glob)
  grep = {
    hidden = true,
    rg_opts = '--column --line-number --no-heading --color=always --smart-case '
      .. '--max-columns=4096 -g "!.git" -e',
  },
})

-- File sidebar: follows the current file and shows dotfiles and gitignored files
require("nvim-tree").setup({
  hijack_directories = { auto_open = false },
  view = { width = { min = 30, max = 60 } },
  renderer = { group_empty = true },
  update_focused_file = { enable = true },
  filters = {
    dotfiles = false,
    git_ignored = false,
    custom = { "^\\.git$" },
  },
})

local tree = require("nvim-tree.api").tree

-- Close the sidebar when quitting the last file window, so :q exits Neovim
vim.api.nvim_create_autocmd("QuitPre", {
  callback = function()
    if vim.api.nvim_win_get_config(0).relative ~= "" then
      return
    end
    local wins = vim.tbl_filter(function(win)
      return vim.api.nvim_win_get_config(win).relative == ""
    end, vim.api.nvim_tabpage_list_wins(0))
    if #wins == 2 and tree.is_visible() then
      if vim.bo.filetype == "NvimTree" then
        -- Keep the window being quit alive until :q finishes.
        for _, win in ipairs(wins) do
          local buf = vim.api.nvim_win_get_buf(win)
          if vim.bo[buf].filetype ~= "NvimTree" and not vim.bo[buf].modified then
            vim.api.nvim_win_close(win, false)
          end
        end
      else
        tree.close()
      end
    end
  end,
})

-- Close a buffer like VS Code closes a tab: its window switches to the
-- neighboring buffer instead of closing and leaving the sidebar on its own
local function close_buffer(buf)
  buf = (buf == nil or buf == 0) and vim.api.nvim_get_current_buf() or buf
  if not vim.bo[buf].buflisted then
    return
  end
  if vim.bo[buf].modified then
    local name = vim.fn.bufname(buf)
    vim.notify("Unsaved changes in " .. (name ~= "" and name or "[No Name]"), vim.log.levels.WARN)
    return
  end
  local has_other = #vim.fn.getbufinfo({ buflisted = 1 }) > 1
  for _, win in ipairs(vim.fn.win_findbuf(buf)) do
    vim.api.nvim_win_call(win, function()
      vim.cmd(has_other and "bprevious" or "enew")
    end)
  end
  vim.cmd.bdelete(buf)
end

-- Tab bar of open buffers, starting to the right of the sidebar
require("bufferline").setup({
  highlights = require("catppuccin.special.bufferline").get_theme(),
  options = {
    close_command = close_buffer,
    right_mouse_command = close_buffer,
    diagnostics = "nvim_lsp",
    offsets = { { filetype = "NvimTree", text = "Explorer", separator = true } },
  },
})

-- Keymaps ------------------------------------------------------------------

local map = vim.keymap.set
map("i", "<C-Space>", vim.lsp.completion.get, { desc = "Trigger completion" })
map("n", "<M-l>", vim.lsp.buf.definition, { desc = "Go to definition" })
map("n", "<leader>f", function()
  vim.lsp.buf.format({ timeout_ms = 3000 })
end, { desc = "Format buffer" })

map("n", "<leader>e", "<cmd>NvimTreeToggle<cr>", { desc = "Toggle file sidebar" })
map("n", "<leader>>", "<cmd>NvimTreeResize +5<cr>", { desc = "Widen sidebar" })
map("n", "<leader><", "<cmd>NvimTreeResize -5<cr>", { desc = "Narrow sidebar" })
map("n", "<S-h>", "<cmd>BufferLineCyclePrev<cr>", { desc = "Previous buffer" })
map("n", "<S-l>", "<cmd>BufferLineCycleNext<cr>", { desc = "Next buffer" })
map("n", "<leader>x", close_buffer, { desc = "Close buffer" })

map("n", "<C-p>", fzf.files, { desc = "Find files" })
map("n", "<leader>/", fzf.live_grep, { desc = "Live grep" })
map("n", "<leader>b", fzf.buffers, { desc = "Buffers" })
map("n", "<leader>h", fzf.helptags, { desc = "Help" })
map("n", "<leader>d", fzf.diagnostics_document, { desc = "Diagnostics" })
map("n", "<leader>s", fzf.lsp_document_symbols, { desc = "Symbols" })
map("n", "<leader><leader>", fzf.resume, { desc = "Resume last picker" })

map("n", "<Esc>", "<cmd>nohlsearch<cr>", { desc = "Clear search highlighting" })
