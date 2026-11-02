# Waydroid — Nio Player e STV não abrem (splash eterna)

> **Caso real:** Omarchy/Arch, Waydroid 1.6.3, LineageOS 20 GAPPS,
> UFW ativo, WAN atual `enp6s0`.
> **Sintoma:** os dois apps abrem o processo e param na splash/logo:
> - Nio Player (`com.nio.smart.player`) fica em `com.fusion.SplashActivity`;
> - STV (`com.bx.livf`) fica em `IndexActivity` mostrando só o logo.
>
> **Data do diagnóstico:** 02/11/2026.

---

## 1. Causa raiz

O UFW estava ativo com:

```text
DEFAULT_FORWARD_POLICY="DROP"
```

E as regras de rota do Waydroid no UFW apontavam para **interfaces WAN antigas**:

```text
-A ufw-user-forward -i waydroid0 -o enp0s29u1u5 -j ACCEPT
-A ufw-user-forward -i waydroid0 -o enp0s29u1u2 -j ACCEPT
```

A WAN atual é `enp6s0`. Não existia nenhuma regra de `FORWARD` para ela, então o
tráfego TCP do container era descartado. O que enganava o diagnóstico:

| Tráfego | Resultado | Por quê |
|---|---|---|
| `ping 1.1.1.1` / `ping google.com` | **funciona** | o `ufw-before-forward` aceita `echo-request` (ICMP) |
| DNS | **funciona** | o `dnsmasq` roda no host; é `INPUT`, não `FORWARD` |
| TCP 80/443 para fora | **timeout** | cai no `FORWARD` com política `DROP` |
| ADB host → Android | **funciona** | é entrada no container, não forward |

Sem TCP, os dois apps não carregam API/playlist e ficam na splash. Não era
licença, não era crash, não era tradução ARM, não era áudio.

### Evidências

Dentro do Android:

```text
ping 1.1.1.1            -> 2/2 pacotes, 0% perda
ping google.com         -> 2/2 pacotes, 0% perda
curl https://www.google.com/generate_204
                        -> Failed to connect ... port 443 ... Connection timed out
```

Logcat do Nio:

```text
java.net.SocketTimeoutException: failed to connect to
android.bugly.qq.com/14.22.7.199 (port 443) from /192.168.240.112
```

Logcat do STV:

```text
TrafficStats: tagSocket(...) ...
ConnectivityService/NetworkMonitor: PROBE_HTTPS ...
Probe failed with exception java.net.SocketTimeoutException
```

---

## 2. Solução definitiva

```bash
cd /home/luisao/Projects/waydroid/hypr/waydroid
sudo ./fix_waydroid_apps.sh
```

O script:

1. confere container e sessão do Waydroid;
2. grava e aplica `/usr/local/lib/waydroid/net-fix` com regras de `FORWARD`/NAT
   que **não dependem do nome da WAN**;
3. adiciona ao UFW regras genéricas persistidas em `/etc/ufw/user.rules`:

   ```text
   -A ufw-user-forward -i waydroid0 -j ACCEPT
   -A ufw-user-forward -o waydroid0 -j ACCEPT
   ```

4. instala persistência para o problema não voltar:
   - `/etc/NetworkManager/dispatcher.d/90-waydroid-net-fix` — reaplica quando a
     rede/VPN muda;
   - `waydroid-net-fix.timer` — reaplica no máximo a cada 3 minutos;
   - `waydroid-net-fix.service` com `StartLimitIntervalSec=0`;
   - o `waydroid-net-fix.path` antigo é **desativado/removido**, porque o
     `PathExists` re-disparava o serviço em loop enquanto `waydroid0` existia.
5. configura ADB TCP (baixa platform-tools se faltar e grava a chave);
6. valida TCP de dentro do Android;
7. reabre o Nio pelo caminho de auto-login (`SplashActivity`) e o STV
   (`IndexActivity`);
8. valida foco/processo e mostra o resultado.

### Diagnóstico sem alterar nada

```bash
./fix_waydroid_apps.sh --check
```

Saída esperada no final:

```text
https://www.google.com/generate_204              HTTP 204
http://bnewsc.top/player_api.php                 HTTP 200
https://nio.gerenciapro.top/bnsc/api/            HTTP 200
==> Conclusão
  ✓ TCP de saída OK.
```

---

## 3. Validação feita nesta máquina

```console
$ sudo ./fix_waydroid_apps.sh
...
==> Nio Player (com.nio.smart.player)
  ✓ Nio abriu no dashboard
==> STV (com.bx.livf)
  ✓ STV abriu (lista de canais carregada)
  ✓ Nio continua rodando em segundo plano
================================================================
  RESULTADO: Nio e STV abriram
================================================================
  Foco atual: ... com.bx.livf/com.bx.live.activity.MainActivity
```

Conferência manual:

```bash
A=/tmp/opencode/platform-tools/adb
$A shell dumpsys window | grep mCurrentFocus
$A shell "curl -sS -m 8 -o /dev/null -w '%{http_code}\n' https://www.google.com/generate_204"
# 204
```

O STV abriu na lista de canais (categorias ABERTOS, NOTÍCIAS, etc.) e o Nio
chegou ao dashboard e reproduziu vídeo.

---

## 4. Por que não “consertar” desativando o UFW

Desativar o UFW resolveria o sintoma, mas abriria o firewall inteiro. A correção
acima mantém o UFW ativo e libera **somente** o forward do `waydroid0`, nos dois
sentidos, sem depender da interface WAN.

As quatro regras antigas (`enp0s29u1u5`/`enp0s29u1u2`) continuam no arquivo por
histórico; elas não atrapalham. As regras genéricas novas é que valem.

---

## 5. Se o sintoma voltar

1. Rode o diagnóstico:

   ```bash
   ./fix_waydroid_apps.sh --check
   ```

2. Se o TCP estiver bloqueado:

   ```bash
   sudo ./fix_waydroid_apps.sh
   ```

3. Se o TCP estiver OK mas o app continuar na splash, veja o logcat:

   ```bash
   A=/tmp/opencode/platform-tools/adb
   $A logcat -d | grep -iE 'nio|fusion|bx.livf|SocketTimeout|ANR|FATAL' | tail -60
   ```

4. Áudio mudo é outro problema (HAL do Android), tratado em
   `AUDIO-SEM-SOM.md` e `fix_waydroid_audio.sh`.

---

## 6. Comandos manuais equivalentes (referência)

Caso queira aplicar sem o script:

```bash
# 1) regras de forward independentes da WAN
sudo ufw route allow in on waydroid0 comment 'Waydroid outbound'
sudo ufw route allow out on waydroid0 comment 'Waydroid return'

# 2) garantia no iptables (idempotente)
sudo iptables -C FORWARD -i waydroid0 -j ACCEPT 2>/dev/null || \
  sudo iptables -I FORWARD -i waydroid0 -j ACCEPT
sudo iptables -C FORWARD -o waydroid0 -j ACCEPT 2>/dev/null || \
  sudo iptables -I FORWARD -o waydroid0 -j ACCEPT

# 3) NAT (se não existir)
sudo iptables -t nat -C POSTROUTING -s 192.168.240.0/24 ! -d 192.168.240.0/24 -j MASQUERADE 2>/dev/null || \
  sudo iptables -t nat -A POSTROUTING -s 192.168.240.0/24 ! -d 192.168.240.0/24 -j MASQUERADE

# 4) reabrir os apps
waydroid app launch com.nio.smart.player
waydroid app launch com.bx.livf
```

O script faz tudo isso e ainda deixa a persistência pronta.
