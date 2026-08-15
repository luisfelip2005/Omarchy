# Mapeamento: configs `.conf` → `.lua`

Este documento mapeia as diferenças e semelhanças entre os dois formatos de
configuração coexistentes em `~/.config/hypr/` nesta máquina Omarchy.

## Visão geral

Existem dois formatos:

- **`.conf`** — formato nativo antigo do Hyprland (`key = value`, blocos `{ }`,
  `source =`, `bind`, `bindd`, `unbind`, `env`, `monitor`).
- **`.lua`** — novo formato Lua do Omarchy, usando helpers (`hl.config`,
  `o.bind`, `hl.unbind`, `hl.monitor`, `hl.env`, `hl.gesture`) e
  `require("hypr.x")` / `require("default.hypr.omarchy")`.

### Pares equivalentes (existem em `.conf` e `.lua`)

| Par | `.conf` | `.lua` |
|-----|---------|--------|
| Config principal | `hyprland.conf` | `hyprland.lua` |
| Autostart | `autostart.conf` | `autostart.lua` |
| Keybindings | `bindings.conf` | `bindings.lua` |
| Entrada/teclado | `input.conf` | `input.lua` |
| Aparência | `looknfeel.conf` | `looknfeel.lua` |
| Monitores | `monitors.conf` | `monitors.lua` |

### Arquivos somente `.conf`

| Arquivo | Função |
|---------|--------|
| `envs.conf` | Variáveis de ambiente (GDK_SCALE, QT_SCALE_FACTOR...) |
| `hypridle.conf` | Idle: screensaver e lock automático |
| `hyprlock.conf` | Tela de bloqueio |
| `hyprsunset.conf` | Perfis de night light |
| `xdph.conf` | XDG Desktop Portal (seletor de região) |

## Diferença central

Os arquivos **`.conf` estão com configuração ATIVA**. A maioria dos **`.lua` está
COMENTADA** (todo o corpo fica dentro de blocos `-- ...`), servindo como
*template de override* — o usuário descomenta o que quer alterar. As exceções são
`monitors.lua` e `hyprland.lua`, que já têm valores ativos.

O `hyprland.conf` referencia os `.conf` da própria pasta via `source =`:

```conf
source = ~/.config/hypr/monitors.conf
source = ~/.config/hypr/input.conf
source = ~/.config/hypr/bindings.conf
source = ~/.config/hypr/envs.conf
source = ~/.config/hypr/looknfeel.conf
source = ~/.config/hypr/autostart.conf
```

Já o `hyprland.lua` carrega os `.lua` por `require`:

```lua
require("hypr.monitors")
require("hypr.input")
require("hypr.bindings")
require("hypr.looknfeel")
require("hypr.autostart")
```

## Comparação por par

### hyprland
- **.conf**: grande arquivo de `source =` encadeando defaults
  (`~/.local/share/omarchy/default/hypr/*.conf`) e os overrides locais em
  `~/.config/hypr/*.conf`.
- **.lua**: usa `dofile(...)/default/hypr/bootstrap.lua` + `require("default.hypr.omarchy")`,
  depois carrega os overrides `hypr.*`. Expõe opções `omarchy_default_bindings`
  e `omarchy_preinstalled_bindings` (desligar binds padrão) que não existem no
  formato .conf.

### autostart
- **.conf**: ativo, com `exec-once = hyprsunset` e um `exec-once` que força
  `kb_layout br`, `kb_model abnt2` e `kb_options ""` via `hyprctl keyword`.
- **.lua**: só o comentário `-- o.launch_on_start("my-service")` (template vazio).

### bindings
- **.conf**: **ativo**, com ~30 binds de aplicativos (`bindd = SUPER SHIFT, N,
  Editor, exec, omarchy-launch-editor` etc.), 3 binds de workspace
  (`bind = SUPER ALT, UP/DOWN, workspace, -1/+1`), mover janela
  (`SUPER CTRL ALT, UP/DOWN`), fechar janela (`SUPER, Q`), gaps
  (`SUPER ALT, M`), brightness (`SUPER SHIFT CTRL, F5/F6`) e night light
  (`SUPER SHIFT, N`).
- **.lua**: vazio (só comentários de template), exceto o novo bloco adaptado
  desta migração.

### input
- **.conf**: ativo, com `kb_layout = br`, `kb_options = grp:alts_toggle`,
  `repeat_rate 40`, `repeat_delay 600`, `numlock_by_default`, `touchpad
  scroll_factor 0.4`, `windowrule` de scroll para terminais e `gesture`.
- **.lua**: template comentado. O default Omarchy em
  `/usr/share/omarchy/default/hypr/input.lua` define `kb_options =
  "compose:caps,..."` (Caps Lock como tecla Compose). O override ativo
  (adicionado nesta migração) zera `kb_options` para restaurar o Caps Lock.

### looknfeel
- **.conf**: ativo, mínimo — só `decoration.rounding = 8` e blocos
  `general`/`layout` quase vazios.
- **.lua**: mais completo que o .conf (mesmo comentado): cobre `general`,
  `decoration` (rounding, dim), `animations`, `layout` e até layout
  `scrolling` com `column_width`.

### monitors
- **.conf**: específico — `monitor=eDP-1,1920x1080@60,auto,1.25`, `GDK_SCALE,1`
  e `HDMI-A-1` em mirror do eDP-1.
- **.lua**: diverge — monitor genérico `output = ""`, `mode = "preferred"`,
  `scale = 1.33`, sem mirror.

## Observações

- Arquivos `.conf.bak` (backups antigos de hypridle/hyprlock) ficam na raiz,
  não na pasta `backup_conf/`.
- Os `.conf` foram movidos para `backup_conf/` nesta migração; a configuração
  ativa agora é a `.lua`.
- Scripts auxiliares usados pelos binds vivem em
  `~/.config/hypr/controllers/` (decrease/increase_brightness.sh,
  toggle_gaps.sh, toggle_night_light.sh).