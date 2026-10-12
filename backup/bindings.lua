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
-- Adapted from bindings.conf (section "# Adapar para o .lua")
-- ---------------------------------------------------------------------------

-- Brightness (decrease / increase)
o.bind("SUPER + SHIFT + CTRL + F5", "Decrease brightness", os.getenv("HOME") .. "/.config/hypr/controllers/decrease_brightness.sh")
o.bind("SUPER + SHIFT + CTRL + F6", "Increase brightness", os.getenv("HOME") .. "/.config/hypr/controllers/increase_brightness.sh")

-- Temperature (decrease / increase) — hyprsunset
o.bind("SUPER + CTRL + SHIFT + N", "Decrease temperature", os.getenv("HOME") .. "/.config/hypr/controllers/decrease_temperature.sh")
o.bind("SUPER + CTRL + ALT + N", "Increase temperature", os.getenv("HOME") .. "/.config/hypr/controllers/increase_temperature.sh")

-- Close windows (replace default SUPER + W)
hl.unbind("SUPER + W")
o.bind("SUPER + Q", "Close window", hl.dsp.window.close())

-- Switch to previous/next workspace (navigates all workspaces, including empty)
o.bind("SUPER + CTRL + LEFT", "Previous workspace", hl.dsp.focus({ workspace = "-1" }))
o.bind("SUPER + CTRL + RIGHT", "Next workspace", hl.dsp.focus({ workspace = "+1" }))

-- Move active window to previous/next workspace
o.bind("SUPER + CTRL + ALT + LEFT", "Move window to previous workspace", hl.dsp.window.move({ workspace = "-1" }))
o.bind("SUPER + CTRL + ALT + RIGHT", "Move window to next workspace", hl.dsp.window.move({ workspace = "+1" }))
