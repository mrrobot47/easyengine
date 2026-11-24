#!/bin/bash
# Disabled sites across the upgrade. Usage: dis.sh pre (on the old stable) | post <upgrade-dir> (after the upgrade, release installed).
# Expected (core 7765d9f6 Containers::migrate_site_containers / SiteContainers::update_disabled_site_compose_file): a disabled site keeps
# site_enabled 0 and no containers; its docker-compose.yml is rewritten to this release's tags when it names an older one (backup in
# .backup/<site>/), otherwise left alone; `ee site enable` then starts it on the new images (pulled then if the prune removed them).
. "$(dirname "$0")/lib.sh"; P=$1; D=$OUT/dis; mkdir -p $D/compose-before $D/compose-after; cd /tmp
f() { awk -F'\t' -v n="$1" -v k="$2" '$1==n{print $k}' "$3"; }
c() { local l=$1; shift; ee "$@" < /dev/null > $D/$l.out 2>&1; RC=$?; echo "rc=$RC" >> $D/$l.out; }
ver() { case $1 in $D81) echo 8.1 ;; $D82) echo 8.2 ;; $D83) echo 8.3 ;; $D85) echo 8.5 ;; $D86) echo 8.6 ;; $DH) echo none ;; *) echo 8.4 ;; esac; }
ncont() { docker ps -a --format '{{.Names}}' | grep -c "^$(cname $1)-"; }
marker() { case $1 in $DH) echo "ok-$DH" ;; $DP) echo "ok-$DP" ;; $DPP) echo "ok-$DPP-public" ;; $DSUB) echo "u6dsub" ;; $DCUR) echo "u6dcur" ;; *) echo "u6$(cname $1 | sed 's/^u6//')" ;; esac; }
page_ok() { local L=$1 s=$2 c b; c=$(hwait $s); b=$(hbody $s /)
  chk "$L: $s / HTTP" 200 "$c"; has "$L: $s / serves its own content" "$(marker $s)" "$b"
  case $s in $DCUR) eqs "$L: $s /u6-release.txt served from releases/1 through current" "release-1" "$(hbody $s /u6-release.txt)" ;;
             $DSUB) chk "$L: $s /wp/wp-login.php HTTP (core in wp/)" 200 "$(hcode $s /wp/wp-login.php)" ;;
             $DPP) eqs "$L: $s /u6-pub.txt from the public dir" "public-dir" "$(hbody $s /u6-pub.txt)" ;; esac; }

case $P in
pre)
  for s in $D81 $D82 $D83 $D84 $D85 $D86; do c create-$s site create $s --type=wp --php=$(ver $s) --title=$(marker $s) $W; chk "dis pre: create $s (wp $(ver $s)) rc" 0 "$RC"; done
  c create-$DSUB site create $DSUB --type=wp --php=8.4 --title=u6dsub $W; chk "dis pre: create $DSUB rc" 0 "$RC"
  c create-$DCUR site create $DCUR --type=wp --php=8.4 --public-dir=current --title=u6dcur $W; chk "dis pre: create $DCUR --public-dir=current rc" 0 "$RC"
  c create-$DH site create $DH --type=html; chk "dis pre: create $DH rc" 0 "$RC"
  c create-$DP site create $DP --type=php --php=8.4; chk "dis pre: create $DP rc" 0 "$RC"
  c create-$DPP site create $DPP --type=php --php=8.4 --public-dir=public; chk "dis pre: create $DPP --public-dir=public rc" 0 "$RC"
  echo "ok-$DH" > $SITES_DIR/$DH/app/htdocs/index.html
  echo "<?php echo 'ok-$DP ', PHP_VERSION;" > $SITES_DIR/$DP/app/htdocs/index.php
  echo "<?php echo 'ok-$DPP-public ', PHP_VERSION;" > $SITES_DIR/$DPP/app/htdocs/public/index.php; echo public-dir > $SITES_DIR/$DPP/app/htdocs/public/u6-pub.txt
  chown -R 33:33 $SITES_DIR/$DH/app/htdocs $SITES_DIR/$DP/app/htdocs $SITES_DIR/$DPP/app/htdocs/public
  bash $F/layout.sh current $DCUR > $D/layout-$DCUR.txt 2>&1; chk "dis pre: layout current on $DCUR rc" 0 "$?"
  echo release-1 > $SITES_DIR/$DCUR/app/htdocs/releases/1/u6-release.txt; chown 33:33 $SITES_DIR/$DCUR/app/htdocs/releases/1/u6-release.txt
  bash $F/layout.sh subdir $DSUB > $D/layout-$DSUB.txt 2>&1; chk "dis pre: layout subdir on $DSUB rc" 0 "$?"
  for s in $DIS_ALL; do page_ok "dis pre" $s; done
  for s in $D82 $D83 $D84; do info "dis pre: $s .env $(setkey $s $NRKEY)"; done
  for s in $DIS_ALL; do c disable-$s site disable $s; chk "dis pre: ee site disable $s rc" 0 "$RC"
    eqs "dis pre: $s site_enabled after disable" 0 "$(db "select site_enabled from sites where site_url='$s'")"
    chk "dis pre: $s containers after disable" 0 "$(ncont $s)"
    cp $SITES_DIR/$s/docker-compose.yml $D/compose-before/$s.yml; done
  for s in $DIS_ALL; do info "dis pre: $s / HTTP while disabled: $(hcode $s /)"; done
  db "select site_url,site_enabled,php_version,site_fs_path,site_container_fs_path from sites where site_url like 'u6-d%' order by site_url" > $D/sites-pre.txt 2>&1
  done_mark dis-pre ;;
post)
  U=$2; L="dis post"
  for s in $DIS_ALL; do cp $SITES_DIR/$s/docker-compose.yml $D/compose-after/$s.yml
    eqs "$L: $s still disabled (site_enabled)" 0 "$(db "select site_enabled from sites where site_url='$s'")"
    chk "$L: $s has no containers after the upgrade (not recreated)" 0 "$(ncont $s)"
    old=$(grep -oE 'easyengine/[a-z0-9.-]+:v[0-9.]+' $D/compose-before/$s.yml | sort -u | tr '\n' ' ')
    stale=$(grep -oE 'easyengine/[a-z0-9.-]+:v[0-9.]+' $D/compose-before/$s.yml | sort -u | while read -r i; do [ "${i#*:}" != "$(tag ${i%%:*})" ] && echo $i; done | tr '\n' ' ')
    new=$(grep -oE 'easyengine/[a-z0-9.-]+:v[0-9.]+' $D/compose-after/$s.yml | sort -u | while read -r i; do [ "${i#*:}" != "$(tag ${i%%:*})" ] && echo $i; done | tr '\n' ' ')
    chk "$L: $s compose file names only this release's tags" "" "$new"
    nonimg=$(diff $D/compose-before/$s.yml $D/compose-after/$s.yml | grep '^[<>]' | grep -vcE '^[<>]\s*image:')
    chk "$L: $s compose file: only image lines changed" 0 "$nonimg"
    if [ -n "$stale" ]; then
      chk "$L: $s compose rewritten (it named $stale)" changed "$(cmp -s $D/compose-before/$s.yml $D/compose-after/$s.yml && echo same || echo changed)"
      chk "$L: $s compose backup in .backup/$s/" present "$([ -f /opt/easyengine/.backup/$s/docker-compose.yml.backup ] && echo present || echo absent)"
      chk "$L: ee.log ran update-disabled-$s-docker-compose" '[1-9][0-9]*' "$(grep -c "Executing update-disabled-$(re $s)-docker-compose" $U/ee.log.part)"
    else
      chk "$L: $s compose untouched (already on this release's tags: $old)" same "$(cmp -s $D/compose-before/$s.yml $D/compose-after/$s.yml && echo same || echo changed)"
      chk "$L: ee.log did not touch $s" 0 "$(grep -c "update-disabled-$(re $s)-docker-compose" $U/ee.log.part)"
    fi
    info "$L: $s images before [$old] after [$(grep -oE 'easyengine/[a-z0-9.-]+:v[0-9.]+' $D/compose-after/$s.yml | sort -u | tr '\n' ' ')]"; done
  chk "$L: no ee.WARNING about a disabled site's compose file" 0 "$(grep -c 'Could not update docker-compose.yml of the disabled site' $U/ee.log.part)"
  info "$L: images of the disabled sites' new tags present after the upgrade's prune: $(for t in php8.1 php8.2 php8.3 php8.4; do docker image inspect easyengine/$t:$(tag easyengine/$t) > /dev/null 2>&1 && echo "$t=yes" || echo "$t=no"; done | tr '\n' ' ')"
  for s in $DIS_ALL; do c enable-$s site enable $s; chk "$L: ee site enable $s rc" 0 "$RC"
    eqs "$L: $s site_enabled after enable" 1 "$(db "select site_enabled from sites where site_url='$s'")"
    page_ok "$L" $s
    v=$(ver $s); [ $v = none ] && { chk "$L: $s nginx on the release tag" "easyengine/nginx:$(re $(tag easyengine/nginx))" "$(docker inspect -f '{{.Config.Image}}' $(cname $s)-nginx-1 2>&1)"; continue; }
    t=$(tag easyengine/php$v)
    chk "$L: $s php container image + PHP" "easyengine/php$(re $v):$(re $t) $(pe $v)" "$(docker inspect -f '{{.Config.Image}}' $(phpc $s) 2>&1) $(docker exec $(phpc $s) php -r 'echo PHP_VERSION;' 2>&1 | tail -1)"
    [ $t = v4.16.0 ] && chk "$L: $s php runs the GO digest" yes "$(digest_ok $(phpc $s) php$v)"
    chk "$L: $s php container log has no load/startup warnings" 0 "$(docker logs $(phpc $s) 2>&1 | grep -cE "$WARN_RE|Failed loading|docker-entrypoint: could not")"
  done
  # New Relic guard on enable (8.2/8.3 entrypoint copies the ini back with the key; 8.4's zip has no ini, the entrypoint adds it).
  for s in $D82 $D83 $D84; do
    eqs "$L: $s NEWRELIC_LICENSE_KEY in the php container" "$NRKEY" "$(docker exec $(phpc $s) printenv NEWRELIC_LICENSE_KEY 2>/dev/null)"
    chk "$L: $s conf.d/newrelic.ini" present "$([ -f "$(nr_ini $s)" ] && echo present || echo absent)"
    eqs "$L: $s newrelic.ini license" "\"$NRKEY\"" "$(grep -E '^newrelic\.license = ' "$(nr_ini $s)" 2>/dev/null | sed -E 's/^[^=]+= *//')"
    chk "$L: $s newrelic loaded (php -m, php-fpm -m)" 'cli=1 fpm=1' "$(nr_mods $s)"
    eqs "$L: $s phpversion('newrelic') = NR_AGENT" "$NR_AGENT" "$(docker exec $(phpc $s) php -r 'echo phpversion("newrelic");' 2>&1 | tail -1)"
    chk "$L: $s entrypoint/extension warnings in the php log" 0 "$(nr_dlog $s)"
    info "$L: $s agent: $(nr_connect $s $D)"; done
  for s in $D84 $D86; do wplogin "$L" $s $D; done
  for s in $DIS_ALL; do ee site info $s < /dev/null > $D/info-$s.txt 2>&1; chk "$L: ee site info $s rc" 0 "$?"; done
  # php-compat on the layout sites (scan root = site_container_fs_path; records what v3.11.x reports for these layouts).
  for s in $DPP $DCUR $DSUB; do ee site php-compat $s --php=8.5 --format=json < /dev/null > $D/pc-$s.json 2> $D/pc-$s.err; r=$?
    info "$L: php-compat $s --php=8.5: rc $r $(jq -c '{status,target,safe_to_upgrade,errors,warnings,files:(.files // .scanned_files // null),message}' $D/pc-$s.json 2>&1 | cut -c1-300) $(head -c 200 $D/pc-$s.err)"; done
  done_mark dis-post ;;
esac
exit 0
