return {
    {
        "lewis6991/gitsigns.nvim",
        config = function()
            require "core.config.git"
        end,
    },
    {
        "NeogitOrg/neogit",
        dependencies = {
            "nvim-lua/plenary.nvim",         -- required
            "sindrets/diffview.nvim",        -- optional - Diff integration
        },
        config = true
    },
    { "tpope/vim-fugitive" },
}
