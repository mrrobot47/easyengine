#!/bin/bash
# Fresh install (no /opt/easyengine, no DB) of the phar under test: cli info, a WP --cache and a PHP site, then checks.
# Usage (as root): fresh.sh. Env: OUT, RES, PHAR, EXPECT_VERSION. Writes PASS/FAIL/INFO lines to $RES.
set +e
cd /tmp
pass() { echo "PASS | $1 | $2" | tee -a "$RES"; }
fail() { echo "FAIL | $1 | $2" | tee -a "$RES"; }
info() { echo "INFO | $1" | tee -a "$RES"; }
chk() { local n=$1 d=$2; shift 2; if "$@"; then pass "$n" "$d"; else fail "$n" "$d"; fi; }
eq() { [ "$1" = "$2" ]; }
db() { sqlite3 /opt/easyengine/db/ee.sqlite "$1"; }
code() { curl -s -m 30 -o /dev/null -w '%{http_code}' --resolve "$1:80:127.0.0.1" "http://$1${2:-/}"; }
W="--admin-user=admin --admin-email=a@example.com --admin-pass=Adm1nPass414x"
NEW_MIGS="20261023193000_site-command_drop_deprecated_session_sid_settings.php 20261023233000_site-command_recheck_session_upload_progress.php 20261102100000_easyengine_cap_host_syslog.php"

info "arch $(uname -m); $(. /etc/os-release; echo "$PRETTY_NAME"); php $(php -r 'echo PHP_VERSION;'); docker $(docker version --format '{{.Server.Version}}')"
# --- before
chk "pre: no /opt/easyengine (fresh host)" "$(ls -d /opt/easyengine 2>&1)" eval '[ ! -e /opt/easyengine ]'
CP=$(command -v docker-compose); CSHA=$(sha256sum "$CP" | cut -d' ' -f1); CV=$(docker-compose version --short)
echo "$CP $CSHA $CV" > "$OUT/compose-before.txt"; info "compose before: $CP $CV sha256 $CSHA"
md5sum /etc/logrotate.d/rsyslog > "$OUT/rsyslog-before.md5" 2>&1; cp /etc/logrotate.d/rsyslog "$OUT/rsyslog-before" 2>/dev/null
ls -la /etc/systemd/system/logrotate.timer.d /etc/cron.hourly > "$OUT/logrotate-dropins-before.txt" 2>&1
docker images --format '{{.Repository}}:{{.Tag}}' | sort > "$OUT/images-before.txt"

# --- install + cli info
install -m 0755 "$PHAR" /usr/local/bin/ee
v=$(ee cli version 2>&1); chk "ee cli version = EE $EXPECT_VERSION" "$v" eq "$v" "EE $EXPECT_VERSION"
ee cli info > "$OUT/cli-info.out" 2> "$OUT/cli-info.err"; r=$?
cp /opt/easyengine/logs/ee.log "$OUT/ee.log.after-cli-info" 2>/dev/null
info "ee.log after cli info: $(wc -l < /opt/easyengine/logs/ee.log 2>/dev/null) lines, $(grep -c 'Pulling docker image' /opt/easyengine/logs/ee.log 2>/dev/null) image pulls, $(grep -c 'Migrating:' /opt/easyengine/logs/ee.log 2>/dev/null) Migrating lines"

cat "$OUT/cli-info.out" "$OUT/cli-info.err"
chk "ee cli info rc 0 on a fresh host" "rc=$r" eq "$r" 0
chk "cli info shows EE version $EXPECT_VERSION" "$(grep -i 'EE version' "$OUT/cli-info.out" | tr -s ' ')" grep -qiE "EE version[[:space:]|]+$EXPECT_VERSION" "$OUT/cli-info.out"
info "after cli info: /opt/easyengine $(ls /opt/easyengine 2>&1 | tr '\n' ' '); db $(ls -la /opt/easyengine/db/ee.sqlite 2>&1)"

# --- sites
start=$(date +%s)
timeout 1500 ee site create fresh-wp.test --type=wp --cache --title=freshwp $W </dev/null > "$OUT/create-wp.log" 2>&1; r=$?
tail -20 "$OUT/create-wp.log"
chk "ee site create fresh-wp.test --type=wp --cache" "rc=$r $(( $(date +%s) - start ))s" eq "$r" 0
start=$(date +%s)
timeout 900 ee site create fresh-php.test --type=php </dev/null > "$OUT/create-php.log" 2>&1; r=$?
tail -20 "$OUT/create-php.log"
chk "ee site create fresh-php.test --type=php" "rc=$r $(( $(date +%s) - start ))s" eq "$r" 0
info "first pull/arch error in output or ee.log: $(grep -hiE 'no matching manifest|exec format|Unable to pull|platform' "$OUT/create-wp.log" "$OUT/create-php.log" /opt/easyengine/logs/ee.log 2>/dev/null | head -3 | cut -c1-300 | tr '\n' ';')"
for s in fresh-wp.test fresh-php.test; do
  grep -qE "[[:space:]]$s([[:space:]]|\$)" /etc/hosts || echo "127.0.0.1 $s" >> /etc/hosts
  d=/opt/easyengine/sites/$s/app/htdocs; [ -d $d ] && { echo "marker $s" > $d/m.txt; chmod 644 $d/m.txt; }
done
sleep 3
c=$(code fresh-wp.test /); chk "fresh-wp.test / 200" "$c" eq "$c" 200
c=$(code fresh-wp.test /m.txt); chk "fresh-wp.test marker 200" "$c" eq "$c" 200
c=$(code fresh-php.test /m.txt); chk "fresh-php.test marker 200" "$c" eq "$c" 200
h1=$(curl -s -m 30 -o /dev/null -D - --resolve fresh-wp.test:80:127.0.0.1 http://fresh-wp.test/ | grep -i '^x-srcache-fetch-status' | tr -d '\r')
h2=$(curl -s -m 30 -o /dev/null -D - --resolve fresh-wp.test:80:127.0.0.1 http://fresh-wp.test/ | grep -i '^x-srcache-fetch-status' | tr -d '\r')
info "fresh-wp.test cache headers: [$h1] then [$h2]"
ee site list > "$OUT/site-list.txt" 2>&1; r=$?; cat "$OUT/site-list.txt"
chk "ee site list rc 0, both sites listed" "rc=$r" eval '[ $r = 0 ] && grep -q fresh-wp.test "$OUT/site-list.txt" && grep -q fresh-php.test "$OUT/site-list.txt"'

# --- compose untouched
CP2=$(command -v docker-compose); CSHA2=$(sha256sum "$CP2" | cut -d' ' -f1); CV2=$(docker-compose version --short)
echo "$CP2 $CSHA2 $CV2" > "$OUT/compose-after.txt"
chk "docker-compose untouched (path, sha256, version)" "$CP2 $CV2 $CSHA2" eq "$CP2 $CSHA2 $CV2" "$CP $CSHA $CV"
chk "no docker-compose backup/download left in .backup" "$(ls /opt/easyengine/.backup 2>&1 | tr '\n' ' ')" eval '[ ! -e /opt/easyengine/.backup/docker-compose.backup ] && [ ! -e /opt/easyengine/.backup/docker-compose ]'

# --- pulls and images
cp /opt/easyengine/logs/ee.log* "$OUT/" 2>/dev/null
zgrep -hoE 'docker pull [^ ]+|Pulling docker image [^ ]+|Pulling [^ ]+ \(' /opt/easyengine/logs/ee.log* 2>/dev/null | sort | uniq -c > "$OUT/pulls.txt"
info "pulls in ee.log: $(tr -s ' ' < "$OUT/pulls.txt" | tr '\n' ';')"
docker images --format '{{.Repository}}:{{.Tag}}' | sort > "$OUT/images-after.txt"
comm -13 "$OUT/images-before.txt" "$OUT/images-after.txt" > "$OUT/images-new.txt"
info "images present after: $(grep easyengine/ "$OUT/images-after.txt" | tr '\n' ' ')"
chk "no easyengine/mailhog pulled" "$(grep -c easyengine/mailhog "$OUT/images-new.txt") images, $(grep -c 'pull easyengine/mailhog' "$OUT/pulls.txt") log lines" eval '! grep -q easyengine/mailhog "$OUT/images-new.txt" && ! grep -q "easyengine/mailhog" "$OUT/pulls.txt"'
chk "no generic easyengine/php: pulled" "$(grep '^easyengine/php:' "$OUT/images-new.txt" | tr '\n' ' ')" eval '! grep -q "^easyengine/php:" "$OUT/images-new.txt" && ! grep -qE "easyengine/php:" "$OUT/pulls.txt"'
php -r 'echo file_get_contents("phar://" . $argv[1] . "/img-versions.json");' "$PHAR" > "$OUT/img-versions.json"
docker ps -a --format '{{.Names}}\t{{.Image}}\t{{.Status}}' | sort > "$OUT/containers.txt"; cat "$OUT/containers.txt"
bad=""; n=0
while IFS=$'\t' read -r name img st; do
  case $img in easyengine/*) ;; *) continue;; esac
  n=$((n+1)); want=$(jq -r --arg k "${img%%:*}" '.[$k] // "missing"' "$OUT/img-versions.json")
  [ "${img##*:}" = "$want" ] || bad="$bad $name=$img(want $want)"
  case $st in Up*) ;; *) bad="$bad $name:$st";; esac
done < "$OUT/containers.txt"
chk "$n easyengine containers up on the img-versions.json tags" "${bad:-ok}" eq "$bad" ""
for c in services_global-nginx-proxy_1 services_global-db_1 services_global-redis_1 services_global-cron_1 fresh-wptest-nginx-1 fresh-wptest-php-1 fresh-phptest-php-1; do
  info "image $c: $(docker inspect -f '{{.Config.Image}} {{.State.Status}}' $c 2>&1)"; done

# --- DB
dv=$(db "select value from options where key='version'"); chk "DB options.version = $EXPECT_VERSION" "$dv" eq "$dv" "$EXPECT_VERSION"
db "select id,migration,type from migrations order by id" > "$OUT/migrations.txt"
info "migrations rows: $(wc -l < "$OUT/migrations.txt"); duplicates: $(db "select count(*) from (select migration from migrations group by migration having count(*)>1)")"
miss=""; for m in $NEW_MIGS; do grep -q "|$m|" "$OUT/migrations.txt" || miss="$miss $m"; done
chk "the 3 new v4.14.0 migrations recorded" "${miss:-all 3 present}" eq "$miss" ""
dups=$(db "select count(*) from (select migration from migrations group by migration having count(*)>1)"); chk "no duplicate migration rows" "$dups" eq "$dups" 0
db "select key,value from options where key not in ('global-db','self-signed-secret') order by key" > "$OUT/options.txt"; info "options: $(tr '\n' ' ' < "$OUT/options.txt" | cut -c1-900)"

# --- logrotate / rsyslog (fresh install: recorded, not asserted)
md5sum /etc/logrotate.d/rsyslog > "$OUT/rsyslog-after.md5" 2>&1; cp /etc/logrotate.d/rsyslog "$OUT/rsyslog-after" 2>/dev/null
info "rsyslog rule: before $(cut -c1-12 "$OUT/rsyslog-before.md5") after $(cut -c1-12 "$OUT/rsyslog-after.md5"); maxsize lines after: $(grep -c maxsize /etc/logrotate.d/rsyslog 2>/dev/null)"
ls -la /etc/systemd/system/logrotate.timer.d /etc/cron.hourly > "$OUT/logrotate-dropins-after.txt" 2>&1
info "logrotate drop-ins after: $(ls /etc/systemd/system/logrotate.timer.d 2>/dev/null | tr '\n' ' ') cron.hourly: $(ls /etc/cron.hourly 2>/dev/null | tr '\n' ' ')"
info "EE logrotate rules: $(ls /etc/logrotate.d | grep -i ee | tr '\n' ' '); .backup/logrotate: $(ls /opt/easyengine/.backup/logrotate 2>&1 | tr '\n' ' ')"
info "logs dir: $(stat -c '%a %U' /opt/easyengine/logs) files: $(stat -c '%a %n' /opt/easyengine/logs/* | tr '\n' ' ')"
grep -iE 'warning|error' "$OUT/create-wp.log" "$OUT/create-php.log" "$OUT/cli-info.err" | head -20 > "$OUT/warnings.txt"
info "warnings/errors in command output: $(wc -l < "$OUT/warnings.txt") ($(head -5 "$OUT/warnings.txt" | cut -c1-200 | tr '\n' ';'))"
exit 0
