local parallax = {}

parallax.setup = function()
    local wezterm = require "wezterm"

    -- The art is a bit too bright and colorful to be useful as a backdrop
    -- for text, so we're going to dim it down to 10% of its normal brightness
    local dimmer = { brightness = 0.1, hue = 1.0, saturation = 1.02 }

    return {
        background = {
            -- This is the deepest/back-most layer. It will be rendered first
            {
                source = {
                    File = {
                        path = wezterm.home_dir .. "/.config/wezterm/images/backgrounds/spaceship_bg_3@2x.png",
                    },
                },
                -- When the viewport scrolls, move this layer 10% of the number of
                -- pixels moved by the main viewport. This makes it appear to be
                -- further behind the text.
                attachment = { Parallax = 0.1 },
                hsb = dimmer,
                -- The texture tiles vertically but not horizontally.
                -- When we repeat it, mirror it so that it appears "more seamless".
                -- An alternative to this is to set `width = "100%"` and have
                -- it stretch across the display
                repeat_x = "Mirror",
            },
            -- Subsequent layers are rendered over the top of each other
            {
                source = {
                    File = {
                        path = wezterm.home_dir .. "/.config/wezterm/images/overlays/overlay_1_spines@2x.png",
                        speed = 0.2,
                    },
                },

                -- The parallax factor is higher than the background layer, so this
                -- one will appear to be closer when we scroll
                attachment = { Parallax = 0.2 },
                hsb = dimmer,
                repeat_x = "NoRepeat",
                repeat_y_size = "200%",
                -- position the spins starting at the bottom, and repeating every
                -- two screens.
                vertical_align = "Bottom",
                width = "100%",
            },
            {
                source = {
                    File = {
                        path = wezterm.home_dir .. "/.config/wezterm/images/overlays/overlay_2_alienball@2x.png",
                        speed = 0.2,
                    },
                },
                attachment = { Parallax = 0.3 },

                hsb = dimmer,
                repeat_x = "NoRepeat",
                repeat_y_size = "200%",
                -- start at 10% of the screen and repeat every 2 screens
                vertical_offset = "10%",
                width = "100%",
            },
            {
                source = {
                    File = {
                        path = wezterm.home_dir .. "/.config/wezterm/images/overlays/overlay_3_lobster@2x.png",
                        speed = 0.2,
                    },
                },
                attachment = { Parallax = 0.4 },

                hsb = dimmer,
                repeat_x = "NoRepeat",
                repeat_y_size = "200%",
                vertical_offset = "30%",
                width = "100%",
            },
            {
                source = {
                    File = {
                        path = wezterm.home_dir .. "/.config/wezterm/images/overlays/overlay_4_spiderlegs@2x.png",
                        speed = 0.2,
                    },
                },
                attachment = { Parallax = 0.5 },

                hsb = dimmer,
                repeat_x = "NoRepeat",
                repeat_y_size = "150%",
                vertical_offset = "50%",
                width = "100%",
            },
            {
                source = {
                    Color = "#282c35",
                },
                width = "100%",
                height = "100%",
                opacity = 0.15,
            },
        },
        colors = {
            scrollbar_thumb = "white",
        },
        enable_scroll_bar = true,
        min_scroll_bar_height = "2cell",
        window_padding = {
            right = 15,
            left = 15,
            top = 10,
            bottom = 10,
        },
    }
end

return parallax
