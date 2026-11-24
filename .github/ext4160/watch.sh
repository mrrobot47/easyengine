#!/bin/bash
# During the upgrade: snapshots of the update-ee-* support containers and site db containers (with their logs, which vanish on removal). Usage: watch.sh <dir>; stops when $STOP exists.
. "$(dirname "$0")/lib.sh"; D=$1; mkdir -p $D/logs; prev=
while [ ! -e $STOP ]; do
  cur=$(docker ps -a --format '{{.ID}} {{.Names}} {{.Image}} {{.Status}}' | grep -E ' (update-ee|[^ ]*-db-1 )' | sort)
  [ "$cur" != "$prev" ] && { echo "== $(ts)"; echo "$cur"; } >> $D/ps.txt; prev=$cur
  echo "$cur" | while read -r id name _; do [ -n "$id" ] && docker logs -t $id > $D/logs/.tmp 2>&1 && mv $D/logs/.tmp $D/logs/$name.$id.log; done
  sleep 0.5
done
