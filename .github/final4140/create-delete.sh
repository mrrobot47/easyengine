#!/bin/bash
# Create -> HTTP -> delete for each site type with the upgraded ee; checks nothing is left behind. Usage: create-delete.sh <label>
. "$(dirname "$0")/lib.sh"; L=$1; cd /tmp
while read -r s args; do
  ee site create $s $args </dev/null > /tmp/f4cd.out 2>&1; crc=$?
  [ $crc -eq 0 ] || tail -5 /tmp/f4cd.out
  grep -qE "[[:space:]]$s([[:space:]]|\$)" /etc/hosts || echo "127.0.0.1 $s" >> /etc/hosts
  sleep 2; proto=http; [[ $args == *ssl* ]] && proto=https
  c=$(curl -sk -m 20 -o /dev/null -w '%{http_code}' --resolve $s:80:127.0.0.1 --resolve $s:443:127.0.0.1 $proto://$s/)
  ee site delete $s --yes </dev/null > /dev/null 2>&1; drc=$?
  left=$(docker ps -a --format '{{.Names}}' | grep -c "^$(cname $s)-")
  dir=$([ -e /opt/easyengine/sites/$s ] && echo present || echo gone); rows=$(db "select count(*) from sites where site_url='$s'")
  chk "$L: create $s $args" "create=0 http=200 delete=0 left=0 dir=gone rows=0" "create=$crc http=$c delete=$drc left=$left dir=$dir rows=$rows"
done <<'X'
f4-cd-wp.test --type=wp
f4-cd-wpc.test --type=wp --cache
f4-cd-sd.test --type=wp --mu=subdir
f4-cd-sub.test --type=wp --mu=subdom
f4-cd-ldb.test --type=wp --local-db
f4-cd-php.test --type=php
f4-cd-pdb.test --type=php --with-db
f4-cd-p74.test --type=php --php=7.4
f4-cd-p80.test --type=php --php=8.0
f4-cd-p81.test --type=php --php=8.1
f4-cd-p83.test --type=php --php=8.3
f4-cd-p85.test --type=php --php=8.5
f4-cd-html.test --type=html
f4-cd-ssl.test --type=html --ssl=self
X
