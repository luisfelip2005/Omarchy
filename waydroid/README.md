# Waydroid + GAPPS no Omarchy/Arch — prompt de replicação

> **Origem deste documento:** Omarchy 4.0.6 (Arch Linux), kernel `7.2.8-9-omarchy`,
> Waydroid `1.6.3`, imagem oficial LineageOS 20 GAPPS.
> **Branch:** `setup-waydroid` (o Git não aceita espaço em nome de branch).
>
> **Status na máquina de origem:** setup, binderfs, rede, Play Store e GMS validados.
> A certificação da Play Store estava em andamento no momento em que este documento
> foi gerado; o fluxo abaixo é o que deve ser concluído no outro computador.
>
> **Importante:** todos os comandos com `sudo` devem ser executados pelo usuário.
> O agente que receber este prompt não deve tentar executar `sudo` sozinho; ele deve
> preparar o comando, pedir para o usuário rodar e analisar a saída.

---

## 1. Prompt para o agente (copie daqui)

```text
Você é um agente de TI atuando em um Arch Linux/Omarchy x86_64 com Wayland.

Objetivo: instalar o Waydroid com a imagem oficial LineageOS 20 GAPPS, deixar a
rede funcionando (DHCP, DNS, NAT e UFW) e orientar a certificação da Play Store.

Os scripts e este guia estão em ~/.config/hypr/waydroid, na branch setup-waydroid.
Leia o README.md inteiro e use os scripts anexados; não recrie a lógica de rede
nem edite arquivos em /usr/lib/waydroid.

Regras obrigatórias:
1. NÃO execute comandos com sudo. Prepare o comando completo e peça ao usuário
   para executá-lo, colando a saída. Só continue depois de analisar a saída.
2. Se o Waydroid já estiver instalado/inicializado, NÃO tente consertar por cima:
   rode `sudo ./cleanup_waydroid.sh --check`, mostre exatamente o que será apagado,
   peça confirmação explícita e então rode `sudo ./cleanup_waydroid.sh --yes`.
   Use `--remove-package` somente se o usuário pedir para remover o pacote também.
3. Não troque kernel, bootloader, Secure Boot ou driver de vídeo. Use binderfs
   nativo. Se `/proc/filesystems` não tiver `binder`, pare e reporte; o fallback
   DKMS só pode ser usado com autorização explícita.
4. Não desative o UFW. Adicione regras específicas para waydroid0 e preserve o
   restante do firewall.
5. Não edite /usr/lib/waydroid nem os scripts do pacote. Use os scripts deste
   diretório.
6. Responda em português e siga a ordem das fases. Valide cada fase antes de
   avançar; não pule a verificação de rede.
7. Avise que a certificação da Play Store exige a conta Google do usuário e que
   a propagação leva de 10 a 20 minutos. Play Integrity/SafetyNet e alguns apps
   bancários podem continuar falhando mesmo com a Play Store certificada.

Fluxo esperado:
  ./setup_waydroid.sh --check
  [limpeza, se necessário]
  sudo ./setup_waydroid.sh
  sudo ./setup_waydroid.sh --verify
  waydroid show-full-ui
  sudo ./setup_waydroid.sh --certify

No fim, o usuário deve conseguir abrir a Play Store, fazer login e instalar um app.
```

---

## 2. Arquivos deste diretório

| Arquivo | Para que serve |
|---|---|
| `setup_waydroid.sh` | Setup completo: dependências, binderfs, imagens GAPPS, rede, serviço de sessão, verificação e certificação. |
| `cleanup_waydroid.sh` | Remove uma instalação existente (imagens, dados, unidades, regras de rede) para começar do zero. |
| `waydroid-net-debug.sh` | Diagnóstico de rede: regras do host, rotas internas do Android e testes de ping/DNS. |
| `fix_waydroid_audio.sh` | Corrige o áudio mudo do Waydroid reiniciando só a HAL de áudio do Android (`--status` para diagnosticar). |
| `AUDIO-SEM-SOM.md` | Contexto do bug "Waydroid sem som": diagnóstico pelo PipeWire, causa, correção e validação. |
| `PROMPT-APPS.md` | Prompt de implementação dos apps Android (Nio Player e STV): tradução ARM, ADB sem root, instalação, correção de áudio, manual de uso do STV e diagnóstico do Nio. |
| `SOLUCAO-NIO.md` | Solução do Nio Player na máquina A: sintoma, diagnóstico comparativo com a máquina B, causa raiz (auto-login × login manual), correção aplicada, validação e backup recomendado. |
| `README.md` | Este prompt/guia. |

Todos os scripts usam `set -Eeuo pipefail` e podem ser chamados de qualquer
diretório. O `setup_waydroid.sh` detecta o usuário do desktop via `SUDO_USER`,
`loginctl` ou pelo uid ≥ 1000.

---

## 3. Pré-requisitos e diagnóstico inicial

Requisitos:

- Arch Linux ou Omarchy, x86_64.
- Sessão Wayland ativa (Hyprland no caso do Omarchy).
- ~5 GB livres em `/var/lib` (a imagem GAPPS tem cerca de 1,2 GB comprimida e
  ~3 GB extraída, além dos dados Android).
- Internet funcionando no host.
- `sudo` com senha.
- Kernel com binderfs. O kernel do Omarchy usa o binder em Rust e expõe
  `binder` em `/proc/filesystems`; não é necessário DKMS.

Diagnóstico sem alterar nada:

```bash
cd ~/.config/hypr/waydroid
./setup_waydroid.sh --check
```

O relatório mostra distro, kernel, binderfs, Wayland, espaço, Waydroid, UFW,
backend do iptables, `ip_forward`, interface WAN e status do `waydroid0`.

Conferências manuais úteis:

```bash
uname -r
grep -w binder /proc/filesystems
printf '%s\n' "$XDG_SESSION_TYPE"
waydroid --version
systemctl is-active waydroid-container
ufw status verbose
iptables --version
sysctl net.ipv4.ip_forward
df -h /var/lib
```

Resultado esperado na origem:

- `grep -w binder /proc/filesystems` → `nodev binder`
- `waydroid --version` → `1.6.3`
- `ufw status` → `Status: active`, `Default: deny (incoming), allow (outgoing), deny (routed)`
- `iptables --version` → `iptables v1.8.13 (nf_tables)`
- `ip_forward` → `0` antes do setup; `1` depois.

> Se o kernel não tiver binderfs, **pare**. O script tem um fallback com
> `binder_linux-dkms` (AUR), mas ele exige headers do kernel e não foi o caminho
> usado nesta replicação.

---

## 4. Limpeza: se o Waydroid já existir

O `cleanup_waydroid.sh` apaga **todos** os dados Android, imagens, configuração,
unidades systemd e regras de rede do Waydroid. O pacote é mantido por padrão.

Primeiro, veja o que existe (não altera nada):

```bash
cd ~/.config/hypr/waydroid
sudo ./cleanup_waydroid.sh --check
```

Depois, com confirmação:

```bash
sudo ./cleanup_waydroid.sh
# digite APAGAR quando solicitado
```

Ou, sem confirmação (use com cuidado):

```bash
sudo ./cleanup_waydroid.sh --yes
```

Para remover também o pacote `waydroid`/`waydroid-git`:

```bash
sudo ./cleanup_waydroid.sh --remove-package --yes
```

O que a limpeza remove:

- sessão do usuário e `~/.config/systemd/user/waydroid-session.service`;
- `waydroid-container`, `waydroid-binderfs`, `dev-binderfs.mount` e
  `waydroid-net-fix.path/service`;
- `/usr/local/lib/waydroid` (alocador binderfs e `net-fix`);
- `/etc/sysctl.d/99-waydroid.conf`;
- regras UFW/iptables/NAT específicas de `waydroid0`;
- `/var/lib/waydroid` (imagens, dados, configuração);
- `~/.local/share/waydroid` (dados Android do Waydroid 1.6+);
- logs e caches temporários.

> **Backup:** se houver apps ou dados Android importantes em
> `~/.local/share/waydroid`, faça backup antes. A limpeza é destrutiva.

---

## 5. Setup completo

```bash
cd ~/.config/hypr/waydroid
sudo ./setup_waydroid.sh
```

O script pede confirmação antes de baixar a imagem GAPPS. Para executar sem
interação (baixa e configura, mas não pausa para certificação):

```bash
sudo ./setup_waydroid.sh -y
```

Opções principais:

```bash
sudo ./setup_waydroid.sh --force-images   # rebaixa as imagens
sudo ./setup_waydroid.sh --skip-images    # não baixa/inicializa imagens
sudo ./setup_waydroid.sh --no-start       # não inicia a sessão no fim
sudo ./setup_waydroid.sh --no-network-fix # não mexe em firewall/NAT
sudo ./setup_waydroid.sh --no-certify     # não pausa para certificação
sudo ./setup_waydroid.sh --autostart      # habilita a sessão no login
```

O que acontece, em ordem:

1. Verifica Arch/Omarchy, x86_64, espaço e Wayland.
2. Instala pacotes que faltam (`lxc`, `dnsmasq`, `python-gbinder`, `libgbinder`,
   `libglibutil`, `mesa`, `vulkan-radeon`, `libglvnd`, `sqlite`).
3. Cria `/dev/binderfs` via `dev-binderfs.mount`, aloca `binder`, `vndbinder` e
   `hwbinder` com ioctl `BINDER_CTL_ADD`, cria symlinks em `/dev` e chmod 0666.
4. Para qualquer sessão/container existente.
5. Baixa e inicializa a imagem oficial `lineage-20.0-...-GAPPS` com
   `waydroid init -s GAPPS` (~1,2 GB).
6. Corrige a rede: `ip_forward=1`, NAT MASQUERADE, regras de FORWARD/INPUT no
   backend nft, regras de rota persistentes no UFW, MSS clamp e checksum de DHCP.
7. Cria `waydroid-net-fix.path`, que observa `waydroid0`, e aplica as regras
   também no início de cada sessão.
8. Cria o serviço de usuário `waydroid-session.service`.
9. Inicia a sessão, espera o boot do Android e verifica Play Store/GMS.
10. Obtém o Android ID (GSF) e oferece a certificação.

O download pode demorar. Se falhar, rode de novo: o cache é reaproveitado. Para
forçar um novo download, use `--force-images`.

---

## 6. Validar a rede e a Play Store

Com a sessão já iniciada:

```bash
waydroid status
sudo ./setup_waydroid.sh --verify
```

O `--verify` aplica as regras de rede, espera o boot e testa:

- `/dev/binder`, `/dev/vndbinder`, `/dev/hwbinder`;
- `system.img` e `vendor.img`, e se a imagem é GAPPS;
- `ip_forward`, `waydroid0`, dnsmasq em `192.168.240.1:53`, NAT e FORWARD;
- sessão, Play Store (`com.android.vending`) e GMS (`com.google.android.gms`);
- `ping 1.1.1.1` e resolução de `google.com` **dentro** do Android;
- Android ID, se o banco do GSF já existir.

Saída esperada (resumo):

```text
✓ /dev/binder presente
✓ system.img e vendor.img presentes
✓ imagem GAPPS configurada
✓ ip_forward=1
✓ waydroid0: 192.168.240.1/24
✓ dnsmasq escutando em 192.168.240.1:53
✓ NAT MASQUERADE presente
✓ regras de FORWARD presentes
✓ Android boot concluído
✓ Play Store presente
✓ Google Play Services presente
✓ ping 1.1.1.1 OK
✓ DNS/rota para google.com OK
✓ Verificação concluída sem falhas críticas.
```

### Se `IP address: UNKNOWN` ou o ping falhar

Isso aconteceu na primeira execução porque o `waydroid-net-fix.path` foi
iniciado no mesmo instante em que o `waydroid0` apareceu e perdeu o evento. O
script já aplica as regras dentro de `start_session`, mas, se a sessão estiver
rodando sem rede, force manualmente:

```bash
sudo systemctl start waydroid-net-fix.service
systemctl --user restart waydroid-session.service
sleep 30
sudo ./setup_waydroid.sh --verify
```

O lease DHCP fica em:

```bash
cat /var/lib/misc/dnsmasq.waydroid0.leases
```

O IP do Android deve aparecer em `waydroid status` como `192.168.240.x`.

Diagnóstico detalhado:

```bash
sudo bash ~/.config/hypr/waydroid/waydroid-net-debug.sh
```

Ele mostra as regras FORWARD/NAT/UFW do host, as rotas internas do Android e
testa gateway, `1.1.1.1` e `google.com`. Use a saída para distinguir:

- Android pinga o gateway, mas não `1.1.1.1` → problema de FORWARD/UFW no host;
- Android não pinga nem o gateway → problema de rota/DHCP dentro do Android.

---

## 7. Abrir a interface e certificar a Play Store

Abra o Android (como usuário, **sem** sudo):

```bash
waydroid show-full-ui
```

`Container: FROZEN` no `waydroid status` é normal quando a janela está fechada;
a UI descongela o container.

Abra a **Play Store** uma vez e espere 1–2 minutos. Isso inicializa o GMS/GSF e
cria o banco com o Android ID. Mesmo que apareça “dispositivo não certificado”,
deixe carregar.

Depois:

```bash
sudo ./setup_waydroid.sh --certify
```

O script:

1. Confirma que a sessão está rodando e o Android concluiu o boot.
2. Confirma Play Store e GMS.
3. Lê o Android ID do GSF em:
   - `/data/data/com.google.android.gsf/databases/gservices.db`
   - fallback: `com.google.android.gms`
   - fallback: `/data/user_de/0/...`
   - se o `sqlite3` não existir dentro do Android, copia o banco e consulta no host.
4. Mostra o ID e abre https://www.google.com/android/uncertified/.
5. Pausa para você registrar o ID com a **mesma conta Google** que será usada na
   Play Store.
6. Ao pressionar ENTER, limpa os dados da Play Store, reinicia a sessão e abre a
   loja novamente.

Depois de registrar, aguarde **10 a 20 minutos** e faça login na Play Store.

### Se o Android ID continuar indisponível

Confirme que a Play Store foi aberta e aguarde mais um pouco. Para localizar o
banco real:

```bash
sudo waydroid shell -- sh -c 'find /data/data /data/user_de/0 -name gservices.db 2>/dev/null'
```

Se o caminho for diferente dos listados, ajuste a consulta no `setup_waydroid.sh`
ou peça ao agente para adaptar. O ID do GSF é o que o site do Google espera; não
use o SSAID de `settings get secure android_id`.

Se a Play Store disser que o dispositivo não é certificado depois do prazo:

```bash
sudo ./setup_waydroid.sh --certify
# ou, manualmente:
sudo waydroid shell pm clear com.android.vending
systemctl --user restart waydroid-session.service
```

---

## 8. Teste final

1. Abra a Play Store e faça login.
2. Instale um app gratuito de teste.
3. Abra o app.
4. Rode novamente:

```bash
sudo ./setup_waydroid.sh --verify
```

Autostart opcional (a sessão inicia junto com o desktop):

```bash
sudo ./setup_waydroid.sh --autostart
```

Conferir o serviço de usuário:

```bash
systemctl --user status waydroid-session.service
```

---

## 9. Histórico exato de comandos executados na origem

Esta é a ordem real usada na máquina de origem. Comandos com `sudo` foram
executados pelo usuário; o agente apenas preparou e analisou.

### 9.1 Diagnóstico inicial

```bash
cd /home/luisao
./setup_waydroid.sh --check
./setup_waydroid.sh --help
bash -n setup_waydroid.sh
shellcheck -S warning setup_waydroid.sh
```

Diagnósticos complementares usados:

```bash
uname -r
cat /etc/os-release
grep -w binder /proc/filesystems
ls -l /dev/binder /dev/vndbinder /dev/hwbinder
mount | grep -E 'binderfs|waydroid'
systemctl is-active waydroid-container
waydroid --version
waydroid status
ufw status verbose
iptables --version
sysctl net.ipv4.ip_forward
ip route
df -h /var/lib
```

### 9.2 Setup

```bash
sudo /home/luisao/setup_waydroid.sh
```

Resultado: imagens baixadas e extraídas.

```text
system.img  2.5G
vendor.img  537M
```

Binderfs e unidades:

```bash
ls -l /dev/binder /dev/vndbinder /dev/hwbinder
mount | grep binderfs
systemctl is-active waydroid-container waydroid-binderfs.service waydroid-net-fix.path
```

### 9.3 Primeira validação e correção de rede

```bash
waydroid status
```

Resultado inicial: sessão `RUNNING`, mas `IP address: UNKNOWN`, sem lease DHCP.

```bash
sudo systemctl start waydroid-net-fix.service
systemctl --user restart waydroid-session.service
```

Depois:

```bash
waydroid status
```

Resultado: `IP address: 192.168.240.112`.

```bash
sudo /home/luisao/setup_waydroid.sh --verify
```

Resultado: falhou nos pings. Causa: o comando de teste era
`waydroid shell ping -c ...`; o `waydroid` interpretava `-c`/`-W` como opções
dele. O teste manual funcionava porque usava `--`.

Correção aplicada no script:

```bash
waydroid shell -- ping -c 1 -W 2 1.1.1.1
waydroid shell -- ping -c 1 -W 3 google.com
```

Diagnóstico completo:

```bash
sudo bash /home/luisao/waydroid-net-debug.sh
```

Resultado: Android pinga `192.168.240.1`, `1.1.1.1` e `google.com`; NAT e
FORWARD do host contabilizam tráfego. A rede estava boa; o teste do script
estava errado.

Nova validação:

```bash
sudo /home/luisao/setup_waydroid.sh --verify
```

Resultado: todas as verificações passaram, incluindo ping e DNS.

### 9.4 Play Store e certificação

```bash
waydroid show-full-ui
```

Play Store aberta manualmente. Depois:

```bash
sudo /home/luisao/setup_waydroid.sh --certify
```

Resultado inicial: “Android ID indisponível”. Causa: o script consultava
`com.google.android.gms`; o ID do GSF fica em `com.google.android.gsf`.

Correção aplicada: `get_android_id()` agora tenta GSF e GMS, em `/data/data` e
`/data/user_de/0`, com fallback de cópia do banco e do WAL para consulta no host.

> Na origem, a certificação ainda não havia sido concluída quando este documento
> foi gerado. No outro computador, siga a seção 7 e valide o ID.

### 9.5 Comandos de diagnóstico úteis

```bash
pgrep -af 'setup_waydroid|waydroid init|waydroid session'
ls -lh /var/lib/waydroid/images/
grep -E '^(binder|vndbinder|hwbinder|system_ota|vendor_ota)' /var/lib/waydroid/waydroid.cfg
ls -l /dev/binder /dev/vndbinder /dev/hwbinder
mount | grep -E 'binderfs|waydroid'
systemctl is-active waydroid-container waydroid-binderfs.service waydroid-net-fix.path
waydroid status
ip -br addr show waydroid0
sysctl -n net.ipv4.ip_forward
cat /var/lib/misc/dnsmasq.waydroid0.leases
ping -c 2 192.168.240.112
ping -I 192.168.240.1 -c 2 1.1.1.1
```

O último ping testa o NAT do host usando o endereço do bridge como origem; se
funcionar, o problema não é NAT/WAN.

---

## 10. Problemas encontrados e correções

| Sintoma | Causa | Correção |
|---|---|---|
| `IP address: UNKNOWN` e sem internet | `waydroid-net-fix.path` perdeu o evento de criação do `waydroid0` na primeira execução | `sudo systemctl start waydroid-net-fix.service`, reiniciar a sessão e rodar `--verify`; o script agora aplica no `start_session` |
| `--verify` falha no ping, mas o ping manual funciona | `waydroid shell ping -c ...` sem `--`; argparse do Waydroid consome `-c`/`-W` | usar `waydroid shell -- ping ...` |
| `--verify` falha logo após reiniciar a sessão | Android ainda não terminou DHCP/validação | o script agora tenta por até ~30 s antes de falhar |
| Android ID indisponível | script consultava o banco do GMS, mas o ID do GSF está em `com.google.android.gsf` | `get_android_id()` corrigido com GSF + GMS e fallbacks |
| Play Store “não certificada” | ID não registrado ou propagação pendente | registrar em google.com/android/uncertified, aguardar 10–20 min, limpar dados da Play Store e reiniciar |
| `Container: FROZEN` | UI fechada | normal; `waydroid show-full-ui` descongela |
| UFW bloqueia DHCP/FORWARD | `DEFAULT_FORWARD_POLICY=DROP` e backend nft | regras `ufw route allow` + `iptables -I FORWARD` no backend nft; não desativar o UFW |
| Waydroid usa `iptables-legacy` e UFW usa nft | scripts do Waydroid preferem `iptables-legacy` | o `net-fix` replica as regras no backend nft; as regras legacy não são suficientes |
| App ARM não instala | imagem x86_64 sem tradução ARM | opcional: instalar `libndk`/`libhoudini`; `lzip` pode ser necessário |
| Download da imagem falha | rede/OTA instável | rodar de novo (cache) ou `--force-images`; conferir `ota.waydro.id` |
| App toca vídeo mas nenhum app Android tem som | HAL de áudio do Android acumula conexões no PipeWire e trava (bug do Waydroid) | `./fix_waydroid_audio.sh`, depois pause/play no app; detalhes em `AUDIO-SEM-SOM.md` |

---

## 11. Limitações e avisos

- A certificação exige uma conta Google e a propagação leva de 10 a 20 minutos.
- Play Integrity/SafetyNet, apps bancários e alguns jogos podem continuar
  falhando; isso é limitação do Waydroid, não da rede.
- A imagem GAPPS é oficial do projeto Waydroid, mas o Android dentro do container
  não é um dispositivo certificado de fábrica.
- A sessão roda como o usuário do desktop; a UI deve ser aberta sem `sudo`.
- O `waydroid0` é criado no início da sessão, não quando o
  `waydroid-container.service` sobe. Por isso existe o path unit e a aplicação
  explícita no `start_session`.
- A limpeza apaga dados Android. Faça backup antes.
- Não remova nós `/dev/binder` que sejam devices reais (módulo DKMS); o cleanup
  só remove symlinks para binderfs.
- Não altere kernel/bootloader para “resolver” binder; o binderfs do kernel do
  Omarchy funciona.

---

## 12. Checklist final

- [ ] `./setup_waydroid.sh --check` sem erros
- [ ] `/proc/filesystems` contém `binder`
- [ ] `/dev/binder`, `/dev/vndbinder`, `/dev/hwbinder` presentes
- [ ] `system.img` e `vendor.img` GAPPS presentes
- [ ] `waydroid status` com `Session: RUNNING` e IP `192.168.240.x`
- [ ] `sudo ./setup_waydroid.sh --verify` sem falhas
- [ ] ping `1.1.1.1` e DNS `google.com` OK dentro do Android
- [ ] Play Store e Google Play Services presentes
- [ ] Android ID (GSF) registrado no site do Google
- [ ] login na Play Store funcionando
- [ ] app de teste instalado e aberto
- [ ] (opcional) `sudo ./setup_waydroid.sh --autostart`

Se algum item falhar, rode o `waydroid-net-debug.sh` e envie a saída junto com
`waydroid status` e `sudo ./setup_waydroid.sh --verify`.
