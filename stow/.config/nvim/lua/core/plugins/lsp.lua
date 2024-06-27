return {
    {
        "VonHeikemen/lsp-zero.nvim",
        branch = "v3.x",
        dependencies = {
            -- LSP Support
            { "neovim/nvim-lspconfig" }, -- Required
            { -- Optional
                "williamboman/mason.nvim",
                build = function()
                    pcall(vim.cmd, "MasonUpdate")
                end,
            },
            { "williamboman/mason-lspconfig.nvim" }, -- Optional
            { "WhoIsSethDaniel/mason-tool-installer.nvim" }, -- Optional

            -- Rust
            {
                "mrcjkb/rustaceanvim",
                version = "^4", -- Recommended
                lazy = false, -- This plugin is already lazy
            },
            { "simrat39/rust-tools.nvim" },
            {
                "saecki/crates.nvim",
                requires = { "nvim-lua/plenary.nvim" },
                config = function()
                    require("crates").setup()
                end,
            },

            -- Autoformatting
            "stevearc/conform.nvim",

            -- Schema information
            "b0o/SchemaStore.nvim",

            -- UI (Outline)
            "simrat39/symbols-outline.nvim",
        },
        config = function()
            require "core.config.lsp"
        end,
    },
}
