# Hyprland Configuration Mapping — `.conf` vs `.lua`

This document precisely maps the differences and similarities between the two
configuration formats that coexist in `~/.config/hypr/`.

- **`.conf`** — Hyprland's original native format. On this machine they were
  **moved to `backup_conf/`** (backup; no longer loaded).
- **`.lua`** — Omarchy's new format, actively loaded. Uses helpers
  (`hl.config`, `hl.bind`, `o.bind`, `hl.dsp`, `hl.monitor`, `hl.env`,
  `hl.gesture`) and `require("hypr.<name>")`.

---

## 1. File inventory

| Base | `.conf` | `.lua` | Status |
|------|---------|--------|--------|
| `hyprland` | yes | yes | ✅ paired |
| `autostart` | yes | yes | ✅ paired |
| `bindings` | yes | yes | ✅ paired |
| `input` | yes | yes | ✅ paired |
| `looknfeel` | yes | yes | ✅ paired |
| `monitors` | yes | yes | ✅ paired |
| `envs` | yes | **no** | ⚠️ `.conf` only |
| `hypridle` | yes | **no** | ⚠️ `.conf` only |
| `hyprlock` | yes | **no** | ⚠️ `.conf` only |
| `hyprsunset` | yes | **no** | ⚠️ `.conf` only |
| `xdph` | yes | **no** | ⚠️ `.conf` only |

> All `.conf` files are in `backup_conf/`. The `.conf.bak` files
> (`hypridle.conf.bak.*`, `hyprlock.conf.bak.*`) are old backups and remain
> in the root directory.

---

## 2. Structural differences (general)

| Aspect | `.conf` | `.lua` |
|--------|---------|--------|
| Syntax | `key = value`, `{ }` blocks | Lua: tables + helpers |
| Sections | `general { }`, `decoration { }`, `input { }` | `hl.config({ ... })` calls |
| Comments | `#` | `--` |
| Loading | `source = <path>` in `hyprland.conf` | `require("hypr.<name>")` in `hyprland.lua` |
| Helpers | none | `hl.*`, `o.*` |
| Bindings | `bind` / `bindd` / `unbind` | `o.bind(...)`, `hl.unbind(...)` |
| Default state | active values | many values **commented out** (template) |

---

## 3. Side-by-side comparison

### 3.1 `hyprland` (main file)
**Similarities:** both are the bootstrap that loads modules in the same order
(Omarchy defaults → monitors → input → bindings → looknfeel → autostart →
toggles) and both support disabling default bindings through
`omarchy_default_bindings` / `omarchy_preinstalled_bindings`.

**Differences:**
| `.conf` | `.lua` |
|---------|--------|
| `source = ~/.local/share/omarchy/default/hypr/...` for defaults | `dofile((os.getenv("OMARCHY_PATH") or "/usr/share/omarchy") .. "/default/hypr/bootstrap.lua")` + `require("default.hypr.omarchy")` |
| `source = ~/.config/hypr/*.conf` for user files | `require("hypr.monitors")`, `require("hypr.input")`, etc. |
| toggles via `source = ~/.local/state/omarchy/toggles/hypr/*.conf` | toggles via `require("default.hypr.toggles")` |
| loads theme via `~/.local/state/omarchy/current/theme/hyprland.conf` | bootstrap resolves paths via `OMARCHY_PATH` |

### 3.2 `autostart`
| `.conf` (active) | `.lua` (empty) |
|------------------|-----------------|
| `exec-once = hyprsunset` | only a comment `o.launch_on_start("my-service")` |
| `exec-once = hyprctl keyword input:kb_layout br && hyprctl keyword input:kb_model abnt2 && ...` | nothing active |
| **effective content:** yes | **effective content:** no |

### 3.3 `bindings`
| `.conf` (active) | `.lua` |
|------------------|--------|
| ~30 active binds (apps, webapps, workspaces, brightness, gaps, night light, scratchpad) | empty template + "Adapted from bindings.conf" block added in this session |
| uses `$terminal` / `$browser` as variables | does not use variables |
| uses `unbind` to replace defaults | uses `hl.unbind` |
| calls `~/.config/hypr/controllers/*.sh` | the same scripts (via `os.getenv("HOME")`) |

### 3.4 `input`
| `.conf` (active) | `.lua` |
|------------------|--------|
| `kb_layout = br`, `kb_options = grp:alts_toggle` | ACTIVE `hl.config({...})` block (added in this session) with `kb_layout="br"`, `kb_options=""` |
| `repeat_delay = 600` | `repeat_delay = 250` |
| `windowrule = match:class (Alacritty|kitty|foot), scroll_touchpad 1.5` | `o.window("(Alacritty|kitty|foot)", { scroll_touchpad = 1.5 })` (commented) |

**Note:** the `.lua` file was edited to **restore Caps Lock** — Omarchy's default
maps Caps Lock to the Compose key (`compose:caps`), so
`kb_options = ""` was set to disable it.

### 3.5 `looknfeel`
| `.conf` | `.lua` |
|---------|--------|
| `general` gaps commented out; only `rounding = 8` active | `gaps_in=0`, `gaps_out=5`, `border_size=2`, `rounding=8`, `dim_inactive=true`, `dim_strength=0.15` — all active |
| no `animations` / `scrolling` | `animations` and `scrolling` blocks commented out |

**Conclusion:** the `.lua` file is richer and more active than the `.conf` one.

### 3.6 `monitors`
| `.conf` (active) | `.lua` (active) |
|------------------|-----------------|
| `monitor=HDMI-A-1,1360x768@60,auto,auto` + `env = GDK_SCALE,1` | `hl.monitor({ output="", mode="preferred", position="auto", scale=1.03 })` + `hl.env("GDK_SCALE","1")` |
| uses `auto` for scale | fixed scale `1.03` |
| nonexistent variables | `omarchy_gdk_scale`, `omarchy_monitor_scale` variables |

**Divergence:** the two point to different active monitors.

---

## 4. `.conf`-only files (no Lua counterpart)

| File | Purpose |
|---------|--------|
| `envs.conf` | environment variables (`GDK_SCALE`, `GDK_DPI_SCALE`, `QT_SCALE_FACTOR`, `QT_AUTO_SCREEN_SCALE_FACTOR`, `XCURSOR_SIZE`) |
| `hypridle.conf` | idle daemon (lock/suspend/screensaver) |
| `hyprlock.conf` | lock screen (`source`s the theme in `~/.config/omarchy/current/theme/hyprlock.conf`) |
| `hyprsunset.conf` | night light (07:00 identity / 18:00 2000K profiles) |
| `xdph.conf` | screen sharing portal (`hyprland-preview-share-picker`) |

> These still have no Lua counterpart in the current Omarchy model.

---

## 5. Changes made in this session (post-migration state)

1. **`.conf` files moved to `backup_conf/`** (Task 2).
2. **`input.lua`**: added an active `hl.config` block to restore Caps Lock
   (`kb_layout="br"`, `kb_options=""`).
3. **`bindings.lua`**: added the "Adapted from bindings.conf" block with:
   - `SUPER+SHIFT+CTRL+F5/F6` → brightness (scripts in `controllers/`)
   - `SUPER+Q` → close window (`hl.unbind("SUPER + W")` + `hl.dsp.window.close()`)
   - `SUPER+SHIFT+CTRL+LEFT/RIGHT` → previous/next workspace (**`-1`/`+1`**, all workspaces)
   - `SUPER+CTRL+ALT+LEFT/RIGHT` → move window to previous/next workspace (`-1`/`+1`)
4. **Caps Lock fix**: removed `compose:caps` via `kb_options = ""`.
5. **Workspace > 9 widget fix**: cloned `omarchy.workspaces` →
   `<user>.workspaces` and adjusted `workspaceIds()` (removed `id <= 10`,
   always includes the active workspace).
6. **`foot.ini` fix**: removed the defective line `\n[text-bindings]` and the
   duplicated `[text-bindings]` section.

---

## 6. Summary of key differences

1. **Active state vs template:** `.conf` active; `.lua` mostly template.
2. **Syntax:** `key=value`+blocks vs Lua helpers.
3. **Loading:** `source=` vs `require()`.
4. **Bindings:** ~30 binds in `.conf` vs a smaller adapted block in `.lua`.
5. **Input:** `.conf` active; `.lua` now active (after the Caps Lock fix).
6. **Look'n'feel:** `.lua` more complete and active than `.conf`.
7. **Monitors:** they diverge on the active monitor.
8. **Autostart:** `.conf` runs hyprsunset + sets the layout; `.lua` empty.
9. **`.conf` only:** envs, hypridle, hyprlock, hyprsunset, xdph.

## 7. Conclusion

Both formats cover the same scope (main, autostart, bindings, input,
looknfeel, monitors), but they are NOT equivalent in effective content: the
real configuration today lives mostly in the active `.lua` format (after this
session's migration), while the `.conf` files were left as backups in `backup_conf/`.
