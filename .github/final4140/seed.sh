#!/bin/bash
# Seeds, with the installed OLD ee (4.13.3), the states the 4.14.0 upgrade acts on and records their baseline: a disabled site, a stopped global cron, sid/upload-progress lines, host logrotate files. Usage: seed.sh
. "$(dirname "$0")/lib.sh"; cd /tmp; O=$OUTDIR/seed; mkdir -p "$O"; : > "$O/cmds.txt"
e() { ee "$@" </dev/null > "$O/last.out" 2>&1; local r=$?; { echo "rc=$r ee $*"; cat "$O/last.out"; } >> "$O/cmds.txt"; return $r; }

# Sid settings in php.ini (8.4/8.5 drop them; 8.3 is the control) and upload-progress lines in custom.ini, per site.
for s in $PHPSITES $OFF; do d=/opt/easyengine/sites/$s/config/php
  echo "$s sid=$(grep -cE '^\s*session\.sid_(length|bits_per_character)\s*=' $d/php/php.ini 2>/dev/null) upoff=$(grep -chE '^\s*session\.upload_progress\.enabled\s*=\s*Off' $d/php/conf.d/custom.ini 2>/dev/null)"; done | tee "$O/php-ini.txt"
chk "seed: php8.4/8.5 sites carry sid lines on 4.13.3 (precheck)" "[1-9][0-9]* [1-9][0-9]*" "$(grep -oP '^f4-p84.test sid=\K[0-9]+' "$O/php-ini.txt") $(grep -oP '^f4-p85.test sid=\K[0-9]+' "$O/php-ini.txt")"

# Host logrotate state before the upgrade.
for f in /etc/logrotate.d/rsyslog /etc/logrotate.d/syslog /etc/systemd/system/logrotate.timer.d/hourly.conf /etc/cron.hourly/ee-logrotate /etc/logrotate.d/ee_cli /etc/logrotate.d/ee_sites /etc/logrotate.d/ee_nginx_proxy; do
  if [ -e $f ]; then echo "$f $(md5sum < $f | cut -c1-32) maxsize=$(grep -c maxsize $f)"; cp $f "$O/$(echo $f | tr / _)"; else echo "$f absent"; fi; done | tee "$O/logrotate.txt"
systemctl cat logrotate.timer > "$O/logrotate-timer.txt" 2>&1; dpkg -l rsyslog logrotate 2>&1 | tail -2 >> "$O/logrotate.txt"

# Disabled site: its compose file should get the new tags, its containers stay down until enabled.
e site disable $OFF; chk "seed: site disable $OFF" 0 "$?"
chk "seed: $OFF has no running container" 0 "$(docker ps --format '{{.Names}}' | grep -c "^$(cname $OFF)-")"

# Stopped global cron (L2-15 shape). 4.13.3's `service disable` only knows nginx-proxy/db/redis/newrelic-daemon.
if e service disable cron; then info "seed: cron stopped with ee service disable cron"; else docker stop services_global-cron_1 > /dev/null; info "seed: ee service disable cron refused ($(head -c 100 "$O/last.out" | tr '\n' ' ')); stopped with docker stop"; fi
sleep 2
chk "seed: global cron stopped on its old tag" "exited easyengine/cron:v4\.11\.0" "$(docker inspect -f '{{.State.Status}} {{.Config.Image}}' services_global-cron_1 2>&1)"
exit 0
