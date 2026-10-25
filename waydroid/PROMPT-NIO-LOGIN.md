# Prompt para o agente da máquina onde o Nio Player funciona

> **Objetivo deste documento:** levar ao agente que atua na máquina **B** (onde o
> login do Nio Player funciona) todo o diagnóstico já feito na máquina **A**
> (onde o mesmo APK não loga), e pedir a ele a **solução concreta** para a
> máquina A — incluindo os dados/arquivos necessários e o passo a passo.
>
> **Regra:** todo comando com `sudo` é executado pelo **usuário**; o agente
> prepara, pede para rodar e analisa a saída. Não desative o UFW, não edite
> `/usr/lib/waydroid`, não troque kernel/bootloader/driver.
>
> **Privacidade:** não cole senhas. Chaves de licença, device code, Android ID e
> conteúdo de `shared_prefs` podem ser colados (se quiser, com a senha
> mascarada).

---

## 1. Contexto

Duas máquinas, **mesmo APK**, **mesmo Waydroid + GAPPS**, resultado diferente no
login do Nio Player.

| | Máquina A (falha) | Máquina B (funciona) |
|---|---|---|
| Papel | objeto do problema | referência que funciona |
| Distro | Omarchy (Arch), kernel `7.2.8-9-omarchy` | (preencher) |
| CPU | AMD Ryzen 7 5700U (AuthenticAMD) | Intel Xeon E5-2650 v4, segundo o `PROMPT-APPS.md` |
| GPU | Radeon integrada (Mesa) | AMD Radeon RX 470/480/570/580/590 |
| Sessão | Wayland/Hyprland | Wayland/Hyprland |
| Waydroid | 1.6.3 | 1.6.3 |
| Imagem | LineageOS 20 GAPPS, `lineage-20.0-20261022-MAINLINE` (Android 13) | LineageOS 20 GAPPS |
| Tradutor ARM | **libndk** (`libndk_translation.so`) | **libhoudini** (`libhoudini.so`) |
| Áudio | `analog-stereo`, ok | HDMI da TV, ok |
| APK Nio | `sha256 cc717253d74cc6c9fe0113b04b69ded3dcfcc54cb913148e2ded0870fa70d5a7` | **confirmar hash (ver §4.1)** |
| Login Nio | toast genérico “Algo deu errado…” | funciona |

Na máquina A o Nio **instala, abre, passa da splash e mostra a tela de login**;
só o login não conclui. O STV (`com.bx.livf`) funciona com vídeo e áudio na
máquina A, então tradução ARM, rede, áudio e GPU estão OK.

---

## 2. Diagnóstico já feito na máquina A (com evidências)

### 2.1 Sintoma

- `LoginActivity` (`com.nio.smart.player/com.fusion.login.LoginActivity`) abre
  normalmente.
- Ao tentar logar (e também sozinho, sem digitar nada), aparece o toast:
  **“Algo deu errado, por favor, tente novamente mais tarde!”**
- Nada de `FATAL`, `ANR`, `Exception`, `SSLHandshake`, `CLEARTEXT` no logcat.
- Processo vivo, sem crash, foco permanece no `LoginActivity`.

### 2.2 Rede do container está saudável

Dentro do Android, via ADB TCP (uid 2000, sem root):

```text
ping 1.1.1.1        → 2/2 pacotes, 0% perda
ping google.com     → 2/2 pacotes, 0% perda
```

E o próprio host do app responde por HTTPS de dentro do Android:

```text
adb shell curl -sS https://nio.gerenciapro.top/bnsc/api/
→ {"http_code":"403","status":"failure","licence":"Inactive"}
```

### 2.3 O APK é um mod do “PlugadoApk” e o backend diz que a licença está inativa

Endpoints extraídos do DEX:

```text
https://nio.gerenciapro.top/bnsc/api/
https://nio.gerenciapro.top/bnsc/api/sports.php
https://nio.gerenciapro.top/bnsc/api/vsdk/tag.php
https://nio.gerenciapro.top/bnsc/api/player/mobile/v1/an.json
```

Respostas (idênticas do host e de dentro do Android):

```text
GET /bnsc/api/                    → HTTP 200, corpo {"http_code":"403","status":"failure","licence":"Inactive"}
GET /bnsc/api/sports.php          → HTTP 302 → https://gerenciapro.top/sport.php
GET /bnsc/api/vsdk/tag.php        → HTTP 500
GET /bnsc/api/player/mobile/v1/an.json → HTTP 200, JSON de configuração (fluxo oficial: my.nioplayer.com + Device Code)
```

O `an.json` traz:

```json
"content": {
  "mackey_step": "1) Register or Login at https://my.nioplayer.com ... 2) Playlist > Add New Playlist ... 3) Enter Device Id and Device Key ...",
  "activation_step": "1) Register or Login at https://my.nioplayer.com ... 4) Enter the 'Device Code' in the box below"
}
```

Strings de licenciamento no DEX: `sub_licence_key`, `getSub_licence_key`,
`setSub_licence_key`, `api/device-by-key`, `activation_step`, `activationTime`.

Sinais de mod/repack: popup “Changelogs 2.1 — Entre no meu grupo para receber
mais apps Premium” + `purplesmarttv.com`; config remota
`https://pastebin.com/raw/SA03cC8M` (`{"version":"2.1","title":"Grupo PlugadoApk Telegram","downloadLink":"https://t.me/PlugadoApk"...}`);
`Firebase Analytics disabled: Missing google_app_id`; `libbugsnag-root-detection.so`;
`assets/protected_by_np/ApkVmProtect_*`.

### 2.4 O app realmente chama esse host no login

Captura sem root, com proxy global no Android (já revertido para `:0`):

```text
CONNECT nio.gerenciapro.top:443
CONNECT googleads.g.doubleclick.net:443
CONNECT sessions.bugsnag.com:443
```

Ou seja: a chamada de validação sai do app e chega ao servidor do mod; o
servidor é que responde `403 / licence: Inactive`.

### 2.5 O que já foi descartado na máquina A

- tradução ARM (`abilist` com `arm64-v8a,armeabi-v7a`, bridge ativo);
- rede/DNS/NAT (`ping` e `curl` ok dentro do Android);
- crash/ANR/exceção/SSL;
- instalação (pacote presente, `versionName=1.0.8`, `primaryCpuAbi=x86_64`,
  `firstInstallTime=2026-10-25 15:28:22`);
- Play Protect (verificação de ADB foi desligada só para instalar; não afeta login).

### 2.6 Identificadores da máquina A (para comparar)

```text
fingerprint : waydroid/lineage_waydroid_x86_64/waydroid_x86_64:13/TQ3A.230901.001/eng.aleast.20260927.143833:userdebug/test-keys
model       : WayDroid x86_64 Device
device      : waydroid_x86_64
serial      : (vazio)
android_id  : 7bb861dca3aa28c0
APK sha256  : cc717253d74cc6c9fe0113b04b69ded3dcfcc54cb913148e2ded0870fa70d5a7
APK size    : 54 MB
```

---

## 3. Hipóteses (ordem de probabilidade)

1. **Licença atrelada ao dispositivo/chave, e a máquina B é a que está
   registrada.** O servidor devolve `licence: Inactive` para a A e `Active` para
   a B. O mod usa `sub_licence_key` + `api/device-by-key`; pode ser 1 device por
   licença ou exigir “Add New Device” no painel do mod.
2. **Sessão/licença em cache na máquina B.** O app pode ter `sub_licence_key`,
   `activationTime` e token salvos em `shared_prefs`/`databases` e funcionar
   offline; na A, sem esse estado, cai no 403.
3. **APK diferente apesar de “mesmo APK”.** Confirmar `sha256` na B. Se for
   outro build (2.2+, ou outro mod), o servidor pode tratar diferente.
4. **Registro/ativação feito só na B** (Device Code/Device Key no painel
   `my.nioplayer.com` ou no painel do mod), sem equivalente na A.
5. **Detecção de root/emulador** — possível (Waydroid é `userdebug/test-keys` e o
   APK tem root detection), mas **pouco provável**: a requisição chega ao
   servidor e o servidor responde 403 de licença, não o app bloqueando antes.

---

## 4. O que o agente da máquina B deve fazer (pedido)

### 4.1 Confirmar que é o mesmo APK

```bash
sha256sum ~/Downloads/nio     # esperado: cc717253d74cc6c9fe0113b04b69ded3dcfcc54cb913148e2ded0870fa70d5a7
ls -l ~/Downloads/nio
```

Se o hash for diferente, **pare e reporte** (é outro build).

### 4.2 Confirmar o estado da licença no servidor, a partir da B

```bash
curl -sS -w '\nhttp=%{http_code}\n' https://nio.gerenciapro.top/bnsc/api/
curl -sS -w '\nhttp=%{http_code}\n' https://nio.gerenciapro.top/bnsc/api/player/mobile/v1/an.json
```

Pergunta a responder: na B o corpo vem com `"licence":"Active"`? Se sim, está
confirmada a hipótese 1.

### 4.3 Extrair o estado do app na B (root, o usuário roda)

```bash
sudo waydroid shell -- sh -c 'dumpsys package com.nio.smart.player | grep -E "versionName|firstInstallTime|lastUpdateTime|codePath"'

sudo waydroid shell -- sh -c 'ls -l /data/data/com.nio.smart.player/shared_prefs/ 2>/dev/null; ls -l /data/data/com.nio.smart.player/databases/ 2>/dev/null; ls -l /data/data/com.nio.smart.player/files/ 2>/dev/null'

sudo waydroid shell -- sh -c 'for f in /data/data/com.nio.smart.player/shared_prefs/*.xml; do echo "== $f"; cat "$f"; echo; done'

sudo waydroid shell -- sh -c 'ls -l /data/user_de/0/com.nio.smart.player/ 2>/dev/null; ls -l /data/user_de/0/com.nio.smart.player/shared_prefs/ 2>/dev/null'

sudo waydroid shell -- sh -c 'cat /data/data/com.nio.smart.player/files/* 2>/dev/null | head -c 4000'
```

Procurar explicitamente por: `sub_licence_key`, `licence`, `activation_step`,
`activationTime`, `device_code`, `device_key`, `deviceId`, `token`, `user`,
`playlist`, `mackey`, `serial`, `android_id`.

Se houver banco:

```bash
sudo waydroid shell -- sh -c 'ls -l /data/data/com.nio.smart.player/databases/'
sudo waydroid shell -- sh -c 'sqlite3 /data/data/com.nio.smart.player/databases/<arquivo> ".tables"'
```

### 4.4 Reproduzir a captura de rede na B (sem root)

Objetivo: ver se o login na B também passa por `nio.gerenciapro.top` e se há
algum outro host/chave envolvido.

No host da B, subir um listener simples:

```bash
python3 - <<'EOF'
import socket
s=socket.socket(); s.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR,1)
s.bind(('0.0.0.0', 8888)); s.listen(50)
while True:
    c,a=s.accept(); c.settimeout(2)
    try: print(c.recv(400).decode('utf-8','ignore').split('\r\n')[0], flush=True)
    except Exception: pass
    c.close()
EOF
```

Em outro terminal:

```bash
A=/tmp/opencode/platform-tools/adb    # ou o caminho do adb na B
$A shell settings put global http_proxy 192.168.240.1:8888
$A shell am force-stop com.nio.smart.player
waydroid app launch com.nio.smart.player
sleep 20
$A shell settings put global http_proxy :0
```

Reportar a lista de `CONNECT host:443` observada na B.

### 4.5 Logcat do login na B

```bash
$A logcat -c
# faça o login na B (UI) e depois:
$A logcat -d | grep -iE 'nio|fusion|licen|activat|device|token|401|403|okhttp|http' | tail -80
```

### 4.6 Comparar identidade do dispositivo

```bash
waydroid status
$A shell getprop ro.product.cpu.abilist
$A shell getprop ro.dalvik.vm.native.bridge
$A shell getprop ro.build.fingerprint
$A shell getprop ro.serialno
$A shell settings get secure android_id
sudo waydroid shell -- sh -c 'sqlite3 /data/data/com.google.android.gsf/databases/gservices.db "select value from main where name=\"android_id\";"' 2>/dev/null
```

### 4.7 Dizer o que exatamente “funciona” na B

- O login é usuário/senha do painel do mod, ou o fluxo “Device Code” do
  `an.json` (`my.nioplayer.com`)?
- O app mostra o popup “Changelogs 2.1 / PlugadoApk” na B?
- A licença foi obtida em algum grupo/Telegram? Existe chave (`licence key`)?
- Quantos dispositivos a licença permite?
- O login na B continua funcionando **hoje** (a API pode ter mudado)?

---

## 5. O que eu preciso de volta (entregável)

1. **Diagnóstico comparativo**: por que a B passa e a A não, com a evidência
   (corpo do `/bnsc/api/` na B, prefs, hosts contatados).
2. **Solução passo a passo para a A**, na ordem, com comandos prontos:
   - se for transferir licença: como desregistrar/registrar (painel, Device
     Code, chave);
   - se for copiar estado: exatamente **quais arquivos/chaves** copiar de B para
     A (ex.: `shared_prefs/...xml`, `databases/...`), com os `chown`/`chmod`
     corretos (`chown 10145:10145` no host, ou `chown` dentro do container) e o
     aviso de que copiar sessão pode invalidar a B;
   - se for trocar de build/APK: link/hash do build que funciona na B;
   - se for root detection: qual módulo/config (Magisk + Zygisk/DenyList) e como
     validar.
3. **Como validar na A** ao final (o que deve aparecer na tela/logcat).
4. **Riscos e efeitos colaterais** (perder licença da B, invalidar sessão,
   precisar reinstalar, etc.).

Se a solução depender de um dado que só existe na B (chave, device code, APK),
**entregue o dado ou o procedimento exato** para obtê-lo — não diga apenas
“copie a licença”.

---

## 6. Anexo A — dado que falta na máquina A (rodar no host A, com root)

Estes comandos ainda **não** foram executados na A (o agente da A não roda
`sudo`). A saída deles completa a comparação com a B e deve ser anexada a este
prompt quando existir:

```bash
sudo waydroid shell -- sh -c 'ls -l /data/data/com.nio.smart.player/shared_prefs/ 2>/dev/null; ls -l /data/data/com.nio.smart.player/databases/ 2>/dev/null'
sudo waydroid shell -- sh -c 'for f in /data/data/com.nio.smart.player/shared_prefs/*.xml; do echo "== $f"; cat "$f"; echo; done'
sudo waydroid shell -- sh -c 'ls -l /data/user_de/0/com.nio.smart.player/ 2>/dev/null; cat /data/user_de/0/com.nio.smart.player/shared_prefs/*.xml 2>/dev/null'
```

O que se espera descobrir na A: se `sub_licence_key` está **vazio/ausente**
(hipótese 1/2) ou se já existe uma chave e o servidor a considera inválida
(máquina/limite de devices).

> Se a saída for colada ao agente da A, ele deve atualizar este documento e
> reenviá-lo ao agente da B.

---

## 7. Restrições

- Nada de `sudo` executado pelo agente; comandos com `sudo` são para o usuário.
- Não desativar UFW, não mexer em kernel/bootloader/Secure Boot/driver de vídeo.
- Não editar `/usr/lib/waydroid`.
- Não reinstalar/reinicializar o Waydroid da A sem necessidade: o STV está
  funcionando (vídeo + áudio) e não deve ser quebrado. Se a solução exigir
  reiniciar a sessão, avisar antes.
- Responder em português e explicar o porquê de cada passo.
