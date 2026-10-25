# Waydroid — prompt de implementação: apps Android (Nio Player e STV)

> **Origem deste documento:** Omarchy 4.0.6 (Arch Linux), kernel `7.2.8-9-omarchy`,
> Waydroid `1.6.3`, imagem oficial LineageOS 20 **GAPPS**, PipeWire `1.6.9`,
> GPU AMD (Radeon RX 470/480/570/580/590) com `mesa`/`radeon`, saída de áudio HDMI
> ligada numa TV LG.
> **Branch:** `setup-waydroid`.
> **Pré-requisito:** o Waydroid + GAPPS já instalado e validado conforme o
> `README.md` deste diretório (sessão `RUNNING`, IP `192.168.240.x`, Play Store ok).
>
> **Status na máquina de origem (estado final):**
> - **STV** (`com.bx.livf`) — vídeo **e áudio** funcionando, troca de canal validada
>   (número + OK, lista e zapping por setas).
> - **Nio Player** (`com.nio.smart.player`) — instalado, mas **parado na splash**
>   (`com.fusion.SplashActivity`). Não foi resolvido; a seção 9 explica o que já
>   foi descartado e como diagnosticar.
>
> **Regra obrigatória:** todo comando com `sudo` é executado pelo **usuário**. O
> agente prepara o comando, pede para rodar e analisa a saída. O agente nunca roda
> `sudo` sozinho.

---

## 1. Prompt para o agente (copie daqui)

```text
Você é um agente de TI atuando em um Arch Linux/Omarchy x86_64 com Wayland
(Hyprland) e PipeWire. O Waydroid 1.6.3 com a imagem LineageOS 20 GAPPS já está
instalado e validado pelo README.md deste diretório (branch setup-waydroid).

Objetivo: instalar e fazer funcionar dois apps Android no Waydroid —
Nio Player (com.nio.smart.player) e STV (com.bx.livf) — com áudio, e ensinar o
usuário a operar o STV (trocar de canal, lista, EPG, zapping).

Leia PROMPT-APPS.md inteiro antes de começar. Siga as fases na ordem e valide
cada uma antes de avançar.

Regras obrigatórias:
1. NÃO execute sudo. Prepare o comando completo e peça ao usuário para rodar,
   colando a saída. Só continue depois de analisar.
2. Não edite /usr/lib/waydroid, não desative o UFW, não troque kernel,
   bootloader, Secure Boot nem driver de vídeo.
3. Controle o Android por ADB TCP (uid 2000) sempre que possível; `waydroid
   shell` exige root e é exceção, não regra.
4. O STV é um APK ARM (armeabi-v7a) clonado com AppCloner: só funciona com
   tradução ARM (libhoudini/libndk). O Nio é x86_64 nativo.
5. Áudio: o sintoma clássico é `audio_hw_primary: Failed to open pcm_out after
   100 tries` a cada ~2 s. A correção exige root em UM comando (seção 8).
6. Responda em português. Explique o porquê de cada passo, não só o comando.
7. No fim, entregue ao usuário o manual de uso do STV (seção 10) e valide o
   checklist da seção 12.

Fluxo esperado:
  Fase 1  tradução ARM (libhoudini)            -> abilist com arm64-v8a/armeabi-v7a
  Fase 2  ADB TCP autorizado (sem root)        -> adb devices = device
  Fase 3  instalar Nio e STV                   -> pm list packages
  Fase 4  parar popups do app Google/Assistente-> googlequicksearchbox desabilitado
  Fase 5  corrigir áudio do STV                -> sink-input "Waydroid/ALSA Playback"
  Fase 6  diagnosticar Nio (splash travada)   -> relatório honesto
  Fase 7  validar troca de canal               -> 594 VIVA 4K tocando
  Fase 8  ensinar o usuário                    -> manual da seção 10

Critérios de aceite:
- `waydroid status` = RUNNING com IP 192.168.240.x
- `adb devices` mostra `device` (não `unauthorized`)
- `pm list packages` contém com.nio.smart.player e com.bx.livf
- com o STV tocando: `pactl list short sink-inputs` mostra um stream do Waydroid
  (`media.name = "ALSA Playback"`, s16le 2ch 48000Hz), sem mute e sem cork
- o logcat mostra `IJKMEDIA: FFP_MSG_AUDIO_RENDERING_START`
- trocar de canal por número + OK funciona
```

---

## 2. O que significa “funcionando” neste documento

| Item | Critério objetivo |
|---|---|
| STV com vídeo | `dumpsys window` mostra `com.bx.livf/com.bx.live.activity.MainActivity` em foco e a imagem avança |
| STV com áudio | `pactl list sink-inputs` com `application.name = "Waydroid"`, `media.name = "ALSA Playback"`, `Corked: no`, `Mute: no` |
| Áudio chegando no app | `adb logcat` com `IJKMEDIA: SDL_Android_AudioTrack` e `FFP_MSG_AUDIO_RENDERING_START` |
| Troca de canal | digitar `594` + OK sintoniza o canal 594 (VIVA 4K) |
| Nio | **não** atende: fica na splash. Instalado e reconhecido pelo Android |

---

## 3. Pré-requisitos

- Waydroid + GAPPS do `README.md`, sessão `RUNNING` e com IP:

  ```bash
  waydroid status
  ```

- PipeWire e `pipewire-pulse` ativos no host:

  ```bash
  systemctl --user is-active pipewire pipewire-pulse wireplumber
  ```

- Sink de áudio do host escolhido e ligado (na origem, HDMI da TV):

  ```bash
  pactl get-default-sink
  pactl list short sinks
  ```

- APKs em mãos (na origem):

  ```text
  ~/Downloads/nio   54 MB  com.nio.smart.player 1.0.8  (x86_64 nativo)
  ~/Downloads/stv   18 MB  com.bx.livf 20250701       (armeabi-v7a, clone AppCloner)
  ```

- ~2 GB livres em `/var/lib` (imagens + apps + tradução ARM).

---

## 4. Fase 1 — Tradução ARM (libhoudini)

O STV é ARM de 32 bits. Sem tradução, o Android x86_64 instala mas o app não abre.
Na origem foi usado o **libhoudini** (CPU Intel Xeon E5-2650 v4).

```bash
cd /home/luisao/Projects/waydroid
git clone https://github.com/casualsnek/waydroid_script
cd waydroid_script
python3 -m venv venv
venv/bin/pip install -r requirements.txt
```

Instalação (o usuário roda; baixa e aplica as libs na imagem):

```bash
cd /home/luisao/Projects/waydroid/waydroid_script
sudo venv/bin/python3 main.py install libhoudini
```

> Em CPU AMD o `libndk` costuma ser a escolha; em Intel, `libhoudini`. Ambos
> exigem `lzip` no host (`sudo pacman -S lzip`).

O script usa `waydroid upgrade -o`, que é **offline** (só reaplica a configuração,
não baixa imagem nova). Ele para/inicia a sessão e reinicia o container.

Validar (com o Android de pé):

```bash
waydroid shell -- getprop ro.product.cpu.abilist
waydroid shell -- getprop ro.dalvik.vm.native.bridge
```

Esperado na origem:

```text
x86_64,x86,arm64-v8a,armeabi-v7a,armeabi
libhoudini.so
```

Também confirmado em `/var/lib/waydroid/waydroid.prop`:

```ini
ro.product.cpu.abilist=x86_64,x86,arm64-v8a,armeabi-v7a,armeabi
ro.product.cpu.abilist32=x86,armeabi-v7a,armeabi
ro.product.cpu.abilist64=x86_64,arm64-v8a
ro.dalvik.vm.native.bridge=libhoudini.so
ro.enable.native.bridge.exec=1
```

---

## 5. Fase 2 — ADB por TCP, sem root

Motivo: `waydroid shell` exige root a cada comando, e o agente não pode rodar
`sudo`. O `adbd` do container já escuta em `5555`; o ADB do host entra como
usuário `shell` (uid 2000), suficiente para instalar, ler logs, simular teclas e
tirar prints.

### 5.1 Baixar o ADB (sem instalar nada no sistema)

```bash
mkdir -p /tmp/opencode && cd /tmp/opencode
curl -sL --max-time 120 -o platform-tools.zip \
  https://dl.google.com/android/repository/platform-tools-latest-linux.zip
unzip -oq platform-tools.zip
./platform-tools/adb version
```

### 5.2 Conectar

Descubra o IP e conecte:

```bash
IP=$(waydroid status | awk '/IP address/ {print $3}')
cd /tmp/opencode
./platform-tools/adb connect "$IP:5555"
./platform-tools/adb devices -l
```

Se aparecer **`unauthorized`**, autorize escrevendo a chave pública do host no
container. O diretório é gravável pelo usuário do desktop:

```bash
IP=$(waydroid status | awk '/IP address/ {print $3}')
cat ~/.android/adbkey.pub > ~/.local/share/waydroid/data/misc/adb/adb_keys
chmod 640 ~/.local/share/waydroid/data/misc/adb/adb_keys
cd /tmp/opencode
./platform-tools/adb kill-server
./platform-tools/adb connect "$IP:5555"
./platform-tools/adb devices
```

Esperado:

```text
List of devices attached
192.168.240.112:5555	device
```

> `adb root` responde `not available in Waydroid`. Não insista: o caminho é
> `sudo waydroid shell` (usuário roda) quando precisar de root.

### 5.3 Atalhos úteis

```bash
A=/tmp/opencode/platform-tools/adb

# print da tela do Android (o screencap imprime um aviso do driver AMD antes do PNG;
# o trecho abaixo remove esse prefixo)
$A exec-out screencap -p > /tmp/opencode/tela.raw
python3 - <<'EOF'
d = open('/tmp/opencode/tela.raw','rb').read()
i = d.find(b'\x89PNG')
open('/tmp/opencode/tela.png','wb').write(d[i:])
EOF

# teclas (códigos Android)
$A shell input keyevent 23   # OK / DPAD_CENTER
$A shell input keyevent 19   # cima
$A shell input keyevent 20   # baixo
$A shell input keyevent 21   # esquerda
$A shell input keyevent 22   # direita
$A shell input keyevent 4    # voltar
$A shell input keyevent 24   # volume +
$A shell input keyevent 25   # volume -
$A shell input keyevent 8    # dígito 1  (7 = 0, 8..16 = 1..9)

# qual app está em foco
$A shell dumpsys window | grep mCurrentFocus
```

---

## 6. Fase 3 — Instalar os APKs

`waydroid app install` funciona **como usuário** (não precisa de sudo):

```bash
waydroid app install ~/Downloads/nio
waydroid app install ~/Downloads/stv
```

Validar:

```bash
waydroid app list | grep -A2 -iE 'nio|stv'
adb shell pm list packages | grep -E 'com\.nio|com\.bx'
adb shell dumpsys package com.nio.smart.player | grep -E 'versionName|primaryCpuAbi'
adb shell dumpsys package com.bx.livf | grep -E 'versionName|primaryCpuAbi'
```

Esperado na origem:

```text
com.nio.smart.player  versionName=1.0.8   primaryCpuAbi=x86_64
com.bx.livf           versionName=20250701 primaryCpuAbi=armeabi-v7a
```

Observações:

- O `stv` é um clone feito com **AppCloner** (pacote `com.bx.livf`), com
  `libappcloner.so` e `libforcetv.so` em `armeabi-v7a`; por isso depende do
  libhoudini.
- Reinstalar/atualizar sem perder dados: `adb install -r caminho.apk`.
- Desinstalar: `waydroid app remove com.nio.smart.player`.
- Abrir: `waydroid app launch com.bx.livf` (ou pelo ícone na interface).

---

## 7. Fase 4 — Parar os popups do Google/Assistente

Sintoma na origem: a tela do Assistente/Google app subia sozinha de tempos em
tempos. Diagnóstico pelas tarefas recentes do Android:

```bash
for f in ~/.local/share/waydroid/data/system_ce/0/recent_tasks/*_task.xml; do
  printf '%s -> ' "$(basename "$f")"
  strings -a "$f" | grep -A1 'real_activity$' | tail -1
done
```

Apareceram `...GoogleAppActivity` e `...FragmentHostDefaultActivity` (voz do
Assistente) do pacote `com.google.android.googlequicksearchbox`.

Correção (usuário roda; reversível):

```bash
sudo waydroid shell -- pm disable-user --user 0 com.google.android.googlequicksearchbox
sudo waydroid shell -- am force-stop com.google.android.googlequicksearchbox
```

Reativar, se quiser:

```bash
sudo waydroid shell -- pm enable --user 0 com.google.android.googlequicksearchbox
```

Play Store (`com.android.vending`) e Google Play Services
(`com.google.android.gms`) **não** são afetados.

---

## 8. Fase 5 — Áudio do STV (a parte difícil)

### 8.1 Sintoma

O STV reproduz vídeo, mas **nenhum som** — e não é só o STV: qualquer som do
Android (tecla de volume, notificação) também não sai. Logcat:

```bash
adb logcat -d | grep -iE 'audio_hw|pcm_out' | tail
```

```text
E audio_hw_primary: Failed to open pcm_out after 100 tries
```

a cada ~2 s. O app decodifica o áudio normalmente:

```text
I IJKMEDIA: FFP_MSG_AUDIO_DECODED_START:
I IJKMEDIA: FFP_MSG_AUDIO_RENDERING_START:
```

### 8.2 Diagnóstico (o que foi verificado)

```bash
# 1) não há stream do Waydroid no PipeWire
pactl list short sink-inputs
pactl list clients | grep -c 'application.name = "Waydroid"'

# 2) o socket do Pulse está montado e acessível dentro do container
adb shell 'ls -l /run/xdg/pulse/native; getprop waydroid.pulse_runtime_path'
# srw-rw-rw- 1 system system 0 ... /run/xdg/pulse/native
# /run/xdg/pulse

# 3) o socket aceita conexão
adb shell 'echo | nc -U /run/xdg/pulse/native >/dev/null 2>&1; echo rc=$?'

# 4) o HAL está de pé
adb shell 'getprop init.svc.vendor.audio-hal; getprop init.svc_debug_pid.vendor.audio-hal'

# 5) o volume de mídia não é a causa
adb shell 'settings get system volume_music'
adb shell 'dumpsys audio | grep -A6 "STREAM_MUSIC:" | grep -E "Muted|Current|Devices"'
```

Resultados na origem:

- `pactl list clients` tinha **60 clientes presos** com
  `application.name = "Waydroid"`, `application.process.id = 97`
  (`vendor.audio-hal`), todos com `application.process.binary = "threaded-ml"`;
- nenhum `sink-input` do Waydroid;
- socket presente, 666, `waydroid.pulse_runtime_path=/run/xdg/pulse`;
- `nc -U` conectava (rc=0);
- volume de mídia `5` (depois 15), `STREAM_MUSIC` não mudo, device `speaker`;
- host saudável: sink HDMI `RUNNING`, 71%, sem mute.

### 8.3 Causa

O HAL de áudio (`/vendor/lib64/hw/audio.primary.waydroid.so`, pid 97) usa o plugin
Pulse do ALSA (`snd_pcm_open("pulse")`) apontando para
`PULSE_RUNTIME_PATH=/run/xdg/pulse`. Ele subiu **antes** de o socket do PipeWire
estar pronto/utilizável, entrou em loop de falha (`100 tries`) e deixou 60
conexões penduradas no servidor. Enquanto isso, `audioserver` também ficou com o
device de saída quebrado.

Ou seja: não é codec, não é volume, não é o app — é o **HAL travado**.

### 8.4 Correção (dois passos)

**Passo 1 — limpar os clientes presos (o agente pode rodar):**

```bash
systemctl --user restart pipewire-pulse
pactl list clients | grep -c 'application.name = "Waydroid"'   # deve dar 0
```

**Passo 2 — reiniciar o HAL/audioserver (o usuário roda, exige root):**

```bash
sudo waydroid shell -- setprop ctl.restart vendor.audio-hal
```

Esse comando derruba o `audioserver` junto (o `.rc` do serviço tem
`onrestart restart audioserver`). No logcat aparece:

```text
I AudioFlinger: loadHwModule() Loaded ... audio interface
I AudioFlinger: systemReady
```

Na origem o áudio voltou imediatamente após esse passo, sem reiniciar a sessão.

> **Atenção:** `adb shell setprop ctl.restart vendor.audio-hal` (uid 2000) **não
> funciona**: ele marca o serviço como `stopping` mas não consegue sinalizar o
> init, deixando o HAL num estado esquisito (`init.svc.vendor.audio-hal=stopping`
> com o processo vivo). Use `sudo waydroid shell`.

### 8.5 Validação

Com o STV tocando:

```bash
pactl list short sink-inputs
pactl list sink-inputs | grep -E 'Sink Input|Corked|Mute:|application.name|media.name'
```

Esperado (origem):

```text
2227	56	2221	PipeWire	s16le 2ch 48000Hz
	Corked: no
	Mute: no
		application.name = "Waydroid"
		media.name = "ALSA Playback"
```

E o sink precisa estar `RUNNING` (na origem, HDMI da TV):

```bash
pactl list short sinks
# 56  alsa_output.pci-0000_03_00.1.hdmi-stereo-extra4  PipeWire  s32le 2ch 48000Hz  RUNNING
```

No Android:

```bash
adb logcat -d | grep -E 'SDL_Android_AudioTrack|FFP_MSG_AUDIO_RENDERING_START'
```

### 8.6 Se o som sumir de novo (ex.: depois de reiniciar o PC)

A ordem de inicialização importa: PipeWire precisa estar de pé antes do Waydroid.
Repita os dois passos da seção 8.4. Para prevenir, garanta que a sessão do
Waydroid só suba depois do `pipewire-pulse` (o autostart do README usa
`waydroid-session.service`; se necessário, adicione
`After=pipewire-pulse.service` no unit de usuário).

---

## 9. Fase 6 — Nio Player: estado e diagnóstico

Instalado (`com.nio.smart.player`, 1.0.8), mas fica **parado na splash**
(`com.fusion.SplashActivity`): o processo está vivo, ~1,6% de CPU, 100+ threads,
sem crash e sem ANR.

O que já foi descartado na origem:

| Hipótese | Evidência |
|---|---|
| Falta de ABI | o APK tem `lib/x86_64/libijkplayer.so`, `libffmpegJNI.so`, `libijkffmpeg.so` — é nativo x86_64 |
| GPU/renderização | `ro.hardware.egl=mesa`, `ro.hardware.gralloc=minigbm_gbm_mesa`, `ro.hardware.vulkan=radeon` |
| Rede do container | bridge `waydroid0` com NAT e DNS ok (validado pelo `--verify` do README) |
| Crash | sem tombstone, sem `FATAL`, sem ANR do pacote |

Suspeitas restantes: checagem de root/emulador (o APK traz
`libbugsnag-root-detection.so`, e o Waydroid é `userdebug`/`test-keys`) ou espera
de resposta de API na splash.

Diagnóstico (usuário roda):

```bash
sudo waydroid shell -- sh -c '
echo "== rede =="; ping -c 2 -W 3 1.1.1.1 | tail -2; ping -c 2 -W 3 google.com | tail -2
echo "== log nio =="; logcat -d -t 1500 | grep -iE "nio|AndroidRuntime|FATAL|ANR|bugsnag" | tail -40
'
```

Tentar um start limpo:

```bash
sudo waydroid shell -- am force-stop com.nio.smart.player
waydroid app launch com.nio.smart.player
```

Caminhos possíveis se aparecer `SecurityException`/detecção de root: esconder o
root (Magisk + Zygisk/DenyList), usar uma build x86_64 do app ou aceitar a
limitação. Não é problema do Waydroid em si.

---

## 10. Manual de uso do STV (para o usuário)

O STV é um app de TV: tudo funciona como num controle remoto (D-pad), e **não**
por toque. O toque na tela fecha os menus.

### 10.1 Mapa do controle

| Tecla / ação | O que faz |
|---|---|
| **OK** (ou clique) | abre a **lista de canais** |
| **↑ / ↓** | na lista: muda o canal destacado; no vídeo: **zapping** (canal anterior/seguinte) |
| **← / →** | no vídeo: seleciona funções do OSD (favorito, feedback…); na lista: **→** abre o **EPG** |
| **Voltar** (◀ do Android) | fecha a lista/OSD; no vídeo pode recarregar o canal atual |
| **Números + OK** | vai **direto** ao canal (ex.: `594` + OK) |
| **↑** (com OSD aberto) | mostra nome do canal, programa atual e próximo |

### 10.2 Trocar de canal — 3 formas

**a) Pelo número (mais rápida e a que validei):**

1. com o vídeo em tela cheia, digite o número (ex.: `5` `9` `4`);
2. aparece o número grande em verde no centro da tela;
3. aperte **OK** → sintoniza.

Exemplos: `1` + OK (A&E 4K), `594` + OK (VIVA 4K), `677` + OK (SBT News).

**b) Pela lista:**

1. **OK** abre a lista;
2. **↑/↓** escolhe o canal;
3. **OK** sintoniza;
4. **→** abre o EPG do canal (grade de horários, dias da semana, “Assinar”);
5. **←/Voltar** fecha.

**c) Zapping:**

- **↑/↓** durante o vídeo troca para o canal seguinte/anterior e mostra o OSD.

> ⚠️ **Vá devagar.** O STV é ARM traduzido e responde em 1–3 s. Várias setas
> seguidas disparam “**STV isn't responding**”. Se aparecer, escolha **Wait**
> (nunca “Close app”). Se o app reiniciar na splash, espere ~20 s.

### 10.3 Categorias (coluna da esquerda da lista)

Observadas na origem:

```text
ABERTOS · NOTÍCIAS · VARIEDADES · FILMES E SÉRIES · CULTURA ·
INFANTIL · INTERNACIONAL · ÁRABE
```

E, ao rolar/entrar pelo seletor de número (lista “TODOS”, 681 canais):

```text
TODOS · 4K · PLAYBACK · NOVIDADES & TENDÊNCIAS · FUTEBOL ·
ESPORTE · 24H · DOCUMENTÁRIO
```

### 10.4 Se um canal não tiver som

O player usa ExoPlayer2 + ijkplayer e tem seletor de faixa de áudio. Toque na
tela para abrir os controles e escolha **Estéreo**/faixa simples — evite
“Áudio surround 5.1/7.1”, que o Android não decodifica. Se só existir a faixa
surround, o canal não terá som.

### 10.5 Canais fora do ar

O app mostra **“CANAL COM FALHA NA ORIGEM”** quando a fonte do canal caiu. Não é
problema do Waydroid. Na origem, o `677 SBT NEWS HD` estava assim; `001 A&E 4K`,
`036 CAZÉ TV 04 HD` e `594 VIVA 4K` funcionavam.

---

## 11. Histórico exato da origem (ordem cronológica)

| Hora | Ação | Resultado |
|---|---|---|
| 13:18 | sessão Waydroid iniciada | `RUNNING`, IP `192.168.240.112` |
| 13:43–13:44 | APKs baixados (`~/Downloads/stv`, `~/Downloads/nio`) | 18 MB / 54 MB |
| 13:46 | `waydroid app install ~/Downloads/nio` | `com.nio.smart.player` 1.0.8 |
| 13:50 | `libhoudini` aplicado (waydroid_script) e container reiniciado | abilist com ARM |
| 13:51 | `waydroid app install ~/Downloads/stv` | `com.bx.livf` 20250701 |
| 13:54 | ANR do STV (input dispatch timeout) | “Wait”; app seguiu |
| 13:56 | popups do Google identificados nas tarefas recentes | `GoogleAppActivity`, `FragmentHostDefaultActivity` |
| 13:57 | `pm disable-user com.google.android.googlequicksearchbox` | popups pararam |
| 14:02 | STV tocando vídeo sem áudio | `Failed to open pcm_out` |
| 14:36 | ADB TCP autorizado via `adb_keys` | `adb devices` = `device` |
| 14:36–14:40 | diagnóstico de áudio | 60 clientes presos, socket ok, volume ok |
| 14:41 | primeira troca de canal (BACK + setas) | instável, ANR |
| 15:02 | `systemctl --user restart pipewire-pulse` | clientes Waydroid: 60 → 0 |
| 15:08 | `sudo waydroid shell -- setprop ctl.restart vendor.audio-hal` | `audioserver` reiniciou |
| 15:08 | áudio validado | sink-input `Waydroid/ALSA Playback` |
| 15:0x | canais testados | `001 A&E 4K` → `036 CAZÉ TV` → `677` (fora do ar) → `594 VIVA 4K` |

Comandos exatos do ciclo de áudio:

```bash
# limpeza dos clientes presos (host, sem root)
pactl list clients | grep -c 'application.name = "Waydroid"'
systemctl --user restart pipewire-pulse
pactl list clients | grep -c 'application.name = "Waydroid"'

# reinício do HAL (root, usuário executa)
sudo waydroid shell -- setprop ctl.restart vendor.audio-hal

# validação
adb logcat -c
adb shell input keyevent 24
sleep 5
pactl list short sink-inputs
adb logcat -d | grep -iE 'pcm_out|SDL_Android_AudioTrack|FFP_MSG_AUDIO'
```

---

## 12. Checklist de replicação

- [ ] Waydroid `RUNNING` com IP `192.168.240.x` (README.md)
- [ ] PipeWire + `pipewire-pulse` ativos e sink de saída escolhido
- [ ] `libhoudini` (Intel) ou `libndk` (AMD) instalado
- [ ] `getprop ro.product.cpu.abilist` contém `arm64-v8a` e `armeabi-v7a`
- [ ] `getprop ro.dalvik.vm.native.bridge` = `libhoudini.so` (ou `libndk_translation.so`)
- [ ] ADB TCP conectado como `device` (não `unauthorized`)
- [ ] `com.nio.smart.player` e `com.bx.livf` em `pm list packages`
- [ ] app Google/Assistente desabilitado (se estava popando)
- [ ] `pactl list clients` sem clientes “Waydroid” presos
- [ ] HAL reiniciado com `sudo waydroid shell -- setprop ctl.restart vendor.audio-hal`
- [ ] com o STV tocando: `sink-input` do Waydroid, sem mute/cork, sink `RUNNING`
- [ ] logcat com `FFP_MSG_AUDIO_RENDERING_START`
- [ ] troca de canal por número + OK validada
- [ ] usuário recebeu o manual da seção 10

---

## 13. Problemas e correções

| Sintoma | Causa | Correção |
|---|---|---|
| STV não instala / não abre | APK ARM (`armeabi-v7a`) sem tradução | instalar `libhoudini` (Intel) ou `libndk` (AMD) |
| `adb devices` = `unauthorized` | chave do host não está no container | copiar `~/.android/adbkey.pub` para `~/.local/share/waydroid/data/misc/adb/adb_keys` (640) e reconectar |
| `adb root` = `not available in Waydroid` | Waydroid bloqueia | usar `sudo waydroid shell` quando precisar de root |
| Popups do Assistente/Google | `com.google.android.googlequicksearchbox` | `pm disable-user --user 0 ...` (seção 7) |
| Sem áudio em tudo (`Failed to open pcm_out after 100 tries`) | HAL travado + 60 clientes presos no PipeWire | `systemctl --user restart pipewire-pulse` + `sudo waydroid shell -- setprop ctl.restart vendor.audio-hal` |
| `setprop ctl.restart` via ADB shell não resolve | uid 2000 não sinaliza o init | rodar com `sudo waydroid shell` |
| Som volta a falhar após reiniciar | ordem PipeWire × Waydroid | repetir a correção; garantir PipeWire antes da sessão |
| “STV isn't responding” | app ARM traduzido + muitas teclas seguidas | escolher **Wait**, ir devagar (1–3 s entre teclas) |
| “CANAL COM FALHA NA ORIGEM” | fonte do canal caiu | trocar de canal; não é o Waydroid |
| Nio parado na splash | suspeita de root/emulador ou API | seção 9 (diagnóstico e alternativas) |
| `screencap` gera arquivo inválido | aviso do driver AMD antes do PNG | cortar até o magic `\x89PNG` (seção 5.3) |

---

## 14. Limitações e avisos

- O áudio do Waydroid depende do PipeWire do host; sessão iniciada antes do
  PipeWire reproduz o defeito.
- O STV é um clone AppCloner de um app ARM; a tradução custa desempenho e
  provoca ANRs se o usuário navegar rápido.
- Canais IPTV caem com frequência; “falha na origem” é do provedor.
- O Nio Player não foi validado além da instalação.
- Não é necessário (nem recomendado) desativar UFW, trocar kernel ou driver de
  vídeo para nada descrito aqui.
- Todos os comandos `sudo` deste documento devem ser executados pelo usuário.
