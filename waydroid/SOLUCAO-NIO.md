# Nio Player — solução aplicada na máquina A

> **Data:** 2026-10-25
> **Máquina A (onde falhava):** Omarchy, kernel `7.2.8-9-omarchy`, AMD Ryzen 7 5700U,
> Waydroid `1.6.3` MAINLINE, tradutor ARM **libndk**.
> **Máquina B (referência que funcionava):** Intel Xeon E5-2650 v4, Radeon RX 580/590,
> Waydroid `1.6.3`, tradutor ARM **libhoudini**.
> **App:** `com.nio.smart.player` 1.0.8 — APK `sha256 cc717253d74cc6c9fe0113b04b69ded3dcfcc54cb913148e2ded0870fa70d5a7`
> (idêntico nas duas máquinas).

---

## 1. Sintoma

O Nio instalava, abria, passava da splash e **parava no `LoginActivity`**
(`com.fusion.login.LoginActivity`). Ao tentar logar aparecia o toast genérico:

> "Algo deu errado, por favor, tente novamente mais tarde!"

Sem `FATAL`, sem `ANR`, sem `Exception`, sem erro de SSL ou `CLEARTEXT` no
logcat. Processo vivo, foco no `LoginActivity`.

---

## 2. Diagnóstico

### 2.1 Comparação A × B

| Verificação | Máquina A | Máquina B |
|---|---|---|
| APK `sha256` | `cc717253…d5a7` | idêntico |
| `versionName` | `1.0.8` | `1.0.8` |
| Waydroid | 1.6.3, MAINLINE, IP `192.168.240.112` | 1.6.3 |
| Tradutor ARM | libndk | libhoudini |
| `android_id` | `7bb861dca3aa28c0` | `99d0982437032008` |
| Arquivo de device | `1418c5bc714e7981.uid` | `387a46f859545343.uid` |
| `GET https://nio.gerenciapro.top/bnsc/api/` | `{"http_code":"403","status":"failure","licence":"Inactive"}` | **igual** |
| Host usado pelo app | `http://bnewsc.top/` | `http://bnewsc.top/` |
| Branding (`KEY_APP_BRANDING`) | `app_mode: Xtream`, DNS `BNSC → http://bnewsc.top` (inferido do comportamento¹) | igual (lido dos prefs) |
| Dashboard | GB PERNAMBUCO FHD, A FAZENDA 18, Domingão com Huck | igual |
| Vídeo + áudio | OK | OK |

¹ Na máquina A os `shared_prefs` não foram lidos: o diretório
`~/.local/share/waydroid/data/data/com.nio.smart.player` é `0700` do uid `10145`
e o agente não executa `sudo`. O branding foi inferido do comportamento (o app
usa o modo Xtream e conecta em `http://bnewsc.top/`).

**Conclusão:** não é licença por device, não é APK diferente, não é rede, não é
tradutor ARM. O `licence: Inactive` do mod é **irrelevante para o
funcionamento** — a máquina B também recebe `Inactive` e toca vídeo normalmente.

### 2.2 O servidor Xtream responde

```text
http://bnewsc.top/player_api.php                          → 200 (corpo vazio, sem credenciais)
http://bnewsc.top/player_api.php?username=x&password=y    → 404
http://bnewsc.top/get.php?username=x&password=y           → 404
http://bnewsc.top/                                        → 302 https://www.google.com.br/
http://bnewsc.top/xmltv.php                               → 200
```

Cloudflare na frente, `X-Powered-By: PHP/7.4.5`. Com credenciais válidas o
`player_api.php` devolve o JSON da conta; o app obtém isso do banco local.

### 2.3 Evidência no logcat (máquina A)

```text
16:32:02.487  START u0 {cmp=com.nio.smart.player/com.fusion.login.LoginActivity}
16:32:19.413  START u0 {cmp=com.nio.smart.player/com.fusion.FetchDataActivity}
16:32:23.123  W/okhttp.OkHttpClient: A connection to http://bnewsc.top/ was leaked
16:32:27.694  START u0 {cmp=com.nio.smart.player/com.fusion.dashboard.DashboardActivity}
16:32:27.844  Displayed com.nio.smart.player/com.fusion.dashboard.DashboardActivity: +149ms
```

Ou seja: o app **passa sozinho** do `LoginActivity` para o `FetchDataActivity` e
chega ao `DashboardActivity`, sem nenhuma digitação.

---

## 3. Causa raiz

O app tem **duas portas de entrada**:

1. **Auto-login (funciona).** Lê a playlist e as credenciais do SQLite
   `HS_PurpleSDK_Database` (tabela `ConnectionInfoModel`) e segue
   `Splash → LoginActivity → FetchDataActivity → DashboardActivity`.
   Esse caminho **só é disparado na inicialização** do app.
2. **Login manual (não funciona).** `LoginActivity` → botão **Enviar** passa pela
   API do mod (`https://nio.gerenciapro.top/bnsc/api/`), que responde
   `403 / licence: Inactive` **nas duas máquinas**. É a origem do toast genérico.

O app estava **parado no `LoginActivity`** e não retentava o auto-login sozinho —
esse era o "login que falha". O estado local (playlist/sessão) estava íntegro o
tempo todo.

> A hipótese do login manual é sustentada pelo `403 / licence: Inactive` na API
> do mod em ambas as máquinas; o botão **Enviar** não foi pressionado para não
> arriscar o estado salvo.

---

## 4. Solução aplicada

```bash
A=/tmp/opencode/platform-tools/adb    # ADB sobre TCP (192.168.240.112:5555)

$A shell am force-stop com.nio.smart.player
sleep 3
$A shell am start -n com.nio.smart.player/com.fusion.SplashActivity
```

Resultado observado (repetido duas vezes, sempre o mesmo):

```text
Splash → LoginActivity → FetchDataActivity → DashboardActivity   em 7 s
```

Sem digitar nada, sem reinstalar, sem copiar dados da máquina B, sem `pm clear`.

---

## 5. Como validar

```bash
# 1) a tela final deve ser o dashboard
$A shell dumpsys window | grep -m1 mCurrentFocus
# esperado: com.nio.smart.player/com.fusion.dashboard.DashboardActivity

# 2) o app deve ter contatado o servidor Xtream
$A logcat -d | grep -i 'bnewsc.top'
# esperado: W/okhttp.OkHttpClient ... A connection to http://bnewsc.top/ was leaked

# 3) ao abrir um canal, deve haver áudio tocando
$A shell dumpsys audio | grep -i 'AudioTrack' | grep -i started
# esperado: u/pid:10145 state:started usage=USAGE_MEDIA
```

Critérios de sucesso: dashboard com canais recentes (ex.: `GB PERNAMBUCO FHD`),
vídeo renderizando e `AudioTrack` em `state:started`.

---

## 6. O que NÃO fazer

- **Não pressione "Enviar"** no `LoginActivity`: é o caminho que bate na API com
  `licence: Inactive` e produz o toast de erro.
- **Não rode `pm clear com.nio.smart.player`**: apaga a única sessão que
  funciona e, sem root, não há como restaurar.
- **Não reinstale o APK "para limpar"**: o problema não é a instalação.
- **Não copie o banco da máquina B para a A**: a A já tem sessão própria e a
  cópia pode derrubar a sessão da B (limite de conexões do Xtream).

---

## 7. Backup recomendado (root — o usuário executa)

O estado que faz o app funcionar está em:

```text
~/.local/share/waydroid/data/data/com.nio.smart.player   (uid 10145, modo 0700)
```

Backup:

```bash
sudo waydroid shell -- tar -czf /data/local/tmp/nio-backup.tgz -C /data/data com.nio.smart.player
sudo waydroid shell -- cat /data/local/tmp/nio-backup.tgz > ~/nio-backup-$(date +%F).tgz
```

Restauração (somente se a sessão for perdida):

```bash
sudo waydroid shell -- sh -c 'rm -rf /data/data/com.nio.smart.player && tar -xzf /data/local/tmp/nio-backup.tgz -C /data/data'
```

Depois de restaurar, abrir o app uma vez para ele reescrever o estado.

---

## 8. Resumo em uma linha

O Nio da máquina A **não estava sem licença**: estava preso no `LoginActivity` e
o auto-login só roda na inicialização. `force-stop` + abrir de novo resolve;
o botão "Enviar" e o `pm clear` devem ser evitados.
