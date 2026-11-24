#!/bin/bash
# Docker Hub block for the failpull legs. Usage: block.sh on|off|check
#   on:    registry, auth and index hosts -> 10.255.255.1 in /etc/hosts, plus an iptables/ip6tables REJECT (tcp-reset) of the
#          addresses they resolved to just before, so an idle keep-alive connection of the daemon can't finish a pull either.
#   off:   restores /etc/hosts byte for byte and deletes the rules.
#   check: prints blocked/not-blocked (a pull of an image that isn't local, 20 s timeout).
H="registry-1.docker.io auth.docker.io index.docker.io production.cloudflare.docker.com"
S=/var/tmp/ext-block; mkdir -p $S
case $1 in
on)
  [ -f $S/hosts.orig ] || cp -p /etc/hosts $S/hosts.orig
  : > $S/ips
  for h in $H; do getent ahosts $h | awk '{print $1}' | sort -u >> $S/ips; done
  sort -u -o $S/ips $S/ips
  echo "10.255.255.1 $H" >> /etc/hosts
  while read -r ip; do
    case $ip in *:*) ip6tables -I OUTPUT -d $ip -p tcp -j REJECT --reject-with tcp-reset 2>/dev/null && echo "$ip v6" >> $S/rules ;;
                *) iptables -I OUTPUT -d $ip -p tcp -j REJECT --reject-with tcp-reset && echo "$ip v4" >> $S/rules ;; esac
  done < $S/ips
  echo "block on: $(wc -l < $S/ips) addresses rejected, hosts entry added" ;;
off)
  [ -f $S/hosts.orig ] && cp -p $S/hosts.orig /etc/hosts && rm -f $S/hosts.orig
  [ -f $S/rules ] && while read -r ip v; do
    if [ $v = v6 ]; then ip6tables -D OUTPUT -d $ip -p tcp -j REJECT --reject-with tcp-reset; else iptables -D OUTPUT -d $ip -p tcp -j REJECT --reject-with tcp-reset; fi
  done < $S/rules; rm -f $S/rules
  echo "block off: hosts restored, $(iptables -S OUTPUT | grep -c 'tcp-reset') v4 reject rules left" ;;
check)
  if timeout 20 docker pull -q busybox:1.36.1-musl > /dev/null 2>&1; then docker rmi -f busybox:1.36.1-musl > /dev/null 2>&1; echo not-blocked; else echo blocked; fi ;;
esac
