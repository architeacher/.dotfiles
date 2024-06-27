return {
    {
        -- https://github.com/catppuccin/nvim
        "catppuccin/nvim",
        name = "catppuccin",
        priority = 1000,
        config = function()
            require "core.config.colorscheme"
        end,
    },
    "dracula/vim",
    "folke/tokyonight.nvim",
    { "rose-pine/neovim", name = "rose-pine" },
    "oahlen/iceberg.nvim",
}
