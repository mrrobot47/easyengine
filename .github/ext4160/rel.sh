#!/bin/bash
# v4.16.0 release-specific checks (BRIEF-COMMON 1-7) with the release as /usr/local/bin/ee: on the upgraded sites (fresh path: sites created with the release)
# plus sites created here (PCX; N86 on the 4.14.0 path). Runs after checks.sh and func.sh after: it switches PHP versions, provokes entrypoint warnings and adds sites.
# Usage: rel.sh <section>, in this order: cronstart compat img26 img22 nrd sc61 cronend.
. "$(dirname "$0")/lib.sh"; P=$1; D=$OUT/rel/$P; mkdir -p $D; cd /tmp
one() { tr -d '\r' | sed '/^$/d' | tail -1; }
ND=services_global-newrelic-daemon_1; CR=services_global-cron_1; SC=easyengine/compat-scanner
CF=/var/www/htdocs/u6-cron-fired.txt; CFH=$SITES_DIR/$W81/app/htdocs/u6-cron-fired.txt
S86=$W86; [ -n "$HAS86" ] || S86=$N86
cstate() { docker inspect -f '{{.State.Status}} restarts={{.RestartCount}}' $(phpc $1) 2>&1; }
fpm_master() { docker top $(phpc $1) -o pid,args 2>/dev/null | grep -c 'php-fpm: master process'; }
iniv() { grep -E "^newrelic\.$2 = " "$(nr_ini $1)" 2>/dev/null | sed -E 's/^[^=]+= *//'; }
dlog_since() { docker logs --since "$2" $(phpc $1) 2>&1; }
# pc <label> <args...>: ee site php-compat with stdout and stderr apart (json is parsed from stdout); sets RC.
pc() { local l=$1; shift; ee site php-compat "$@" < /dev/null > $D/$l.out 2> $D/$l.err; RC=$?; echo "rc=$RC" > $D/$l.rc; }
js() { jq -r "$1" < $D/$2.out 2>&1 | tail -1; }
php_ok() { local s=$1 v=$2 L=$3 t img pv; t=$(tag easyengine/php$v)
  chk "$L: $s sites.php_version" "$(re $v)" "$(db "select php_version from sites where site_url='$s'")"
  chk "$L: $s compose php image" "easyengine/php$(re $v):$(re $t)" "$(grep -oE 'easyengine/php[0-9.]*:v[0-9.]+' $SITES_DIR/$s/docker-compose.yml | sort -u | tr '\n' ' ' | sed 's/ $//')"
  img=$(docker inspect -f '{{.Config.Image}}' $(phpc $s) 2>&1); pv=$(docker exec $(phpc $s) php -r 'echo PHP_VERSION;' 2>&1 | one)
  chk "$L: $s php container image + PHP" "easyengine/php$(re $v):$(re $t) $(pe $v)" "$img $pv"
  chk "$L: $s php container" 'running restarts=0' "$(cstate $s)"
  [ -n "$(dg php$v)" ] && [ "$t" = v4.16.0 ] && chk "$L: $s php$v:v4.16.0 runs the GO digest" yes "$(digest_ok $(phpc $s) php$v)"
  chk "$L: $s / HTTP" 200 "$(hwait $s)"; }

case $P in
cronstart)
  run_ee create-fire $D cron create $W81 --command="date -u >> $CF" --schedule='@every 1m'; chk "cron: ee cron create $W81 @every 1m rc" 0 "$RC"
  id=$(db "select id from cron where site_url='$W81' and command like '%u6-cron-fired%'"); chk "cron: @every 1m job row" '[0-9]+' "$id"
  echo "$id" > $OUT/rel/cron-fire-id.txt; date +%s > $OUT/rel/cron-fire-start.txt
  info "cron: config.ini lines for the job: $(grep -F u6-cron-fired /opt/easyengine/services/cron/conf/config.ini | tr '\n' ' ')" ;;

compat)
  chk "php-compat: compat-scanner images before the first scan (never pulled by install or upgrade)" 0 "$(docker images -q $SC | wc -l)"
  chk "php-compat: options row for compat-scanner before the first scan" 0 "$(db "select count(*) from options where key='$SC'")"
  if [ -z "$HAS86" ]; then ee site create $N86 --type=wp --php=8.6 --title=u6new86 $W < /dev/null > $D/create-$N86.out 2>&1; chk "php-compat: ee site create $N86 --type=wp --php=8.6 rc" 0 "$?"; fi
  # Fixtures: a legacy plugin (wp scope is wp-content) and a legacy file in the php site's htdocs; 2 known errors each.
  for s in $W84 $S86; do d=$SITES_DIR/$s/app/htdocs/wp-content/plugins/u6-legacy; mkdir -p $d
    printf '<?php\n/*\nPlugin Name: U6 Legacy\nVersion: 1.0\n*/\n$f = create_function( %s, %s );\neach( $a );\n' "''" "'return 1;'" > $d/u6-legacy.php; chown -R 33:33 $d; chmod 755 $d; chmod 644 $d/u6-legacy.php; done
  d=$SITES_DIR/$PHPS/app/htdocs/legacy; mkdir -p $d; printf '<?php\n$f = create_function( %s, %s );\neach( $a );\n' "''" "'return 1;'" > $d/legacy.php; chown -R 33:33 $d; chmod 755 $d; chmod 644 $d/legacy.php
  # 1. First scan (pulls the scanner on first use), json.
  pc wp84-json $W84 --php=8.4 --format=json; chk "php-compat: $W84 --php=8.4 json rc" 0 "$RC"
  eqs "php-compat: $W84 json status/site/target/safe" "ok $W84 8.4 false" "$(js '"\(.status) \(.site) \(.target) \(.safe_to_upgrade)"' wp84-json)"
  chk "php-compat: $W84 json errors (fixture has 2)" '[2-9]|[1-9][0-9]+' "$(js .errors wp84-json)"
  eqs "php-compat: $W84 json tool.image" "$SC:v4.16.0" "$(js .tool.image wp84-json)"
  chk "php-compat: scanner image after the first scan has the GO digest" yes "$(img_digests $SC:v4.16.0 | tr ' ' '\n' | grep -qx "$SC@$(dg compat-scanner)" && echo yes || echo "no[$(img_digests $SC:v4.16.0)]")"
  info "php-compat: local scanner images: $(docker images --format '{{.Repository}}:{{.Tag}} {{.ID}}' $SC | tr '\n' ' ')"
  pc wp84-table85 $W84 --php=8.5; chk "php-compat: $W84 --php=8.5 table rc" 0 "$RC"
  has "php-compat: $W84 table verdict line" "Not safe to upgrade $W84 to PHP 8.5" "$(head -3 $D/wp84-table85.out)"
  has "php-compat: $W84 table names the fixture plugin" "U6 Legacy" "$(cat $D/wp84-table85.out)"
  pc php-json85 $PHPS --php=8.5 --format=json; chk "php-compat: $PHPS --php=8.5 json rc" 0 "$RC"
  eqs "php-compat: $PHPS json status/site/target/safe" "ok $PHPS 8.5 false" "$(js '"\(.status) \(.site) \(.target) \(.safe_to_upgrade)"' php-json85)"
  pc php-table84 $PHPS --php=8.4; chk "php-compat: $PHPS --php=8.4 table rc" 0 "$RC"
  has "php-compat: $PHPS table verdict line" "Not safe to upgrade $PHPS to PHP 8.4" "$(head -3 $D/php-table84.out)"
  # 3. A PHP 8.6 site, scanned for 8.6; --php=8.7 refused before any docker call.
  php_ok $S86 8.6 "php-compat"
  pc s86-json86 $S86 --php=8.6 --format=json; chk "php-compat: $S86 --php=8.6 json rc" 0 "$RC"
  eqs "php-compat: $S86 json status/site/target/safe" "ok $S86 8.6 false" "$(js '"\(.status) \(.site) \(.target) \(.safe_to_upgrade)"' s86-json86)"
  pc s86-87 $S86 --php=8.7 --format=json; chk "php-compat: $S86 --php=8.7 refused rc" 1 "$RC"
  has "php-compat: --php=8.7 message" "Invalid value specified for 'php'" "$(cat $D/s86-87.out $D/s86-87.err)"
  chk "php-compat: --php=8.7 printed no document" 0 "$(grep -c '"v":1' $D/s86-87.out)"
  # 2. --output: accepted in a root-only dir and in sticky /tmp (file 0600 root, report_bytes = size); refused in a dir writable by others,
  # a dir owned by another user and a symlink to one (rc 1, nothing written).
  install -d -m 0755 -o root -g root /root/u6-pc; install -d -m 0777 -o root -g root /var/tmp/u6-pc-ww; chmod 0777 /var/tmp/u6-pc-ww
  install -d -m 0755 -o 1000 -g 1000 /var/tmp/u6-pc-bob; ln -sfn /var/tmp/u6-pc-bob /var/tmp/u6-pc-link
  info "php-compat: output dirs: $(stat -c '%A %U %n' /root/u6-pc /tmp /var/tmp /var/tmp/u6-pc-ww /var/tmp/u6-pc-bob | tr '\n' ';')"
  for o in /root/u6-pc/r1.json /tmp/u6-pc-r2.json; do l=ok-$(basename $o .json); rm -f $o
    pc $l $PHPS --php=8.4 --format=json --output=$o; chk "php-compat: --output=$o accepted rc" 0 "$RC"
    chk "php-compat: $o written 0600 root:root" '600 root:root' "$(stat -c '%a %U:%G' $o 2>&1)"
    eqs "php-compat: $o summary report/report_bytes = path/size" "$o $(stat -c %s $o 2>/dev/null)" "$(js '"\(.report) \(.report_bytes)"' $l)"
    eqs "php-compat: $o is the scan report (status site target)" "ok $PHPS 8.4" "$(jq -r '"\(.status) \(.site) \(.target)"' $o 2>&1)"
    cp $o $D/$l.report.json 2>/dev/null; rm -f $o; done
  for o in /var/tmp/u6-pc-ww/r.json /var/tmp/u6-pc-bob/r.json /var/tmp/u6-pc-link/r.json; do l=refused-$(basename $(dirname $o))
    pc $l $PHPS --php=8.4 --format=json --output=$o; chk "php-compat: --output=$o refused rc" 1 "$RC"
    has "php-compat: --output=$o refusal message" "--output must be in a directory only root can change: $(readlink -f $(dirname $o))" "$(cat $D/$l.out $D/$l.err)"
    chk "php-compat: --output=$o nothing written" absent "$([ -e $o ] && echo present || echo absent)"; done
  # 1. --cancel: a scan of the 5,000-file php site stopped from a second process; then with nothing running.
  ee site create $PCX --type=php --php=8.4 < /dev/null > $D/create-$PCX.out 2>&1; chk "php-compat: ee site create $PCX --type=php rc" 0 "$?"
  H=$SITES_DIR/$PCX/app/htdocs; mkdir -p $H/bulk $H/legacy
  body=$(for i in $(seq 1 120); do echo "\$v$i = strtoupper( 'line $i of a generated fixture file' ) . PHP_EOL;"; done)
  for i in $(seq 1 5000); do printf '<?php\n// generated %d\n%s\n' $i "$body" > $H/bulk/f$i.php; done
  printf '<?php\n$f = create_function( %s, %s );\neach( $a );\n' "''" "'return 1;'" > $H/legacy/legacy.php; chown -R 33:33 $H/bulk $H/legacy; chmod -R a+rX $H/bulk $H/legacy
  info "php-compat: $PCX fixture files $(find $H -name '*.php' | wc -l)"
  N=ee-php-compat-$PCX
  race() { local t=$1 sf=$2 cf=$3 o=/root/u6-pc/cancel-$1.json A i src crc
    rm -f $o; ee site php-compat $PCX --php=8.4 --format=$sf --output=$o < /dev/null > $D/$t-scan.out 2> $D/$t-scan.err & A=$!
    for i in $(seq 1 600); do [ "$(docker inspect -f '{{.State.Running}}' $N 2>/dev/null)" = true ] && break; sleep 0.2; done
    info "php-compat cancel $t: scan container running after ~$((i/5)) s"; sleep 3
    ee site php-compat $PCX --cancel --format=$cf < /dev/null > $D/$t-cancel.out 2> $D/$t-cancel.err; crc=$?
    wait $A; src=$?
    echo "$src $crc $([ -e $o ] && echo present || echo absent) $(docker inspect $N > /dev/null 2>&1 && echo container-left || echo container-gone)" > $D/$t-state.txt; }
  for t in json table; do race c-$t $t $t
    if grep -q '"status":"ok"\|safe to upgrade' $D/c-$t-scan.out; then info "php-compat cancel c-$t: the scan ended before the cancel (timing); retrying once"; race c-$t $t $t; fi
    read -r src crc of cs < $D/c-$t-state.txt
    chk "php-compat cancel ($t): scan rc / cancel rc" '0 0' "$src $crc"
    if [ $t = json ]; then
      eqs "php-compat cancel (json): cancel document" "{\"v\":1,\"status\":\"cancelled\",\"cancel\":true,\"site\":\"$PCX\"}" "$(one < $D/c-$t-cancel.out)"
      eqs "php-compat cancel (json): scan document" "{\"v\":1,\"status\":\"cancelled\",\"site\":\"$PCX\",\"target\":\"8.4\",\"safe_to_upgrade\":null}" "$(one < $D/c-$t-scan.out)"
    else
      eqs "php-compat cancel (table): cancel line" "Cancelled the check of $PCX." "$(one < $D/c-$t-cancel.out)"
      eqs "php-compat cancel (table): scan line" "The check of $PCX for PHP 8.4 was cancelled." "$(one < $D/c-$t-scan.out)"
    fi
    eqs "php-compat cancel ($t): --output file / scan container after" "absent container-gone" "$of $cs"
    chk "php-compat cancel ($t): cancel request file left" absent "$([ -e /opt/easyengine/tmp/php-compat/.cancel-$PCX ] && echo present || echo absent)"; done
  pc nr-json $PCX --cancel --format=json; chk "php-compat: --cancel with nothing running (json) rc" 0 "$RC"
  eqs "php-compat: --cancel with nothing running (json)" "{\"v\":1,\"status\":\"not_running\",\"cancel\":true,\"site\":\"$PCX\"}" "$(one < $D/nr-json.out)"
  pc nr-table $PCX --cancel; chk "php-compat: --cancel with nothing running (table) rc" 0 "$RC"
  eqs "php-compat: --cancel with nothing running (table)" "No check of $PCX is running." "$(one < $D/nr-table.out)"
  chk "php-compat: options row for compat-scanner after the scans" 0 "$(db "select count(*) from options where key='$SC'")"
  chk "php-compat: scan containers left" "" "$(docker ps -a --format '{{.Names}}' | grep '^ee-php-compat-' | tr '\n' ' ')"
  info "php-compat: /opt/easyengine/tmp after: $(find /opt/easyengine/tmp -printf '%M %u %p\n' 2>/dev/null | tr '\n' ';' | cut -c1-600)"
  grep -h 'php-compat' /opt/easyengine/logs/ee.log | tail -5 | cut -c1-200 | while read -r l; do info "php-compat: ee.log: $l"; done ;;

img26)
  # AVIF encode: fixed on php8.1, 8.2 and 8.4 (libheif-plugin-aomenc); 8.3 and 8.5 had it already (control).
  for s in $W81 $W82 $W83 $W84 $W85; do c=$(phpc $s); mm=$(docker inspect -f '{{.Config.Image}}' $c | sed -nE 's#^easyengine/php([0-9.]+):.*#\1#p'); L="img26: $s (php$mm)"
    eqs "$L identify -list format AVIF mode" 'rw+' "$(docker exec $c identify -list format 2>&1 | awk '$1 ~ /^AVIF\*?$/ {print $3; exit}')"
    r=$(docker exec --user www-data $c sh -c 'cd /tmp && rm -f u6-in.png u6-out.avif && convert -size 320x240 gradient:red-blue u6-in.png && convert u6-in.png u6-out.avif && identify -format "%m %wx%h" u6-out.avif' 2>&1 | tr '\n' ' ' | sed 's/ $//')
    chk "$L convert in.png out.avif, identify" '(AVIF|HEIC) 320x240' "$r"
    docker exec --user www-data $c sh -c 'rm -f /var/www/htdocs/u6-up.avif; convert -size 1200x800 gradient:red-blue /var/www/htdocs/u6-up.avif' > $D/mk-$s.txt 2>&1
    eqs "$L WordPress wp_image_editor_supports(image/avif)" true "$(wpx $s "eval 'echo var_export(wp_image_editor_supports([\"mime_type\" => \"image/avif\"]), true);'" 2>&1 | one)"
    id=$(wpx $s "media import /var/www/htdocs/u6-up.avif --title=u6-avif --porcelain" 2>&1 | one); chk "$L wp media import u6-up.avif (attachment ID)" '[0-9]+' "$id"
    m=$(wpx $s "eval '\$m = wp_get_attachment_metadata(${id:-0}); \$d = dirname(get_attached_file(${id:-0})); \$n = 0; \$a = 0; foreach (\$m[\"sizes\"] as \$x) { if (file_exists(\$d . \"/\" . \$x[\"file\"])) { \$n++; } if (\$x[\"mime-type\"] === \"image/avif\") { \$a++; } } echo count(\$m[\"sizes\"]), \" \", \$a, \" \", \$n;'" 2>&1 | one)
    read -r cnt na ne <<< "$m"
    chk "$L AVIF upload: >= 1 sub-size, every sub-size image/avif and on disk" yes "$([[ $cnt =~ ^[0-9]+$ ]] && [ "$cnt" -ge 1 ] && [ "$cnt" = "$na" ] && [ "$cnt" = "$ne" ] && echo yes || echo "no[$m]")"
    info "$L AVIF sub-sizes: $(wpx $s "eval 'echo json_encode(array_map(function (\$x) { return \$x[\"width\"] . \"x\" . \$x[\"height\"] . \" \" . \$x[\"mime-type\"]; }, wp_get_attachment_metadata(${id:-0})[\"sizes\"]));'" 2>&1 | one)"
  done ;;

img22)
  # (a) 8.2/8.3: key set, the site's newrelic.ini removed, php restarted: the entrypoint copies /data/newrelic.ini in and the agent loads.
  # (b) conf.d root-owned (not writable by the container): b1 with the ini present, b2 without it: a warning, php-fpm still starts. Then restored.
  for s in $W82 $W83; do mm=$(docker inspect -f '{{.Config.Image}}' $(phpc $s) | sed -nE 's#^easyengine/php([0-9.]+):.*#\1#p'); L="img22 php$mm $s"; CD=$SITES_DIR/$s/config/php/php/conf.d
    info "$L: .env: $(setkey $s $NRKEY)"
    run_ee enable-$s $D site enable $s --force; chk "$L: ee site enable --force rc (applies the key)" 0 "$RC"
    rm -f "$(nr_ini $s)"; chk "$L: (a) newrelic.ini removed" absent "$([ -f "$(nr_ini $s)" ] && echo present || echo absent)"
    t0=$(date -u +%FT%T); (cd $SITES_DIR/$s && docker-compose restart php) > $D/restart-a-$s.txt 2>&1; sleep 4
    chk "$L: (a) php container after restart" 'running restarts=0' "$(cstate $s)"
    chk "$L: (a) php-fpm master" 1 "$(fpm_master $s)"
    chk "$L: (a) newrelic.ini copied in (owner)" www-data "$(stat -c %U "$(nr_ini $s)" 2>&1)"
    eqs "$L: (a) newrelic.ini license" "\"$NRKEY\"" "$(iniv $s license)"
    chk "$L: (a) newrelic loaded (php -m, php-fpm -m)" 'cli=1 fpm=1' "$(nr_mods $s)"
    dlog_since $s $t0 > $D/dlog-a-$s.txt; chk "$L: (a) entrypoint warnings in the log since the restart" 0 "$(grep -c 'docker-entrypoint: could not' $D/dlog-a-$s.txt)"
    chk "$L: (a) / HTTP" 200 "$(hwait $s)"
    chown -R root:root $CD; chmod 0755 $CD
    t0=$(date -u +%FT%T); (cd $SITES_DIR/$s && docker-compose restart php) > $D/restart-b1-$s.txt 2>&1; sleep 4
    dlog_since $s $t0 > $D/dlog-b1-$s.txt
    has "$L: (b1) conf.d root-owned, ini present: warning" "docker-entrypoint: could not write the New Relic license" "$(cat $D/dlog-b1-$s.txt)"
    chk "$L: (b1) php container" 'running restarts=0' "$(cstate $s)"; chk "$L: (b1) php-fpm master" 1 "$(fpm_master $s)"; chk "$L: (b1) / HTTP" 200 "$(hwait $s)"
    rm -f "$(nr_ini $s)"
    t0=$(date -u +%FT%T); (cd $SITES_DIR/$s && docker-compose restart php) > $D/restart-b2-$s.txt 2>&1; sleep 4
    dlog_since $s $t0 > $D/dlog-b2-$s.txt
    has "$L: (b2) conf.d root-owned, no ini: warning" "New Relic stays off" "$(cat $D/dlog-b2-$s.txt)"
    chk "$L: (b2) php container" 'running restarts=0' "$(cstate $s)"; chk "$L: (b2) php-fpm master" 1 "$(fpm_master $s)"; chk "$L: (b2) / HTTP" 200 "$(hwait $s)"
    chk "$L: (b2) newrelic not loaded" 'cli=0 fpm=0' "$(nr_mods $s)"
    run_ee restore-$s $D site enable $s --force; chk "$L: restore: ee site enable --force rc" 0 "$RC"
    (cd $SITES_DIR/$s && docker-compose restart php) > $D/restart-r-$s.txt 2>&1; sleep 4
    chk "$L: restore: conf.d owner" www-data "$(stat -c %U $CD)"; chk "$L: restore: newrelic loaded" 'cli=1 fpm=1' "$(nr_mods $s)"; chk "$L: restore: / HTTP" 200 "$(hwait $s)"
  done
  # 8.4: a site with a key moved with site update --php=8.4 (php84.zip has no newrelic.ini): php-fpm starts, the ini is copied in, the agent loads; again after a restart.
  s=$W85; L="img22 8.4-switch $s"
  info "$L: .env: $(setkey $s $NRKEY)"
  run_ee enable-$s $D site enable $s --force; chk "$L: ee site enable --force rc" 0 "$RC"; info "$L: on 8.5 with the key: $(nr_mods $s)"
  t0=$(date -u +%FT%T); run_ee update84 $D site update $s --php=8.4; chk "$L: ee site update --php=8.4 rc" 0 "$RC"
  php_ok $s 8.4 "$L"
  chk "$L: php-fpm master" 1 "$(fpm_master $s)"
  chk "$L: newrelic.ini copied in (owner)" www-data "$(stat -c %U "$(nr_ini $s)" 2>&1)"
  eqs "$L: newrelic.ini license" "\"$NRKEY\"" "$(iniv $s license)"
  chk "$L: newrelic.ini appname" "\"$(re $s)[^\"]*\"" "$(iniv $s appname)"
  chk "$L: newrelic loaded (php -m, php-fpm -m)" 'cli=1 fpm=1' "$(nr_mods $s)"
  eqs "$L: phpversion('newrelic') = NR_AGENT" "$NR_AGENT" "$(docker exec $(phpc $s) php -r 'echo phpversion("newrelic");' 2>&1 | one)"
  dlog_since $s $t0 > $D/dlog-84-$s.txt; chk "$L: entrypoint warnings / load errors in the log" 0 "$(grep -cE 'docker-entrypoint: could not|Unable to load dynamic library|sed: can' $D/dlog-84-$s.txt)"
  (cd $SITES_DIR/$s && docker-compose restart php) > $D/restart-84-$s.txt 2>&1; sleep 4
  chk "$L: second start: php container" 'running restarts=0' "$(cstate $s)"; chk "$L: second start: newrelic loaded" 'cli=1 fpm=1' "$(nr_mods $s)"; chk "$L: second start: / HTTP" 200 "$(hwait $s)" ;;

nrd)
  chk "nrd: $ND running" running "$(docker inspect -f '{{.State.Status}}' $ND 2>&1)"
  eqs "nrd: $ND image" "easyengine/newrelic-daemon:v4.16.0" "$(docker inspect -f '{{.Config.Image}}' $ND 2>&1)"
  chk "nrd: $ND runs the GO digest" yes "$(digest_ok $ND newrelic-daemon)"
  eqs "nrd: $ND Alpine release" 3.24.4 "$(docker exec $ND cat /etc/alpine-release 2>&1 | one)"
  chk "nrd: newrelic-daemon process" '[1-9][0-9]*' "$(docker top $ND -o pid,args 2>/dev/null | grep -c '[n]ewrelic-daemon')"
  for s in $K84 $W85 $W82 $W83; do l=$(nr_connect $s $D)
    chk "nrd: $s agent daemon connect succeeded (CLI request, key from newrelic.ini)" yes "$([ "$l" != none ] && echo yes || echo no)"; info "nrd: $s agent: $l"; done
  for i in 1 2 3 4 5; do grep -q 'invalid license' $D/nr-agent-*.log 2>/dev/null && break; sleep 5; nr_connect $K84 $D > /dev/null; done
  chk "nrd: the fake key is rejected (agent log 'invalid license')" '[1-9][0-9]*' "$(cat $D/nr-agent-*.log | grep -c 'invalid license')"
  grep -h 'invalid license' $D/nr-agent-*.log | head -2 | cut -c1-220 | while read -r x; do info "nrd: $x"; done
  docker logs $ND > $D/daemon.log 2>&1; info "nrd: daemon log tail: $(tail -5 $D/daemon.log | tr '\n' ' ' | cut -c1-500)" ;;

sc61)
  # >= 20 real switches (wp and php sites, to 8.6 and back): every one succeeds, none refused. Then a real holder of the config volume: refused, nothing changed.
  n=0; ok=0; ref=0
  sw() { local s=$1 v=$2 r; n=$((n+1)); L="sc61 #$n $s -> $v"
    ee --debug site update $s --php=$v < /dev/null > $D/sw-$n.out 2>&1; r=$?
    chk "$L: rc" 0 "$r"; [ $r = 0 ] && ok=$((ok+1))
    if grep -q 'still mounted by a running container' $D/sw-$n.out; then ref=$((ref+1)); fi
    php_ok $s $v "$L"
    if [ $s = $PHPS ]; then chk "$L: page" "ok-$PHPS $(pe $v)" "$(hbody $s / | one)"; else chk "$L: FPM probe" "fpm-fcgi $(pe $v) .*" "$(fpm $s)"; fi
    info "$L: docker ps volume listings non-empty / inspect calls in --debug: $(grep -c "filter 'volume=" $D/sw-$n.out) / $(grep -c 'docker inspect' $D/sw-$n.out)"; }
  for v in 8.6 8.4 8.1 8.6 8.2 8.3 8.5 8.6 8.3 8.4; do sw $SW $v; done
  for v in 8.5 8.6 8.1 8.4 8.2 8.6 8.3 8.5 8.6 8.4; do sw $PHPS $v; done
  chk "sc61: switches done" '(2[0-9]|[3-9][0-9])' "$n"
  eqs "sc61: switches with rc 0" "$n" "$ok"
  chk "sc61: refusals ('still mounted') over all switches" 0 "$ref"
  VOL=$(echo $PHPS | tr -d '.-')_config_php; # compose volume prefix drops dots and dashes (container names keep dashes)
  L="sc61 holder"; chk "$L: config volume $VOL exists" yes "$(docker volume inspect $VOL > /dev/null 2>&1 && echo yes || echo no)"
  hid=$(docker run -d --name u6-holder --entrypoint sleep -v $VOL:/x easyengine/php8.4:v4.16.0 infinity 2>&1); info "$L: holder $hid on $VOL"
  run_ee holder $D site update $PHPS --php=8.5; chk "$L: site update --php=8.5 refused rc" 1 "$RC"
  has "$L: refusal names the holder" "still mounted by a running container (${hid:0:12})" "$(cat $D/holder.out)"
  has "$L: refusal says nothing changed" "Nothing was changed." "$(cat $D/holder.out)"
  php_ok $PHPS 8.4 "$L (unchanged)"
  chk "$L: page still served on 8.4" "ok-$PHPS $(pe 8.4)" "$(hbody $PHPS / | one)"
  docker rm -f u6-holder > /dev/null 2>&1
  run_ee holder-gone $D site update $PHPS --php=8.5; chk "$L: after the holder is gone: site update --php=8.5 rc" 0 "$RC"
  php_ok $PHPS 8.5 "$L (after)"
  chk "$L: page on 8.5" "ok-$PHPS $(pe 8.5)" "$(hbody $PHPS / | one)" ;;

cronend)
  eqs "cron: $CR image" "easyengine/cron:v4.16.0" "$(docker inspect -f '{{.Config.Image}}' $CR 2>&1)"
  chk "cron: $CR runs the GO digest" yes "$(digest_ok $CR cron)"
  chk "cron: $CR running" running "$(docker inspect -f '{{.State.Status}}' $CR 2>&1)"
  ov=${OFELIA_VERSION#v}; vv=
  for m in 'ofelia --version' 'ofelia version' 'ofelia --help'; do o=$(docker exec $CR timeout 10 sh -c "$m" 2>&1 | head -5 | tr '\n' ' '); echo "$m: $o" >> $D/ofelia-version.txt
    [[ $o == *"$ov"* ]] && { vv="$m"; break; }; done
  [ -n "$vv" ] || { o=$(docker exec $CR sh -c 'grep -c "'"$ov"'" "$(command -v ofelia)"' 2>&1 | one); echo "binary grep: $o" >> $D/ofelia-version.txt; [[ $o =~ ^[1-9] ]] && vv='string in the ofelia binary'; }
  chk "cron: ofelia version $ov found" '.+' "$vv"; info "cron: ofelia version probes: $(tr '\n' ';' < $D/ofelia-version.txt | cut -c1-400)"
  id=$(cat $OUT/rel/cron-fire-id.txt 2>/dev/null); st=$(cat $OUT/rel/cron-fire-start.txt 2>/dev/null || date +%s)
  w=$(( st + 135 - $(date +%s) )); [ $w -gt 0 ] && { info "cron: waiting $w s for the @every 1m job"; sleep $w; }
  n0=$(wc -l < $CFH 2>/dev/null || echo 0)
  chk "cron: @every 1m job fired (lines in u6-cron-fired.txt, $(( $(date +%s) - st )) s after create)" '[1-9][0-9]*' "$n0"
  docker logs $CR > $D/cron.log 2>&1; info "cron: scheduler log lines naming the job: $(grep -c 'u6-cron-fired' $D/cron.log); last: $(grep 'u6-cron-fired' $D/cron.log | tail -1 | cut -c1-200)"
  run_ee runnow $D cron run-now ${id:-0}; chk "cron: ee cron run-now $id rc" 0 "$RC"
  chk "cron: run-now appended a line" yes "$([ "$(wc -l < $CFH 2>/dev/null || echo 0)" -gt "$n0" ] && echo yes || echo no)"
  # CRON-19: --user=0 is kept (create, run-now as uid 0, update without --user).
  run_ee c19 $D cron create $W81 --command='id -u' --schedule='@every 1h' --user=0; chk "cron: CRON-19 create --user=0 rc" 0 "$RC"
  id19=$(db "select id from cron where site_url='$W81' and command like '%id -u%'" | tail -1)
  eqs "cron: CRON-19 DB user" 0 "$(db "select user from cron where id='${id19:-0}'")"
  run_ee c19run $D cron run-now ${id19:-0}; chk "cron: CRON-19 run-now rc" 0 "$RC"; chk "cron: CRON-19 run-now ran as uid 0" 1 "$(grep -cx 0 $D/c19run.out)"
  run_ee c19up $D cron update ${id19:-0} --schedule='@every 2h'; chk "cron: CRON-19 update --schedule rc" 0 "$RC"
  eqs "cron: CRON-19 DB user after update" 0 "$(db "select user from cron where id='${id19:-0}'")"
  info "cron: list: $(ee cron list $W81 < /dev/null 2>&1 | tr -s ' \n' ' ' | cut -c1-400)"
  # CRON-21: an empty or blank command is refused (create and update), nothing changes.
  rows=$(db "select count(*) from cron"); cmd19=$(db "select command from cron where id='${id19:-0}'")
  run_ee c21a $D cron create $W81 --command='' --schedule='@every 1m'; chk "cron: CRON-21 create --command='' rc" 1 "$RC"; has "cron: CRON-21 create --command='' message" "The cron command cannot be empty." "$(cat $D/c21a.out)"
  run_ee c21b $D cron create $W81 --command='   ' --schedule='@every 1m'; chk "cron: CRON-21 create --command='   ' rc" 1 "$RC"
  run_ee c21c $D cron update ${id19:-0} --command=''; chk "cron: CRON-21 update --command='' rc" 1 "$RC"
  eqs "cron: CRON-21 rows / job command unchanged" "$rows $cmd19" "$(db "select count(*) from cron") $(db "select command from cron where id='${id19:-0}'")" ;;
*) echo "unknown section $P"; exit 1 ;;
esac
done_mark rel-$P
exit 0
