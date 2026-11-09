-- Extra autostart processes.
-- o.launch_on_start("my-service")

-- Dynamic night light: follows the real sun position (see night_light.jsonc).
-- The daemon applies the temperature to hyprsunset and runs a single instance.
o.exec_on_start(
  "setsid -f " .. os.getenv("HOME") .. "/.config/hypr/controllers/night_light_dynamic.py >/dev/null 2>&1"
)
