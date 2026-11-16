#!/bin/bash
# Every 0.5 s: public-IP probes (sibling, subsite, aliases, main hosts, with and without credentials) plus 127.0.0.1 availability of every site. Usage: probe.sh <out>
. "$(dirname "$0")/lib.sh"; O=$1; T=$(mktemp -d)
PUB="shop.f4-ms.test a.f4-ms.test x.y.f4-ms.test f4-alias.test foo.f4-wild.test f4-ms.test f4-php.test f4-html.test"
while [ ! -e /tmp/f4-stop-probe ]; do
  t=$(ts); line="$t"
  for h in $PUB; do curl -s -m 8 -o /dev/null -w "%{http_code}/%{time_total}" --resolve $h:80:$IP http://$h/ > $T/p_$h & done
  curl -s -m 8 -o /dev/null -w "%{http_code}/%{time_total}" -u u1:p1 --resolve shop.f4-ms.test:80:$IP http://shop.f4-ms.test/ > $T/shopu1 &
  curl -s -m 8 -o /dev/null -w "%{http_code}/%{time_total}" -u g:g --resolve shop.f4-ms.test:80:$IP http://shop.f4-ms.test/ > $T/shopg &
  curl -s -m 8 -o /dev/null -w "%{http_code}/%{time_total}" -u u1:p1 --resolve a.f4-ms.test:80:$IP http://a.f4-ms.test/ > $T/au1 &
  for h in $ALL; do curl -s -m 8 -o /dev/null -w "%{http_code}/%{time_total}" --resolve $h:80:127.0.0.1 http://$h/ > $T/l_$h & done
  wait
  for h in $PUB; do line="$line p:$h=$(cat $T/p_$h)"; done
  line="$line shopu1=$(cat $T/shopu1) shopg=$(cat $T/shopg) au1=$(cat $T/au1)"
  for h in $ALL; do line="$line l:$h=$(cat $T/l_$h)"; done
  echo "$line" >> $O; sleep 0.5
done
