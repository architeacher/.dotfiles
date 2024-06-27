XDG_CACHE_HOME = os.getenv("XDG_CACHE_HOME")

-- [[ Basic Keymaps ]]
-- Set <space> as the leader key
-- See `:help mapleader`
--  NOTE: Must happen before plugins are required (otherwise wrong leader will be used)
vim.g.base16_colorspace = 256 -- Access colors present in 256 colorspace
vim.g.mapleader = ' '
vim.g.maplocalleader = ' '

-- ===============
-- EDITOR SETTINGS
-- ===============

local opt = vim.opt

opt.autoindent     = true -- Auto-indent new lines by copying indent from current line when starting new one.
opt.autochdir      = true -- Change working directory to open buffer.
opt.autoread       = true -- Reload file if changed outside of vim.
opt.autowrite      = true
opt.autowriteall   = true -- Auto-write all file changes
opt.backupdir      = { XDG_CACHE_HOME .. "/vim-tmp", XDG_CACHE_HOME .. "./tmp", XDG_CACHE_HOME .. "/tmp" }
opt.backspace      = { "indent", "eol", "start" } -- Controls backspace behaviour on indent, end of line or insert mode start position.
opt.breakindent    = true      -- Enables break indent.
opt.cindent        = true      -- Uses 'C' style program indenting.
opt.clipboard      = "unnamed" -- Put contents of unnamed register in OS X clipboard.
opt.colorcolumn    = "81"      -- A coloured column at 80 chars
opt.completeopt    = { "menu", "menuone", "noselect" } -- Set completeopt to have a better completion experience
opt.conceallevel   = 2     -- Concealer for Neorg
opt.confirm        = true  -- Prompts confirmation dialogs.
opt.cursorline     = true
opt.directory      = { XDG_CACHE_HOME .. "/vim-tmp", XDG_CACHE_HOME .. "./tmp", XDG_CACHE_HOME .. "/tmp" }
opt.encoding       = 'utf-8'
opt.errorbells     = true  -- Beeps or flash screen on errors
---- Folds
opt.foldlevelstart = 999
opt.foldcolumn     = "0"
opt.foldnestmax    = 3
-- opt.foldmethod = "expr"
opt.foldenable     = true
-- opt.foldexpr = "nvim_treesitter#foldexpr()"
opt.gdefault       = true --Always substitute all matches in a line
opt.hidden         = true -- allow buffers to be hidden before saving
opt.laststatus     = 2    -- Show Vim status all the time
opt.linebreak      = true -- Break lines at word (requires Wrap lines).
opt.list           = true
opt.listchars      = {
                           conceal = "※",
                           eol = "↲",
                           extends = "»",
                           nbsp = "␣",
                           precedes = "«",
                           space = ".",
                           tab = "¬ ",
                           trail = "•",
                         } -- Display tabs and trailing spaces visually
opt.mouse          = "n"   -- Mouse in NORMAL mode only, good for copy-pasting
opt.number         = true  -- Show line numbers
opt.numberwidth    = 5
--opt.relativenumber = true
opt.ruler         = true  -- Shows row and column ruler information.
opt.scrolloff     = 8     -- Keeps 8 lines visible around the cursor.
opt.showbreak     = "…"   -- Shows ellipsis prefix at Wrapped-broken lines.
opt.showcmd       = true
opt.showmatch     = true  -- Shows/Highlights the matching brace briefly when we close.
opt.showmode      = false
opt.showtabline   = 2     -- Shows the tab bar.
opt.sidescrolloff = 15    -- Keeps 15 chars to the right on scrolling
opt.signcolumn    = "yes" -- Reserve space for diagnostic sign column so that text doesn't shift.
opt.smartindent   = true  -- Enables smart-indent.
opt.smarttab      = true  -- Enables smart-tabs.
opt.spell         = true  -- Enables spell-checking.
opt.splitbelow    = true  -- Split horizontal window to the bottom.
opt.splitright    = true  -- Split vertical window to the right.
opt.swapfile      = false
opt.textwidth     = 100	  -- Line wrap (number of cols)
opt.termguicolors = true  -- Set termguicolors to enable highlight groups.
opt.timeoutlen    = 300
opt.title         = true  -- Update terminal title
opt.undodir       = XDG_CACHE_HOME .. "/vim/undo-dir"
opt.undofile      = true
opt.undolevels    = 10000  -- Max number of undo levels for the changes the can be undone.
opt.undoreload    = 100000 -- max number of lines to save for undo on a buffer reload
opt.updatetime    = 50
opt.virtualedit   = all    -- Enables free-range cursor.
opt.visualbell    = true   -- Use visual bell (no beeping).
opt.wildmenu      = true
opt.wildmode      = "longest:full" -- Configure auto completion in command line
opt.wildignore    = { ".hg", ".svn", "*~", "*.png", "*.jpg", "*.gif", "*.settings", "Thumbs.db", "*.min.js", "*.swp",
                       "publish/*", "intermediate/*", "*.o", "*.hi", "Zend", "vendor" }
opt.wrap          = false

-- use spaces for tabs and whatnot
opt.expandtab   = true -- Expands tab to spaces.
opt.softtabstop = 4    -- Number of spaces per Tab.
opt.shiftround  = true
opt.shiftwidth  = 4    -- Number of auto-indent spaces, 4 spaces for indent width.
opt.tabstop     = 4    -- 4 spaces for tabs (prettier default).

opt.isfname:append("@-@")

vim.cmd [[ set termguicolors ]]

vim.lsp.inlay_hint.enable(true, { 0 })

--Line numbers
vim.wo.number = true

vim.wo.signcolumn = 'yes'

vim.g.secure_modelines_allowed_items = {
    "textwidth", "tw",
    "softtabstop", "sts",
    "tabstop", "ts",
    "shiftwidth", "sw",
    "expandtab", "et", "noexpandtab", "noet",
    "filetype", "ft",
    "readonly", "ro", "noreadonly", "noro",
    "rightleft", "rl", "norightleft", "norl",
    "colorcolumn"
}

---- Undos, TODO: Migrate to lua
vim.cmd([[
  " Let's save undo info!
  if !isdirectory($XDG_CACHE_HOME."/vim")
    call mkdir($XDG_CACHE_HOME."/vim", "", 0770)
  endif
  if !isdirectory($XDG_CACHE_HOME."/vim/undo-dir")
    call mkdir($XDG_CACHE_HOME."/vim/undo-dir", "", 0700)
  endif
]])


vim.g.tmux_resizer_no_mappings = 0 -- Fix tmux resizing

-- Wrapping Options
-- o.formatoptions = o.formatoptions
--                    + 't'    -- auto-wrap text using textwidth
--                    + 'c'    -- auto-wrap comments using textwidth
--                    + 'r'    -- auto insert comment leader on pressing enter
--                    - 'o'    -- don't insert comment leader on pressing o
--                    + 'q'    -- format comments with gq
--                    - 'a'    -- don't autoformat the paragraphs (use some formatter instead)
--                    + 'n'    -- autoformat numbered list
--                    - '2'    -- I am a programmer and not a writer
--                    + 'j'    -- Join comments smartly
vim.o.formatoptions = vim.o.formatoptions .. 'tcrqnj'

---- Search
vim.o.incsearch  = true  -- Searches for strings incrementally.
vim.o.ignorecase = true  -- Always case-insensitive searching UNLESS /C or capital in search.
vim.o.smartcase  = true  -- Enables smart-case search and disables ignorecase if search term has capital letters.
vim.o.hlsearch   = true  -- Highlights all search results.

if vim.fn.has "nvim-0.7" then
    -- highlights yanked text for a little extra visual feedback
    -- so we don't need to rely on visual mode as much, try yip or y4y
    local api = vim.api
    local yankGrp = api.nvim_create_augroup("YankHighlight", { clear = true })
    api.nvim_create_autocmd("TextYankPost", {
        command = "silent! lua vim.highlight.on_yank()",
        group = yankGrp,
    })
    -- Windows to close with "q"
    api.nvim_create_autocmd(
        "FileType",
        { pattern = { "help", "startuptime", "qf", "lspinfo" }, command = [[nnoremap <buffer><silent> q :close<CR>]] }
    )
    api.nvim_create_autocmd("FileType", { pattern = "man", command = [[nnoremap <buffer><silent> q :quit<CR>]] })


    -- remove superfluous spaces at the end of files
    api.nvim_create_autocmd(
        "BufWritePre",
        { pattern = { "*.c", "*.cpp", "*.py", "*.rs" }, command = [[:%s/\s\+$//e]] }
    )

    -- check if we need to reload the file when it's changed
    api.nvim_create_autocmd(
        "FocusGained",
        { command = [[:checktime]] }
    )

    -- -- CursorLine gets background
    local cursorLine = api.nvim_create_augroup("CursorLine", { clear = true })
    api.nvim_create_autocmd({ "InsertLeave", "WinEnter" }, {
        pattern = "*",
        command = "set cursorline",
        group = cursorLine,
    })
    api.nvim_create_autocmd({ "InsertEnter", "WinLeave" }, {
        pattern = "*",
        command = "set nocursorline",
        group = cursorLine,
    })
end
