-- https://github.com/jascha030/macos-nvim-dark-mode
local os_is_dark = function()
    return (vim.call(
        'system',
        [[echo $(defaults read -globalDomain AppleInterfaceStyle &> /dev/null && echo 'dark' || echo 'light')]]
    )):find('dark') ~= nil
end

vim.api.nvim_set_hl(0, "Normal", { bg = "none" })
vim.api.nvim_set_hl(0, "NormalFloat", { bg = "none" })

vim.o.termguicolors = true
vim.o.background = "dark"
vim.cmd[[colorscheme catppuccin]]

require("catppuccin").setup({
    flavour = function()
        if not os_is_dark() then
            -- colorscheme catppuccin " catppuccin-latte, catppuccin-frappe, catppuccin-macchiato, catppuccin-mocha"
            return "latte"
        end

        return "mocha"
    end,
    transparent_background = true,
    integrations = {
        notify = true,
        mini = true,
    },
    styles = { -- Handles the styles of general hi groups (see `:h highlight-args`):
        comments = { "italic" }, -- Change the style of comments
    },
})
