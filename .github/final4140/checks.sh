#!/bin/bash
# 4.14.0-specific checks. Usage: checks.sh <label> <mode> [upgrade-dir]
# upgraded: read-only checks after a successful upgrade (3 new rows, db kept, pulls, prune, sid, upload progress, host log cap, disabled site, stopped cron).
# failed:   after a failed upgrade (failpull/faillate): record what stayed / changed.
# cli:      state-changing checks after the post.sh matrices (enable the disabled site, cron service enable/refresh).
. "$(dirname "$0")/lib.sh"; L=$1; MODE=$2; D=${3:-}; cd /tmp; O=$OUTDIR/checks-$L; mkdir -p "$O"
e() { ee "$@" </dev/null > "$O/last.out" 2>&1; local r=$?; { echo "rc=$r ee $*"; cat "$O/last.out"; } >> "$O/cmds.txt"; return $r; }
SID=20261023193000_site-command_drop_deprecated_session_sid_settings.php
UPP=20261023233000_site-command_recheck_session_upload_progress.php
CAP=20261102100000_easyengine_cap_host_syslog.php
row() { db "select count(*) from migrations where migration='$1'"; }
tag() { jq -r --arg r "$1" '.[$r] // "none"' "$IMG_JSON"; }
otag() { jq -r --arg r "$1" '.[$r] // "none"' "$IMG_OLD_JSON"; }
sidn() { grep -cE '^\s*session\.sid_(length|bits_per_character)\s*=' /opt/easyengine/sites/$1/config/php/php/php.ini 2>/dev/null; }
upoff() { grep -chE '^\s*session\.upload_progress\.enabled\s*=\s*Off' /opt/easyengine/sites/$1/config/php/php/conf.d/custom.ini 2>/dev/null; }
cron_state() { docker inspect -f '{{.State.Status}} {{.Config.Image}} {{.Id}}' services_global-cron_1 2>&1 | cut -c1-80; }

# Every easyengine/* image in the site's compose file is on its img-versions.json tag.
compose_tags() { local f=/opt/easyengine/sites/$1/docker-compose.yml bad="" i; for i in $(grep -oE 'easyengine/[a-z0-9.-]+:[A-Za-z0-9._-]+' $f | sort -u); do [ "${i#*:}" = "$(tag ${i%%:*})" ] || bad="$bad $i"; done; echo "${bad:-ok}"; }

logrotate_checks() {
  local base=$OUTDIR/seed/logrotate.txt f
  for f in /etc/logrotate.d/rsyslog /etc/logrotate.d/syslog; do
    if grep -q "^$f absent" $base; then [ -e $f ] && info "$L: $f created by the upgrade?" || info "$L: $f absent on this runner image (host cap n/a for it)"; continue; fi
    local st=$(grep -cE '^[^#]*\{' $f) ms=$(grep -cE '^\s*maxsize 2G' $f)
    chk "$L: $f: every stanza has maxsize 2G (stanzas, maxsize lines)" "$st $st" "$st $ms"
    chk "$L: $f: original saved in .backup/logrotate" "[1-9][0-9]*" "$(ls /opt/easyengine/.backup/logrotate/ 2>/dev/null | grep -c "$(basename $f)")"
    logrotate -d $f > "$O/logrotate-d-$(basename $f).txt" 2>&1; chk "$L: logrotate -d $f has no error" 0 "$(grep -ciE '^error' "$O/logrotate-d-$(basename $f).txt")"
  done
  if systemctl cat logrotate.timer >/dev/null 2>&1; then
    chk "$L: logrotate.timer hourly drop-in" "present hourly" "$([ -f /etc/systemd/system/logrotate.timer.d/hourly.conf ] && echo present || echo absent) $(grep -oE 'OnCalendar=hourly' /etc/systemd/system/logrotate.timer.d/hourly.conf 2>/dev/null | head -1 | cut -d= -f2)"
    info "$L: logrotate.timer: $(systemctl show logrotate.timer -p TimersCalendar --value 2>&1 | tr '\n' ' ' | cut -c1-200)"
  else
    chk "$L: no logrotate.timer: /etc/cron.hourly/ee-logrotate" present "$([ -x /etc/cron.hourly/ee-logrotate ] && echo present || echo absent)"
  fi
  chk "$L: host cap migration row" 1 "$(row $CAP)"
  for f in /etc/logrotate.d/ee_cli /etc/logrotate.d/ee_sites /etc/logrotate.d/ee_nginx_proxy; do
    [ -e $f ] || { info "$L: $f absent"; continue; }
    chk "$L: $f maxsize 1G, no copytruncate" "[1-9][0-9]* 0" "$(grep -cE '^\s*maxsize 1G' $f) $(grep -cE '^\s*copytruncate' $f)"; done
}

sid_checks() {
  local s b a
  for s in f4-p84.test f4-p85.test; do b=$(grep -oP "^$s sid=\K[0-9]+" $OUTDIR/seed/php-ini.txt); a=$(sidn $s)
    chk "$L: $s php.ini sid lines removed (was $b)" 0 "$a"
    chk "$L: $s php.ini backup kept" present "$([ -f /opt/easyengine/.backup/$s/php.ini.with-session-sid-settings ] && echo present || echo absent)"
    docker exec $(cname $s)-php-1 php -r 'echo ini_get("session.sid_length"), "/", ini_get("session.sid_bits_per_character");' > "$O/sid-$s.txt" 2>&1
    chk "$L: $s php CLI: no Deprecated, sid at PHP defaults" "0 32/4" "$(grep -c Deprecated "$O/sid-$s.txt") $(grep -v Deprecated "$O/sid-$s.txt" | tr -d '\n')"
  done
  for s in f4-p83.test f4-p81.test; do b=$(grep -oP "^$s sid=\K[0-9]+" $OUTDIR/seed/php-ini.txt); chk "$L: $s (php < 8.4) sid lines unchanged" "$b" "$(sidn $s)"; done
  chk "$L: sid migration row" 1 "$(row $SID)"
}

upload_checks() {
  local s bad=""
  for s in $PHPSITES; do [ "$(upoff $s)" = 1 ] || bad="$bad $s=$(upoff $s)"; done
  chk "$L: every wp/php site's custom.ini has exactly one 'session.upload_progress.enabled = Off'" ok "${bad:-ok}"
  chk "$L: upload-progress recheck migration row" 1 "$(row $UPP)"
  # Through FPM: the php site serves a probe.
  echo '<?php echo var_export(ini_get("session.upload_progress.enabled"), true);' > /opt/easyengine/sites/f4-p85.test/app/htdocs/f4-up.php; chmod 644 /opt/easyengine/sites/f4-p85.test/app/htdocs/f4-up.php
  chk "$L: f4-p85.test FPM ini_get(session.upload_progress.enabled)" "''|'0'|false" "$(curl -s -m 20 --resolve f4-p85.test:80:127.0.0.1 http://f4-p85.test/f4-up.php)"
}

case $MODE in
upgraded)
  [ -n "$D" ] || { echo "upgraded needs the upgrade dir"; exit 2; }
  chk "$L: the 3 new migration rows once each" "1 1 1" "$(row $SID) $(row $UPP) $(row $CAP)"
  chk "$L: no duplicate migration rows" 0 "$(db "select count(*) from (select migration from migrations group by migration having count(*) > 1)")"
  # db: mariadb tag unchanged, container kept.
  b=$(awk -F'\t' '$1=="services_global-db_1"{print $3}' $D/before/containers.txt); a=$(awk -F'\t' '$1=="services_global-db_1"{print $3}' $D/after/containers.txt)
  chk "$L: global db container not recreated (ID)" "$b" "$a"
  grep -oE 'docker pull [^ ]+' $D/ee.log.part | sort | uniq -c > "$O/pulls.txt"; info "$L: pulls in the upgrade: $(tr -s ' ' < "$O/pulls.txt" | tr '\n' ';')"
  chk "$L: no pull of mailhog, easyengine/php: or cron:$(tag easyengine/cron) (stopped cron)" 0 "$(grep -cE 'easyengine/mailhog|easyengine/php:|easyengine/cron:' "$O/pulls.txt")"
  # Images before/after: what went away must be EE images no container (running or stopped) used.
  cut -f1 $D/before/images.txt | sort > "$O/img-before.txt"; cut -f1 $D/after/images.txt | sort > "$O/img-after.txt"
  comm -23 "$O/img-before.txt" "$O/img-after.txt" > "$O/img-removed.txt"; comm -13 "$O/img-before.txt" "$O/img-after.txt" > "$O/img-added.txt"
  info "$L: images removed: $(tr '\n' ' ' < "$O/img-removed.txt")"; info "$L: images added: $(tr '\n' ' ' < "$O/img-added.txt")"
  cut -f2 $D/before/containers.txt | sort -u > "$O/img-used-before.txt"
  chk "$L: removed images were all easyengine/* and unused by any container" "0 0" "$(grep -vc '^easyengine/' "$O/img-removed.txt") $(comm -12 "$O/img-removed.txt" "$O/img-used-before.txt" | wc -l)"
  miss=""; while IFS=$'\t' read -r n i _; do docker image inspect "$i" >/dev/null 2>&1 || miss="$miss $n=$i"; done < $D/after/containers.txt
  chk "$L: every container's image still present" ok "${miss:-ok}"
  sid_checks; upload_checks; logrotate_checks
  # Disabled site: compose updated, nothing started.
  chk "$L: disabled $OFF: compose on the new tags" ok "$(compose_tags $OFF)"
  chk "$L: disabled $OFF: no container started" 0 "$(docker ps --format '{{.Names}}' | grep -c "^$(cname $OFF)-")"
  # Stopped cron (L2-15 reading of the code: kept on the old image, started again by the cron-config step).
  info "$L: cron before: $(awk -F'\t' '$1=="services_global-cron_1"{print $2" "$4}' $D/before/containers.txt); after: $(cron_state)"
  chk "$L: stopped cron kept its old image (not recreated)" "easyengine/cron:$(otag easyengine/cron)" "$(docker inspect -f '{{.Config.Image}}' services_global-cron_1 2>&1)"
  info "$L: cron after the upgrade: state $(docker inspect -f '{{.State.Status}}' services_global-cron_1) (plan L2-15 expects running: restarted by ee-update-cron-config); 'docker restart services_global-cron_1' lines: $(grep -c 'restart services_global-cron_1' $D/ee.log.part)"
  chk "$L: services compose has cron on $(tag easyengine/cron)" 1 "$(grep -c "easyengine/cron:$(tag easyengine/cron)" /opt/easyengine/services/docker-compose.yml)"
  info "$L: options row easyengine/cron = $(db "select value from options where key='easyengine/cron'")" ;;
failed)
  info "$L: rows after the failure: sid=$(row $SID) upp=$(row $UPP) cap=$(row $CAP)"
  info "$L: sid lines p84/p85: $(sidn f4-p84.test)/$(sidn f4-p85.test); cron: $(cron_state)"
  for f in /etc/logrotate.d/rsyslog /etc/systemd/system/logrotate.timer.d/hourly.conf /etc/cron.hourly/ee-logrotate; do info "$L: $f $([ -e $f ] && echo "present maxsize=$(grep -c maxsize $f)" || echo absent)"; done
  chk "$L: disabled $OFF still has no running container" 0 "$(docker ps --format '{{.Names}}' | grep -c "^$(cname $OFF)-")" ;;
cli)
  grep -qE "[[:space:]]$OFF([[:space:]]|\$)" /etc/hosts || echo "127.0.0.1 $OFF" >> /etc/hosts
  e site enable $OFF; r=$?; sleep 3
  bad=""; for c in $(docker ps --format '{{.Names}}' | grep "^$(cname $OFF)-"); do i=$(docker inspect -f '{{.Config.Image}}' $c); case $i in easyengine/*) [ "${i#*:}" = "$(tag ${i%%:*})" ] || bad="$bad $c=$i";; esac; done
  chk "$L: enable $OFF: rc, containers on the new tags, http /" "0 ok 200" "$r ${bad:-ok} $(lcode $OFF /)"
  s0=$(cron_state)
  e service enable cron; r=$?; info "$L: ee service enable cron rc=$r: $(tail -c 200 "$O/last.out" | tr '\n' ' ')"
  info "$L: cron after service enable: $(cron_state) ($([ "$s0" = "$(cron_state)" ] && echo same || echo changed))"
  e service refresh cron; r=$?; info "$L: ee service refresh cron rc=$r: $(tail -c 200 "$O/last.out" | tr '\n' ' ')"
  info "$L: cron after service refresh: $(cron_state); options row $(db "select value from options where key='easyengine/cron'")"
  e cron list --all; chk "$L: cron list --all" 0 "$?"
  idw=$(db "select id from cron where site_url='f4-wp.test' limit 1")
  timeout 120 ee cron run-now "$idw" </dev/null > "$O/runnow.out" 2>&1; chk "$L: cron run-now of the old version's WP job" 0 "$?" ;;
*) echo "unknown mode $MODE"; exit 2 ;;
esac
exit 0
