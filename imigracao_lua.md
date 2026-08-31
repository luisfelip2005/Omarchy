# Prompt de Imigração — Migrar Configurações `.conf` → `.lua` + Correções (Hyprland/Omarchy)

Cole o prompt abaixo em outro computador com **opencode + deepseek** para reproduzir
exatamente o mesmo processo realizado nesta sessão.

---

## PROMPT PARA COLAR

```
# Contexto
Esta máquina é um sistema Omarchy (Arch Linux com Hyprland + Quickshell).
A pasta ~/.config/hypr/ contém DOIS formatos de configuração coexistentes:
- Arquivos .conf (formato nativo antigo do Hyprland)
- Arquivos .lua (novo formato Lua do Omarchy, usando helpers como hl.config,
  hl.bind, o.bind, hl.dsp, hl.monitor, o.window)

Estão presentes arquivos equivalentes por tema: hyprland, autostart, bindings,
input, looknfeel, monitors (em .conf e .lua). Também existem arquivos somente
.conf: envs, hypridle, hyprlock, hyprsunset, xdph.

A SESSÃO ANTERIOR JÁ FEZ as tarefas abaixo. Execute cada uma EXATAMENTE como
descrito, nesta ordem, e VALIDE ao final.

## Tarefa 1 — Criar mapeamento.md
Crie um arquivo ~/.config/hypr/mapeamento.md em português que mapeie as
diferenças e semelhanças entre os arquivos .conf e .lua:
- Liste os 6 pares equivalentes (hyprland, autostart, bindings, input,
  looknfeel, monitors) e os 5 arquivos só .conf (envs, hypridle, hyprlock,
  hyprsunset, xdph).
- Compare estrutura: .conf usa "key = value" + blocos { } + source =; .lua usa
  helpers (hl.config, o.bind, hl.monitor, hl.env, hl.gesture) + require("hypr.x").
- Destaque a diferença central: os .conf estão com configuração ATIVA, a maioria
  dos .lua está COMENTADA (servem de template de override).
- Cite exemplos concretos por par (ex.: bindings.conf tem ~30 binds ativos vs
  bindings.lua vazio; looknfeel.lua é mais completo que o .conf; monitors
  diverge em monitor ativo).
Consulte os arquivos reais antes de escrever para ser preciso e específico.

## Tarefa 2 — Mover arquivos .conf para backup_conf
Crie a pasta ~/.config/hypr/backup_conf/ e mova para ela TODOS os arquivos .conf:
autostart.conf, bindings.conf, envs.conf, hypridle.conf, hyprland.conf,
hyprlock.conf, hyprsunset.conf, input.conf, looknfeel.conf, monitors.conf,
xdph.conf.
NÃO mova os arquivos .conf.bak (backups antigos do hypridle/hyprlock ficam na raiz).
OBSERVAÇÃO: antes de mover, os arquivos .conf ainda são a configuração ativa.
O conteúdo deles servirá de base para as tarefas seguintes (leia antes de mover).

## Tarefa 3 — Corrigir Caps Lock (não funciona)
CAUSA RAIZ: o default do Omarchy em
/usr/share/omarchy/default/hypr/input.lua define
kb_options = "compose:caps,shift:both_capslock_cancel", que mapeia o Caps Lock
como tecla Compose, desativando o caps lock.
CORREÇÃO: editar ~/.config/hypr/input.lua e adicionar um bloco hl.config({...})
ATIVO que sobrescreva esse default:
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
VALIDAÇÃO: rodar `hyprctl getoption input:kb_options` deve retornar vazio, e
`hyprctl configerrors` deve estar limpo. O Hyprland recarrega ao salvar o arquivo.

## Tarefa 4 — Analisar keybinds do bindings.conf (seção "# Adapar para o .lua")
LER o arquivo ~/.config/hypr/backup_conf/bindings.conf. A seção abaixo do
comentário "# Adapar para o .lua" contém atalhos personalizados (brightness,
night light, gaps, fechar janela, workspace anterior/próximo, mover janela).
Verificar, contra os defaults em /usr/share/omarchy/default/hypr/bindings/,
se cada atalho JÁ é usado por outro binding (conflito/duplicata). NÃO modificar
nada aqui — apenas reportar a análise.

## Tarefa 5 — Adaptar os atalhos para bindings.lua
Editar ~/.config/hypr/bindings.lua e ADICIONAR (não remover o template existente)
um bloco "Adapted from bindings.conf (section # Adapar para o .lua)" com:
- Brightness decrease/increase:
  o.bind("SUPER + SHIFT + CTRL + F5", "Decrease brightness", os.getenv("HOME") .. "/.config/hypr/controllers/decrease_brightness.sh")
  o.bind("SUPER + SHIFT + CTRL + F6", "Increase brightness", os.getenv("HOME") .. "/.config/hypr/controllers/increase_brightness.sh")
- Fechar janela (substituir default SUPER+W por SUPER+Q):
  hl.unbind("SUPER + W")
  o.bind("SUPER + Q", "Close window", hl.dsp.window.close())
- Workspace anterior/próximo — NAVEGA POR TODOS os workspaces, inclusive vazios:
  o.bind("SUPER + SHIFT + CTRL + LEFT", "Previous workspace", hl.dsp.focus({ workspace = "-1" }))
  o.bind("SUPER + SHIFT + CTRL + RIGHT", "Next workspace", hl.dsp.focus({ workspace = "+1" }))
- Mover janela ativa para workspace anterior/próximo:
  o.bind("SUPER + CTRL + ALT + LEFT", "Move window to previous workspace", hl.dsp.window.move({ workspace = "-1" }))
  o.bind("SUPER + CTRL + ALT + RIGHT", "Move window to next workspace", hl.dsp.window.move({ workspace = "+1" }))
IMPORTANTE SOBRE WORKSPACE: NÃO usar "e-1"/"e+1" (só navega entre workspaces
EXISTENTES). Usar "-1"/"+1" para navegar por TODOS os workspaces, mesmo vazios.
VALIDAÇÃO: `hyprctl binds` deve listar os novos bindings e `hyprctl configerrors`
deve estar limpo.

## Tarefa 6 — Corrigir bolinha de workspace ativo acima de 9
PROBLEMA: no widget de workspaces do Omarchy, a bolinha/indicador do workspace
ativo NÃO aparece quando o workspace tem id maior que 9.
CAUSA RAIZ: em /usr/share/omarchy/shell/plugins/bar/widgets/Workspaces.qml a
função workspaceIds() tinha "if (id > 0 && id <= 10 ...)" — o limite id <= 10
exclui workspaces acima de 9, e a lista inicial fixa [1,2,3,4,5] fazia 6+ só
aparecerem após criados.
CORREÇÃO (seguir o padrão do Omarchy de NÃO editar arquivo embutido):
1. Clonar o plugin: `omarchy plugin clone omarchy.workspaces`
   (cria ~/.config/omarchy/plugins/<usuario>.workspaces/ e troca a barra para
   o clone, atualizando shell.json com "id": "<usuario>.workspaces")
2. Editar Workspaces.qml do clone. Em workspaceIds():
   - Remover o filtro "id <= 10" (aceitar qualquer id > 0 existente).
   - Adicionar a lógica de sempre incluir o workspace ativo:
     var focusedId = Hyprland.focusedWorkspace !== null ? Hyprland.focusedWorkspace.id : -1
     if (focusedId > 0 && ids.indexOf(focusedId) === -1) ids.push(focusedId)
VALIDAÇÃO: navegar para workspace > 9 (ex.: hyprctl dispatch
"hl.dsp.focus({ workspace = \"13\" })") e o indicador do workspace ativo deve
aparecer. Se não refletir, limpar ~/.cache/quickshell/qmlcache/ e reiniciar o
shell (`omarchy restart shell`) — o Quickshell usa cache QML compilado (.qmlc)
que pode ficar preso.

## Tarefa 7 — Corrigir erro do foot.ini no terminal
PROBLEMA: ao abrir o terminal foot aparece:
  error: foot: ~/.config/foot/foot.ini:21: [key-bindings].\n[text-bindings]:
  syntax error: key/value pair has no value
CAUSA RAIZ: em ~/.config/foot/foot.ini havia uma linha com o texto literal
"\n[text-bindings]" (linha 21) dentro/antes da seção, além de uma seção
[text-bindings] DUPLICADA.
CORREÇÃO: remover a linha defeituosa "\n[text-bindings]" mantendo apenas UMA
seção [text-bindings] com os mapeamentos válidos:
  [text-bindings]
  \x1b[13;4u=Mod1+Shift+Return
  \x1b[13;2u=Shift+Return
VALIDAÇÃO: `foot --check-config` deve retornar exit 0 sem erros.

## VALIDAÇÃO FINAL
Rodar e confirmar sem erros:
- hyprctl configerrors
- hyprctl binds (lista os bindings da Tarefa 5)
- hyprctl getoption input:kb_options (vazio)
- foot --check-config
- Navegar para workspace >9 e ver o indicador ativo no widget.

## OBSERVAÇÕES GERAIS
- NUNCA editar arquivos em /usr/share/omarchy/ (é somente leitura, sobrescrito
  em update). Usar overrides em ~/.config/ e clones de plugins.
- Para config de usuário do Omarchy, seguir o guia (skill omarchy):
  - Barra/plugins: ~/.config/omarchy/shell.json e clones em plugins/
  - Hyprland: ~/.config/hypr/*.lua
- Sempre validar com os comandos acima após cada mudança.
```

---

## Notas para execução

- **Ordem crítica:** a Tarefa 2 (mover .conf) apaga a configuração ativa .conf.
  Portanto a Tarefa 4/5 (adaptar keybinds) depende de ler `backup_conf/bindings.conf`
  APÓS mover, ou ler antes de mover e depois adaptar. O prompt já indica "leia antes de mover".
- A Tarefa 6 depende de o Quickshell estar rodando com Hyprland (só faz sentido
  na máquina de destino). Se não houver Hyprland rodando, as validações
  interativas (hyprctl) não funcionarão.
- Se o usuário da máquina de destino for diferente de `luisao`, o clone do
  plugin (Tarefa 6) criará `<nome-do-usuario>.workspaces` automaticamente.
