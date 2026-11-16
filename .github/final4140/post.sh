#!/bin/bash
# Post-upgrade checks: auth matrix (global on/off), whitelist matrix, content, PHP per container, HTTP on every site. Usage: post.sh <label> <global:0|1> <baseline-content> [whitelist]
. "$(dirname "$0")/lib.sh"; L=$1; G=$2; BASE=$3; cd /tmp
m() { chk "$L: $1 ${2:--}" "$3" "$(code "$1" "$2")"; }
w() { sleep 3; }
if [ "$G" = 1 ]; then
  m f4-ms.test "" 401; m f4-ms.test u1:p1 200; m a.f4-ms.test "" 401; m a.f4-ms.test u1:p1 '200|302'; m a.f4-ms.test u3:p3 401; m x.y.f4-ms.test "" 401
  m shop.f4-ms.test "" 401; m shop.f4-ms.test g:g 200; m shop.f4-ms.test u1:p1 401
  m f4-php.test "" 401; m f4-php.test u3:p3 200; m f4-alias.test "" 401; m f4-alias.test u3:p3 200; m foo.f4-wild.test "" 401; m foo.f4-wild.test u3:p3 200
  m f4-pdb.test "" 401; m f4-pdb.test u4:p4 200; m f4-html.test "" 401; m f4-html.test g:g 200; m f4-wp.test "" 401; m f4-wp.test g:g 200
else
  m f4-ms.test "" 401; m f4-ms.test u1:p1 200; m a.f4-ms.test "" 401; m a.f4-ms.test u1:p1 '200|302'; m a.f4-ms.test u3:p3 401; m x.y.f4-ms.test "" 401
  m shop.f4-ms.test "" 200; m shop.f4-ms.test u1:p1 200
  m f4-php.test "" 401; m f4-php.test u3:p3 200; m f4-alias.test "" 401; m f4-alias.test u3:p3 200; m foo.f4-wild.test "" 401; m foo.f4-wild.test u3:p3 200
  m f4-pdb.test "" 401; m f4-pdb.test u4:p4 200; m f4-html.test "" 200; m f4-wp.test "" 200
fi
if [ "${4:-}" = whitelist ]; then
  info "$L: runner IP $IP, frontend subnet $(db "select value from options where key='frontend_subnet_ip'")"
  ee auth update f4-ms.test --ip=$IP >/dev/null 2>&1; chk "$L: auth update f4-ms.test --ip (adds)" 0 "$?"; w
  for h in f4-ms.test a.f4-ms.test x.y.f4-ms.test; do m $h "" '200|301|302'; done; m shop.f4-ms.test "" 200; m f4-php.test "" 401
  for f in f4-ms.test_acl _wildcard.f4-ms.test_acl; do chk "$L: $f allows $IP and keeps 198.51.100.7" 2 "$(grep -cE "allow ($IP|198\.51\.100\.7);" $P/vhost.d/$f)"; done
  ee auth delete f4-ms.test --ip=$IP >/dev/null 2>&1; chk "$L: auth delete f4-ms.test --ip" 0 "$?"; w
  for h in f4-ms.test a.f4-ms.test x.y.f4-ms.test; do m $h "" 401; done
  ee auth update f4-php.test --ip=$IP >/dev/null 2>&1; chk "$L: auth update f4-php.test --ip (adds)" 0 "$?"; w
  for h in f4-php.test f4-alias.test foo.f4-wild.test; do m $h "" '200|301|302'; done; m f4-ms.test "" 401
  ee auth delete f4-php.test --ip=$IP >/dev/null 2>&1; w
  for h in f4-php.test f4-alias.test foo.f4-wild.test; do m $h "" 401; done
  ee auth update global --ip=$IP >/dev/null 2>&1; chk "$L: auth update global --ip (adds)" 0 "$?"; w
  for h in f4-ms.test a.f4-ms.test f4-php.test f4-alias.test foo.f4-wild.test f4-pdb.test; do m $h "" '200|301|302'; done
  ee auth delete global --ip=$IP >/dev/null 2>&1; chk "$L: auth delete global --ip" 0 "$?"; w
  for h in f4-ms.test a.f4-ms.test f4-php.test foo.f4-wild.test; do m $h "" 401; done
  chk "$L: global whitelist keeps 192.0.2.10" 1 "$(grep -c 'allow 192.0.2.10;' $P/vhost.d/default_acl)"
  docker exec services_global-nginx-proxy_1 nginx -t >/dev/null 2>&1; chk "$L: nginx -t" 0 "$?"
fi
bash $F/content.sh /tmp/f4-content-now.txt; cp /tmp/f4-content-now.txt "$OUTDIR/content-$L.txt"
if diff "$BASE" /tmp/f4-content-now.txt > /tmp/f4-content.diff; then chk "$L: content checksums = old-version baseline" same same; else chk "$L: content checksums = old-version baseline" same "DIFF $(tr '\n' ' ' < /tmp/f4-content.diff | head -c 400)"; fi
# Image = the img-versions.json tag of the site's php image; PHP version = the baseline one when the tag is unchanged, else PHP_EXPECT (e.g. "8.3=8.3.35") or any X.Y.z.
declare -A PE; for kv in ${PHP_EXPECT:-}; do PE[${kv%%=*}]=${kv#*=}; done
for s in $PHPSITES; do c=$(cname $s)-php-1
  v=$(docker exec $c php -r 'echo PHP_VERSION;' 2>/dev/null); img=$(docker inspect -f '{{.Config.Image}}' $c 2>/dev/null)
  read -r _ bimg bv < <(grep "^$c " "$OUTDIR/baseline/php-versions.txt")
  repo=${bimg%%:*}; mm=${repo#easyengine/php}
  tag=$(jq -r --arg r "$repo" '.[$r] // "none"' "$IMG_JSON"); otag=$(jq -r --arg r "$repo" '.[$r] // "none"' "$IMG_OLD_JSON")
  if [ "$tag" = "$otag" ]; then ev=$bv; else ev=${PE[$mm]:-${mm//./\\.}\\.[0-9]+}; fi
  chk "$L: $s PHP version + image" "$ev $repo:$tag" "$v $img"; done
# f4-ssl.test redirects HTTP to HTTPS; it is checked over HTTPS below.
for s in $ALL; do [ $s = f4-ssl.test ] && continue; chk "$L: $s /f4-marker.txt via 127.0.0.1" 200 "$(lcode $s /f4-marker.txt)"; done
chk "$L: f4-ssl.test http redirects to https" 301 "$(lcode f4-ssl.test /f4-marker.txt)"
for s in $PHPSITES $HTML; do [ $s = f4-ssl.test ] && continue; chk "$L: $s / via 127.0.0.1" 200 "$(lcode $s /)"; done
chk "$L: f4-ssl.test https" 200 "$(curl -sk -m 20 -o /dev/null -w '%{http_code}' --resolve f4-ssl.test:443:127.0.0.1 https://f4-ssl.test/)"
chk "$L: pdb page reads the DB" "f4-one f4-two " "$(curl -s -m 20 --resolve f4-pdb.test:80:127.0.0.1 http://f4-pdb.test/f4-db.php)"
db "select site_url,command,schedule,user from cron order by 1,2" > /tmp/f4-cron-now.txt; cp /tmp/f4-cron-now.txt "$OUTDIR/cron-rows-$L.txt"
chk "$L: cron rows = old-version baseline ($(wc -l < /tmp/f4-cron-now.txt) rows)" same "$(cmp -s "$OUTDIR/baseline/state/cron-rows.txt" /tmp/f4-cron-now.txt && echo same || echo DIFF)"
info "$L: f4-wp.test cron rows: $(grep '^f4-wp.test|' /tmp/f4-cron-now.txt | tr '\n' ';')"
chk "$L: admin-tools + mailhog on f4-ms.test" '1\|1' "$(db "select admin_tools, mailhog_enabled from sites where site_url='f4-ms.test'")"
