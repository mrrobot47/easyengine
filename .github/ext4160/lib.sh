# shellcheck shell=bash
# Shared settings for the v4.16.0 extended coverage (copy of Lane A's lib.sh: old stable -> release phar; failure paths, disabled sites, PHP 5.6-8.0, older stables; sourced). Expected values are derived per job from the DB, the phars and the compose files.
export LC_ALL=C
F=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# Population: the same sites on every path (old stable or, with OLD_VERSION=fresh, the release itself). 4.14.0 has no PHP 8.6, so W86 exists only on the other paths.
W81=u6-wp81.test; W82=u6-wp82.test; MUD=u6-mud.test; W83=u6-wp83.test; W84=u6-wp84.test; K84=u6-key84.test; W85=u6-wp85.test; W86=u6-wp86.test
SW=u6-sw.test; PHPS=u6-php.test; PHPA=u6-phpalias.test; HTML=u6-html.test; HTMLA=u6-htmlalias.test; LDB=u6-ldb.test
# Created by rel.sh on the release: PCX (php, 5,000-file fixture for php-compat --cancel) and, on the 4.14.0 path, N86 (the 8.6 site).
PCX=u6-pcx.test; N86=u6-new86.test
# Only 4.15.0 and the release have PHP 8.6.
case ${OLD_VERSION:-} in 4.15.0|fresh) HAS86=1 ;; *) HAS86= ;; esac
# Fake New Relic license (40 chars, not a real key): the agent loads and reaches the daemon, the collector rejects it.
NRKEY=0123456789abcdef0123456789abcdef01234567
WPS="$W81 $W82 $MUD $W83 $W84 $K84 $W85 ${HAS86:+$W86 }$SW $LDB"
ENABLED="$W81 $W82 $MUD $W83 $W84 $K84 $W85 ${HAS86:+$W86 }$SW $PHPS $HTML $LDB"
DISS=
# Extended scenarios. Disabled before the upgrade (dis.sh): wp 8.1-8.6 (8.2-8.4 with a New Relic key), html, a php site, and layout sites:
# a php --public-dir site, a wp CI/CD-style `current -> releases/1` site and a wp site with WordPress in its own wp/ subdirectory.
D81=u6-d81.test; D82=u6-d82.test; D83=u6-d83.test; D84=u6-d84.test; D85=u6-d85.test; D86=u6-d86.test; DH=u6-dhtml.test; DP=u6-dphp.test
DPP=u6-dpubphp.test; DCUR=u6-dcur.test; DSUB=u6-dsub.test
DIS_WPS="$D81 $D82 $D83 $D84 $D85 $D86 $DCUR $DSUB"; DIS_ALL="$DIS_WPS $DH $DP $DPP"
# PHP 5.6-8.0 sites (legacy.sh): php type on each version, wp on 7.4 and 8.0; layout sites (8.4): wp --public-dir, php --public-dir
# (one level and nested), wp `current -> releases/1`, wp in a wp/ subdirectory.
L56=u6-l56.test; L70=u6-l70.test; L72=u6-l72.test; L73=u6-l73.test; L74=u6-l74.test; L80=u6-l80.test; LW74=u6-lw74.test; LW80=u6-lw80.test
LPW=u6-lpubwp.test; LPP=u6-lpubphp.test; LPN=u6-lpubnest.test; LCUR=u6-lcur.test; LSUB=u6-lsub.test
LEG_PHP="$L56:5.6 $L70:7.0 $L72:7.2 $L73:7.3 $L74:7.4 $L80:8.0"; LEG_WPS="$LW74 $LW80 $LPW $LCUR $LSUB"; LEG_ALL="$L56 $L70 $L72 $L73 $L74 $L80 $LW74 $LW80 $LPW $LPP $LPN $LCUR $LSUB"
# Layout sites are rearranged by layout.sh after create.
# plugfix <site> <wp-content dir relative to app/htdocs>: the php-compat legacy plugin fixture (create_function, each: 2 errors on PHP >= 8.0).
plugfix() { local d=$SITES_DIR/$1/app/htdocs/$2/plugins/u6-legacy; mkdir -p $d
  printf '<?php\n/*\nPlugin Name: U6 Legacy\nVersion: 1.0\n*/\n$f = create_function( %s, %s );\neach( $a );\n' "''" "'return 1;'" > $d/u6-legacy.php
  chown -R 33:33 $d; chmod 755 $d; chmod 644 $d/u6-legacy.php; }
# pcfix <label> <site> <outfile>: php-compat --php=8.5 json of a layout site with the fixture: ok, 2+ errors (the fixture was scanned).
pcfix() { local L=$1 s=$2 o=$3; ee site php-compat $s --php=8.5 --format=json < /dev/null > $o 2> $o.err
  chk "$L: php-compat $s --php=8.5 rc" 0 "$?"
  info "$L: php-compat $s: $(jq -c 'del(.tool)' $o 2>&1 | cut -c1-300) $(head -c 200 $o.err)"
  eqs "$L: php-compat $s status/safe" "ok false" "$(jq -r '"\(.status) \(.safe_to_upgrade)"' $o 2>&1 | tail -1)"
  chk "$L: php-compat $s errors (the fixture plugin/file was scanned)" '[2-9]|[1-9][0-9]+' "$(jq -r .errors $o 2>&1 | tail -1)"; }
# WP sites outside the Lane A population that add a cron row each (checks.sh counts cron rows): set per scenario.
case ${SCEN:-} in disabled) XWPS=$DIS_WPS ;; legacy) XWPS=$LEG_WPS ;; *) XWPS= ;; esac
# Every URL that must answer 200: sites, the multisite subsite, aliases (host path).
URLS="$W81 / $W82 / $MUD / $MUD /sub1/ $W83 / $W84 / $K84 / $W85 / ${HAS86:+$W86 / }$SW / $PHPS / $PHPA / $HTML / $HTMLA / $LDB /"
PROXY=services_global-nginx-proxy_1
REDIS=services_global-redis_1
EE_LOG=/opt/easyengine/logs/ee.log
SITES_DIR=/opt/easyengine/sites
STOP=/tmp/u6-stop-probe
W="--admin-user=admin --admin-email=a@example.com --admin-pass=Adm1nPass4160u"
ts() { date -u +%T.%N | cut -c1-12; }
db() { sqlite3 /opt/easyengine/db/ee.sqlite "$@"; }
cname() { echo "$1" | tr -d .; }
phpc() { echo "$(cname "$1")-php-1"; }
# chk <label> <expected-regex> <actual>
chk() { local r=FAIL; [[ "$3" =~ ^($2)$ ]] && r=PASS; echo "$r | $1 | exp $2 | got $3" | tee -a "${RES:-/dev/null}"; }
# has <label> <fixed substring> <text>: PASS when the text contains the substring.
has() { local r=FAIL; [[ "$3" == *"$2"* ]] && r=PASS; echo "$r | $1 | exp contains [$2] | got $(echo "$3" | tr '\n' ' ' | cut -c1-300)" | tee -a "${RES:-/dev/null}"; }
# eqs <label> <expected literal> <actual>
eqs() { local r=FAIL; [ "$2" = "$3" ] && r=PASS; echo "$r | $1 | exp $2 | got $3" | tee -a "${RES:-/dev/null}"; }
info() { echo "INFO | $*" | tee -a "${RES:-/dev/null}"; }
done_mark() { echo "DONE $1" >> "$OUT/done.txt"; }
hcode() { curl -s -m 20 -o /dev/null -w '%{http_code}' --resolve "$1:80:127.0.0.1" "http://$1${2:-/}"; }
hbody() { curl -s -m 20 --resolve "$1:80:127.0.0.1" "http://$1${2:-/}"; }
# HTTP code after up to 20 s of retries (proxy and fpm may lag a freshly started site); the wait is logged.
hwait() { local s=$1 p=${2:-/} i c; for i in $(seq 0 20); do c=$(hcode $s $p); [ "$c" = 200 ] && break; sleep 1; done
  [ $i -gt 0 ] && info "$s $p took ${i} s of retries (last $c)" >&2; echo $c; }
# wpx <site> <wp args as one string>: WP-CLI as www-data in the site's php service (as the Behat suites do).
wpx() { (cd "$SITES_DIR/$1" && docker-compose exec -T --user=www-data php sh -c "wp $2"); }
# A known, user-pending issue: recorded as KNOWN (PASS when clean), never counted as a FAIL.
known() { local r=KNOWN; [[ "$3" =~ ^($2)$ ]] && r=PASS; echo "$r | $1 | exp $2 | got $3" | tee -a "${RES:-/dev/null}"; }
tag() { jq -r --arg r "$1" '.[$r] // "none"' "${2:-$IMG_JSON}"; }
re() { echo "$1" | sed 's/[.]/\\./g'; }
# Load-warning lines in php -v / php-fpm -t output: failed or duplicate extension loads, startup warnings.
WARN_RE='Unable to load dynamic library|already loaded|PHP (Warning|Notice|Deprecated|Fatal error|Startup)|^(Warning|Deprecated|Notice):'
# php_line <site> <dir>: "<image> <PHP_VERSION> fpm-t=<rc> warn=<load-warning lines in php -v + php-fpm -t>"; raw output and module lists kept in <dir>.
php_line() { local s=$1 D=$2 c r v; c=$(phpc $s)
  docker exec $c php -v > $D/php-v-$s.txt 2>&1
  docker exec $c php-fpm -t > $D/fpm-t-$s.txt 2>&1; r=$?
  docker exec $c php -m 2>/dev/null | sed -e '/^\[/d' -e '/^$/d' | sort -u > $D/mods-cli-$s.txt
  docker exec $c php-fpm -m 2>/dev/null | sed -e '/^\[/d' -e '/^$/d' | sort -u > $D/mods-fpm-$s.txt
  v=$(docker exec $c php -r 'echo "V=", PHP_VERSION, "\n";' 2>/dev/null | sed -n 's/^.*V=//p' | tail -1)
  echo "$(docker inspect -f '{{.Config.Image}}' $c 2>&1) ${v:-none} fpm-t=$r warn=$(cat $D/php-v-$s.txt $D/fpm-t-$s.txt | grep -cE "$WARN_RE")"; }
# Probe pages: FPM-side facts (CLI ini differs: opcache is off in the CLI) and a session counter.
put_probes() { local s=$1 d=$SITES_DIR/$1/app/htdocs
  cat > $d/f50-ini.php <<'PHP'
<?php header('Content-Type: text/plain');
if (isset($_GET['k'])) { echo var_export(ini_get($_GET['k']), true); exit; }
$o = function_exists('opcache_get_status') ? @opcache_get_status(false) : false;
echo PHP_SAPI, ' ', PHP_VERSION, ' opcache=', is_array($o) ? var_export($o['opcache_enabled'], true) : 'none';
PHP
  cat > $d/f50-session.php <<'PHP'
<?php session_start(); $_SESSION['n'] = ($_SESSION['n'] ?? 0) + 1;
echo session_id(), ' ', $_SESSION['n'], ' ', PHP_VERSION, ' ', ini_get('session.save_handler'), ' ', session_save_path(), ' samesite=', ini_get('session.cookie_samesite');
PHP
  cat > $d/f51-imagick.php <<'PHP'
<?php header('Content-Type: text/plain'); echo PHP_SAPI, ' ', var_export(phpversion('imagick'), true);
PHP
  chmod 644 $d/f50-ini.php $d/f50-session.php $d/f51-imagick.php; }
fpm() { hbody $1 "/f50-ini.php?${2:-x=1}&t=$(date +%s%N)"; }
# sess_rt <label> <site> <dir>: two requests with one cookie jar: counter 1 then 2, same id.
sess_rt() { local L=$1 s=$2 D=$3 J a b id1 n1 id2 n2; J=$D/session-$s.jar; rm -f $J
  a=$(curl -s -m 20 -c $J -b $J --resolve "$s:80:127.0.0.1" "http://$s/f50-session.php"); b=$(curl -s -m 20 -c $J -b $J --resolve "$s:80:127.0.0.1" "http://$s/f50-session.php")
  read -r id1 n1 _ <<< "$a"; read -r id2 n2 _ <<< "$b"
  chk "$L: $s session round trip (counter 1 then 2, same id)" "1 2 same" "$n1 $n2 $([ -n "$id1" ] && [ "$id1" = "$id2" ] && echo same || echo "differ[$id1/$id2]")"
  info "$L: $s session page: $b"; }
# objcache <label> <site>: phpredis loaded, WP uses the external object cache, a fresh key survives into a second process and lands in the global redis.
objcache() { local L=$1 s=$2 v; v=f50-$L-$(date +%s%N)
  chk "$L: $s class_exists('Redis')" 'bool\(true\)' "$(wpx $s "eval 'var_dump(class_exists(\"Redis\"));'" 2>&1 | tr -d '\r' | tail -1)"
  chk "$L: $s wp_using_ext_object_cache()" 'bool\(true\)' "$(wpx $s "eval 'var_dump(wp_using_ext_object_cache());'" 2>&1 | tr -d '\r' | tail -1)"
  wpx $s "cache set f50probe $v f50 600" > /dev/null 2>&1
  chk "$L: $s wp cache get (second process) returns the value just set" "$v" "$(wpx $s 'cache get f50probe f50' 2>&1 | tr -d '\r' | tail -1)"
  chk "$L: global redis holds the object-cache key ${s}_obj:*f50probe" '[1-9][0-9]*' "$(docker exec $REDIS sh -c "redis-cli --scan --pattern '${s}_obj:*f50probe' | wc -l" 2>&1 | tr -d '\r' | tail -1)"; }
# pagecache <label> <site>: drop the site's page keys, then expect MISS -> HIT.
srch() { curl -s -m 20 -D - -o /dev/null --resolve "$1:80:127.0.0.1" "http://$1$2" | tr -d '\r' | awk 'tolower($1)=="x-srcache-fetch-status:"{print $2}'; }
pagecache() { local L=$1 s=$2 first hit i
  docker exec $REDIS sh -c "redis-cli --scan --pattern '${s}_page:*' | xargs -r redis-cli del" > /dev/null 2>&1
  first=$(srch $s /); hit=; for i in $(seq 1 20); do hit=$(srch $s /); [ "$hit" = HIT ] && break; sleep 1; done
  info "$L: $s page cache first fetch after clearing: ${first:-<no header>}"
  chk "$L: $s page cache X-SRCache-Fetch-Status HIT within 20 s" HIT "$hit"; }
# PHP_EXPECT "8.2=8.2.36 ..." -> PE[8.2]=8.2.36
declare -A PE; for kv in ${PHP_EXPECT:-}; do PE[${kv%%=*}]=${kv#*=}; done
pe() { local p=${PE[$1]:-$1.[0-9]+}; echo "${p//./\\.}"; }
# site_ok <label> <site> <minor> [db php_version]: DB value, compose image, running image + PHP at core's tag, php-fpm -t, no load warnings, HTTP 200.
site_ok() { local L=$1 s=$2 mm=$3 dbv=${4:-$3} D=$OUT/sites img v fpm wn t; mkdir -p $D; t=$(tag easyengine/php$mm)
  chk "$L: $s sites.php_version" "$(re "$dbv")" "$(db "select php_version from sites where site_url='$s'")"
  chk "$L: $s compose php image" "easyengine/php$(re "$mm"):$(re "$t")" "$(grep -oE 'easyengine/php[0-9.]*:v[0-9.]+' $SITES_DIR/$s/docker-compose.yml | sort -u | tr '\n' ' ' | sed 's/ $//')"
  read -r img v fpm wn <<< "$(php_line $s $D)"
  chk "$L: $s php image + PHP" "easyengine/php$(re "$mm"):$(re "$t") $(pe $mm)" "$img $v"
  chk "$L: $s php-fpm -t" fpm-t=0 "$fpm"
  chk "$L: $s no load warnings in php -v / php-fpm -t" warn=0 "$wn"
  [ "$wn" = warn=0 ] || grep -hE "$WARN_RE" $D/php-v-$s.txt $D/fpm-t-$s.txt | sort -u | head -5 | while read -r l; do info "$L: $s: $l"; done
  chk "$L: $s / HTTP" 200 "$(hwait $s)"; }
# leftovers <site>: nothing of a site that must not exist (dir, DB row, containers, /etc/hosts line).
leftovers() { local s=$1 n; n=$(cname $s)
  echo "dir=$([ -e $SITES_DIR/$s ] && echo yes || echo no) db=$(db "select count(*) from sites where site_url='$s'") containers=$(docker ps -a --format '{{.Names}}' | grep -c "^$n-") hosts=$(grep -cw "$s" /etc/hosts)"; }
NOLEFT='dir=no db=0 containers=0 hosts=0'
# ee.log since a mark (ee-setup-logrotate may rename ee.log at the end of a migration run).
eelog_mark() { echo "$(stat -c %i $EE_LOG 2>/dev/null || echo 0) $(stat -c %s $EE_LOG 2>/dev/null || echo 0)"; }
eelog_since() { local ino=${1%% *} off=${1##* } f
  if [ "$(stat -c %i $EE_LOG 2>/dev/null)" = "$ino" ]; then tail -c +$((off+1)) $EE_LOG; return; fi
  for f in $EE_LOG.1 $EE_LOG.2; do [ "$(stat -c %i $f 2>/dev/null)" = "$ino" ] && { tail -c +$((off+1)) $f; [ $f = $EE_LOG.2 ] && cat $EE_LOG.1; cat $EE_LOG 2>/dev/null; return; }; done
  cat $EE_LOG 2>/dev/null; }
# With EELOG_ACC set, each ee call appends its own ee.log lines there, including nested ee runs (the first site create runs
# `ee auth update global`). A -nightly- VERSION force-rotates ee.log on every command (rotate 30, compress, delaycompress)
# and a process keeps writing to its renamed file, so files are matched by content, not by name or inode.
eefiles() { local n; for n in $(seq 40 -1 1); do [ -f $EE_LOG.$n.gz ] && echo $EE_LOG.$n.gz; [ -f $EE_LOG.$n ] && echo $EE_LOG.$n; done; [ -f $EE_LOG ] && echo $EE_LOG; }
fmd5() { zcat -f "$1" | md5sum | cut -c1-32; }
ee() { [ -n "${EELOG_ACC:-}" ] || { command ee "$@"; return; }
  local off h pre r f got=; off=$(stat -c %s $EE_LOG 2>/dev/null || echo 0); h=$(head -c $off $EE_LOG 2>/dev/null | md5sum | cut -c1-32)
  pre=" $(for f in $(eefiles); do fmd5 $f; done | tr '\n' ' ') "
  command ee "$@"; r=$?
  echo "#### ee $* (rc=$r)" >> "$EELOG_ACC"
  for f in $(eefiles); do [[ $pre == *" $(fmd5 $f) "* ]] && continue; got=1
    if [ "$off" -gt 0 ] && [ "$(zcat -f $f | head -c $off | md5sum | cut -c1-32)" = "$h" ]; then zcat -f $f | tail -c +$((off+1)); else zcat -f $f; fi >> "$EELOG_ACC"; done
  [ -n "$got" ] || echo "#### capture-missed" >> "$EELOG_ACC"
  return $r; }
# eeacc_checks <label> [allowed-regex]: every ee call was captured (at least one "ee invoked" banner each), then eelog_checks on the capture.
eeacc_checks() { local L=$1
  local c b; c=$(grep -c '^#### ee ' "$EELOG_ACC"); b=$(grep -c 'ee invoked' "$EELOG_ACC")
  chk "$L: ee.log captured for every ee call (banners >= calls; nested ee runs add banners)" yes "$([ "$b" -ge "$c" ] && echo yes || echo "no: $b banners, $c calls")"
  info "$L: ee calls $c, ee.log banners $b"
  chk "$L: no missed ee.log capture" 0 "$(grep -c '^#### capture-missed' "$EELOG_ACC")"
  eelog_checks "$L" "$EELOG_ACC" "${2:-^$}"; }
# eelog_checks <label> <log slice> [allowed-regex]: no warning/error-level lines (except deliberately provoked ones) and no rollback.
eelog_checks() { local L=$1 S=$2 A=${3:-^$}
  chk "$L: ee.log has no ee.ERROR/ee.WARNING lines (outside deliberate error cases)" 0 "$(grep -E 'ee\.(ERROR|WARNING|CRITICAL|ALERT|EMERGENCY):' "$S" | grep -cvE "$A")"
  grep -E 'ee\.(ERROR|WARNING|CRITICAL|ALERT|EMERGENCY):' "$S" | grep -vE "$A" | head -5 | cut -c1-300 | while read -r l; do info "$L: ee.log: $l"; done
  info "$L: ee.log deliberate error lines: $(grep -E 'ee\.(ERROR|WARNING):' "$S" | grep -cE "$A")"
  chk "$L: ee.log has no Reverting (rollback) lines" 0 "$(grep -c 'Reverting' "$S")"
  grep -iE 'error|fatal' "$S" | grep -vE 'No such object: services_global-(redis|newrelic-daemon)_1|ee\.(ERROR|WARNING)' | head -10 | cut -c1-300 | while read -r l; do info "$L: ee.log error-like line: $l"; done; }

# New Relic helpers.
# setkey <site> <key>: replace or append NEWRELIC_LICENSE_KEY in the site's .env; prints the resulting line.
setkey() { local e=$SITES_DIR/$1/.env
  if grep -q '^NEWRELIC_LICENSE_KEY=' $e; then sed -i "s/^NEWRELIC_LICENSE_KEY=.*/NEWRELIC_LICENSE_KEY=$2/" $e; else echo "NEWRELIC_LICENSE_KEY=$2" >> $e; fi
  grep '^NEWRELIC_LICENSE_KEY=' $e; }
nr_ini() { echo "$SITES_DIR/$1/config/php/php/conf.d/newrelic.ini"; }
# nr_mods <site>: "cli=<0|1> fpm=<0|1>" newrelic in php -m / php-fpm -m of the running php container.
nr_mods() { local c; c=$(phpc $1); echo "cli=$(docker exec $c php -m 2>/dev/null | grep -cx newrelic) fpm=$(docker exec $c php-fpm -m 2>/dev/null | grep -cx newrelic)"; }
# nr_dlog <site>: extension-load and entrypoint-guard lines in the php container's docker logs.
nr_dlog() { docker logs $(phpc $1) 2>&1 | grep -cE 'Unable to load dynamic library|Failed loading|already loaded|PHP Startup|docker-entrypoint: could not'; }
# nr_connect <site> <logdir>: a CLI request in the site's php container with the agent at verbosedebug (license from newrelic.ini, not -d);
# prints the "daemon connect(...) succeeded" line or "none". The full agent log is kept in <logdir>/nr-agent-<site>.log.
nr_connect() { local c l; c=$(phpc $1); l=/tmp/f50-nr-$(date +%s%N).log
  docker exec --user root $c sh -c "php -d newrelic.loglevel=verbosedebug -d newrelic.cli.enabled=1 -d newrelic.logfile=$l -r 'usleep(300000);' > /dev/null 2>&1; sleep 3; cat $l 2>/dev/null; rm -f $l" > $2/nr-agent-$1.log 2>&1
  l=$(grep -m1 -E 'daemon connect\(fd=[0-9]+ uds=/run/newrelic/newrelic\.sock\) succeeded' $2/nr-agent-$1.log | cut -c1-200); echo "${l:-none}"; }

# Session defaults (run 2). PHP 8.6's own defaults are strict mode On, httponly On, SameSite Lax; 8.5 keeps php.ini's 0 / empty and no SameSite.
# sess_ini <label> <site> <minor>: the three values in php -i (CLI) and through FPM (needs put_probes); raw lines logged.
sess_ini() { local L=$1 s=$2 m=$3 pi k i e f
  pi=$(docker exec $(phpc $s) php -i 2>&1 | grep -E '^session\.(use_strict_mode|cookie_httponly|cookie_samesite) => ')
  info "$L: $s php -i: $(echo "$pi" | tr '\n' ';')"
  if [ "$m" = 8.6 ]; then e=(On On Lax); f=("'1'" "'1'" "'Lax'"); else e=(Off Off 'no value'); f=("'0'" "''" "''"); fi
  i=0; for k in use_strict_mode cookie_httponly cookie_samesite; do
    eqs "$L: $s php -i session.$k" "session.$k => ${e[$i]} => ${e[$i]}" "$(echo "$pi" | grep "^session\.$k => ")"
    eqs "$L: $s FPM ini_get(session.$k)" "${f[$i]}" "$(fpm $s k=session.$k)"; i=$((i+1)); done; }
# sess_strict <label> <site> <minor>: a made-up PHPSESSID on f50-session.php. 8.6 (strict mode) replaces it and sends a cookie with HttpOnly and SameSite=Lax; older keeps it.
sess_strict() { local L=$1 s=$2 m=$3 sid=0123456789abcdef0123456789abcdef h b id sc
  h=$(mktemp); b=$(curl -s -m 20 -D $h -b "PHPSESSID=$sid" --resolve "$s:80:127.0.0.1" "http://$s/f50-session.php"); read -r id _ <<< "$b"
  sc=$(tr -d '\r' < $h | grep -i '^set-cookie: PHPSESSID=' | head -1); rm -f $h
  info "$L: $s made-up session ID: page [$b] Set-Cookie [$sc]"
  if [ "$m" = 8.6 ]; then
    chk "$L: $s made-up session ID rejected (strict mode: new ID issued)" new "$([ -n "$id" ] && [ "$id" != "$sid" ] && echo new || echo "kept[$id]")"
    has "$L: $s session Set-Cookie has HttpOnly" "; HttpOnly" "$sc"
    has "$L: $s session Set-Cookie has SameSite=Lax" "; SameSite=Lax" "$sc"
  else
    chk "$L: $s made-up session ID accepted (strict mode off)" kept "$([ "$id" = "$sid" ] && echo kept || echo "new[$id]")"
  fi; }
# wplogin <label> <site> <dir>: GET wp-login.php (test cookie), POST admin credentials -> 302 to wp-admin, then /wp-admin/ with the cookies -> 200 dashboard.
# wp-login.php is rate-limited by the site nginx, so a 429/503 is retried (logged).
wplogin() { local L=$1 s=$2 D=$3 J h c i loc c2
  J=$D/login-$s.jar; h=$D/login-$s.hdr; rm -f $J
  curl -s -m 20 -c $J -o /dev/null --resolve "$s:80:127.0.0.1" "http://$s/wp-login.php"
  for i in 1 2 3 4 5; do sleep 2
    c=$(curl -s -m 30 -c $J -b $J -D $h -o $D/login-$s.body -w '%{http_code}' --resolve "$s:80:127.0.0.1" --data-urlencode log=admin --data-urlencode pwd=Adm1nPass4160u \
      --data-urlencode 'wp-submit=Log In' --data-urlencode "redirect_to=http://$s/wp-admin/" --data-urlencode testcookie=1 "http://$s/wp-login.php")
    case $c in 429|503) info "$L: $s login POST got $c (attempt $i), retrying" ;; *) break ;; esac; done
  loc=$(tr -d '\r' < $h | awk 'tolower($1)=="location:"{print $2}' | tail -1)
  chk "$L: $s WordPress login POST HTTP" 302 "$c"
  has "$L: $s WordPress login redirect" "http://$s/wp-admin/" "$loc"
  c2=$(curl -s -m 30 -c $J -b $J -o $D/dash-$s.html -w '%{http_code}' --resolve "$s:80:127.0.0.1" "http://$s/wp-admin/")
  chk "$L: $s /wp-admin/ with the login cookies HTTP" 200 "$c2"
  chk "$L: $s /wp-admin/ is the dashboard" yes "$(grep -q '<title>Dashboard' $D/dash-$s.html && echo yes || echo no)"
  info "$L: $s login: POST $c Location [$loc], /wp-admin/ $c2, cookies $(awk -F'\t' 'NF>=7{print $6}' $J | sort | tr '\n' ' ')"; }
# Release knobs (filled from GO.env by fill-4160.sh): "DIGEST <image> <sha256:...>", "OLD_DIGESTS <egrep alternation>", "NR_AGENT <v>", "OFELIA_VERSION <v>".
KN=$F/knobs.txt
kv() { awk -v k="$1" '$1==k {print $2; exit}' "$KN"; }
dg() { awk -v i="$1" '$1=="DIGEST" && $2==i {print $3; exit}' "$KN"; }
OLD_DIGESTS=$(kv OLD_DIGESTS); NR_AGENT=$(kv NR_AGENT); OFELIA_VERSION=$(kv OFELIA_VERSION)
: "${OLD_DIGESTS:?OLD_DIGESTS missing in knobs.txt}" "${NR_AGENT:?NR_AGENT missing}" "${OFELIA_VERSION:?OFELIA_VERSION missing}"
# img_digests <image ref or ID>: its RepoDigests, space-separated.
img_digests() { docker image inspect -f '{{join .RepoDigests " "}}' "$1" 2>&1; }
# digest_ok <container> <image name without easyengine/>: "yes" when the container's image has easyengine/<image>@<GO digest> among its RepoDigests.
digest_ok() { local g e; e=$(dg "$2"); [ -n "$e" ] || { echo "no-knob[$2]"; return; }
  g=$(img_digests "$(docker inspect -f '{{.Image}}' "$1" 2>&1)")
  echo "$g" | tr ' ' '\n' | grep -qx "easyengine/$2@$e" && echo yes || echo "no[$g]"; }
# run_ee <label> <dir> <ee args...>: ee with stdin closed, output in <dir>/<label>.out (rc appended), sets RC.
run_ee() { local l=$1 d=$2; shift 2; ee "$@" < /dev/null > "$d/$l.out" 2>&1; RC=$?; echo "rc=$RC" >> "$d/$l.out"; return 0; }
