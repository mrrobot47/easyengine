#!/bin/bash
# Every ~0.25 s: HTTP to every enabled site via 127.0.0.1, plus an uncached /?f50=<t> on the --cache site ($W84) (its / can come from the page cache; /wp-login.php is rate-limited). Usage: probe.sh <out>; stops when $STOP exists.
. "$(dirname "$0")/lib.sh"; O=$1; T=$(mktemp -d)
while [ ! -e $STOP ]; do
  t=$(date +%s.%N | cut -c1-14)
  for s in $ENABLED; do curl -s -m 3 -o /dev/null -w '%{http_code}' --resolve "$s:80:127.0.0.1" "http://$s/" > $T/h_$s & done
  curl -s -m 3 -o /dev/null -w '%{http_code}' --resolve "$W84:80:127.0.0.1" "http://$W84/?f50=$t" > $T/nocache &
  wait
  line="$t"; for s in $ENABLED; do line="$line $s=$(cat $T/h_$s)"; done
  echo "$line $W84/?f50=$(cat $T/nocache)" >> $O; sleep 0.25
done
