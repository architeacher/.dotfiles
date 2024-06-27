return {
    {
        "hrsh7th/nvim-cmp",  -- Required
        event = "InsertEnter",
        lazy = false,
        priority = 100,
        dependencies = {
            { "hrsh7th/cmp-nvim-lsp" }, -- Required
            -- Snippets
            {
              "L3MON4D3/LuaSnip", -- Required
              tag = "v2.*",
              build = "make install_jsregexp",
              -- Snippet Collection (Optional)
              dependencies = { "rafamadriz/friendly-snippets" },
            },
        },
        opts = function(_, opts)
            opts.sources = opts.sources or {}
            table.insert(opts.sources, {
                name = "lazydev",
                group_index = 0, -- set group index to 0 to skip loading LuaLS completions
            })
        end,
        config = function()
            require "core.config.completion"
        end,
    },

    -- Additional lua configuration, makes nvim stuff amazing!
    {
        "folke/lazydev.nvim",
        ft = "lua", -- only load on lua files
        opts = {
            library = {
                -- See the configuration section for more details
                -- Load luvit types when the `vim.uv` word is found
                { path = "luvit-meta/library", words = { "vim%.uv" } },
            },
        },
    },

    { "hrsh7th/cmp-buffer" },
    { "hrsh7th/cmp-cmdline" },
    { "hrsh7th/cmp-path" },
    { "onsails/lspkind.nvim" },
    { "saadparwaiz1/cmp_luasnip" },

    { "github/copilot.vim" },

    ---- Annotation Toolkit
    { "danymat/neogen" },
    ---- Comments
    { "numToStr/Comment.nvim" },

    ---- End certain structures automatically.
    { "tpope/vim-endwise" },
}
