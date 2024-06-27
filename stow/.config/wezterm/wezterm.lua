local wezterm = require ("wezterm")
local theme = wezterm.plugin.require("https://github.com/neapsix/wezterm").moon

function deepMerge(target, source)
    for k, v in pairs(source) do
        if type(v) == "table" and type(target[k]) == "table" then
            deepMerge(target[k], v) -- Recursively merge nested tables
        else
            target[k] = v -- Copy value from source to target
        end
    end

    return target
end

function scheme_for_appearance(appearance)
    if appearance:find "Dark" then
        return "Catppuccin Mocha"
    else
        return "Catppuccin Latte"
    end
end

local parallax = require("config.parallax")

return deepMerge(
    parallax.setup(),
    {
        colors = theme.colors(),
        color_scheme = scheme_for_appearance(wezterm.gui.get_appearance()),
        font = wezterm.font("ComicShannsMono Nerd Font"),
        font_size = 18.0,
        keys = {
            {
                key = 'f',
                mods = 'CTRL',
                action = wezterm.action.ToggleFullScreen,
            },
            {
                key = '\'',
                mods = 'CTRL',
                action = wezterm.action.ClearScrollback 'ScrollbackAndViewport',
            },
        },
        macos_window_background_blur = 30,
        mouse_bindings = {
            -- Ctrl-click will open the link under the mouse cursor
            {
                event = { Up = { streak = 1, button = 'Left' } },
                mods = 'CTRL',
                action = wezterm.action.OpenLinkAtMouseCursor,
            },
        },
        window_background_opacity = 0.1,
        --window_decorations = 'RESIZE',
        window_frame = theme.window_frame(),
    }
)
