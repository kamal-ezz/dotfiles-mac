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
  "https://github.com/folke/tokyonight.nvim",
  "https://github.com/nvim-treesitter/nvim-treesitter",
  "https://github.com/neovim/nvim-lspconfig",
  "https://github.com/mason-org/mason.nvim",
  "https://github.com/mason-org/mason-lspconfig.nvim",
  "https://github.com/ibhagwan/fzf-lua",
  "https://github.com/nvim-tree/nvim-tree.lua",
  "https://github.com/nvim-tree/nvim-web-devicons",
  "https://github.com/akinsho/bufferline.nvim",
  "https://github.com/lewis6991/gitsigns.nvim",
  "https://github.com/sindrets/diffview.nvim",
})

-- Night variant matches the kitty and starship palettes
require("tokyonight").setup({ style = "night" })
vim.cmd.colorscheme("tokyonight-night")

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

-- Long merged folder chains (Maven packages) keep their last two names and
-- shorten the rest to initials: test/java/com/acme/billing/service becomes
-- t/j/c/a/billing/service. Dot-folders keep the dot (.github -> .g).
local function compact_group(path)
  if vim.fn.strchars(path) <= 24 then
    return path
  end
  local parts = vim.split(path, "/", { plain = true })
  for i = 1, #parts - 2 do
    parts[i] = vim.fn.strcharpart(parts[i], 0, vim.startswith(parts[i], ".") and 2 or 1)
  end
  return table.concat(parts, "/")
end

-- File sidebar: follows the current file and shows dotfiles and gitignored files
require("nvim-tree").setup({
  hijack_directories = { auto_open = false },
  -- Fit the longest visible name, capped so it never crowds out the editor
  view = { width = { min = 20, max = "40%" } },
  renderer = {
    group_empty = compact_group,
    -- Names cut off by the cap pop up in full under the cursor
    full_name = true,
  },
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
  options = {
    close_command = close_buffer,
    right_mouse_command = close_buffer,
    diagnostics = "nvim_lsp",
    offsets = { { filetype = "NvimTree", text = "Explorer", separator = true } },
  },
})

-- Git ----------------------------------------------------------------------

-- Gutter markers for changed lines, plus hunk actions on the line under the
-- cursor (or the selected lines, for stage/reset)
local gitsigns = require("gitsigns")
gitsigns.setup({
  current_line_blame_opts = { delay = 300 },
  on_attach = function(buf)
    local function bmap(mode, lhs, rhs, desc)
      vim.keymap.set(mode, lhs, rhs, { buffer = buf, desc = desc })
    end
    -- In a diff window ]c/[c keep their built-in meaning
    bmap("n", "]h", function()
      if vim.wo.diff then vim.cmd.normal({ "]c", bang = true }) else gitsigns.nav_hunk("next") end
    end, "Next change")
    bmap("n", "[h", function()
      if vim.wo.diff then vim.cmd.normal({ "[c", bang = true }) else gitsigns.nav_hunk("prev") end
    end, "Previous change")
    bmap("n", "<leader>gp", gitsigns.preview_hunk_inline, "Preview change")
    bmap("n", "<leader>gs", gitsigns.stage_hunk, "Stage/unstage change")
    bmap("n", "<leader>gr", gitsigns.reset_hunk, "Discard change")
    bmap("v", "<leader>gs", function()
      gitsigns.stage_hunk({ vim.fn.line("."), vim.fn.line("v") })
    end, "Stage/unstage selected lines")
    bmap("v", "<leader>gr", function()
      gitsigns.reset_hunk({ vim.fn.line("."), vim.fn.line("v") })
    end, "Discard selected lines")
    bmap("n", "<leader>gS", gitsigns.stage_buffer, "Stage file")
    bmap("n", "<leader>gR", gitsigns.reset_buffer, "Discard file changes")
    bmap("n", "<leader>gb", function() gitsigns.blame_line({ full = true }) end, "Blame line")
    bmap("n", "<leader>gB", gitsigns.toggle_current_line_blame, "Toggle inline blame")
  end,
})

-- Side-by-side diffs, file/branch history and 3-way merge conflicts.
-- Each key opens its view, or closes whichever diffview is open.
require("diffview").setup({ enhanced_diff_hl = true })
local function diffview(cmd)
  return function()
    if require("diffview.lib").get_current_view() then
      vim.cmd.DiffviewClose()
    else
      vim.cmd(cmd)
    end
  end
end

-- lazygit in a floating terminal. lazygit.yml uses the nvim-remote preset, so
-- editing a file from lazygit opens it here rather than in a nested Neovim.
local function lazygit()
  local prev = vim.api.nvim_get_current_win()
  local width = math.floor(vim.o.columns * 0.9)
  local height = math.floor(vim.o.lines * 0.85)
  local buf = vim.api.nvim_create_buf(false, true)
  local win = vim.api.nvim_open_win(buf, true, {
    relative = "editor",
    style = "minimal",
    border = "rounded",
    width = width,
    height = height,
    row = math.floor((vim.o.lines - height) / 2),
    col = math.floor((vim.o.columns - width) / 2),
  })
  vim.fn.jobstart({ "lazygit" }, {
    term = true,
    on_exit = function()
      vim.schedule(function()
        -- A file lazygit opened may have landed in the float; move it back.
        local shown = vim.api.nvim_win_is_valid(win) and vim.api.nvim_win_get_buf(win)
        if vim.api.nvim_win_is_valid(win) then
          vim.api.nvim_win_close(win, true)
        end
        if shown and shown ~= buf and vim.api.nvim_win_is_valid(prev) then
          vim.api.nvim_win_set_buf(prev, shown)
          vim.api.nvim_set_current_win(prev)
        end
        if vim.api.nvim_buf_is_valid(buf) then
          vim.api.nvim_buf_delete(buf, { force = true })
        end
        vim.cmd.checktime() -- pick up checkouts, stashes and rebases
        tree.reload()
      end)
    end,
  })
  vim.cmd.startinsert()
end

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
-- Manual resizes pin the width; this goes back to fitting the filenames
map("n", "<leader>=", function()
  tree.resize()
  tree.reload() -- re-measure now instead of on the next tree change
end, { desc = "Auto-fit sidebar" })
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

map("n", "<leader>gg", lazygit, { desc = "lazygit" })
map("n", "<leader>gd", diffview("DiffviewOpen"), { desc = "Diff all changes" })
map("n", "<leader>gh", diffview("DiffviewFileHistory %"), { desc = "File history" })
map("n", "<leader>gH", diffview("DiffviewFileHistory"), { desc = "Branch history" })
map("n", "<leader>gf", fzf.git_status, { desc = "Changed files" })
map("n", "<leader>gl", fzf.git_branches, { desc = "Branches" })

map("n", "<Esc>", "<cmd>nohlsearch<cr>", { desc = "Clear search highlighting" })
