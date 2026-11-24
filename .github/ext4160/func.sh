#!/bin/bash
# Functional checks: WordPress login on every WP site (and the network admin on the multisite), redis object + page cache, a PHP session round trip,
# the --local-db site (MIG-7 KNOWN), admin-tools + mailhog, New Relic on the key site, WP-CLI. Usage: func.sh <label> <dir>
. "$(dirname "$0")/lib.sh"; L=$1; D=$2; mkdir -p $D; cd /tmp
one() { tr -d '\r' | tail -1; }
for s in $WPS; do wplogin $L $s $D; done
for s in $MUD; do c=$(curl -s -m 30 -c $D/login-$s.jar -b $D/login-$s.jar -o $D/net-$s.html -w '%{http_code}' --resolve "$s:80:127.0.0.1" "http://$s/wp-admin/network/")
  chk "$L: $s /wp-admin/network/ with the login cookies HTTP" 200 "$c"
  chk "$L: $s network admin dashboard" yes "$(grep -q '<title>Dashboard.*Network Admin' $D/net-$s.html && echo yes || echo no)"; done
chk "$L: $MUD subsite /sub1/ is the subsite" yes "$(hbody $MUD /sub1/ | grep -q 'u6sub1' && echo yes || echo no)"
chk "$L: $PHPA alias serves $PHPS" yes "$(hbody $PHPA / | grep -q "ok-$PHPS" && echo yes || echo no)"
chk "$L: $HTMLA alias serves $HTML" yes "$(hbody $HTMLA / | grep -q "ok-$HTML" && echo yes || echo no)"
objcache $L $W84
pagecache $L $W84
sess_rt $L $PHPS $D
body=$(hbody $LDB /)
chk "$L: $LDB home has no DB connection error" 0 "$(grep -c 'Error establishing a database connection' <<< "$body")"
chk "$L: $LDB marker post" 1 "$(wpx $LDB 'post list --post_type=post --field=post_title' 2>&1 | grep -c '^u6-ldb-marker$')"
DBC=$(cname $LDB)-db-1; docker logs -t $DBC > $D/ldb-db.log 2>&1
info "$L: $DBC id $(docker inspect -f '{{.Id}} {{.State.StartedAt}} {{.Config.Image}}' $DBC 2>&1 | cut -c1-120)"
known "$L: $DBC log has no [ERROR] lines (KNOWN MIG-7 / core#1964: support project starts a second db)" 0 "$(grep -c '\[ERROR\]' $D/ldb-db.log)"
grep '\[ERROR\]' $D/ldb-db.log | head -5 | cut -c1-250 | while read -r l; do info "$L: $DBC: $l"; done
for s in $WPS; do chk "$L: $s WP-CLI option get siteurl" "http://$s" "$(wpx $s 'option get siteurl' 2>&1 | one)"; done
# admin-tools + mailhog on $W84 (recreated on every upgrade path: php8.4 changes).
eqs "$L: $W84 admin_tools|mailhog_enabled in the DB" '1|1' "$(db "select admin_tools, mailhog_enabled from sites where site_url='$W84'")"
chk "$L: $W84 mailhog container running" running "$(docker inspect -f '{{.State.Status}}' $(cname $W84)-mailhog-1 2>&1)"
ac=$(hcode $W84 /ee-admin/); echo "$ac" > $D/admin-http.txt
chk "$L: $W84 /ee-admin/ answers (no 404/5xx/000)" '[1-4][0-9][0-9]' "$([ "$ac" = 404 ] && echo 404-notfound || echo "$ac")"
[ $L = after ] && [ -f $OUT/func-before/admin-http.txt ] && eqs "$L: $W84 /ee-admin/ HTTP code = before" "$(cat $OUT/func-before/admin-http.txt)" "$ac"
ee mailhog status $W84 < /dev/null > $D/mailhog-status.txt 2>&1; chk "$L: ee mailhog status $W84 rc" 0 "$?"; info "$L: mailhog status: $(tr '\n' ' ' < $D/mailhog-status.txt | cut -c1-200)"
# New Relic: the key site loads the agent with the key in newrelic.ini.
if [ $L = after ]; then
  chk "$L: $K84 conf.d/newrelic.ini" present "$([ -f "$(nr_ini $K84)" ] && echo present || echo absent)"
  eqs "$L: $K84 newrelic.ini license" "\"$NRKEY\"" "$(grep -E '^newrelic\.license = ' "$(nr_ini $K84)" 2>/dev/null | sed -E 's/^[^=]+= *//')"
  chk "$L: $K84 newrelic loaded (php -m, php-fpm -m)" 'cli=1 fpm=1' "$(nr_mods $K84)"
  eqs "$L: $K84 phpversion('newrelic') = NR_AGENT" "$NR_AGENT" "$(docker exec $(phpc $K84) php -r 'echo phpversion("newrelic");' 2>&1 | one)"
else info "$L: $K84 newrelic.ini $([ -f "$(nr_ini $K84)" ] && echo present || echo absent), license $(grep -E '^newrelic\.license = ' "$(nr_ini $K84)" 2>/dev/null | cut -c1-40), modules $(nr_mods $K84), phpversion('newrelic') $(docker exec $(phpc $K84) php -r 'echo phpversion("newrelic");' 2>&1 | one)"; fi
info "$L: $SW (8.4, no key) newrelic modules $(nr_mods $SW) (the php8.4 image config loads the agent without a key too)"
done_mark func-$L
exit 0
