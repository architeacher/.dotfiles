return {
    {
        "stevearc/oil.nvim",
        dependencies = {
            "nvim-tree/nvim-web-devicons", -- optional, for file icons"
        },
        config = function()
            require "core.config.oil"
        end,
    }
}
