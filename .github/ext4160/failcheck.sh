#!/bin/bash
# State after a failed upgrade (faults already off, the old phar still installed). Expectations from core 7765d9f6's code:
#   failpull      cron is the only explicit pull (php*, newrelic-daemon are pulled by compose): Docker Hub blocked -> "Unable to pull", nothing touched.
#   failpull-mid  the php8.3 pull of $W83 fails inside its upgrade step after the globals and $W81/$W82/$MUD were recreated: the inner
#                 processor reverts every site and global it touched (old images are still local; prune hasn't run), DB options untouched.
#   faillate-site `docker-compose up` of $W83 fails after the pulls: same rollback as failpull-mid.
#   faillate      ee-update-docker-compose throws after the image step completed: containers stay on the new images, the image step's
#                 options rows stay written, ee-keep-container-migrations keeps the container migrations, options.version stays old.
# In every mode: rc 1, "PHAR is broken", the old phar stays installed, the sites are served, `ee` still works.
# Usage: failcheck.sh <mode> <before-dir> <fail-upgrade-dir> <after-fail-dir>. Env: OLD_MD5, OLD_VERSION, NEW_VERSION, IMG_JSON.
. "$(dirname "$0")/lib.sh"; M=$1; B=$2; U=$3; A=$4; L=$M; X=$OUT/derived-$M; mkdir -p $X
f() { awk -F'\t' -v n="$1" -v k="$2" '$1==n{print $k}' "$3"; }
LOG=$U/ee.log.part; OUTS="$(cat $U/cliinfo.out $U/cliinfo.err $U/update.out 2>/dev/null)"
read -r crc urc < $U/rc.txt
chk "$L: cli info rc with the candidate (failed)" '[1-9][0-9]*' "$crc"
chk "$L: simulated ee cli update rc" 1 "$urc"
has "$L: update says the PHAR is broken" "PHAR is broken" "$(cat $U/update.out)"
eqs "$L: /usr/local/bin/ee is still the old phar (md5)" "$OLD_MD5" "$(md5sum /usr/local/bin/ee | cut -c1-32)"
eqs "$L: ee cli version" "EE $OLD_VERSION" "$(cat $A/cli-version.txt)"
eqs "$L: options.version stays $OLD_VERSION" "$OLD_VERSION" "$(db "select value from options where key='version'")"
chk "$L: no /tmp/ee_*.phar left" "" "$(ls /tmp/ee_*.phar 2>/dev/null | tr '\n' ' ')"
d=$(diff $B/migrations.txt $A/migrations.txt | grep '^[<>]' | tr '\n' ' '); chk "$L: migrations rows unchanged (4.16.0 adds none)" "" "$d"
mo() { sed -E 's/\|([0-9-]+ [0-9:]+)\|[0-9-]+ [0-9:]+\|/|\1|MODIFIED|/' $1; }
d=$(diff <(mo $B/sites-full.txt) <(mo $A/sites-full.txt) | grep '^[<>]' | tr '\n' ' '); chk "$L: sites rows unchanged (all columns but modified_on)" "" "$d"
d=$(diff $B/cron-db.txt $A/cron-db.txt | grep '^[<>]' | tr '\n' ' '); chk "$L: cron rows unchanged" "" "$d"
d=$(diff $B/site-list.txt $A/site-list.txt | grep '^[<>]' | tr '\n' ' '); chk "$L: ee site list (old phar) unchanged" "" "$d"
for s in $ENABLED; do chk "$L: $s ee site info (old phar) has the site" yes "$(grep -q "$s" $A/info/$s.txt && echo yes || echo no)"; done
chk "$L: containers: same set of names" "$(cut -f1 $B/containers.txt | tr '\n' ' ')" "$(cut -f1 $A/containers.txt | tr '\n' ' ')"
chk "$L: containers: all running" "" "$(awk -F'\t' '$3!="running"{print $1":"$3}' $A/containers.txt | tr '\n' ' ')"
chk "$L: no update-ee-* support container left" "" "$(cut -f1 $A/containers.txt | grep '^update-ee' | tr '\n' ' ')"
while read -r s p c; do [ "$c" = 200 ] || c=$(hwait $s $p); chk "$L: $s $p HTTP after the failed upgrade" 200 "$c"; done < $A/http.txt
chk "$L: global nginx-proxy: nginx -t" 0 "$(docker exec $PROXY nginx -t > /dev/null 2>&1; echo $?)"
chk "$L: global db: ping rc" 0 "$(docker exec services_global-db_1 sh -c 'mysqladmin ping > /dev/null 2>&1 || mariadb-admin ping > /dev/null 2>&1'; echo $?)"
chk "$L: global redis: ping" PONG "$(docker exec $REDIS redis-cli ping 2>&1 | tr -d '\r')"
chk "$L: docker-compose still runs (>= 2.26.1)" '2\.(2[6-9]|[3-9][0-9])\.[0-9]+' "$(/usr/local/bin/docker-compose version --short 2>&1)"
chk "$L: compat-scanner not pulled by the failed upgrade" 0 "$(awk '$2=="image" && $3=="pull"' $U/docker-events.txt | grep -c compat-scanner)"
chk "$L: ee.log has the step error line" '[1-9][0-9]*' "$(grep -c 'Error while executing' $LOG)"
grep 'Error while executing' $LOG | head -3 | cut -c1-300 | while read -r l; do info "$L: ee.log: $l"; done
info "$L: fault log: $(tr '\n' ' ' < /var/tmp/ext-fault-fired.txt 2>/dev/null | cut -c1-400)"
info "$L: probe rounds down per site: $(awk '{for(i=2;i<=NF;i++){split($i,a,"=");k=a[1];c=a[2]; tot[k]++; if(c=="000"||c ~ /^5/){n[k]++}}} END{for(k in tot) printf "%s=%d/%d ", k, n[k]+0, tot[k]}' $U/probe.txt)"
info "$L: v4.16.0 images on disk after the failure: $(grep -oE 'easyengine/[^:]+:v4\.16\.0' $A/images.txt | tr '\n' ' ')"
info "$L: wall: $(tail -1 $U/cmd.txt)"

rolled_back() { # globals and sites back on their old images, DB options and compose files as before
  local sv="$W81 $W82 $MUD $W83"
  d=$(diff <(cut -f1,6 $B/containers.txt) <(cut -f1,6 $A/containers.txt) | grep '^[<>]' | tr '\n' ' '); chk "$L: every container on its image from before (name, image)" "" "$d"
  chk "$L: no container on a v4.16.0 image" "" "$(awk -F'\t' '$6 ~ /:v4\.16\.0$/ {print $1}' $A/containers.txt | tr '\n' ' ')"
  d=$(diff $B/options.txt $A/options.txt | grep '^[<>]' | tr '\n' ' '); chk "$L: options rows identical to before" "" "$d"
  d=$(diff $B/compose.md5 $A/compose.md5 | grep '^[<>]' | tr '\n' ' '); chk "$L: global and site compose files identical to before (md5)" "" "$d"
  chk "$L: no pending global compose snapshot left (.pending)" absent "$([ -e /opt/easyengine/.backup/services/docker-compose.yml.backup.pending ] && echo present || echo absent)"
  for s in $sv; do chk "$L: ee.log reverted $s (Reverting upgrade/disable steps)" '[1-9][0-9]*' "$(grep -cE "Reverting (upgrade|disable)-$(re $s)-containers" $LOG)"; done
  chk "$L: ee.log reverted the global compose backup step" '[1-9][0-9]*' "$(grep -c 'Reverting backup-global-docker-compose-file' $LOG)"
  # Untouched by the run: sites after $W83 and the globals whose image doesn't change keep ID and StartedAt.
  for s in $ENABLED; do case " $sv " in *" $s "*) continue ;; esac; p=$(cname $s)-
    chk "$L: $s containers kept (ID, StartedAt, image)" "" "$(diff <(grep "^$p" $B/containers.txt | cut -f1,2,4,6) <(grep "^$p" $A/containers.txt | cut -f1,2,4,6) | grep '^[<>]' | tr '\n' ' ')"; done
  for c in services_global-nginx-proxy_1 services_global-db_1 services_global-redis_1; do
    eqs "$L: $c kept (ID StartedAt)" "$(f $c 2 $B/containers.txt) $(f $c 4 $B/containers.txt)" "$(f $c 2 $A/containers.txt) $(f $c 4 $A/containers.txt)"; done
  for c in services_global-cron_1 services_global-newrelic-daemon_1; do info "$L: $c ID $(f $c 2 $B/containers.txt | cut -c1-12) -> $(f $c 2 $A/containers.txt | cut -c1-12), image $(f $c 6 $A/containers.txt)"; done
  for s in $sv; do info "$L: $s php ID $(f $(phpc $s) 2 $B/containers.txt | cut -c1-12) -> $(f $(phpc $s) 2 $A/containers.txt | cut -c1-12)"; done
  for s in $W81 $W82 $W83 $W84; do chk "$L: $s WP-CLI option get siteurl" "http://$s" "$(wpx $s 'option get siteurl' 2>&1 | tr -d '\r' | tail -1)"; done
  pagecache $L $W84; }

case $M in
failpull)
  eqs "$L: Docker Hub blocked during the run" blocked "$(cat $U/block-check.txt 2>/dev/null)"
  has "$L: pull failure reported (Unable to pull easyengine/cron)" "Unable to pull easyengine/cron" "$OUTS $(cat $LOG)"
  d=$(diff <(cut -f1,2,4,6 $B/containers.txt) <(cut -f1,2,4,6 $A/containers.txt) | grep '^[<>]' | tr '\n' ' '); chk "$L: no container touched (name, ID, StartedAt, image)" "" "$d"
  d=$(diff $B/options.txt $A/options.txt | grep '^[<>]' | tr '\n' ' '); chk "$L: options rows identical to before" "" "$d"
  d=$(diff $B/compose.md5 $A/compose.md5 | grep '^[<>]' | tr '\n' ' '); chk "$L: compose files identical to before (md5)" "" "$d"
  chk "$L: no site or global step ran (no Reverting upgrade-/backup-global lines)" 0 "$(grep -cE 'Reverting (upgrade-|backup-global)' $LOG)"
  chk "$L: no pending global compose snapshot" absent "$([ -e /opt/easyengine/.backup/services/docker-compose.yml.backup.pending ] && echo present || echo absent)" ;;
failpull-mid)
  has "$L: the Docker Hub block fired inside upgrade-$W83-containers" "mid fault fired" "$(cat /var/tmp/ext-fault-fired.txt 2>/dev/null)"
  has "$L: ee.log: the $W83 upgrade step failed" "Error while executing upgrade-$W83-containers" "$(cat $LOG)"
  rolled_back ;;
faillate-site)
  has "$L: the compose fault fired inside upgrade-$W83-containers" "site fault fired" "$(cat /var/tmp/ext-fault-fired.txt 2>/dev/null)"
  has "$L: ee.log: the $W83 upgrade step failed" "Error while executing upgrade-$W83-containers" "$(cat $LOG)"
  rolled_back ;;
faillate)
  has "$L: the late fault fired (docker-compose said 2.20.0 in ee-update-docker-compose)" "late fault fired" "$(cat /var/tmp/ext-fault-fired.txt 2>/dev/null)"
  has "$L: ee.log: ee-update-docker-compose failed" "Error while executing ee-update-docker-compose" "$(cat $LOG)"
  has "$L: ee.log: container migrations kept" "Keeping the container migrations of this run" "$(cat $LOG)"
  chk "$L: no site or global step reverted" 0 "$(grep -cE 'Reverting (upgrade-|disable-|backup-global|enable-support)' $LOG)"
  for s in $ENABLED; do case $(f $(phpc $s) 6 $B/containers.txt) in easyengine/php8.[1-4]:*)
    chk "$L: $s php on v4.16.0 (the image step completed)" "easyengine/php8\.[1-4]:v4\.16\.0" "$(f $(phpc $s) 6 $A/containers.txt)"
    chk "$L: $s php runs the GO digest" yes "$(digest_ok $(phpc $s) $(f $(phpc $s) 6 $A/containers.txt | sed -E 's#easyengine/([^:]+):.*#\1#'))" ;; esac; done
  for n in cron newrelic-daemon; do eqs "$L: global $n on v4.16.0" "easyengine/$n:v4.16.0" "$(f services_global-${n}_1 6 $A/containers.txt)"; done
  for k in easyengine/cron easyengine/php8.2 easyengine/php8.3 easyengine/php8.4; do eqs "$L: options $k written by the image step" "$(tag $k)" "$(db "select value from options where key='$k'")"; done
  chk "$L: other options rows unchanged" "" "$(diff <(grep -vE '^(easyengine/(cron|php8\.[2-4])|version)\|' $B/options.txt) <(grep -vE '^(easyengine/(cron|php8\.[2-4])|version)\|' $A/options.txt) | grep '^[<>]' | tr '\n' ' ')"
  chk "$L: no pending global compose snapshot" absent "$([ -e /opt/easyengine/.backup/services/docker-compose.yml.backup.pending ] && echo present || echo absent)"
  info "$L: options rows of the image step say v4.16.0 while options.version says $OLD_VERSION (documented: the image step commits its rows; the retry finishes the run)" ;;
esac
done_mark failcheck
exit 0
