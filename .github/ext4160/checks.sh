#!/bin/bash
# Checks after <old stable> -> release phar. Expectations are derived here as core's container migration does: an image is updated when its tag in use
# (a running container's tag, else its options row; compat-scanner excluded, NOT_MIGRATED_IMAGES) differs from the new img-versions.json; an enabled site is
# recreated when one of its containers runs an updated image; a global service is recreated when its image is updated. Options rows are only updated, never added.
# Usage: checks.sh <before-dir> <upgrade-dir> <after-dir>. Env: EXPECT_UPDATED (matrix knob, independent of the derivation).
. "$(dirname "$0")/lib.sh"; B=$1; U=$2; A=$3; X=$OUT/derived; mkdir -p $X
f() { awk -F'\t' -v n="$1" -v k="$2" '$1==n{print $k}' "$3"; }
read -r crc urc < $U/rc.txt
chk "update: cli info rc with the candidate" 0 "$crc"
chk "update: replace rc (whole simulated ee cli update)" 0 "$urc"
chk "ee cli version before" "EE $(re "$OLD_VERSION")" "$(cat $B/cli-version.txt)"
chk "ee cli version after" "EE $(re "$NEW_VERSION")" "$(cat $A/cli-version.txt)"

# Derived expectations (Containers::get_current_docker_images_versions: running tags win over options rows).
awk -F'\t' '$3=="running" {print $6}' $B/containers.txt | grep '^easyengine/' | sort -u | awk -F: '{t[$1]=$2} END {for (k in t) print k"|"t[k]}' | sort > $X/running-tags.txt
grep '^easyengine/' $B/options.txt | sort > $X/recorded-tags.txt
{ cat $X/running-tags.txt; cut -d'|' -f1 $X/running-tags.txt | grep -vxFf - <(cut -d'|' -f1 $X/recorded-tags.txt) | while read -r k; do grep "^$k|" $X/recorded-tags.txt; done; } | grep -v '^easyengine/compat-scanner|' | sort > $X/current-tags.txt
while IFS='|' read -r k v; do [ "$(tag $k)" != none ] && [ "$(tag $k)" != "$v" ] && echo $k; done < $X/current-tags.txt | sort > $X/updated-images.txt
while IFS='|' read -r k v; do [ "$(tag $k)" != none ] && [ "$(tag $k)" != "$v" ] && echo $k; done < $X/recorded-tags.txt | grep -vx easyengine/compat-scanner | sort > $X/updated-recorded.txt
UPDATED=" $(tr '\n' ' ' < $X/updated-images.txt)"
info "derived: tags in use before: $(tr '\n' ' ' < $X/current-tags.txt)"
info "derived: updated images (tag in use != new img-versions.json):$UPDATED"
info "derived: updated images with an options row: $(tr '\n' ' ' < $X/updated-recorded.txt)"
info "derived: img-versions.json tag changes old -> new phar: $(cat $OUT/img-changed.txt | tr '\n' ' ')"
chk "derived: every updated image is a tag change between the two phars' img-versions.json" "" "$(comm -23 $X/updated-images.txt $OUT/img-changed.txt | tr '\n' ' ')"
eqs "derived: updated images = EXPECT_UPDATED (from the brief, per path)" "$(echo $EXPECT_UPDATED | tr ' ' '\n' | sort | tr '\n' ' ')" "$(tr '\n' ' ' < $X/updated-images.txt)"
: > $X/expected-recreated.txt
for s in $ENABLED; do p=$(cname $s)-
  for r in $(grep "^$p" $B/containers.txt | cut -f6 | sed 's/:.*//' | sort -u); do [[ "$UPDATED " == *" $r "* ]] && { echo $s >> $X/expected-recreated.txt; break; }; done; done
EXP=" $(tr '\n' ' ' < $X/expected-recreated.txt)"
info "derived: sites expected to be recreated:$EXP"
: > $X/actual-recreated.txt
for s in $ENABLED; do p=$(cname $s)-
  d=$(diff <(grep "^$p" $B/containers.txt | cut -f1,2,4) <(grep "^$p" $A/containers.txt | cut -f1,2,4) | grep -c '^[<>]')
  [ "$d" -gt 0 ] && echo $s >> $X/actual-recreated.txt; done
eqs "sites recreated (any container ID/StartedAt changed) = derived set" "$(sort $X/expected-recreated.txt | tr '\n' ' ')" "$(sort $X/actual-recreated.txt | tr '\n' ' ')"
# v4.16.0: php8.1-8.4 change on every path, so every enabled site whose php container ran php8.1-8.4 before is recreated; from 4.15.0 exactly those (8.5/8.6 and html kept).
for s in $ENABLED; do case $(f $(phpc $s) 6 $B/containers.txt) in easyengine/php8.[1-4]:*) echo $s ;; esac; done | sort > $X/sites-81-84.txt
info "derived: enabled sites on php8.1-8.4 before: $(tr '\n' ' ' < $X/sites-81-84.txt)"
chk "every enabled php8.1-8.4 site is in the recreated set" "" "$(comm -23 $X/sites-81-84.txt <(sort $X/actual-recreated.txt) | tr '\n' ' ')"
chk "php8.1, 8.2, 8.3 and 8.4 sites exist before (population)" 4 "$(for s in $(cat $X/sites-81-84.txt); do f $(phpc $s) 6 $B/containers.txt | cut -d: -f1; done | sort -u | wc -l)"
[ "$OLD_VERSION" = 4.15.0 ] && eqs "4.15.0: recreated set = exactly the enabled php8.1-8.4 sites" "$(tr '\n' ' ' < $X/sites-81-84.txt)" "$(sort $X/actual-recreated.txt | tr '\n' ' ')"

# Per site containers.
for s in $ENABLED; do p=$(cname $s)-
  if [[ "$EXP " == *" $s "* ]]; then
    c=$(phpc $s); [ $s = $HTML ] && c=$(cname $s)-nginx-1
    chk "$s: $c recreated (new ID)" new "$([ "$(f $c 2 $B/containers.txt)" != "$(f $c 2 $A/containers.txt)" ] && echo new || echo same)"
  else
    chk "$s: all containers kept (ID, StartedAt, image)" "" "$(diff <(grep "^$p" $B/containers.txt | cut -f1,2,4,6) <(grep "^$p" $A/containers.txt | cut -f1,2,4,6) | grep '^[<>]' | tr '\n' ' ')"
  fi
  bad=$(grep "^$p" $A/containers.txt | cut -f1,6 | while IFS=$'\t' read -r n i; do r=${i%%:*}; [[ $r == easyengine/* ]] && [ "${i#*:}" != "$(tag $r)" ] && echo "$n=$i"; done | tr '\n' ' ')
  chk "$s: every container on the new img-versions.json tag" "" "$bad"
  chk "$s: containers all running" "" "$(grep "^$p" $A/containers.txt | awk -F'\t' '$3!="running" {print $1":"$3}' | tr '\n' ' ')"
  chk "$s: RestartCount after = before (kept) or 0 (recreated)" "" "$(grep "^$p" $A/containers.txt | cut -f1,2,5 | while IFS=$'\t' read -r n i r; do b=$(awk -F'\t' -v n=$n -v i=$i '$1==n && $2==i {print $5}' $B/containers.txt); [ "$r" = "${b:-0}" ] || echo "$n:${b:-new}->$r"; done | tr '\n' ' ')"
  chk "$s: same container names" "$(grep "^$p" $B/containers.txt | cut -f1 | tr '\n' ' ')" "$(grep "^$p" $A/containers.txt | cut -f1 | tr '\n' ' ')"
done

# php containers: tag, PHP version, php-fpm -t, load warnings (also php -m with startup errors on, and docker logs).
for s in $ENABLED; do [ $s = $HTML ] && continue; c=$(phpc $s)
  read -r _ bimg bv bfpm bwn < <(grep "^$s " $B/php.txt); read -r _ aimg av afpm awn < <(grep "^$s " $A/php.txt)
  mm=$(echo "$bimg" | sed -nE 's#^easyengine/php([0-9.]+):.*#\1#p')
  chk "$s: php image + PHP after (same minor, new tag)" "easyengine/php$(re "$mm"):$(re "$(tag easyengine/php$mm)") $(pe $mm)" "$aimg $av"
  chk "$s: php-fpm -t after" fpm-t=0 "$afpm"
  chk "$s: no load warnings in php -v / php-fpm -t before" warn=0 "$bwn"
  chk "$s: no load warnings in php -v / php-fpm -t after" warn=0 "$awn"
  docker exec $c php -d display_startup_errors=1 -d error_reporting=-1 -m > $A/php-m-startup-$s.txt 2>&1
  chk "$s: php -m with startup errors on: no warning lines" 0 "$(grep -cE "$WARN_RE" $A/php-m-startup-$s.txt)"
  docker logs $c > $A/php-dlog-$s.txt 2>&1
  chk "$s: php container log has no load/startup warnings" 0 "$(grep -cE "$WARN_RE|Failed loading|docker-entrypoint: could not" $A/php-dlog-$s.txt)"
  for m in cli fpm; do d=$(diff $B/mods-$m-$s.txt $A/mods-$m-$s.txt | grep '^[<>]' | tr '\n' ' ')
    if [ $s = $K84 ]; then info "$s: $m modules diff: $d"; else chk "$s: $m modules after = before" "" "$d"; fi; done
  info "$s: php before $bimg $bv $bfpm $bwn; after $aimg $av $afpm $awn"
done

# Digests: every container on a v4.16.0 image runs the GO.env digest of that image; at least one container per updated image.
for c in $(awk -F'\t' '$6 ~ /^easyengine\/[^:]+:v4\.16\.0$/ {print $1}' $A/containers.txt); do i=$(f $c 6 $A/containers.txt); n=${i#easyengine/}; n=${n%%:*}
  chk "$c: runs easyengine/$n@<GO digest>" yes "$(digest_ok $c $n)"; done
for n in cron php8.1 php8.2 php8.3 php8.4 newrelic-daemon; do
  chk "containers on easyengine/$n:v4.16.0 after the upgrade" '[1-9][0-9]*' "$(awk -F'\t' -v i="easyengine/$n:v4.16.0" '$6==i' $A/containers.txt | wc -l)"; done

# Globals.
for c in $(cut -f1 $B/containers.txt | grep '^services_global-'); do r=$(f $c 6 $B/containers.txt); r=${r%%:*}
  chk "$c: running after" running "$(f $c 3 $A/containers.txt)"
  chk "$c: image after at the new tag" "$(re "$r:$(tag $r)")" "$(f $c 6 $A/containers.txt)"
  if [[ "$UPDATED " == *" $r "* ]]; then
    chk "$c: recreated ($r updated)" new "$([ "$(f $c 2 $B/containers.txt)" != "$(f $c 2 $A/containers.txt)" ] && echo new || echo same)"
  else
    chk "$c: same ID ($r not updated)" same "$([ "$(f $c 2 $B/containers.txt)" = "$(f $c 2 $A/containers.txt)" ] && echo same || echo changed)"
    [ $c = services_global-cron_1 ] && { info "$c StartedAt $(f $c 4 $B/containers.txt) -> $(f $c 4 $A/containers.txt)"; continue; }
    chk "$c: not restarted (StartedAt)" "$(f $c 4 $B/containers.txt)" "$(f $c 4 $A/containers.txt)"
  fi; done
eqs "global cron after: image" "easyengine/cron:v4.16.0" "$(f services_global-cron_1 6 $A/containers.txt)"
eqs "global newrelic-daemon after: image" "easyengine/newrelic-daemon:v4.16.0" "$(f services_global-newrelic-daemon_1 6 $A/containers.txt)"
chk "containers: same set of names" "$(cut -f1 $B/containers.txt | tr '\n' ' ')" "$(cut -f1 $A/containers.txt | tr '\n' ' ')"
chk "containers: all running after" "" "$(awk -F'\t' '$3!="running"{print $1":"$3}' $A/containers.txt | tr '\n' ' ')"
chk "containers: no update-ee-* support container left" "" "$(cut -f1 $A/containers.txt | grep '^update-ee' | tr '\n' ' ')"
chk "global redis: redis-cli ping" PONG "$(docker exec $REDIS redis-cli ping 2>&1 | tr -d '\r')"
chk "global db: mysqladmin ping rc (0 = server up)" 0 "$(docker exec services_global-db_1 sh -c 'mysqladmin ping > /dev/null 2>&1 || mariadb-admin ping > /dev/null 2>&1'; echo $?)"
chk "global nginx-proxy: nginx -t" 0 "$(docker exec $PROXY nginx -t > /dev/null 2>&1; echo $?)"

# compat-scanner is never pulled or recorded by the upgrade (NOT_MIGRATED_IMAGES, skipped by the insert migration).
chk "upgrade: docker pull events for compat-scanner" 0 "$(awk '$2=="image" && $3=="pull"' $U/docker-events.txt | grep -c compat-scanner)"
chk "upgrade: compat-scanner images after the upgrade" 0 "$(grep -c '^easyengine/compat-scanner:' $A/images.txt)"
info "upgrade: ee.log lines naming compat-scanner: $(grep -c compat-scanner $U/ee.log.part)"

# DB.
chk "DB: options version" "$(re "$NEW_VERSION")" "$(db "select value from options where key='version'")"
for k in $(cat $X/updated-recorded.txt); do chk "DB: options $k after" "$(re "$(tag $k)")" "$(db "select value from options where key='$k'")"; done
for n in cron php8.1 php8.2 php8.3 php8.4 newrelic-daemon compat-scanner; do k=easyengine/$n
  bv=$(grep "^$k|" $B/options.txt | cut -d'|' -f2); av=$(grep "^$k|" $A/options.txt | cut -d'|' -f2)
  if [ $n = compat-scanner ]; then e=absent; elif [ -n "$bv" ]; then e=$(tag $k); else e=absent; fi
  eqs "DB: options $k (before ${bv:-absent}; rows are updated, never added)" "$e" "${av:-absent}"; done
ex="^(version$(for k in $(cat $X/updated-recorded.txt); do printf '|%s' "${k//./\\.}"; done))\|"
d=$(diff <(grep -vE "$ex" $B/options.txt) <(cut -d'|' -f1 $B/options.txt | while read -r k; do grep "^$k|" $A/options.txt || echo "$k|<missing>"; done | grep -vE "$ex") | grep '^[<>]' | tr '\n' ' ')
chk "DB: every other options row unchanged" "" "$d"
eqs "DB: options rows added" "" "$(comm -13 <(cut -d'|' -f1 $B/options.txt | sort) <(cut -d'|' -f1 $A/options.txt | sort) | tr '\n' ' ')"
d=$(diff $B/migrations.txt <(head -n $(wc -l < $B/migrations.txt) $A/migrations.txt) | grep '^[<>]' | tr '\n' ' '); chk "DB: existing migrations rows unchanged ($(wc -l < $B/migrations.txt) rows)" "" "$d"
eqs "DB: migrations rows added = migrations new in the candidate phar" "$(echo $EXPECT_NEW_MIGRATIONS | tr ' ' '\n' | sed '/^$/d' | awk -F/ '{print $2"|"$1}' | sort | tr '\n' ' ')" "$(tail -n +$(( $(wc -l < $B/migrations.txt) + 1 )) $A/migrations.txt | cut -d'|' -f2,3 | sort | tr '\n' ' ')"
# modified_on (the second timestamp) may move: the migration re-enables mailhog on $W84 and saves its row.
mo() { sed -E 's/\|([0-9-]+ [0-9:]+)\|[0-9-]+ [0-9:]+\|/|\1|MODIFIED|/' $1; }
d=$(diff <(mo $B/sites-full.txt) <(mo $A/sites-full.txt) | grep '^[<>]' | tr '\n' ' '); chk "DB: sites rows unchanged (all columns but modified_on)" "" "$d"
info "DB: sites rows with a new modified_on: $(diff $B/sites-full.txt $A/sites-full.txt | grep '^>' | cut -d'|' -f2 | tr '\n' ' ')"
d=$(diff $B/site_meta.txt $A/site_meta.txt | grep '^[<>]' | tr '\n' ' ' | cut -c1-600); chk "DB: site_meta unchanged" "" "$d"
d=$(diff $B/cron-db.txt $A/cron-db.txt | grep '^[<>]' | tr '\n' ' '); chk "DB: cron rows unchanged" "" "$d"
chk "DB: cron rows (one per WP site + site job + host job)" "$(( $(echo $WPS $XWPS | wc -w) + 2 ))" "$(wc -l < $A/cron-db.txt)"
chk "DB: the host cron job and the extra site job exist" "2" "$(grep -cE "^[0-9]+\|host\|sh -c 'date'\|@every 1h\||^[0-9]+\|$W84\|sh -c 'wp cron event run --due-now'\|@every 10m\|" $A/cron-db.txt)"

# ee site list / site info / cron list.
d=$(diff $B/site-list.txt $A/site-list.txt | grep '^[<>]' | tr '\n' ' '); chk "ee site list unchanged" "" "$d"
for s in $ENABLED; do d=$(diff $B/info/$s.txt $A/info/$s.txt | grep '^[<>]' | tr -s ' \n' ' ' | cut -c1-500)
  chk "$s: ee site info unchanged" "" "$d"
  chk "$s: ee site info rc ok (has the site URL)" yes "$(grep -q "$s" $A/info/$s.txt && echo yes || echo no)"; done
# cron-command <= v2.1.0 (stables 4.10.x-4.12.x) can't list at all ("Invalid field: user"); then the release's list is checked against the DB rows.
if grep -q 'Invalid field: user' $B/cron-list.txt; then info "ee cron list --all on $OLD_VERSION before the upgrade: $(head -1 $B/cron-list.txt) (old cron-command, fixed since)"
  chk "ee cron list --all after lists every cron row" "$(wc -l < $A/cron-db.txt)" "$(tail -n +2 $A/cron-list.txt | grep -c .)"
else d=$(diff $B/cron-list.txt $A/cron-list.txt | grep '^[<>]' | tr '\n' ' '); chk "ee cron list --all unchanged" "" "$d"; fi
for x in 'wp cron event run --due-now' 'date'; do chk "global cron config.ini has the job [$x]" '[1-9][0-9]*' "$(grep '^command = ' $A/cron-config.ini | grep -cF -- "$x")"; done
info "cron config.ini before/after diff: $(diff $B/cron-config.ini $A/cron-config.ini | grep '^[<>]' | tr '\n' ' ' | cut -c1-400)"
eqs "$W84 /ee-admin/ HTTP after = before" "$(cut -d' ' -f3 $B/admin-http.txt)" "$(cut -d' ' -f3 $A/admin-http.txt)"

# HTTP (sites, subsite, aliases).
while read -r s p c; do chk "$s $p HTTP before" 200 "$c"; done < $B/http.txt
while read -r s p c; do [ "$c" = 200 ] || c=$(hwait $s $p); chk "$s $p HTTP after" 200 "$c"; done < $A/http.txt

# ee.log of the upgrade.
eelog_checks upgrade $U/ee.log.part
grep -iE 'migrat|update-ee|support|prune|pull|Error|Warning|Reverting' $U/ee.log.part | tail -200 > $U/ee-log-key.txt
awk '{for(i=2;i<=NF;i++){split($i,a,"=");k=a[1];c=a[2]; tot[k]++; if(c=="000"||c ~ /^5/){n[k]++}}} END{for(k in tot) printf "%s: %d/%d rounds down\n", k, n[k]+0, tot[k]}' $U/probe.txt | sort > $U/downtime.txt
while read -r l; do info "downtime $l"; done < $U/downtime.txt
info "docker image events during the upgrade: $(awk '$2=="image"{print $3":"$4}' $U/docker-events.txt | sort | uniq -c | tr -s ' \n' ' ' | cut -c1-1500)"
done_mark checks
exit 0
