vim.opt.shortmess:append "c"

local lsp_kind = require "lspkind"
lsp_kind.init {}

local lua_snip = require ("luasnip")
local cmp = require "cmp"

local has_words_before = function()
    if vim.api.nvim_buf_get_option(0, "buftype") == "prompt" then return false end
    local line, col = unpack(vim.api.nvim_win_get_cursor(0))
    return col ~= 0 and vim.api.nvim_buf_get_text(0, line - 1, 0, line - 1, col, {})[1]:match("^%s*$") == nil
end

local cmp_config = require("lsp-zero").defaults.cmp_config({
    formatting = {
        format = lsp_kind.cmp_format({
            mode = "symbol",
            ellipsis_char = "...",
        })
    },
    mapping = {
        -- Github Copilot and TAB
        ["<Tab>"] = vim.schedule_wrap(function(fallback)
            if cmp.visible() and has_words_before() then
                cmp.select_next_item({ behavior = cmp.SelectBehavior.Select })
            elseif lua_snip.expand_or_jumpable() then
                lua_snip.expand_or_jump()
            else
                fallback()
            end
        end, { "i", "s" }),
        ["<S-Tab>"] = cmp.mapping(function(fallback)
            if cmp.visible() and has_words_before() then
                cmp.select_prev_item({ behavior = cmp.SelectBehavior.Select })
            elseif lua_snip.jumpable(-1) then
                lua_snip.jump(-1)
            else
                fallback()
            end
        end, { "i", "s" }),
        ["<C-Space>"] = cmp.mapping.complete(),
        ["<C-b>"] = cmp.mapping.scroll_docs(-4),
        ["<C-f>"] = cmp.mapping.scroll_docs(4),
        ["<CR>"] = cmp.mapping.confirm({
            behavior = cmp.ConfirmBehavior.Replace,
            select = true,
        }), -- Accept currently selected item. Set `select` to `false` to only confirm explicitly selected items.
        ["<C-n>"] = cmp.mapping.select_next_item { behavior = cmp.SelectBehavior.Insert },
        ["<C-p>"] = cmp.mapping.select_prev_item { behavior = cmp.SelectBehavior.Insert },
        ["<C-y>"] = cmp.mapping(
            cmp.mapping.confirm {
                behavior = cmp.ConfirmBehavior.Insert,
                select = true,
            },
            { "i", "c" }
        ),
    },
    sources = {
        -- Github copilot
        { name = "copilot",  group_index = 2 },
        -- Other sources
        { name = "buffer",   keyword_length = 3 },
        { name = "cody" },
        { name = "luasnip",  group_index = 1, keyword_length = 2 },
        { name = "neorg",    group_index = 2 },
        { name = "nvim_lsp", group_index = 2 },
        { name = "path",     group_index = 2 },
        {
            name = "spell",
            option = {
                keep_all_entries = false,
                enable_in_context = function()
                    return true
                end,
            },
        },
    },
    -- Enable luasnip to handle snippet expansion for nvim-cmp
    snippet = {
        expand = function(args)
            lua_snip.lsp_expand(args.body)
            --vim.snippet.expand(args.body)
        end,
    },
    view = {
        entries = "native"
    },
    window = {
        completion = cmp.config.window.bordered(),
        documentation = cmp.config.window.bordered(),
    },
})

cmp.setup(cmp_config)

-- Setup up vim-dadbod
cmp.setup.filetype({ "sql" }, {
    sources = {
        { name = "vim-dadbod-completion" },
        { name = "buffer" },
    },
})

require("luasnip.loaders.from_vscode").lazy_load()

-- Outline setup
require("symbols-outline").setup()
