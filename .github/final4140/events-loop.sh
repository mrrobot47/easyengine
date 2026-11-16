#!/bin/bash
# Forces docker-gen events every ~5 s: a throwaway `docker run --rm` and a restart of an unrelated dummy. Usage: events-loop.sh <out>
. "$(dirname "$0")/lib.sh"; O=$1
while [ ! -e /tmp/f4-stop-probe ]; do
  echo "$(ts) run --rm" >> $O; docker run --rm alpine:3 true >/dev/null 2>&1
  echo "$(ts) restart dummy" >> $O; docker restart -t 1 f4-event-dummy >/dev/null 2>&1
  sleep 5
done
