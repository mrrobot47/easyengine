# shellcheck shell=bash
# php-compat extensive matrix (v4.16.0, 2026-11-24): shared helpers, sourced. Every check prints PASS/FAIL/INFO to $RES; expectations are what a user wants.
export LC_ALL=C
F=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
SITES_DIR=/opt/easyengine/sites
EE_LOG=/opt/easyengine/logs/ee.log
SC=easyengine/compat-scanner
W="--admin-user=admin --admin-email=a@example.com --admin-pass=Adm1nPass4160pc"
db() { sqlite3 /opt/easyengine/db/ee.sqlite "$@"; }
cname() { echo "$1" | tr -d .; }
chk() { local r=FAIL; [[ "$3" =~ ^($2)$ ]] && r=PASS; echo "$r | $1 | exp $2 | got $3" | tee -a "${RES:-/dev/null}"; }
has() { local r=FAIL; [[ "$3" == *"$2"* ]] && r=PASS; echo "$r | $1 | exp contains [$2] | got $(echo "$3" | tr '\n' ' ' | cut -c1-300)" | tee -a "${RES:-/dev/null}"; }
eqs() { local r=FAIL; [ "$2" = "$3" ] && r=PASS; echo "$r | $1 | exp $2 | got $3" | tee -a "${RES:-/dev/null}"; }
info() { echo "INFO | $*" | tee -a "${RES:-/dev/null}"; }
one() { tr -d '\r' | sed '/^$/d' | tail -1; }
# run_ee <label> <args...>: ee with output kept in $D/<label>.out; sets RC.
run_ee() { local l=$1; shift; (cd /tmp && ee "$@") < /dev/null > "$D/$l.out" 2>&1; RC=$?; echo "rc=$RC" >> "$D/$l.out"; info "ran: ee $* -> rc $RC"; }
wpx() { (cd "$SITES_DIR/$1" && docker-compose exec -T --user=www-data php sh -c "wp $2"); }
# Canary: 2 PHPCompatibility errors for any target >= 8.0 (create_function, each).
CANARY='<?php
/*
Plugin Name: PCM Canary
Version: 1.0
*/
$pcm_f = create_function( "", "return 1;" );
each( $pcm_a );
'
# plant <host path of file>: write the canary (dirs created, owned 33:33, readable).
plant() { mkdir -p "$(dirname "$1")"; printf '%s' "$CANARY" > "$1"; chown 33:33 "$(dirname "$1")" "$1"; chmod 755 "$(dirname "$1")"; chmod 644 "$1"; }
# rec <label> <site>: DB site_container_fs_path, nginx root, wp-cli.yml, htdocs listing; prints the DB value.
rec() { local l=$1 s=$2 dbv root yml
  dbv=$(db "select site_container_fs_path from sites where site_url='$s'")
  root=$(grep -rhoE 'root\s+/var/www[^;]*' "$SITES_DIR/$s/config/nginx/" 2>/dev/null | sort -u | awk '{print $2}' | tr '\n' ',')
  yml=$(cat "$SITES_DIR/$s/app/htdocs/wp-cli.yml" 2>/dev/null | tr '\n' ' ')
  echo "REC | $l | $s | db=$dbv | nginx_root=$root | wp-cli.yml=[$yml] | enabled=$(db "select site_enabled from sites where site_url='$s'") | htdocs=[$(ls -A "$SITES_DIR/$s/app/htdocs" 2>/dev/null | tr '\n' ' ')] | wp-content dirs=[$(cd "$SITES_DIR/$s/app/htdocs" 2>/dev/null && find -L . -maxdepth 4 -type d -name wp-content 2>/dev/null | tr '\n' ' ')]" | tee -a "${RES:-/dev/null}" >&2
  echo "$dbv"; }
# pcs <label> <site> [extra args]: scan, json, --debug, --output to $D/<label>.report.json (PCV = target, default 8.4).
# Sets RC ST SAFE ERRS FC NC ARGP (argv[3] of the docker run) and CAN (canary errors in the report, by file name in $CANF).
# --output must sit in a root-only directory ($D is under the runner's home): written to /root/pcm-out, then copied.
pcs() { local l=$1 s=$2 R=/root/pcm-out; shift 2; install -d -m 0700 $R; rm -f "$D/$l.report.json" "$R/$l.report.json"
  (cd /tmp && ee --debug site php-compat "$s" --php="${PCV:-8.4}" --format=json --output="$R/$l.report.json" "$@") < /dev/null > "$D/$l.out" 2> "$D/$l.err"; RC=$?
  [ -f "$R/$l.report.json" ] && cp "$R/$l.report.json" "$D/$l.report.json"
  ST=$(jq -r .status "$D/$l.out" 2>/dev/null | tail -1); SAFE=$(jq -r .safe_to_upgrade "$D/$l.out" 2>/dev/null | tail -1)
  ERRS=$(jq -r .errors "$D/$l.out" 2>/dev/null | tail -1); FC=$(jq -r .files_checked "$D/$l.out" 2>/dev/null | tail -1); NC=$(jq -r .files_not_checked "$D/$l.out" 2>/dev/null | tail -1)
  ARGP=$(grep -o "'scan' '[a-z]*' '[^']*'" "$D/$l.err" | tail -1 | awk -F"'" '{print $6}')
  CAN=$(canary "$l" "${CANF:-pcm-canary.php}")
  # --output report carries the same verdict and keys as stdout (lists aside: stdout caps not_checked at 10)
  if [ -s "$D/$l.report.json" ]; then local d; d=$(jq -rn --slurpfile o <(grep -a '^{' "$D/$l.out" | tail -1) --slurpfile r "$D/$l.report.json" '[$o[0] | to_entries[] | select(.key | IN("not_checked","not_checked_more","report","report_bytes","components") | not) | select($r[0][.key] != .value) | .key] | join(",")' 2>&1)
    chk "$l: --output report = stdout (keys outside the lists)" '' "$d"; fi
  echo "SCAN | $l | $s | rc=$RC status=$ST safe=$SAFE errors=$ERRS checked=$FC not_checked=$NC argv_path=$ARGP canary_errors=$CAN | $(head -c 300 "$D/$l.out" | tr '\n' ' ')" | tee -a "${RES:-/dev/null}"; }
canary() { [ -f "$D/$1.report.json" ] || { echo 0; return; }; jq -r --arg f "$2" '[.components[]?.findings[]? | select(.file|endswith($f)) | select(.type=="ERROR")] | length' "$D/$1.report.json" 2>/dev/null || echo err; }
# pce <label> <site>: estimate, json. Sets EST_ST EST_FILES EST_BYTES.
pce() { local l=$1 s=$2; (cd /tmp && ee site php-compat "$s" --php="${PCV:-8.4}" --estimate --format=json) < /dev/null > "$D/$l.out" 2> "$D/$l.err"
  EST_ST=$(jq -r .status "$D/$l.out" 2>/dev/null | tail -1); EST_FILES=$(jq -r .php_files "$D/$l.out" 2>/dev/null | tail -1); EST_BYTES=$(jq -r .php_bytes "$D/$l.out" 2>/dev/null | tail -1)
  echo "EST | $l | $s | status=$EST_ST php_files=$EST_FILES php_bytes=$EST_BYTES" | tee -a "${RES:-/dev/null}"; }
# expect_found <label> <site> <expected argv path regex>: the canary is found (status ok, safe false, canary 2 errors) and the scanner got the WordPress dir.
expect_found() { local l=$1 s=$2 p=$3; pcs "$l" "$s"
  chk "$l: $s php-compat status/safe" 'ok false' "$ST $SAFE"
  chk "$l: $s canary errors in report" '[2-9]|[1-9][0-9]+' "$CAN"
  [ -n "$p" ] && chk "$l: $s scanner path (argv)" "$p" "$ARGP"
  pce "$l-est" "$s"; chk "$l: $s estimate php_files = scan checked + not_checked" "$(( ${FC:-0} + ${NC:-0} ))" "$EST_FILES"; }
# upgrade_to <phar>: what ee cli update does after its download (cli info with the new phar, then replace).
upgrade_to() { local T=/tmp/ee_up.phar; cp "$1" $T; php $T cli info > "$D/upgrade-cliinfo.out" 2>&1; local rc=$?
  info "upgrade: php new.phar cli info rc $rc; $(tail -3 "$D/upgrade-cliinfo.out" | tr '\n' ' ')"
  [ $rc -eq 0 ] && install -m 0755 $T /usr/local/bin/ee; chk "upgrade: ee cli version after" "EE ${NEW_VERSION:-4.16.0}" "$(ee cli version 2>&1 | one)"; }
# expect_guard <label> <site>: a layout the scanner can't cover (v3.11.1: WP_CONTENT_DIR/WP_PLUGIN_DIR/Bedrock) must find the canary or refuse with
# tool_error; never "safe" and never no_code_found.
expect_guard() { local l=$1 s=$2; pcs "$l" "$s"
  chk "$l: $s never safe/no_code_found (ok+canary or tool_error)" 'ok false [2-9]|tool_error null 0' "$ST $SAFE $CAN"
  info "$l detail: $(jq -r '.detail // empty' "$D/$l.out" 2>/dev/null | tail -1); table: $(cd /tmp && ee site php-compat "$s" --php=8.4 < /dev/null 2>&1 | head -1)"; }
# reload_scanner: put the PR-built scanner (DF_REF) back as the pinned tag after something removed or replaced it (prune, rmi, a pull).
reload_scanner() { [ -f /var/tmp/pcm-scanner.tar.gz ] || return 0; gunzip -c /var/tmp/pcm-scanner.tar.gz | docker load > /dev/null
  info "scanner reloaded from the PR build: $(docker images --format '{{.Repository}}:{{.Tag}} {{.ID}}' $SC | tr '\n' ' ')"; }
