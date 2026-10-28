# Waydroid sem som ("está sem som", todos os canais mudos)

> **Caso real:** Omarchy/Arch, Waydroid 1.6.3, PipeWire 1.6.9, imagem oficial
> LineageOS 20 GAPPS (x86_64, build 2026-09-27), saída de áudio HDMI para uma TV LG.
> Sintoma relatado: o app **STV** (`com.bx.livf`) toca o vídeo, mas **nenhum
> canal tem áudio** — e o mesmo vale para qualquer app Android.
> **Data do diagnóstico:** 28/10/2026.

---

## 1. Sintoma

- O vídeo roda normalmente dentro do Waydroid.
- Nenhum som sai, em nenhum canal do STV (não é codec de um canal específico).
- O áudio do host (navegador, música) continua funcionando.
- `pactl list sink-inputs` **não mostra nenhum stream do Waydroid**, mesmo com o
  app tocando. É esse o sinal que separa "problema no app" de "problema na HAL
  de áudio do Android".

---

## 2. Ambiente observado

```console
$ waydroid status
Session:        RUNNING
Container:      RUNNING
Vendor type:    MAINLINE
IP address:     192.168.240.112
Session user:   luisao(1000)
Wayland display: wayland-1
```

- Placa de som: `alsa_output.pci-0000_03_00.1.hdmi-stereo-extra4` (HDMI 5, LG TV).
- `pipewire`, `pipewire-pulse` e `wireplumber` ativos.
- Socket exposto ao container (`/var/lib/waydroid/lxc/waydroid/config_session`):

  ```text
  lxc.mount.entry = /run/user/1000/pulse/native run/xdg/pulse/native none rbind,create=file 0 0
  ```

- Propriedade que aponta o runtime do Pulse para a HAL:

  ```text
  waydroid.pulse_runtime_path=/run/xdg/pulse
  ```

---

## 3. Diagnóstico passo a passo

### 3.1 O Android está mandando áudio para o PipeWire?

```console
$ pactl list short sink-inputs
613  56  106  PipeWire  float32le 2ch 48000Hz   # só o navegador (pausado)
```

Nenhum stream do Waydroid → o problema está **antes** do PipeWire, na HAL de
áudio do Android.

### 3.2 Quantas conexões a HAL mantém no servidor de som?

```console
$ pactl list short clients | wc -l
69

$ pactl list clients | grep -o 'application.process.id = "[0-9]*"' | sort | uniq -c | sort -rn | head -3
     60 application.process.id = "94"      # HAL de áudio do Android
      2 application.process.id = "1451"    # WirePlumber
      ...
```

- 60 clientes pertenciam à HAL (`/vendor/bin/hw/android.hardware.audio.service`,
  pid interno 94 — o mesmo processo que aparece no host como
  `binder:94_2`), todos com `application.process.binary = "threaded-ml"`
  (threads de mainloop do libpulse) e **nenhum stream associado**.

### 3.3 A HAL está com threads acumuladas

```console
$ ps -L -p <pid-da-HAL> -o tid,stat,comm | grep -c threaded-ml
60
$ grep ^Threads /proc/<pid-da-HAL>/status
Threads: 68
```

### 3.4 O que *não* era o problema

| Hipótese | Verificação | Resultado |
|---|---|---|
| Volume do Android no zero | `settings_system.xml` → `volume_music=15`, `volume_music_speaker=15` | volume no máximo |
| Volume do host baixo | `pactl get-sink-volume` → 67% (sink HDMI) | apenas um pouco baixo; não zera |
| Stream mudo | nenhum stream existia | descartado |
| Codec do canal | `vendor/etc/media_codecs*.xml` tem só `aac/mp3/opus/vorbis/flac/raw` (sem AC-3/E-AC-3) | relevante para canais Dolby, **não** para "todos mudos" |
| HDMI sem monitor | `eld#0.4`: `monitor_present 1`, `monitor_name LG TV` | TV ligada e conectada |

> `waydroid shell` exige root (`ERROR: Action "shell" needs root access`) e o
> `adb` do host não estava instalado — por isso o diagnóstico foi feito pelo
> lado do PipeWire (`pactl`), que é suficiente para provar onde o áudio para.

---

## 4. Causa

Bug conhecido do Waydroid: a HAL de áudio (`android.hardware.audio.service`)
**acumula conexões com o servidor de som** (uma por PCM aberto) e uma hora trava.
O `AudioFlinger` fica sem caminho de saída e o app toca em silêncio, sem erro
visível no host — o PipeWire simplesmente não recebe nenhum stream novo.

Referências upstream:

- [waydroid#2292](https://github.com/waydroid/waydroid/issues/2292) — "Unable to
  play sound... after running for some time; fixed by restarting the container".
- [waydroid#1683](https://github.com/waydroid/waydroid/issues/1683) — "recent
  update break pipewire-alsa"; áudio some e o PipeWire trava/consome CPU.
- [waydroid#2333](https://github.com/waydroid/waydroid/issues/2333) — HAL não
  conecta ao Pulse (caso de `PULSE_RUNTIME_PATH` ausente; aqui as conexões
  existiam, então não era esse o cenário).

---

## 5. Correção

Reiniciar **apenas a HAL de áudio do Android**, sem derrubar a sessão nem o
container. O `init` do Android relança o serviço automaticamente.

```console
$ pgrep -af 'android.hardware.audio.service'
3535 /vendor/bin/hw/android.hardware.audio.service

$ kill 3535            # não precisa de sudo: a HAL roda com o uid do usuário
$ sleep 4

$ pgrep -af 'android.hardware.audio.service'
24475 /vendor/bin/hw/android.hardware.audio.service

$ pactl list short clients | wc -l
10                     # as 60 conexões acumuladas sumiram

$ pactl list short sink-inputs
641  56  635  PipeWire  s16le 2ch 48000Hz   # Waydroid voltou a tocar
```

Comprovante de que o áudio realmente voltou (medindo o monitor do sink):

```console
$ timeout 8 parec --device=alsa_output.pci-0000_03_00.1.hdmi-stereo-extra4.monitor \
    --format=s16le --rate=48000 --channels=2 --raw |
  python3 -c 'import sys,struct,math;d=sys.stdin.buffer.read();n=len(d)//2;
v=struct.unpack("<%dh"%n,d[:n*2]);p=max(abs(x) for x in v);
r=math.sqrt(sum(x*x for x in v)/n);print("pico %.1f%% rms %.2f%%"%(100*p/32768,100*r/32768))'
pico 17.4% rms 2.71%
```

Ajuste de volume feito na mesma sessão:

```console
$ pactl set-sink-volume  alsa_output.pci-0000_03_00.1.hdmi-stereo-extra4 100%  # estava 67%
$ pactl set-sink-input-volume <id-do-stream-waydroid> 100%                    # estava 93%
```

> **Importante:** depois de reiniciar a HAL, pause e dê play de novo no app.
> O `AudioFlinger` só recria o stream quando o app reabre a saída de áudio.

---

## 6. Script

`fix_waydroid_audio.sh` faz o procedimento acima e ainda mostra o diagnóstico:

```console
$ ./fix_waydroid_audio.sh --status   # HAL ativa? quantas conexões? há stream?
$ ./fix_waydroid_audio.sh            # reinicia a HAL e mostra o resultado
```

Instalação opcional no `PATH` do usuário:

```console
$ install -m755 fix_waydroid_audio.sh ~/.local/bin/waydroid-audio-fix
```

O script não usa `sudo`. Se a HAL não voltar sozinha, ele orienta:

```console
$ sudo systemctl restart waydroid-container
```

---

## 7. Quando voltar a acontecer

1. `./fix_waydroid_audio.sh` (ou `waydroid-audio-fix`, se instalado).
2. Pause/play no app.
3. Se persistir:

   ```console
   $ sudo systemctl restart waydroid-container
   $ waydroid show-full-ui
   ```

4. Se acontecer com muita frequência, vale testar as mitigações conhecidas do
   upstream (opcionais, alteram o áudio do host inteiro):
   - limitar o quantum mínimo do PipeWire (mitigação do #1683):

     ```ini
     # ~/.config/pipewire/pipewire.conf.d/10-waydroid.conf
     context.properties = {
         default.clock.min-quantum = 512
     }
     ```

     e testar ao vivo com
     `pw-metadata -n settings 0 clock.force-quantum 512`.
   - manter imagens (`system`/`vendor`) e `waydroid-git` atualizados.

---

## 8. Checklist rápido

- [ ] `pactl list short sink-inputs` mostra um stream `Waydroid` quando o app toca
- [ ] `pactl list short clients | wc -l` não cresce sem parar (dezenas de conexões
      `threaded-ml` = HAL acumulando)
- [ ] `pactl get-sink-volume` do sink HDMI em 100% e sem mute
- [ ] TV/monitor com `eld` válido (`/proc/asound/card*/eld#*`)
- [ ] depois do fix, pause/play no app
