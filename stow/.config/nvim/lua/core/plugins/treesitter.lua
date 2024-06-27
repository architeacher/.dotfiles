return {
    {
        "nvim-treesitter/nvim-treesitter",
        dependencies = {
            -- Extended matchers for %
            "andymass/vim-matchup",
            "nvim-treesitter/nvim-treesitter-context",
            --"nvim-treesitter/nvim-treesitter-textobjects",
            -- Auto close <html> tags
            "windwp/nvim-ts-autotag",
        },
        build = ":TSUpdate",
        branch = "main",
        lazy = false,
        config = function()
            require("core.config.treesitter").setup()
        end,
    },
}
