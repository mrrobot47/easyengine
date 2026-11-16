#!/bin/bash
# Dead-peer check after an upgrade: N requests 11 s apart per site via 127.0.0.1, `No route to host` in error.log, SYN-SENT to :9000 in each site nginx netns. Usage: measure.sh <dir> [N=12] [label]
. "$(dirname "$0")/lib.sh"; O=$1; N=${2:-12}; mkdir -p $O; rm -f $O/.stop
url() { case $1 in f4-pdb.test) echo /f4-db.php;; *) echo /f4-marker.txt;; esac; }
for s in $ALL; do echo "$s $(stat -c %s /opt/easyengine/sites/$s/logs/nginx/error.log 2>/dev/null || echo 0)"; done > $O/errlog-offsets.txt
for s in $PHPSITES; do pid=$(docker inspect -f '{{.State.Pid}}' $(cname $s)-nginx-1)
  ( while [ ! -e $O/.stop ]; do nsenter -t $pid -n ss -Htan state syn-sent '( dport = :9000 )' | awk -v t=$(date +%T) '{print t, $4}'; sleep 0.5; done > $O/synsent-$s.txt ) & done
pids=()
for s in $ALL; do
  ( for i in $(seq 1 $N); do curl -s -o /dev/null -w "$s %{http_code} %{time_total} $(date +%T)\n" --max-time 10 --resolve $s:80:127.0.0.1 "http://$s$(url $s)"; [ $i -lt $N ] && sleep 11; done > $O/timing-$s.txt ) & pids+=($!)
done; wait "${pids[@]}"; touch $O/.stop; sleep 1
for s in $ALL; do
  f=/opt/easyengine/sites/$s/logs/nginx/error.log; off=$(awk -v s=$s '$1==s{print $2}' $O/errlog-offsets.txt)
  nr=$(tail -c +$((off+1)) $f 2>/dev/null | grep -c 'No route to host')
  slow=$(awk '$3>2' $O/timing-$s.txt | wc -l); bad=$(awk '$2!~/^[23]/' $O/timing-$s.txt | wc -l); max=$(awk 'm<$3{m=$3}END{print m+0}' $O/timing-$s.txt)
  nsyn=$(cat $O/synsent-$s.txt 2>/dev/null | wc -l)
  ge=$(docker exec $(cname $s)-nginx-1 getent hosts ${s}_php 2>/dev/null | awk '{print $1}' | sort | tr '\n' ' ')
  echo "$s slow=$slow bad=$bad max=$max noroute=$nr synsent=$nsyn php=[$ge]"
done > $O/measure.txt
cat $O/measure.txt
L=${3:-measure}
while read -r s rest; do
  chk "$L: $s after the upgrade: 0 No route to host, 0 SYN-SENT, 0 failed requests" "noroute=0 synsent=0 bad=0" "$(echo "$rest" | grep -oE 'noroute=[0-9]+') $(echo "$rest" | grep -oE 'synsent=[0-9]+') $(echo "$rest" | grep -oE 'bad=[0-9]+')"
done < $O/measure.txt
info "$L: slow>2s / max per site: $(awk '{print $1, $2, $4}' $O/measure.txt | tr '\n' ';')"
