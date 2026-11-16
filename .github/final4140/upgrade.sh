#!/bin/bash
# Installs <phar> the way `ee cli update` does (`php <tmp> cli info`, then replace /usr/local/bin/ee only if that worked), with probes, pollers and forced container events.
# Usage: upgrade.sh <dir> <phar> [block]   (block: Docker Hub blackholed in /etc/hosts for the run)
. "$(dirname "$0")/lib.sh"; D=$1; NEW=$2; MODE=${3:-}; mkdir -p $D
rm -f /tmp/f4-stop-probe
bash $F/state.sh $D/before; bash $F/matrix.sh > $D/matrix-before.txt
for s in $ALL; do echo "$s $(stat -c %s /opt/easyengine/sites/$s/logs/nginx/error.log 2>/dev/null || echo 0)"; done > $D/errlog-offsets-before.txt
off=$(stat -c %s $EE_LOG)
docker events --format '{{.TimeNano}} {{.Type}} {{.Action}} {{.Actor.Attributes.name}} {{.Actor.Attributes.image}}' > $D/docker-events.txt 2>&1 & EP=$!
bash $F/probe.sh $D/probe.txt & PP=$!
bash $F/wildpoll.sh $D/wildpoll.txt & WP=$!
bash $F/events-loop.sh $D/events-forced.txt & XP=$!
if [ "$MODE" = block ]; then
  cp -p /etc/hosts $D/hosts.before-block
  echo "10.255.255.1 registry-1.docker.io auth.docker.io index.docker.io production.cloudflare.docker.com" >> /etc/hosts
  if timeout 20 docker pull -q busybox:1.36 >/dev/null 2>&1; then echo "not-blocked" > $D/block-check.txt; else echo "blocked" > $D/block-check.txt; fi
fi
sleep 3
T=/tmp/ee_$(date +%s%N).phar; cp "$NEW" $T
echo "START $(ts)" > $D/cmd.txt; s=$(date +%s.%N)
php $T cli info > $D/cliinfo.out 2> $D/cliinfo.err; rc=$?
if [ $rc -ne 0 ] || ! grep -qi 'EE version' $D/cliinfo.out; then
  echo "Error: The downloaded PHAR is broken, try running ee cli update again." > $D/update.out; rm -f $T; urc=1
else
  chmod $(stat -c %a /usr/local/bin/ee) $T && mv $T /usr/local/bin/ee && echo "Success: Updated EE." > $D/update.out; urc=$?
fi
e=$(date +%s.%N)
echo "END $(ts) cli-info-rc=$rc update-rc=$urc wall=$(awk "BEGIN{printf \"%.1f\", $e - $s}")s" >> $D/cmd.txt
echo $urc > $D/rc.txt; echo "$s $e" > $D/window.txt
if [ "$MODE" = block ]; then cp -p $D/hosts.before-block /etc/hosts; cmp -s /etc/hosts $D/hosts.before-block && echo "hosts restored byte-identical" >> $D/cmd.txt; fi
for s in $ALL; do echo "$s $(stat -c %s /opt/easyengine/sites/$s/logs/nginx/error.log 2>/dev/null || echo 0)"; done > $D/errlog-offsets-end.txt
sleep 15; touch /tmp/f4-stop-probe; wait $PP $WP $XP 2>/dev/null; kill $EP 2>/dev/null
# This run's ee.log (logrotate may rotate it during the run).
if [ $(stat -c %s $EE_LOG) -lt $off ]; then tail -c +$((off+1)) $EE_LOG.1; cat $EE_LOG; else tail -c +$((off+1)) $EE_LOG; fi > $D/ee.log.part
for s in $ALL; do f=/opt/easyengine/sites/$s/logs/nginx/error.log; o=$(awk -v s=$s '$1==s{print $2}' $D/errlog-offsets-before.txt); e=$(awk -v s=$s '$1==s{print $2}' $D/errlog-offsets-end.txt)
  echo "$s $(tail -c +$((o+1)) $f 2>/dev/null | head -c $((e-o)) | grep -c 'No route to host')"; done > $D/noroute-during.txt
bash $F/state.sh $D/after; bash $F/matrix.sh > $D/matrix-after.txt
ls /tmp/ee_*.phar > $D/tmp-phars.txt 2>/dev/null
cat $D/cmd.txt; tail -5 $D/cliinfo.err
