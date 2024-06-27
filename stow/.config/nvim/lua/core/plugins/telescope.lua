return {
    "nvim-telescope/telescope.nvim",
    dependencies = {
        "nvim-lua/plenary.nvim",
        "nvim-telescope/telescope-fzf-native.nvim",
        "nvim-telescope/telescope-smart-history.nvim",
        "nvim-telescope/telescope-ui-select.nvim",
    },
    config = function()
        require "core.config.telescope"
    end,
}
