#!/bin/bash
# CI-09 variants on a populated 4.13.3 install. Usage: variant.sh hestia|reqfn <phar>
# hestia: HestiaCP's CLI disable_functions (pcntl_*) during and after the upgrade; site commands must work.
# reqfn:  required functions disabled (symlink, disk_free_space): the update succeeds but the migration is deferred, commands are refused until fixed, then it migrates once.
. "$(dirname "$0")/lib.sh"; MODE=$1; NEW=$2; L=$MODE; cd /tmp; O=$OUTDIR/variant-$MODE; mkdir -p "$O"
HESTIA="pcntl_alarm,pcntl_fork,pcntl_waitpid,pcntl_wait,pcntl_wifexited,pcntl_wifstopped,pcntl_wifsignaled,pcntl_wifcontinued,pcntl_wexitstatus,pcntl_wtermsig,pcntl_wstopsig,pcntl_signal,pcntl_signal_dispatch,pcntl_get_last_error,pcntl_strerror,pcntl_sigprocmask,pcntl_sigwaitinfo,pcntl_sigtimedwait,pcntl_exec,pcntl_getpriority,pcntl_setpriority"
SCAN=$(php -r 'echo PHP_CONFIG_FILE_SCAN_DIR;'); INI=$SCAN/50-panel.ini
e() { ee "$@" </dev/null > "$O/last.out" 2>&1; local r=$?; { echo "rc=$r ee $*"; cat "$O/last.out"; } >> "$O/cmds.txt"; return $r; }
ver() { db "select value from options where key='version'"; }
NEWROWS="20261023193000_site-command_drop_deprecated_session_sid_settings.php 20261023233000_site-command_recheck_session_upload_progress.php 20261102100000_easyengine_cap_host_syslog.php"
rows_once() { local n r=""; for n in $NEWROWS; do r="$r $(db "select count(*) from migrations where migration='$n'")"; done; echo $r; }
sites200() { local s bad=""; for s in $ALL; do [ $s = f4-ssl.test ] && continue; c=$(lcode $s /f4-marker.txt); [ "$c" = 200 ] || bad="$bad $s=$c"; done; echo "${bad:-ok}"; }

case $MODE in
hestia)
  echo "disable_functions = $HESTIA" > $INI; info "$L: $INI written (php --ini scan dir $SCAN)"
  php -r 'echo ini_get("disable_functions");' | cut -c1-60 > "$O/df.txt"; info "$L: CLI disable_functions now: $(cat "$O/df.txt")..."
  bash $F/upgrade.sh "$O/upgrade" "$NEW"
  chk "$L: upgrade rc, version, phar" "0 $NEW_VERSION $NEW_MD5" "$(cat "$O/upgrade/rc.txt") $(ver) $(md5sum < /usr/local/bin/ee | cut -c1-32)"
  chk "$L: no 'Call to undefined function' during the upgrade" 0 "$(cat "$O/upgrade/cliinfo.out" "$O/upgrade/cliinfo.err" "$O/upgrade/ee.log.part" | grep -c 'Call to undefined function')"
  chk "$L: the 3 new rows once" "1 1 1" "$(rows_once)"
  chk "$L: sites serve after the upgrade" ok "$(sites200)"
  e cli info; r=$?; chk "$L: cli info rc 0" 0 "$r"; info "$L: cli info PHP rows: $(grep -iE 'php|requirement|optional' "$O/last.out" | tr '\n' ' ' | cut -c1-300)"
  e site list; chk "$L: site list" 0 "$?"
  e site info f4-wp.test; chk "$L: site info f4-wp.test" 0 "$?"
  echo "127.0.0.1 f4-hes.test" >> /etc/hosts
  e --debug site create f4-hes.test --type=wp --title=hes --admin-user=admin --admin-email=a@example.com; r=$?
  chk "$L: site create wp: rc, http, no undefined-function" "0 200 0" "$r $(lcode f4-hes.test /) $(grep -c 'Call to undefined function' "$O/cmds.txt")"
  info "$L: debug lines about signals/pcntl in site create: $(grep -iE 'pcntl|signal' "$O/last.out" | head -3 | tr '\n' ' ' | cut -c1-300)"
  e site update f4-hes.test --ssl=self; chk "$L: site update --ssl=self" 0 "$?"
  e site update f4-hes.test --php=8.3; chk "$L: site update --php=8.3 (from the default 8.4)" 0 "$?"
  e site disable f4-hes.test; r1=$?; e site enable f4-hes.test; r2=$?; chk "$L: site disable/enable" "0 0" "$r1 $r2"
  e site delete f4-hes.test --yes; chk "$L: site delete" 0 "$?"
  chk "$L: no 'Call to undefined function' in any command" 0 "$(grep -c 'Call to undefined function' "$O/cmds.txt")"
  rm -f $INI ;;
reqfn)
  echo "disable_functions = symlink,disk_free_space" > $INI; info "$L: $INI written"
  bash $F/upgrade.sh "$O/upgrade" "$NEW"
  cat "$O/upgrade/cliinfo.out" "$O/upgrade/cliinfo.err" > "$O/update-output.txt"
  chk "$L: update succeeds (cli info rc 0, phar replaced) but the migration is deferred" "0 $NEW_MD5 $OLD_VERSION" "$(cat "$O/upgrade/rc.txt") $(md5sum < /usr/local/bin/ee | cut -c1-32) $(ver)"
  chk "$L: no migration step ran during the update" 0 "$(grep -c 'Executing ee-' "$O/upgrade/ee.log.part")"
  info "$L: update output: $(grep -iE 'warning|error|disabled|symlink' "$O/update-output.txt" | head -3 | tr '\n' ' ' | cut -c1-400)"
  e site list; r=$?
  chk "$L: site list refused: rc, names both functions, names the ini file" "1 1 1" "$r $(grep -c 'symlink' "$O/last.out" | sed 's/^[1-9][0-9]*$/1/') $(grep -c '50-panel.ini' "$O/last.out" | sed 's/^[1-9][0-9]*$/1/')"
  info "$L: refusal: $(head -c 500 "$O/last.out" | tr '\n' ' ')"
  chk "$L: still $OLD_VERSION, no new rows after the refusal" "$OLD_VERSION 0 0 0" "$(ver) $(rows_once)"
  chk "$L: sites still serve" ok "$(sites200)"
  rm -f $INI; mk=$(eelog_mark)
  e site list; r=$?
  eelog_since "$mk" > "$O/fix-ee.log.part"
  chk "$L: after the fix: site list rc, version, rows once, no duplicate rows" "0 $NEW_VERSION 1 1 1 0" "$r $(ver) $(rows_once) $(db "select count(*) from (select migration from migrations group by migration having count(*) > 1)")"
  chk "$L: the migration ran once (image migration step)" 1 "$(grep -c 'Executing ee-docker-image-migrations' "$O/fix-ee.log.part")"
  mk=$(eelog_mark); e site list; r=$?; chk "$L: next command: no re-migration" "0 0" "$r $(eelog_since "$mk" | grep -c 'Executing ee-')"
  sleep 5; chk "$L: sites serve after the deferred migration" ok "$(sites200)"
  info "$L: images in use after: $(docker ps --format '{{.Image}}' | grep easyengine/ | sort -u | tr '\n' ' ')" ;;
*) echo "unknown mode"; exit 2 ;;
esac
exit 0
