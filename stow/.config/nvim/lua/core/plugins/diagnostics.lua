return {
    "folke/trouble.nvim",
    dependencies = {
        "kyazdani42/nvim-web-devicons",
    },
    config = function()
        require "core.config.diagnostics"
    end
}
