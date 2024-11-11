{ pkgs }:

let
  neovimInitLua = pkgs.writeText "init.lua" ''
-- Ugh.
vim.cmd [[source ${pkgs.vimPlugins.vim-plug}/plug.vim]]
vim.opt.runtimepath:append("${pkgs.vimPlugins.vim-plug}")

-- disable netrw at the very start of your init.lua
vim.g.loaded_netrw = 1
vim.g.loaded_netrwPlugin = 1

-- set termguicolors to enable highlight groups
vim.opt.termguicolors = true

-- Who wouldn't want syntax highlighting?
vim.opt.syntax = "enable"

-- filetype plugin indent on

vim.opt.foldmethod = "manual"

-- Last two lines of the window are status lines.
vim.opt.laststatus = 2

python3_host_prog = '/home/djshepard/.pyenv/versions/venv_py3nvim/bin/python'

loaded_perl_provider = 0

-- Parse this out if you must. Or just look at the status line and see if it's ok for you.
vim.opt.statusline = [[%<%f\ %h%m%r%=%-25.(ln=%l\ col=%c%V\ totlin=%L%)\ %h%m%r%=%-20(bval=0x%B,%n%Y%)%P]]

-- Bell-on-error is the worst. Especially when you have a HDMI bug that affects
-- Pulse Audio. :-/
vim.opt.errorbells = false

-- Better for the eyes
vim.opt.background = "dark"

-- Auto-enable mouse in terminal.
vim.opt.mouse = "a"

-- Hide mouse cursor when typing.
vim.opt.mousehide = true

-- Show last 5 lines when scrolling, so that you have some look-ahead room.
vim.opt.scrolloff = 5

--  no backup files
vim.opt.backup = false
vim.opt.writebackup = false

-- Helpful stuff in lower right.
vim.opt.showcmd = true

-- Match braces.
vim.opt.showmatch = true

-- Show whether in, i.e., visual/insert/etc.
vim.opt.showmode = true

-- show location in file (Top/Bottom/%).
vim.opt.ruler = true

-- sets fileformat to unix <N-L> not win <C-R><N-L>
vim.opt.fileformat = "unix"

-- sets unix files and backslashes to forward slashes even in windows
vim.opt.sessionoptions = vim.opt.sessionoptions + "unix,slash"

-- Give more space for displaying messages.
vim.opt.cmdheight = 2

-- Show line numbers.
vim.opt.number = true

-- Search as you type.
vim.opt.incsearch = true

-- Ignore case on search.
vim.opt.ignorecase = true

-- If capitalized, use as typed. Otherwise, ignore case.
vim.opt.smartcase = true

-- Controls how backspace works.
vim.opt.backspace = "2"

-- Use spaces instead of tabs.
vim.opt.expandtab = true

-- Use 4 space tabs.
vim.opt.tabstop = 4

-- Use 4 spaces when using <BS>.
vim.opt.softtabstop = 4

-- Use 4 spaces for tabs in autoindent.
vim.opt.shiftwidth = 4

-- Copy indent on next line when hitting enter, 
-- or using o or O cmd in insert mode.
vim.opt.autoindent = true

-- reload file automatically.
vim.opt.autoread = true

-- Attempt to indent based on 'rules'.
vim.opt.smartindent = true

-- hide buffers instead of unloading them
vim.opt.hidden = true

-- Run commands in a known shell.
vim.opt.shell = "/bin/sh"

-- Having longer updatetime (default is 4000 ms = 4 s) leads to noticeable
-- delays and poor user experience.
vim.opt.updatetime = 300

-- Don't pass messages to |ins-completion-menu|.
vim.opt.shortmess = vim.opt.shortmess + "c"

-- Always show the signcolumn, otherwise it would shift the text each time
-- diagnostics appear/become resolved.
vim.opt.signcolumn = "yes"

vim.opt.packpath = vim.opt.packpath + "$HOME/.config/nvim/pack"

local Plug = vim.fn['plug#']

vim.call('plug#begin')
Plug('parsonsmatt/intero-neovim')
Plug('tmux-plugins/vim-tmux-focus-events')
Plug('mracos/mermaid.vim', { branch = 'main' })
vim.call('plug#end')

local lazypath = vim.fn.stdpath("data") .. "/lazy/lazy.nvim"
if not vim.loop.fs_stat(lazypath) then
  vim.fn.system({
    "git", "clone", "--filter=blob:none", "https://github.com/folke/lazy.nvim.git", "--branch=stable", lazypath,
  })
end
vim.opt.rtp:prepend(lazypath)

vim.g.mapleader = " " -- Make sure to set `mapleader` before lazy so your mappings are correct

local lazy_plugins = {
  "folke/which-key.nvim",
  { "folke/neoconf.nvim", cmd = "Neoconf" },
  "folke/neodev.nvim",
  {
    "nvim-tree/nvim-tree.lua",
    version = "*",
    lazy = false,
    dependencies = {
      "nvim-tree/nvim-web-devicons",
    },
    config = function()
      require("nvim-tree").setup({
        sort_by = "case_sensitive",
        view = {
          width = 30,
        },
        renderer = {
          group_empty = true,
        },
        filters = {
          dotfiles = true,
        },
      })
    end,
  },
  { "ellisonleao/gruvbox.nvim", priority = 1000 , config = true, opts = ...},
  {
    "iamcco/markdown-preview.nvim",
    cmd = { "MarkdownPreviewToggle", "MarkdownPreview", "MarkdownPreviewStop" },
    ft = { "markdown" },
    build = function() vim.fn["mkdp#util#install"]() end,
  },
  {
    "nvim-treesitter/nvim-treesitter",
    build = ":TSUpdate",
    config = function () 
    local configs = require("nvim-treesitter.configs")

    configs.setup({
      ensure_installed = { "c", "lua", "vim", "vimdoc", "query", "elixir", "heex", "javascript", "html", "css", "meson", "python", "rust", "toml", "csv" },
      sync_install = false,
      highlight = { enable = true },
      indent = { enable = true },  
    })
    end
  },
}

require("lazy").setup(lazy_plugins, opts)

-- Default options:
require("gruvbox").setup({
  terminal_colors = true, -- add neovim terminal colors
  undercurl = true,
  underline = true,
  bold = true,
  italic = {
    strings = true,
    emphasis = true,
    comments = true,
    operators = false,
    folds = true,
  },
  strikethrough = true,
  invert_selection = false,
  invert_signs = false,
  invert_tabline = false,
  invert_intend_guides = false,
  inverse = true, -- invert background for search, diffs, statuslines and errors
  contrast = "hard", -- can be "hard", "soft" or empty string
  palette_overrides = {},
  overrides = {},
  dim_inactive = false,
  transparent_mode = false,
})
vim.cmd("colorscheme gruvbox")

-- Return to last edit position when opening files (You want this!)
vim.cmd([[
    autocmd BufReadPost *
         \ if line("'\"") > 0 && line("'\"") <= line("$") |
         \   exe "normal! g`\"" |
         \ endif
]])

vim.cmd([[
augroup remember_folds
  autocmd!
  autocmd BufWinLeave * mkview
  autocmd BufWinEnter * silent! loadview
augroup END
]])
  '';
in
neovimInitLua
