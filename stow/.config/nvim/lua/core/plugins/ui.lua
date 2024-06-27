return {
    {
        "folke/noice.nvim",
        dependencies = {
            -- if you lazy-load any plugin below, make sure to add proper `module="..."` entries
            "MunifTanjim/nui.nvim",
            -- OPTIONAL:
            --   `nvim-notify` is only needed, if you want to use the notification view.
            --   If not available, we use `mini` as the fallback
            "rcarriga/nvim-notify",
        },
        config = function()
            require "core.config.ui"
        end,
    },
    {
        "folke/which-key.nvim",
        event = "VeryLazy",
        init = function()
            vim.o.timeout = true
            vim.o.timeoutlen = 500
        end,
        opts = {},
    },
    {
        "rmagatti/goto-preview",
        event = "BufEnter",
        config = true, -- necessary as per https://github.com/rmagatti/goto-preview/issues/88
    },
    {
        "rcarriga/nvim-notify",
        opts = {
            background_colour = "#000000",
            -- level = vim.log.levels.WARN, -- help vim.log.levels
            enabled = false,
            render = "minimal",
            stages = "static",
        },
    },

    { "j-hui/fidget.nvim", opts = {} },
}
