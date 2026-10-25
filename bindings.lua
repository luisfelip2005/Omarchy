-- Keep only your personal keybinding overrides here. Add new bindings or
-- unbind defaults before replacing them.

-- See current bindings and descriptions:
--   omarchy menu keybindings --print

-- To disable every Omarchy default binding, set this in
-- ~/.config/hypr/hyprland.lua before require("default.hypr.omarchy"), then add
-- only the bindings you want below:
--   omarchy_default_bindings = false

-- To disable all preinstalled app/webapp bindings, set:
--   omarchy_preinstalled_bindings = false

-- Add a new binding.
-- o.bind("SUPER + SHIFT + R", "SSH", "alacritty -e ssh your-server")

-- Change an existing binding by unbinding it first, then binding the key again.
-- This example changes SUPER+SPACE from the launcher to the Omarchy root menu.
-- hl.unbind("SUPER + SPACE")
-- o.bind("SUPER + SPACE", "Omarchy menu", "omarchy-menu toggle root")

-- Disable a default binding without replacing it.
-- hl.unbind("SUPER + SHIFT + B")

-- Logitech MX Keys examples:
-- o.bind("SUPER + SHIFT + S", nil, "omarchy-capture-screenshot")
-- o.bind("SUPER + H", nil, "voxtype record toggle")
-- o.bind("SUPER + PERIOD", nil, "omarchy-shell shell toggle omarchy.emojis")

-- ---------------------------------------------------------------------------
-- Adapted from the hypr-laptop branch
-- ---------------------------------------------------------------------------

-- Brightness (gamma via hyprsunset)
o.bind("SUPER + SHIFT + CTRL + F5", "Decrease brightness", os.getenv("HOME") .. "/.config/hypr/controllers/decrease_brightness.sh")
o.bind("SUPER + SHIFT + CTRL + F6", "Increase brightness", os.getenv("HOME") .. "/.config/hypr/controllers/increase_brightness.sh")

-- Night light (hyprsunset): more orange = lower temperature
o.bind("SUPER + CTRL + SHIFT + N", "Night light: more orange (decrease temperature)", os.getenv("HOME") .. "/.config/hypr/controllers/decrease_temperature.sh")
o.bind("SUPER + CTRL + ALT + N", "Night light: less orange (increase temperature)", os.getenv("HOME") .. "/.config/hypr/controllers/increase_temperature.sh")

-- Close windows (replace default SUPER + W)
hl.unbind("SUPER + W")
o.bind("SUPER + Q", "Close window", hl.dsp.window.close())

-- Close all windows with confirmation pop-up (replace default CTRL + ALT + DELETE)
hl.unbind("CTRL + ALT + DELETE")
o.bind("CTRL + ALT + DELETE", "Close all windows (confirm)", os.getenv("HOME") .. "/.config/hypr/controllers/confirm_close_all.sh")

-- Switch to previous/next workspace (navigates all workspaces, including empty)
-- Unbind the default grouped-window focus on the same keys first.
hl.unbind("SUPER + CTRL + LEFT")
hl.unbind("SUPER + CTRL + RIGHT")
o.bind("SUPER + CTRL + LEFT", "Previous workspace", hl.dsp.focus({ workspace = "-1" }))
o.bind("SUPER + CTRL + RIGHT", "Next workspace", hl.dsp.focus({ workspace = "+1" }))

-- Move active window to previous/next workspace
o.bind("SUPER + CTRL + ALT + LEFT", "Move window to previous workspace", hl.dsp.window.move({ workspace = "-1" }))
o.bind("SUPER + CTRL + ALT + RIGHT", "Move window to next workspace", hl.dsp.window.move({ workspace = "+1" }))

-- Steam
o.bind("SUPER + SHIFT + T", "Steam", { launch = "steam" })

-- VSCode
o.bind("SUPER + SHIFT + V", "VSCode", { launch = "code" })

-- Mission Center
o.bind("SUPER + SHIFT + R", "Mission Center", { launch = "flatpak run io.missioncenter.MissionCenter" })

-- Stremio
o.bind("SUPER + SHIFT + U", "Stremio", { launch = "stremio" })

-- Winboat
o.bind("SUPER + SHIFT + K", "Winboat", { launch = "/opt/winboat/winboat" })

-- Toggle keyboard layout (br,us)
o.bind("SUPER + SHIFT + L", "Toggle keyboard layout", os.getenv("HOME") .. "/.config/hypr/controllers/toggle_keyboard.sh")
