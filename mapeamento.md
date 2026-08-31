# Mapeamento das Configurações do Hyprland — `.conf` vs `.lua`

Este documento mapeia com precisão as diferenças e semelhanças entre os dois
formatos de configuração que coexistem em `~/.config/hypr/`.

- **`.conf`** — formato nativo original do Hyprland. Nesta máquina foram
  **movidos para `backup_conf/`** (backup; já não são carregados).
- **`.lua`** — novo formato do Omarchy, carregado ativamente. Usa helpers
  (`hl.config`, `hl.bind`, `o.bind`, `hl.dsp`, `hl.monitor`, `hl.env`,
  `hl.gesture`) e `require("hypr.<nome>")`.

---

## 1. Inventário de arquivos

| Base | `.conf` | `.lua` | Status |
|------|---------|--------|--------|
| `hyprland` | sim | sim | ✅ par |
| `autostart` | sim | sim | ✅ par |
| `bindings` | sim | sim | ✅ par |
| `input` | sim | sim | ✅ par |
| `looknfeel` | sim | sim | ✅ par |
| `monitors` | sim | sim | ✅ par |
| `envs` | sim | **não** | ⚠️ só `.conf` |
| `hypridle` | sim | **não** | ⚠️ só `.conf` |
| `hyprlock` | sim | **não** | ⚠️ só `.conf` |
| `hyprsunset` | sim | **não** | ⚠️ só `.conf` |
| `xdph` | sim | **não** | ⚠️ só `.conf` |

> Todos os `.conf` estão em `backup_conf/`. Os arquivos `.conf.bak`
> (`hypridle.conf.bak.*`, `hyprlock.conf.bak.*`) são backups antigos e
> permanecem na raiz.

---

## 2. Diferenças estruturais (geral)

| Aspecto | `.conf` | `.lua` |
|---------|---------|--------|
| Sintaxe | `chave = valor`, blocos `{ }` | Lua: tabelas + helpers |
| Seções | `general { }`, `decoration { }`, `input { }` | chamadas `hl.config({ ... })` |
| Comentários | `#` | `--` |
| Carregamento | `source = <caminho>` no `hyprland.conf` | `require("hypr.<nome>")` no `hyprland.lua` |
| Helpers | nenhum | `hl.*`, `o.*` |
| Bindings | `bind` / `bindd` / `unbind` | `o.bind(...)`, `hl.unbind(...)` |
| Estado padrão | valores ativos | muitos valores **comentados** (template) |

---

## 3. Comparação par a par

### 3.1 `hyprland` (arquivo principal)
**Semelhanças:** ambos são o bootstrap que carrega os módulos na mesma ordem
(defaults Omarchy → monitors → input → bindings → looknfeel → autostart →
toggles) e ambos suportam desabilitar bindings padrão via
`omarchy_default_bindings` / `omarchy_preinstalled_bindings`.

**Diferenças:**
| `.conf` | `.lua` |
|---------|--------|
| `source = ~/.local/share/omarchy/default/hypr/...` para defaults | `dofile((os.getenv("OMARCHY_PATH") or "/usr/share/omarchy") .. "/default/hypr/bootstrap.lua")` + `require("default.hypr.omarchy")` |
| `source = ~/.config/hypr/*.conf` para arquivos do usuário | `require("hypr.monitors")`, `require("hypr.input")`, etc. |
| toggles por `source = ~/.local/state/omarchy/toggles/hypr/*.conf` | toggles por `require("default.hypr.toggles")` |
| carrega tema via `~/.local/state/omarchy/current/theme/hyprland.conf` | bootstrap resolve caminhos via `OMARCHY_PATH` |

### 3.2 `autostart`
| `.conf` (ativo) | `.lua` (vazio) |
|------------------|-----------------|
| `exec-once = hyprsunset` | só comentário `o.launch_on_start("my-service")` |
| `exec-once = hyprctl keyword input:kb_layout br && hyprctl keyword input:kb_model abnt2 && ...` | nada ativo |
| **conteúdo efetivo:** sim | **conteúdo efetivo:** não |

### 3.3 `bindings`
| `.conf` (ativo) | `.lua` |
|------------------|--------|
| ~30 binds ativos (apps, webapps, workspaces, brightness, gaps, night light, scratchpad) | template vazio + bloco "Adapted from bindings.conf" adicionado nesta sessão |
| usa `$terminal` / `$browser` como variáveis | não usa variáveis |
| usa `unbind` para substituir defaults | usa `hl.unbind` |
| chama `~/.config/hypr/controllers/*.sh` | os mesmos scripts (via `os.getenv("HOME")`) |

### 3.4 `input`
| `.conf` (ativo) | `.lua` |
|------------------|--------|
| `kb_layout = br`, `kb_options = grp:alts_toggle` | bloco `hl.config({...})` ATIVO (adicionado nesta sessão) com `kb_layout="br"`, `kb_options=""` |
| `repeat_delay = 600` | `repeat_delay = 250` |
| `windowrule = match:class (Alacritty|kitty|foot), scroll_touchpad 1.5` | `o.window("(Alacritty|kitty|foot)", { scroll_touchpad = 1.5 })` (comentado) |

**Nota:** o `.lua` foi editado para **restaurar o Caps Lock** — o default do
Omarchy mapeia Caps Lock como tecla Compose (`compose:caps`), então
`kb_options = ""` foi definido para desativar isso.

### 3.5 `looknfeel`
| `.conf` | `.lua` |
|---------|--------|
| `general` gaps comentados; só `rounding = 8` ativo | `gaps_in=0`, `gaps_out=5`, `border_size=2`, `rounding=8`, `dim_inactive=true`, `dim_strength=0.15` — todos ativos |
| sem `animations` / `scrolling` | blocos `animations` e `scrolling` comentados |

**Conclusão:** o `.lua` é mais rico e ativo que o `.conf`.

### 3.6 `monitors`
| `.conf` (ativo) | `.lua` (ativo) |
|------------------|-----------------|
| `monitor=HDMI-A-1,1360x768@60,auto,auto` + `env = GDK_SCALE,1` | `hl.monitor({ output="", mode="preferred", position="auto", scale=1.03 })` + `hl.env("GDK_SCALE","1")` |
| usa `auto` na escala | escala fixa `1.03` |
| variáveis inexistentes | variáveis `omarchy_gdk_scale`, `omarchy_monitor_scale` |

**Divergência:** os dois apontam monitores diferentes ativos.

---

## 4. Arquivos somente `.conf` (sem par Lua)

| Arquivo | Função |
|---------|--------|
| `envs.conf` | variáveis de ambiente (`GDK_SCALE`, `GDK_DPI_SCALE`, `QT_SCALE_FACTOR`, `QT_AUTO_SCREEN_SCALE_FACTOR`, `XCURSOR_SIZE`) |
| `hypridle.conf` | daemon idle (lock/suspensão/screensaver) |
| `hyprlock.conf` | tela de bloqueio (faz `source` do tema em `~/.config/omarchy/current/theme/hyprlock.conf`) |
| `hyprsunset.conf` | night light (perfis 07:00 identity / 18:00 2000K) |
| `xdph.conf` | portal de compartilhamento de tela (`hyprland-preview-share-picker`) |

> Estes continuam sem contraparte Lua no modelo Omarchy atual.

---

## 5. Mudanças realizadas nesta sessão (estado pós-migração)

1. **`.conf` movidos para `backup_conf/`** (Tarefa 2).
2. **`input.lua`**: adicionado bloco `hl.config` ativo para restaurar Caps Lock
   (`kb_layout="br"`, `kb_options=""`).
3. **`bindings.lua`**: adicionado bloco "Adapted from bindings.conf" com:
   - `SUPER+SHIFT+CTRL+F5/F6` → brightness (scripts em `controllers/`)
   - `SUPER+Q` → fechar janela (`hl.unbind("SUPER + W")` + `hl.dsp.window.close()`)
   - `SUPER+SHIFT+CTRL+LEFT/RIGHT` → workspace prev/next (**`-1`/`+1`**, todos os workspaces)
   - `SUPER+CTRL+ALT+LEFT/RIGHT` → mover janela para workspace prev/next (`-1`/`+1`)
4. **Correção Caps Lock**: removido `compose:caps` via `kb_options = ""`.
5. **Correção workspace > 9 no widget**: clonado `omarchy.workspaces` →
   `<usuario>.workspaces` e ajustado `workspaceIds()` (removido `id <= 10`,
   sempre inclui o workspace ativo).
6. **Correção `foot.ini`**: removida linha defeituosa `\n[text-bindings]` e a
   seção `[text-bindings]` duplicada.

---

## 6. Resumo das diferenças-chave

1. **Estado ativo vs template:** `.conf` ativos; `.lua` majoritariamente template.
2. **Sintaxe:** `key=value`+blocos vs helpers Lua.
3. **Carregamento:** `source=` vs `require()`.
4. **Bindings:** ~30 binds no `.conf` vs bloco adaptado menor no `.lua`.
5. **Input:** `.conf` ativo; `.lua` agora ativo (após correção Caps Lock).
6. **Look'n'feel:** `.lua` mais completo e ativo que o `.conf`.
7. **Monitores:** divergem no monitor ativo.
8. **Autostart:** `.conf` executa hyprsunset + seta layout; `.lua` vazio.
9. **Somente `.conf`:** envs, hypridle, hyprlock, hyprsunset, xdph.

## 7. Conclusão

Os dois formatos cobrem o mesmo escopo (principal, autostart, bindings, input,
looknfeel, monitors), mas NÃO são equivalentes em conteúdo efetivo: a
configuração real hoje vive majoritariamente no formato `.lua` ativo (após a
migração desta sessão), enquanto os `.conf` ficaram em backup em `backup_conf/`.
