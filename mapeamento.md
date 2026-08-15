# Mapeamento das Configurações do Hyprland — `.conf` vs `.lua`

Este documento mapeia as diferenças e semelhanças entre os dois formatos de
configuração presentes em `~/.config/hypr/`:

- **`.conf`** — formato nativo do Hyprland (arquivos antigos / padrão Omarchy, datados de `Jun 28`).
- **`.lua`** — novo formato baseado em Lua (migração em andamento, datados de `Aug 14`), usando helpers como `hl.config()`, `hl.bind()`, `o.window()`, etc.

A pasta contém **6 pares** de arquivos equivalentes e **5 arquivos somente `.conf`**.

---

## 1. Visão Geral dos Arquivos

| Base | `.conf` | `.lua` | Equivalente? |
|------|---------|--------|--------------|
| `hyprland` | sim | sim | ✅ |
| `autostart` | sim | sim | ✅ |
| `bindings` | sim | sim | ✅ |
| `input` | sim | sim | ✅ |
| `looknfeel` | sim | sim | ✅ |
| `monitors` | sim | sim | ✅ |
| `envs` | sim | **não** | ⚠️ só `.conf` |
| `hypridle` | sim | **não** | ⚠️ só `.conf` |
| `hyprlock` | sim | **não** | ⚠️ só `.conf` |
| `hyprsunset` | sim | **não** | ⚠️ só `.conf` |
| `xdph` | sim | **não** | ⚠️ só `.conf` |

---

## 2. Diferenças Estruturais Gerais

| Aspecto | `.conf` | `.lua` |
|---------|---------|--------|
| Sintaxe | chaves e pares `key = value` | Lua (`table`, `function`) |
| Seções | blocos `general { ... }`, `decoration { ... }` | chamadas `hl.config({ ... })` |
| Comentários | `#` | `--` |
| Carregamento | `source = <caminho>` explícito no `hyprland.conf` | `require("hypr.<nome>")` no `hyprland.lua` |
| Helpers | nenhum | `hl.config`, `hl.bind`, `hl.unbind`, `o.window`, `o.launch_on_start`, `hl.env`, `hl.monitor`, `hl.gesture`, `hl.dispatch` |
| Padrão de bind | `bind` / `bindd` / `unbind` | `o.bind(...)`, `hl.unbind(...)` |
| Comportamento | valores ativos direto | muitos valores **comentados** (modelo para override) |

> **Nota importante:** os arquivos `.lua` estão majoritariamente **comentados**
> (servem como modelo/template de personalização), enquanto os `.conf` contêm
> **valores ativos**. Ou seja, o conteúdo "efetivo" hoje está principalmente no
> formato `.conf`.

---

## 3. Comparação Par a Par

### 3.1 `hyprland.conf` vs `hyprland.lua`

**Semelhanças:**
- Ambos são o arquivo "principal"/bootstrap que carrega os demais módulos.
- Ambos carregam na mesma ordem lógica: defaults Omarchy → monitors → input → bindings → looknfeel → autostart → toggles.
- Ambos permitem desabilitar bindings padrão via flag (`omarchy_default_bindings` / `omarchy_preinstalled_bindings`).

**Diferenças:**
| `.conf` | `.lua` |
|---------|--------|
| Usa `source = ~/.local/share/omarchy/default/hypr/...` para defaults | Usa `dofile((os.getenv("OMARCHY_PATH") or "/usr/share/omarchy") .. "/default/hypr/bootstrap.lua")` e `require("default.hypr.omarchy")` |
| Defaults source de `~/.local/share/omarchy/default/hypr/` (autostart, media, clipboard, tiling-v2, utilities, envs, looknfeel, input, windows) + tema `~/.local/state/omarchy/current/theme/hyprland.conf` | Bootstrap via variável `OMARCHY_PATH` |
| Usa `source = ~/.config/hypr/*.conf` para os arquivos do usuário | Usa `require("hypr.monitors")`, `require("hypr.input")`, etc. |
| Carrega toggles por `source = ~/.local/state/omarchy/toggles/hypr/*.conf` | Carrega toggles por `require("default.hypr.toggles")` |
| Não carrega `monitors`/`input` via lua (usa caminhos .conf) | Já carrega `hypr.monitors` e `hypr.input` |
| Exemplo de window rule: comentário | Exemplo: `o.window("qemu", { workspace = "5" })` comentado |

### 3.2 `autostart.conf` vs `autostart.lua`

**Semelhanças:**
- Ambos servem para definir processos que iniciam junto com o Hyprland.
- Ambos começam com um exemplo comentado de como adicionar um serviço.

**Diferenças:**
| `.conf` (ativo) | `.lua` (vazio/template) |
|------------------|--------------------------|
| Usa `exec-once = hyprsunset` | **nenhum** processo configurado |
| Usa `exec-once = hyprctl keyword input:kb_layout br && hyprctl keyword input:kb_model abnt2 && hyprctl keyword input:kb_options ""` (força layout BR/abnt2 no boot) | apenas comentário `o.launch_on_start("my-service")` |
| Inclui o set de keyboard layout via `hyprctl keyword` | usa helper `o.launch_on_start(...)` |
| **Conteúdo efetivo:** sim | **Conteúdo efetivo:** não (só template) |

> Os dois **não são equivalentes em efeito**: o `.conf` executa processos reais,
> o `.lua` está vazio. Se migrar para Lua, o conteúdo ativo precisaria ser
> recriado com `o.launch_on_start`.

### 3.3 `bindings.conf` vs `bindings.lua`

**Semelhanças:**
- Ambos gerenciam keybindings.
- Ambos documentam como desabilitar defaults (`omarchy_default_bindings`, `omarchy_preinstalled_bindings`).
- Ambos mencionam `hl.unbind`/`unbind` para sobrescrever bindings padrão.

**Diferenças:**
| `.conf` (ativo) | `.lua` (template vazio) |
|------------------|--------------------------|
| **~30 binds ativos**: apps (`$terminal`, browser, nautilus, code, spotify, cliamp, btop, lazydocker, signal, obsidian, 1password), webapps (ChatGPT, Grok, Calendar, Email, YouTube, WhatsApp, Google Messages, X), workspaces (`bind = SUPER ALT UP/DOWN`), killactive, gaps, brightness, night light, scratchpad | **nenhum bind ativo** — apenas exemplos comentados |
| Usa `bindd = SUPER ALT, RETURN, Tmux, exec, ...` (com descrição) | exemplo `o.bind("SUPER + SHIFT + R", "SSH", "alacritty -e ssh your-server")` |
| Usa variáveis `$terminal`, `$browser` | não usa variáveis |
| Usa `unbind = SUPER, W, killactive` e remapeia `bind = SUPER, Q, killactive` | exemplo `hl.unbind("SUPER + SHIFT + B")` |
| Chama scripts de `~/.config/hypr/controllers/*.sh` (gaps, brightness, night light) | não referencia controllers |
| Usa `togglespecialworkspace` para scratchpad | não menciona scratchpad |

> **Diferença forte:** o `.conf` tem toda a configuração de teclas de fato;
> o `.lua` é apenas um esqueleto de exemplos. Migrar para Lua exigiria
> reproduzir ~30 binds com `o.bind`.

### 3.4 `input.conf` vs `input.lua`

**Semelhanças:**
- Ambos configuram `kb_layout`, `kb_options`, `repeat_rate`, `numlock_by_default`, `touchpad.scroll_factor`.
- Ambos tratam scroll de apps (Alacritty/kitty/foot, ghostty) e gestos de touchpad.
- Ambos têm valores **comentados** para opções alternativas.

**Diferenças:**
| `.conf` (ativo) | `.lua` (tudo comentado) |
|------------------|--------------------------|
| `kb_layout = br`, `kb_options = grp:alts_toggle` **ativos** | todo o bloco `hl.config({ input = {...} })` **comentado** |
| `repeat_rate = 40`, `repeat_delay = 600` ativos | exemplo com `repeat_delay = 250` (comentado) |
| `numlock_by_default = true` ativo | exemplo `numlock_by_default = true` comentado |
| `touchpad.scroll_factor = 0.4` ativo | exemplo `scroll_factor = 0.4` comentado |
| `windowrule = match:class (Alacritty|kitty|foot), scroll_touchpad 1.5` e ghostty `0.2` **ativos** | `o.window("(Alacritty|kitty|foot)", { scroll_touchpad = 1.5 })` e ghostty **comentados** |
| gestos: comentados | gestos com `hl.gesture` comentados (inclui mover foco esquerda/direita) |
| sintaxe `windowrule = match:class ...` | sintaxe `o.window("regex", { scroll_touchpad = ... })` |

> **Equivalência lógica:** os mesmos parâmetros, mas no `.conf` estão **ativos**
> e no `.lua` estão **todos desativados** (comentados). Diferença de valor:
> `repeat_delay` (600 vs 250 no exemplo) e `kb_options` (`grp:alts_toggle` vs um conjunto maior).

### 3.5 `looknfeel.conf` vs `looknfeel.lua`

**Semelhanças:**
- Ambos configuram `general` (gaps/layout) e `decoration` (`rounding`).
- Ambos têm exemplos comentados de `layout` (`single_window_aspect_ratio`).
- Ambos documentam o layout alternativo.

**Diferenças:**
| `.conf` | `.lua` |
|---------|--------|
| `general`: gaps **comentados** (dois cenários propostos: 5/10 ou 0/0) | `general`: gaps **ativos** (`gaps_in = 0`, `gaps_out = 5`, `border_size = 2`) |
| `layout` comentado | `layout` (exemplo scrolling) comentado |
| `decoration.rounding = 8` **ativo** | `decoration.rounding = 8` **ativo** + `dim_inactive = true`, `dim_strength = 0.15` **ativos** |
| não tem `animations` | bloco `animations` comentado (desabilitar animações) |
| não tem `scrolling` | bloco `scrolling` comentado (`column_width = 0.97`) |
| não configura bordas | `border_size = 2` ativo |
| não configura dim | configura dim de janelas inativas |

> **Diferença significativa:** o `.lua` é **mais rico** — define gaps, bordas e
> dim de forma ativa, enquanto o `.conf` deixa gaps e layout em comentário e
> só aplica `rounding`. Há **conflito potencial**: `.conf` sugere gaps 0/0 ou
> 5/10 comentados, `.lua` aplica 0/5 ativo.

### 3.6 `monitors.conf` vs `monitors.lua`

**Semelhanças:**
- Ambos configuram `GDK_SCALE` via env.
- Ambos documentam múltiplos cenários de monitor (2x retina, laptop, 4K, 1x).
- Ambos usam formato `[porta], resolução, posição, escala`.

**Diferenças:**
| `.conf` (ativo) | `.lua` (ativo) |
|------------------|-----------------|
| `env = GDK_SCALE,1` **ativo** | `hl.env("GDK_SCALE", tostring(1))` ativo |
| `monitor=HDMI-A-1,1360x768@60,auto,auto` **ativo** | monitor ativo genérico: `hl.monitor({ output = "", mode = "preferred", position = "auto", scale = 1.03 })` |
| escala do monitor `auto` | escala fixa `1.03` |
| cenários extras comentados (eDP-1, 4K, Framework) | cenários extras comentados (`DP-2`, transform) |
| não usa variáveis | usa variáveis `omarchy_gdk_scale = 1` e `omarchy_monitor_scale = 1.03` |

> **Diferença de efeito:** o `.conf` fixa um monitor específico
> (`HDMI-A-1` 1360x768@60); o `.lua` usa monitor genérico `preferred` com escala
> 1.03. Os dois **divergem** no monitor ativo.

---

## 4. Arquivos Somente `.conf` (sem equivalente `.lua`)

Estes não têm par em Lua — continuam sendo carregados apenas pelo formato `.conf`
(diretamente pelo Hyprland ou via `source`):

| Arquivo | Função | Observação |
|---------|--------|------------|
| `envs.conf` | variáveis de ambiente (`GDK_SCALE`, `GDK_DPI_SCALE`, `QT_SCALE_FACTOR`, `QT_AUTO_SCREEN_SCALE_FACTOR`, `XCURSOR_SIZE`) | carregado pelo `hyprland.conf`; **não existe** `envs.lua` |
| `hypridle.conf` | daemon idle (lock/suspensão/screensaver) | configuração independente do Hyprland (programa `hypridle`) |
| `hyprlock.conf` | tela de bloqueio | faz `source` do tema em `~/.config/omarchy/current/theme/hyprlock.conf` |
| `hyprsunset.conf` | night light (temperatura de cor) | perfis 07:00 (identity) e 18:00 (2000K) |
| `xdph.conf` | portaals / compartilhamento de tela (`hyprland-preview-share-picker`) | configuração do XDG portal |

> O arquivo `hyprland.conf` ainda faz `source` de `envs.conf`, `monitors.conf`,
> `input.conf`, `bindings.conf`, `looknfeel.conf` e `autostart.conf`. No modelo
> Lua, `envs`, `hypridle`, `hyprlock`, `hyprsunset` e `xdph` **não têm
> contraparte Lua** — seriam tratados por outros mecanismos/arquivos do Omarchy.

---

## 5. Resumo das Diferenças-Chave

1. **Estado ativo vs template:** os `.conf` contêm configuração **ativa**; a maioria
   dos `.lua` está **comentada** (serve de modelo para overrides).
2. **Sintaxe:** `.conf` usa `key = value` e blocos `{ }`; `.lua` usa helpers
   (`hl.config`, `hl.bind`, `o.window`, `hl.monitor`, `hl.gesture`).
3. **Carregamento:** `.conf` via `source =`; `.lua` via `require("hypr.<nome>")`.
4. **Bindings:** `.conf` tem ~30 binds ativos; `bindings.lua` está vazio.
5. **Input:** `.conf` ativo; `input.lua` todo comentado (com valores levemente
   diferentes de exemplo, ex. `repeat_delay` e `kb_options`).
6. **Look'n'feel:** `.lua` é **mais completo** (gaps, border, dim ativos) que o `.conf`.
7. **Monitores:** `.conf` fixa `HDMI-A-1`; `.lua` usa `preferred` genérico com escala 1.03.
8. **Autostart:** `.conf` executa `hyprsunset` e seta layout BR/abnt2; `autostart.lua` vazio.
9. **Somente `.conf`:** `envs`, `hypridle`, `hyprlock`, `hyprsunset`, `xdph` não têm par Lua.

## 6. Conclusão

Os arquivos `.conf` e `.lua` representam **duas gerações/modos de configuração do
mesmo sistema Hyprland/Omarchy**. Eles são estruturalmente equivalentes em *escopo*
(os mesmos domínios: principal, autostart, bindings, input, looknfeel, monitors),
mas **não são equivalentes em conteúdo efetivo** — atualmente a configuração real
vive nos `.conf`, enquanto os `.lua` são templates para a migração.
