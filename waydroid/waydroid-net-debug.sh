#!/usr/bin/env bash
# Diagnóstico de rede do Waydroid
export LC_ALL=C
set +e

echo "===== HOST: FORWARD ====="
iptables -S FORWARD
iptables -L FORWARD -v -n --line-numbers

echo
echo "===== HOST: NAT ====="
iptables -t nat -S POSTROUTING
iptables -t nat -L POSTROUTING -v -n

echo
echo "===== HOST: UFW ====="
ufw status verbose

echo
echo "===== HOST: SYSCTL ====="
sysctl net.ipv4.ip_forward \
       net.ipv4.conf.all.rp_filter \
       net.ipv4.conf.waydroid0.rp_filter \
       net.ipv4.conf.wlp3s0.rp_filter

echo
echo "===== ANDROID: INTERFACES ====="
timeout 15 waydroid shell -- ip -4 addr show

echo
echo "===== ANDROID: ROTAS (todas as tabelas) ====="
timeout 15 waydroid shell -- ip route show table all

echo
echo "===== ANDROID: REGRAS DE ROTA ====="
timeout 15 waydroid shell -- ip rule

echo
echo "===== ANDROID: PING GATEWAY 192.168.240.1 ====="
timeout 20 waydroid shell -- ping -c 2 -W 2 192.168.240.1

echo
echo "===== ANDROID: PING 1.1.1.1 ====="
timeout 20 waydroid shell -- ping -c 2 -W 2 1.1.1.1

echo
echo "===== ANDROID: PING google.com ====="
timeout 20 waydroid shell -- ping -c 1 -W 3 google.com

echo
echo "===== ANDROID: PROPS DE DNS/DHCP ====="
timeout 15 waydroid shell -- sh -c 'getprop | grep -i -E "dns|dhcp"'

echo
echo "===== FIM ====="
