#!/bin/bash
# Sites on PHP 5.6-8.0 (and layout sites) across the upgrade. Usage: legacy.sh pre (old stable) | post (after the upgrade, release installed).
# Expected: php5.6-8.0 images and nginx keep their tags in 4.16.0, so these sites are not recreated and keep serving; php-compat scans them
# and targets 5.6-8.0; `site update --php=8.4` and back works; 7.1 has no image and is refused. Layout sites (8.4) are recreated on php8.4
# v4.16.0 and must keep serving from their public dir / release symlink / wp/ subdirectory.
. "$(dirname "$0")/lib.sh"; P=$1; D=$OUT/leg; mkdir -p $D; cd /tmp
f() { awk -F'\t' -v n="$1" -v k="$2" '$1==n{print $k}' "$3"; }
c() { local l=$1; shift; ee "$@" < /dev/null > $D/$l.out 2>&1; RC=$?; echo "rc=$RC" >> $D/$l.out; }
SC=easyengine/compat-scanner
pc() { local l=$1; shift; ee site php-compat "$@" < /dev/null > $D/$l.out 2> $D/$l.err; RC=$?; }
js() { jq -r "$1" < $D/$2.out 2>&1 | tail -1; }
LV() { for kv in $LEG_PHP; do [ "${kv%%:*}" = $1 ] && { echo ${kv#*:}; return; }; done; case $1 in $LW74) echo 7.4 ;; $LW80) echo 8.0 ;; *) echo 8.4 ;; esac; }
LEGV="$(for kv in $LEG_PHP; do echo -n "${kv%%:*} "; done)$LW74 $LW80"
LAY="$LPW $LPP $LPN $LCUR $LSUB"
body_ok() { local L=$1 s=$2 v=$3 b; b=$(hbody $s /)
  case $s in $LW74|$LW80|$LPW|$LCUR|$LSUB) has "$L: $s / is its WordPress" "u6$(cname $s | sed 's/^u6//')" "$b" ;;
             $LPP|$LPN) has "$L: $s / from its public dir on PHP $v" "ok-$s-public $v." "$b" ;;
             *) has "$L: $s / runs PHP $v" "ok-$s $v." "$b" ;; esac
  case $s in $LCUR) eqs "$L: $s /u6-release.txt from releases/1 through current" release-1 "$(hbody $s /u6-release.txt)" ;;
             $LSUB) chk "$L: $s /wp/wp-login.php HTTP (core in wp/)" 200 "$(hcode $s /wp/wp-login.php)" ;; esac; }
fixture() { local d=$SITES_DIR/$1/app/htdocs/legacy; mkdir -p $d
  printf '<?php\n$f = create_function( %s, %s );\neach( $a );\n' "''" "'return 1;'" > $d/legacy.php; chown -R 33:33 $d; chmod 755 $d; chmod 644 $d/legacy.php; }

case $P in
pre)
  L="leg pre"
  for kv in $LEG_PHP; do s=${kv%%:*} v=${kv#*:}
    c create-$s site create $s --type=php --php=$v; chk "$L: create $s (php $v) rc" 0 "$RC"
    echo "<?php echo 'ok-$s ', PHP_VERSION;" > $SITES_DIR/$s/app/htdocs/index.php; chown 33:33 $SITES_DIR/$s/app/htdocs/index.php; fixture $s; done
  for s in $LW74 $LW80; do c create-$s site create $s --type=wp --php=$(LV $s) --title=u6$(cname $s | sed 's/^u6//') $W; chk "$L: create $s (wp $(LV $s)) rc" 0 "$RC"; done
  c create-$LPW site create $LPW --type=wp --php=8.4 --public-dir=web --title=u6$(cname $LPW | sed 's/^u6//') $W; chk "$L: create $LPW (wp --public-dir=web) rc" 0 "$RC"
  c create-$LPP site create $LPP --type=php --php=8.4 --public-dir=public; chk "$L: create $LPP (php --public-dir=public) rc" 0 "$RC"
  c create-$LPN site create $LPN --type=php --php=8.4 --public-dir=app/public; chk "$L: create $LPN (php --public-dir=app/public, nested) rc" 0 "$RC"
  for s in $LPP $LPN; do pd=$(db "select site_container_fs_path from sites where site_url='$s'"); info "$L: $s site_container_fs_path $pd"
    h=$SITES_DIR/$s/app/htdocs${pd#/var/www/htdocs}; mkdir -p $h; echo "<?php echo 'ok-$s-public ', PHP_VERSION;" > $h/index.php; chown -R 33:33 $SITES_DIR/$s/app/htdocs; fixture $s; done
  c create-$LCUR site create $LCUR --type=wp --php=8.4 --public-dir=current --title=u6$(cname $LCUR | sed 's/^u6//') $W; chk "$L: create $LCUR (wp --public-dir=current) rc" 0 "$RC"
  bash $F/layout.sh current $LCUR > $D/layout-$LCUR.txt 2>&1; chk "$L: layout current on $LCUR rc" 0 "$?"
  echo release-1 > $SITES_DIR/$LCUR/app/htdocs/releases/1/u6-release.txt; chown 33:33 $SITES_DIR/$LCUR/app/htdocs/releases/1/u6-release.txt
  c create-$LSUB site create $LSUB --type=wp --php=8.4 --title=u6$(cname $LSUB | sed 's/^u6//') $W; chk "$L: create $LSUB (wp, to move into wp/) rc" 0 "$RC"
  bash $F/layout.sh subdir $LSUB > $D/layout-$LSUB.txt 2>&1; chk "$L: layout subdir on $LSUB rc" 0 "$?"
  plugfix $LCUR releases/1/wp-content; plugfix $LSUB wp/wp-content; plugfix $LPW web/wp-content
  # 7.1: no easyengine/php7.1 image and not in --php's options.
  c create-71 site create u6-l71.test --type=php --php=7.1; chk "$L: create --php=7.1 refused rc" '[1-9][0-9]*' "$RC"
  info "$L: --php=7.1 message: $(grep -v '^rc=' $D/create-71.out | head -2 | tr '\n' ' ' | cut -c1-200)"; eqs "$L: nothing left of u6-l71.test" "$NOLEFT" "$(leftovers u6-l71.test)"
  for s in $LEGV $LAY; do chk "$L: $s / HTTP" 200 "$(hwait $s)"; body_ok "$L" $s $(LV $s); done
  # New Relic key on the 7.4 and 8.0 sites (applied with enable --force).
  for s in $L74 $L80; do info "$L: $s .env $(setkey $s $NRKEY)"; c nrkey-$s site enable $s --force; chk "$L: ee site enable $s --force (key) rc" 0 "$RC"
    chk "$L: $s / HTTP with the key" 200 "$(hwait $s)"; info "$L: $s newrelic on $(docker inspect -f '{{.Config.Image}}' $(phpc $s)): modules $(nr_mods $s), ini $([ -f "$(nr_ini $s)" ] && echo present || echo absent), log warnings $(nr_dlog $s)"; done
  db "select site_url,site_container_fs_path from sites order by site_url" > $D/paths-before.txt
  done_mark leg-pre ;;
post)
  L="leg post"; B=$OUT/before/containers.txt; A=$OUT/after/containers.txt
  for s in $LEGV; do p=$(cname $s)-
    chk "$L: $s containers kept (ID, StartedAt, image: php$(LV $s) and nginx tags unchanged)" "" "$(diff <(grep "^$p" $B | cut -f1,2,4,6) <(grep "^$p" $A | cut -f1,2,4,6) | grep '^[<>]' | tr '\n' ' ')"
    chk "$L: $s php on its tag" "easyengine/php$(re $(LV $s)):$(re $(tag easyengine/php$(LV $s)))" "$(f $(phpc $s) 6 $A)"
    chk "$L: $s / HTTP" 200 "$(hwait $s)"; body_ok "$L" $s $(LV $s); done
  for s in $LAY; do chk "$L: $s php recreated on php8.4 v4.16.0 (GO digest)" yes "$(digest_ok $(phpc $s) php8.4)"
    eqs "$L: $s site_container_fs_path unchanged" "$(grep "^$s|" $OUT/leg/paths-before.txt | cut -d'|' -f2)" "$(db "select site_container_fs_path from sites where site_url='$s'")"
    chk "$L: $s / HTTP" 200 "$(hwait $s)"; body_ok "$L" $s 8.4; done
  # php-compat: own version on each legacy site, every 5.6-8.0 target on the 7.4 php site; the fixture (create_function, each) is fine
  # before 8.0 and 2 errors on 8.0.
  for s in $(for kv in $LEG_PHP; do echo ${kv%%:*}; done); do v=$(LV $s)
    pc $s-own $s --php=$v --format=json; chk "$L: php-compat $s --php=$v rc" 0 "$RC"
    eqs "$L: php-compat $s status/site/target" "ok $s $v" "$(js '"\(.status) \(.site) \(.target)"' $s-own)"
    eqs "$L: php-compat $s tool.image" "$SC:v4.16.0" "$(js .tool.image $s-own)"; done
  for v in 5.6 7.0 7.2 7.3 7.4 8.0; do pc l74-$v $L74 --php=$v --format=json; chk "$L: php-compat $L74 --php=$v rc" 0 "$RC"
    eqs "$L: php-compat $L74 --php=$v status/target" "ok $v" "$(js '"\(.status) \(.target)"' l74-$v)"
    if [ $v = 8.0 ]; then eqs "$L: php-compat $L74 --php=8.0 not safe (create_function/each removed)" false "$(js .safe_to_upgrade l74-$v)"; chk "$L: php-compat $L74 --php=8.0 errors" '[2-9]|[1-9][0-9]+' "$(js .errors l74-$v)"
    else info "$L: php-compat $L74 --php=$v safe=$(js .safe_to_upgrade l74-$v) errors=$(js .errors l74-$v) warnings=$(js .warnings l74-$v)"; fi; done
  pc l56-table $L56 --php=8.0; chk "$L: php-compat $L56 --php=8.0 table rc" 0 "$RC"; has "$L: php-compat $L56 table verdict" "Not safe to upgrade $L56 to PHP 8.0" "$(head -3 $D/l56-table.out)"
  pc lw80 $LW80 --php=8.4 --format=json; chk "$L: php-compat $LW80 (wp 8.0) --php=8.4 rc" 0 "$RC"; eqs "$L: php-compat $LW80 status/target" "ok 8.4" "$(js '"\(.status) \(.target)"' lw80)"
  pc l71 $L74 --php=7.1 --format=json; chk "$L: php-compat --php=7.1 refused rc" 1 "$RC"
  c create-71 site create u6-l71.test --type=php --php=7.1; chk "$L: create --php=7.1 refused rc (release)" '[1-9][0-9]*' "$RC"; eqs "$L: nothing left of u6-l71.test" "$NOLEFT" "$(leftovers u6-l71.test)"
  for s in $LPP $LPN $LPW $LCUR $LSUB; do pcfix "$L" $s $D/lay-$s.json; done
  # site update --php: to 8.4 and back (SC-61 path), with the New Relic key on $L74 and $L80.
  for s in $LEGV; do v=$(LV $s)
    c up84-$s site update $s --php=8.4; chk "$L: site update $s $v -> 8.4 rc" 0 "$RC"
    eqs "$L: $s sites.php_version 8.4" 8.4 "$(db "select php_version from sites where site_url='$s'")"
    chk "$L: $s php on 8.4 v4.16.0 (GO digest)" yes "$(digest_ok $(phpc $s) php8.4)"
    chk "$L: $s PHP after -> 8.4" "$(pe 8.4)" "$(docker exec $(phpc $s) php -r 'echo PHP_VERSION;' 2>&1 | tail -1)"
    chk "$L: $s / HTTP on 8.4" 200 "$(hwait $s)"; body_ok "$L on 8.4" $s 8.4
    case $s in $L74|$L80)
      eqs "$L: $s newrelic.ini license on 8.4" "\"$NRKEY\"" "$(grep -E '^newrelic\.license = ' "$(nr_ini $s)" 2>/dev/null | sed -E 's/^[^=]+= *//')"
      chk "$L: $s newrelic loaded on 8.4" 'cli=1 fpm=1' "$(nr_mods $s)"; chk "$L: $s entrypoint/extension warnings on 8.4" 0 "$(nr_dlog $s)" ;; esac
    c back-$s site update $s --php=$v; chk "$L: site update $s 8.4 -> $v rc" 0 "$RC"
    eqs "$L: $s sites.php_version back to $v" $v "$(db "select php_version from sites where site_url='$s'")"
    chk "$L: $s php back on php$v" "easyengine/php$(re $v):$(re $(tag easyengine/php$v))" "$(docker inspect -f '{{.Config.Image}}' $(phpc $s) 2>&1)"
    chk "$L: $s / HTTP back on $v" 200 "$(hwait $s)"; body_ok "$L back on $v" $s $v
    case $s in $L74|$L80) info "$L: $s newrelic back on $v: modules $(nr_mods $s), log warnings $(nr_dlog $s)" ;; esac; done
  done_mark leg-post ;;
esac
exit 0
