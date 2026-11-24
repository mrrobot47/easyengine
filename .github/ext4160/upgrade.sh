#!/bin/bash
# Installs the candidate <phar> the way `ee cli update` does after its download and md5 check (`php <tmp> cli info`, then replace /usr/local/bin/ee only if that worked), with the probe, the support/db watcher and docker events running.
# Usage: upgrade.sh <dir> <phar>
. "$(dirname "$0")/lib.sh"; D=$1; NEW=$2; mkdir -p $D; rm -f $STOP
mark=$(eelog_mark)
docker events --format '{{.TimeNano}} {{.Type}} {{.Action}} {{.Actor.Attributes.name}} {{.Actor.Attributes.image}}' > $D/docker-events.txt 2>&1 & EP=$!
bash $F/probe.sh $D/probe.txt & PP=$!
bash $F/watch.sh $D/watch & WP=$!
sleep 3
T=/tmp/ee_$(date +%s%N).phar; cp "$NEW" $T
echo "START $(ts)" > $D/cmd.txt; s=$(date +%s.%N)
php $T cli info --debug > $D/cliinfo.out 2> $D/cliinfo.err; rc=$?
if [ $rc -ne 0 ] || ! grep -qi 'EE version' $D/cliinfo.out; then
  echo "Error: The downloaded PHAR is broken, try running ee cli update again." > $D/update.out; rm -f $T; urc=1
else
  chmod $(stat -c %a /usr/local/bin/ee) $T && mv $T /usr/local/bin/ee && echo "Success: Updated EE." > $D/update.out; urc=$?
fi
e=$(date +%s.%N)
echo "END $(ts) cli-info-rc=$rc update-rc=$urc wall=$(awk "BEGIN{printf \"%.1f\", $e - $s}")s" >> $D/cmd.txt
echo "$rc $urc" > $D/rc.txt; echo "$s $e" > $D/window.txt
sleep 15; touch $STOP; wait $PP $WP 2>/dev/null; kill $EP 2>/dev/null
eelog_since "$mark" > $D/ee.log.part
cat $D/cmd.txt $D/update.out; tail -5 $D/cliinfo.err
