# Migration Prompt — Migrate `.conf` → `.lua` Configurations + Fixes (Hyprland/Omarchy)

Paste the prompt below on another computer with **opencode + deepseek** to reproduce
exactly the same process performed in this session.

---

## PROMPT TO PASTE

```
# Context
This machine is an Omarchy system (Arch Linux with Hyprland + Quickshell).
The ~/.config/hypr/ folder contains TWO coexisting configuration formats:
- .conf files (Hyprland's old native format)
- .lua files (Omarchy's new Lua format, using helpers such as hl.config,
  hl.bind, o.bind, hl.dsp, hl.monitor, o.window)

There are equivalent per-topic files: hyprland, autostart, bindings,
input, looknfeel, monitors (in .conf and .lua). There are also .conf-only
files: envs, hypridle, hyprlock, hyprsunset, xdph.

THE PREVIOUS SESSION ALREADY DID the tasks below. Execute each one EXACTLY as
described, in this order, and VALIDATE at the end.

## Task 1 — Create mapeamento.md
Create a ~/.config/hypr/mapeamento.md file in Portuguese that maps the
differences and similarities between the .conf and .lua files:
- List the 6 equivalent pairs (hyprland, autostart, bindings, input,
  looknfeel, monitors) and the 5 .conf-only files (envs, hypridle, hyprlock,
  hyprsunset, xdph).
- Compare structure: .conf uses "key = value" + { } blocks + source =; .lua uses
  helpers (hl.config, o.bind, hl.monitor, hl.env, hl.gesture) + require("hypr.x").
- Highlight the central difference: the .conf files hold ACTIVE configuration, most
  of the .lua files are COMMENTED OUT (they serve as override templates).
- Cite concrete examples per pair (e.g.: bindings.conf has ~30 active binds vs
  empty bindings.lua; looknfeel.lua is more complete than the .conf; monitors
  diverge on the active monitor).
Consult the real files before writing to be precise and specific.

## Task 2 — Move .conf files to backup_conf
Create the ~/.config/hypr/backup_conf/ folder and move ALL .conf files into it:
autostart.conf, bindings.conf, envs.conf, hypridle.conf, hyprland.conf,
hyprlock.conf, hyprsunset.conf, input.conf, looknfeel.conf, monitors.conf,
xdph.conf.
Do NOT move the .conf.bak files (old hypridle/hyprlock backups stay in the root).
NOTE: before moving, the .conf files are still the active configuration.
Their content will be the basis for the following tasks (read before moving).

## Task 3 — Fix Caps Lock (not working)
ROOT CAUSE: Omarchy's default in
/usr/share/omarchy/default/hypr/input.lua defines
kb_options = "compose:caps,shift:both_capslock_cancel", which maps Caps Lock
to the Compose key, disabling caps lock.
FIX: edit ~/.config/hypr/input.lua and add an ACTIVE hl.config({...}) block
that overrides that default:
  hl.config({
    input = {
      kb_layout = "br",
      kb_options = "",
      repeat_rate = 40,
      repeat_delay = 250,
      numlock_by_default = true,
      touchpad = { scroll_factor = 0.4 },
    },
  })
VALIDATION: run `hyprctl getoption input:kb_options`; it must return empty, and
`hyprctl configerrors` must be clean. Hyprland reloads when the file is saved.

## Task 4 — Analyze the keybinds from bindings.conf (section "# Adapar para o .lua")
READ the file ~/.config/hypr/backup_conf/bindings.conf. The section below the
comment "# Adapar para o .lua" contains custom shortcuts (brightness,
night light, gaps, close window, previous/next workspace, move window).
Check, against the defaults in /usr/share/omarchy/default/hypr/bindings/,
whether each shortcut is ALREADY used by another binding (conflict/duplicate). Do NOT change
anything here — only report the analysis.

## Task 5 — Adapt the shortcuts to bindings.lua
Edit ~/.config/hypr/bindings.lua and ADD (do not remove the existing template)
a block "Adapted from bindings.conf (section # Adapar para o .lua)" with:
- Brightness decrease/increase:
  o.bind("SUPER + SHIFT + CTRL + F5", "Decrease brightness", os.getenv("HOME") .. "/.config/hypr/controllers/decrease_brightness.sh")
  o.bind("SUPER + SHIFT + CTRL + F6", "Increase brightness", os.getenv("HOME") .. "/.config/hypr/controllers/increase_brightness.sh")
- Close window (replace the default SUPER+W with SUPER+Q):
  hl.unbind("SUPER + W")
  o.bind("SUPER + Q", "Close window", hl.dsp.window.close())
- Previous/next workspace — NAVIGATES THROUGH ALL workspaces, including empty ones:
  o.bind("SUPER + SHIFT + CTRL + LEFT", "Previous workspace", hl.dsp.focus({ workspace = "-1" }))
  o.bind("SUPER + SHIFT + CTRL + RIGHT", "Next workspace", hl.dsp.focus({ workspace = "+1" }))
- Move the active window to the previous/next workspace:
  o.bind("SUPER + CTRL + ALT + LEFT", "Move window to previous workspace", hl.dsp.window.move({ workspace = "-1" }))
  o.bind("SUPER + CTRL + ALT + RIGHT", "Move window to next workspace", hl.dsp.window.move({ workspace = "+1" }))
IMPORTANT ABOUT WORKSPACES: do NOT use "e-1"/"e+1" (only navigates between
EXISTING workspaces). Use "-1"/"+1" to navigate through ALL workspaces, even empty ones.
VALIDATION: `hyprctl binds` must list the new bindings and `hyprctl configerrors`
must be clean.

## Task 6 — Fix the active workspace dot above 9
PROBLEM: in the Omarchy workspace widget, the dot/indicator of the active
workspace does NOT appear when the workspace id is greater than 9.
ROOT CAUSE: in /usr/share/omarchy/shell/plugins/bar/widgets/Workspaces.qml the
workspaceIds() function had "if (id > 0 && id <= 10 ...)" — the limit id <= 10
excludes workspaces above 9, and the fixed initial list [1,2,3,4,5] made 6+ only
appear after they were created.
FIX (following Omarchy's pattern of NOT editing bundled files):
1. Clone the plugin: `omarchy plugin clone omarchy.workspaces`
   (creates ~/.config/omarchy/plugins/<user>.workspaces/ and switches the bar to
   the clone, updating shell.json with "id": "<user>.workspaces")
2. Edit the clone's Workspaces.qml. In workspaceIds():
   - Remove the "id <= 10" filter (accept any existing id > 0).
   - Add logic to always include the active workspace:
     var focusedId = Hyprland.focusedWorkspace !== null ? Hyprland.focusedWorkspace.id : -1
     if (focusedId > 0 && ids.indexOf(focusedId) === -1) ids.push(focusedId)
VALIDATION: navigate to a workspace > 9 (e.g.: hyprctl dispatch
"hl.dsp.focus({ workspace = \"13\" })") and the active workspace indicator must
appear. If it does not update, clear ~/.cache/quickshell/qmlcache/ and restart the
shell (`omarchy restart shell`) — Quickshell uses a compiled QML cache (.qmlc)
that can get stuck.

## Task 7 — Fix the foot.ini error in the terminal
PROBLEM: opening the foot terminal shows:
  error: foot: ~/.config/foot/foot.ini:21: [key-bindings].\n[text-bindings]:
  syntax error: key/value pair has no value
ROOT CAUSE: in ~/.config/foot/foot.ini there was a line with the literal text
"\n[text-bindings]" (line 21) inside/before the section, plus a DUPLICATED
[text-bindings] section.
FIX: remove the defective line "\n[text-bindings]" keeping only ONE
[text-bindings] section with the valid mappings:
  [text-bindings]
  \x1b[13;4u=Mod1+Shift+Return
  \x1b[13;2u=Shift+Return
VALIDATION: `foot --check-config` must exit 0 without errors.

## FINAL VALIDATION
Run and confirm with no errors:
- hyprctl configerrors
- hyprctl binds (lists the Task 5 bindings)
- hyprctl getoption input:kb_options (empty)
- foot --check-config
- Navigate to a workspace >9 and see the active indicator in the widget.

## GENERAL NOTES
- NEVER edit files in /usr/share/omarchy/ (it is read-only and overwritten
  on update). Use overrides in ~/.config/ and plugin clones.
- For Omarchy user config, follow the guide (omarchy skill):
  - Bar/plugins: ~/.config/omarchy/shell.json and clones in plugins/
  - Hyprland: ~/.config/hypr/*.lua
- Always validate with the commands above after each change.
```

---

## Execution notes

- **Critical order:** Task 2 (moving .conf) removes the active .conf configuration.
  Therefore Task 4/5 (adapting keybinds) depends on reading `backup_conf/bindings.conf`
  AFTER moving, or reading before moving and adapting afterwards. The prompt already
  says "read before moving".
- Task 6 depends on Quickshell running with Hyprland (it only makes sense
  on the target machine). If no Hyprland is running, the interactive validations
  (hyprctl) will not work.
- If the target machine's user is different from `luisao`, the plugin clone
  (Task 6) will create `<username>.workspaces` automatically.
