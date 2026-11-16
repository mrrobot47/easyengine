#!/bin/bash
# Every 0.2 s: _wildcard.* files in the proxy mounts, the staging dir, and the proxy image/start; logs changes only. Usage: wildpoll.sh <out>
. "$(dirname "$0")/lib.sh"; O=$1; last=""
while [ ! -e /tmp/f4-stop-probe ]; do
  w=$(ls -A $P/htpasswd $P/vhost.d 2>/dev/null | grep '^_wildcard' | sort | tr '\n' ' ')
  s=$([ -d $STAGE ] && echo "staged($(ls -A $STAGE/htpasswd $STAGE/vhost.d 2>/dev/null | grep -c _wildcard))" || echo "nostage")
  px=$(docker inspect -f '{{.Config.Image}}@{{.State.StartedAt}}' services_global-nginx-proxy_1 2>/dev/null || echo "noproxy")
  cur="live=[$w] $s proxy=$px"
  [ "$cur" != "$last" ] && echo "$(ts) $cur" >> $O && last=$cur
  sleep 0.2
done
