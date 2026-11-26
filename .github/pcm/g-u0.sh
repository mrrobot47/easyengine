#!/bin/bash
# Frozen-pair review (2026-11-25): U0/U1 false positives (links from the live release into old releases or core), over-refusals that must be positive, a mid-scan swap, U23 scanner fixture.
. "$(dirname "$0")/lib.sh"; D=$OUT/u0; mkdir -p $D; cd /tmp
DQS_B64='PD9waHAKCi8vIFRlc3Qgc291cmNlOiBodHRwczovL2dpc3QuZ2l0aHViLmNvbS9pbHV1dTE5OTQvNzJlMjE1NGZjNDE1MGYyMjU4MzE2YjAyNTViNjk4ZjIjZmlsZS10ZXN0LXBocAoKLyogdGVzdFNpbXBsZTEgKi8KIiRmb28iOwovKiB0ZXN0U2ltcGxlMiAqLwoieyRmb299IjsKLyogdGVzdFNpbXBsZTMgKi8KIiR7Zm9vfSI7CgovKiB0ZXN0RElNMSAqLwoiJGZvb1tiYXJdIjsKLyogdGVzdERJTTIgKi8KInskZm9vWydiYXInXX0iOwovKiB0ZXN0RElNMyAqLwoiJHtmb29bJ2JhciddfSI7CgovKiB0ZXN0UHJvcGVydHkxICovCiIkZm9vLT5iYXIiOwovKiB0ZXN0UHJvcGVydHkyICovCiJ7JGZvby0+YmFyfSI7CgovKiB0ZXN0TWV0aG9kMSAqLwoieyRmb28tPmJhcigpfSI7CgovKiB0ZXN0Q2xvc3VyZTEgKi8KInskZm9vKCl9IjsKCi8qIHRlc3RDaGFpbjEgKi8KInskZm9vWydiYXInXS0+YmF6KCkoKX0iOwoKLyogdGVzdFZhcmlhYmxlVmFyMSAqLwoiJHskYmFyfSI7Ci8qIHRlc3RWYXJpYWJsZVZhcjIgKi8KIiR7KGZvbyl9IjsKLyogdGVzdFZhcmlhYmxlVmFyMyAqLwoiJHtmb28tPmJhcn0iOwoKLyogdGVzdE5lc3RlZDEgKi8KIiR7Zm9vWyIke2Jhcn0iXX0iOwovKiB0ZXN0TmVzdGVkMiAqLwoiJHtmb29bIiR7YmFyWydiYXonXX0iXX0iOwovKiB0ZXN0TmVzdGVkMyAqLwoiJHtmb28tPnskYmF6fX0iOwovKiB0ZXN0TmVzdGVkNCAqLwoiJHtmb28tPnskeydhJ319fSI7Ci8qIHRlc3ROZXN0ZWQ1ICovCiIke2Zvby0+eyIkeydhJ30ifX0iOwoKLyogdGVzdFBhcnNlRXJyb3IgKi8KIiR7Zm9vWyIke2Jhcgo='
A() { echo $SITES_DIR/$1/app; }
waitrun() { local i; for i in $(seq 1 600); do [ "$(docker inspect -f '{{.State.Running}}' $1 2>/dev/null)" = true ] && return 0; sleep 0.2; done; return 1; }
ncl() { jq -c '.not_checked // [] | map(tostring)' "$D/$1.report.json" 2>/dev/null || jq -c '.not_checked // [] | map(tostring)' "$D/$1.out" 2>/dev/null | tail -1; }
det() { echo "$ST safe=$SAFE errors=$ERRS canary=$CAN detail=$(jq -r '.detail // empty' $D/$1.out 2>/dev/null | tail -1 | cut -c1-220) not_checked=$(ncl $1 | cut -c1-250) unlisted=$(jq -c '.cross_check.unlisted // empty' $D/$1.out 2>/dev/null | tail -1 | cut -c1-200)"; }
neverpos() { CANF=${3:-pcm-canary.php} pcs $1 $2; chk "$1: never positive (tool_error / can't confirm / not safe)" 'tool_error null|ok null|ok false' "$ST $SAFE"; info "$1: $(det $1)"; }
pos() { CANF=none pcs $1 $2; chk "$1: positive (ok true, nothing unchecked)${3:+ $3}" 'ok true \[\]' "$ST $SAFE $(ncl $1)"; [ "$SAFE" = true ] || info "$1: $(det $1)"; }
CLEAN='<?php
/*
Plugin Name: PCM Clean
*/
function pcm_clean() { return 1; }
'
clean() { mkdir -p "$(dirname "$1")"; printf '%s' "$CLEAN" > "$1"; }

# --- U0: php CI/CD site, --public-dir=current/public, current -> releases/2, legacy code only in old release 1
P=pu-php.test; run_ee c-$P site create $P --type=php --public-dir=current/public; PA=$(A $P); PH=$PA/htdocs; rec u0-created $P > /dev/null
mkdir -p $PH/releases $PH/current/public; mv $PH/current $PH/releases/2; ln -s releases/2 $PH/current; R1=$PH/releases/1; R2=$PH/releases/2
mkdir -p $R1/public $R1/vendor $R2/vendor; plant $R1/vendor/autoload.php; plant $R1/h.php; printf '<?php\nrequire __DIR__ . "/../vendor/autoload.php";\necho "old";\n' > $R1/public/index.php
printf '<?php\nreturn true;\n' > $R2/vendor/autoload.php; printf '<?php\nrequire __DIR__ . "/../vendor/autoload.php";\necho "live";\n' > $R2/public/index.php; chown -R 33:33 $PA; chown -h 33:33 $PH/current
rm -rf /var/tmp/pu-php; mkdir -p /var/tmp/pu-php; cp -a $PA/. /var/tmp/pu-php/; preset() { rsync -a --delete /var/tmp/pu-php/ $PA/; chown -R 33:33 $PA; }
command -v rsync > /dev/null || apt-get install -y -qq rsync > /dev/null 2>&1
rec u0-cicd $P > /dev/null; pos U0-base-old-release-legacy $P "(legacy code only in old release 1, nothing links to it)"
preset; rm -rf $R2/vendor; ln -s /var/www/htdocs/releases/1/vendor $R2/vendor; chown -h 33:33 $R2/vendor; info "U0a http: $(curl -s -H "Host: $P" http://127.0.0.1/ | head -c 80)"; neverpos U0a-live-vendor-abs-link-to-old-release $P autoload.php
preset; ln -s ../1/h.php $R2/h.php; chown -h 33:33 $R2/h.php; neverpos U0b-live-file-link-to-old-release $P h.php
preset; mkdir -p $PH/shared; ln -s ../releases/1/vendor $PH/shared/vendor; chown -R 33:33 $PH/shared; chown -h 33:33 $PH/shared/vendor; neverpos U0c-shared-vendor-link-to-old-release $P autoload.php
# release pointers (#546 a1b8fb53): htdocs/previous -> releases/1 is a release pointer (shape a); htdocs/vendor -> releases/1/vendor is not
preset; ln -s releases/1 $PH/previous; chown -h 33:33 $PH/previous; pos R1-previous-pointer-to-old-release $P "(legacy code only in releases/1)"; info "R1: $(det R1-previous-pointer-to-old-release)"
preset; ln -s releases/1/vendor $PH/vendor; chown -h 33:33 $PH/vendor; neverpos R2-htdocs-vendor-link-into-old-release $P autoload.php
# R5 (K7): auto_prepend_file pointing into old release 1 (.user.ini in the served dir; and a conf.d ini in the php container): never positive
preset; plant $R1/prepend.php; printf 'auto_prepend_file = /var/www/htdocs/releases/1/prepend.php\n' > $R2/public/.user.ini; chown -R 33:33 $PH; info "R5 http: $(curl -s -o /dev/null -w '%{http_code}' -H "Host: $P" http://127.0.0.1/)"; neverpos R5-user-ini-prepend-into-old-release $P prepend.php
preset; plant $R1/prepend.php; chown -R 33:33 $PH; (cd $SITES_DIR/$P && docker-compose exec -T --user=root php sh -c 'printf "auto_prepend_file = /var/www/htdocs/releases/1/prepend.php\n" > "${PHP_INI_DIR:-/usr/local/etc/php}"/conf.d/zz-pcm-prepend.ini' && docker-compose restart php) > $D/R5b-ini.log 2>&1; sleep 3
info "R5b fpm sees: $(cd $SITES_DIR/$P && docker-compose exec -T php php -r 'echo ini_get("auto_prepend_file");' 2>&1 | tail -1)"; neverpos R5b-conf-d-prepend-into-old-release $P prepend.php
(cd $SITES_DIR/$P && docker-compose exec -T --user=root php sh -c 'rm -f "${PHP_INI_DIR:-/usr/local/etc/php}"/conf.d/zz-pcm-prepend.ini' && docker-compose restart php) >> $D/R5b-ini.log 2>&1; sleep 3
# shape (a) only through a `current` link beside releases/ (#546 after 4094706c): releases moved under htdocs/sub with current -> sub/releases/2
preset; mkdir -p $PH/sub; mv $PH/releases $PH/sub/releases; rm -f $PH/current; ln -s sub/releases/2 $PH/current; chown -h 33:33 $PH/current; chown -R 33:33 $PH/sub
info "R3 layout: current -> $(readlink $PH/current), htdocs=[$(ls -A $PH | tr '\n' ' ')]"; neverpos R3-current-not-beside-releases $P autoload.php; chk "R3 pinned: not safe, old release scanned (canary found)" 'ok false [2-9][0-9]*' "$ST $SAFE $CAN"
preset
# the served link under another name: php site --public-dir=live/public, live -> releases/2, legacy code only in releases/1
LP=pu-live.test; run_ee c-$LP site create $LP --type=php --public-dir=live/public; LA=$(A $LP); LH=$LA/htdocs; rec u0-live $LP > /dev/null
mkdir -p $LH/releases $LH/live/public; mv $LH/live $LH/releases/2; ln -s releases/2 $LH/live; mkdir -p $LH/releases/1/vendor $LH/releases/2/vendor; plant $LH/releases/1/vendor/autoload.php
printf '<?php\nreturn true;\n' > $LH/releases/2/vendor/autoload.php; printf '<?php\nrequire __DIR__ . "/../vendor/autoload.php";\necho "live";\n' > $LH/releases/2/public/index.php; chown -R 33:33 $LA; chown -h 33:33 $LH/live
rec u0-live-cicd $LP > /dev/null; neverpos R4-served-link-named-live $LP autoload.php; chk "R4 pinned: not safe, old release scanned (canary found)" 'ok false [2-9][0-9]*' "$ST $SAFE $CAN"
preset

# V17 (#546 0f0081c1): a php site with a Python venv whose interpreter links out of the site's files (not code): positive
VP=pu-venv.test; run_ee c-$VP site create $VP --type=php; VA=$(A $VP); printf '<?php\necho "hi";\n' > $VA/htdocs/index.php; chown -R 33:33 $VA
mkdir -p $VA/.venv/bin; ln -s /usr/bin/python3 $VA/.venv/bin/python; ln -s python $VA/.venv/bin/python3; printf 'home = /usr/bin\nversion = 3.12.3\n' > $VA/.venv/pyvenv.cfg; chown -R 33:33 $VA/.venv; chown -h 33:33 $VA/.venv/bin/python $VA/.venv/bin/python3
CANF=none pcs V17-venv-python-link-out $VP; chk "V17 app/.venv/bin/python -> /usr/bin/python3: can't confirm, the link named (acceptance dropped, main 2026-11-26)" 'ok null 1' "$ST $SAFE $( { ncl V17-venv-python-link-out; jq -c '.cross_check.unlisted // empty' $D/V17-venv-python-link-out.out | tail -1; } 2>/dev/null | grep -cF '.venv/bin/python' | awk '{print ($1>0)}')"; info "V17: $(det V17-venv-python-link-out)"
mkdir -p $VA/htdocs/.venv/bin; ln -s /usr/bin/python3 $VA/htdocs/.venv/bin/python; chown -R 33:33 $VA/htdocs/.venv; chown -h 33:33 $VA/htdocs/.venv/bin/python; CANF=none pcs V17b-venv-in-htdocs $VP; chk "V17b htdocs/.venv/bin/python -> /usr/bin/python3: tool_error naming the link (R15, php_site_user_ini can't follow it; main 2026-11-26)" 'tool_error null 1' "$ST $SAFE $(jq -r '.detail // empty' $D/V17b-venv-in-htdocs.out 2>/dev/null | tail -1 | grep -cF '.venv/bin/python')"

# --- U1 and the over-refusals on a wp site
WS=pu-wp.test; run_ee c-$WS site create $WS --type=wp --title=pu $W; WA=$(A $WS); WH=$WA/htdocs; chown -R 33:33 $WA
rm -rf /var/tmp/pu-wp; mkdir -p /var/tmp/pu-wp; cp -a $WA/. /var/tmp/pu-wp/; wreset() { rsync -a --delete /var/tmp/pu-wp/ $WA/; chown -R 33:33 $WA; }
pos U-wp-fresh $WS
clean $WH/wp-content/plugins/clean/clean.php; plant $WH/wp-includes/custom/evil.php; ln -s ../../../wp-includes/custom/evil.php $WH/wp-content/plugins/clean/boot.php; chown -R 33:33 $WH; chown -h 33:33 $WH/wp-content/plugins/clean/boot.php
neverpos U1-plugin-file-link-into-core $WS evil.php
wreset; cp -a $WA/wp-config.php $WA/wp-config.php.bak; chown 33:33 $WA/wp-config.php.bak; pos O1-wp-config-bak $WS "(copy of the config beside it)"
wreset; printf '<?php echo 1;\nls -la\n' > $WA/.bash_history; chown 33:33 $WA/.bash_history; pos O2-bash-history-with-php-tag $WS

# O3: W3TC-style object cache written by the php container during the scan
wreset; mkdir -p $WH/wp-content/cache/object/000; for i in $(seq 1 300); do printf '<?php exit; ?>a:1:{s:4:"data";s:%d:"%s";}' ${#i} "$i" > $WH/wp-content/cache/object/000/$(printf '%032x' $i).php; done; chown -R 33:33 $WH/wp-content/cache
(cd $SITES_DIR/$WS && docker-compose exec -T --user=www-data php sh -c 'rm -f /tmp/pcm-stop; cat > /tmp/pcm-w3tc.sh <<"S"
i=1000; while [ ! -e /tmp/pcm-stop ] && [ $i -lt 20000 ]; do i=$((i+1)); d=/var/www/htdocs/wp-content/cache/object/$(printf %03d $((i % 50))); mkdir -p $d; printf "<?php exit; ?>a:1:{s:4:\"data\";s:5:\"c%05d\";}" $i > $d/$(printf %032x $i).php; sleep 0.05; done
S
chmod 755 /tmp/pcm-w3tc.sh') > /dev/null 2>&1
(cd $SITES_DIR/$WS && docker-compose exec -T -d --user=www-data php sh /tmp/pcm-w3tc.sh) > $D/O3-writer.log 2>&1; sleep 2; n0=$(find $WH/wp-content/cache/object -type f | wc -l)
CANF=none pcs O3-w3tc-cache-written-during-scan $WS; n1=$(find $WH/wp-content/cache/object -type f | wc -l)
(cd $SITES_DIR/$WS && docker-compose exec -T php touch /tmp/pcm-stop) > /dev/null 2>&1; sleep 1
chk "O3 cache files were being written during the scan" 1 "$(( n1 > n0 ))"; o3u=$(jq -c '.cross_check.unlisted // []' $D/O3-w3tc-cache-written-during-scan.out 2>/dev/null | tail -1); o3n=$(ncl O3-w3tc-cache-written-during-scan)
chk "O3 W3TC cache written during the scan: positive, or can't confirm only from the scanner's own not_checked (nothing unlisted)" 'ok true \[\] \[\]|ok null \[\] \[.+\]' "$ST $SAFE $o3u $o3n"; info "O3: files before scan $n0, after $n1; $(det O3-w3tc-cache-written-during-scan)"

# O4: a plugin file replaced with legacy code right after the scan starts (best effort: a bulk plugin keeps the scan busy)
wreset; mkdir -p $WH/wp-content/plugins/mmm-bulk; body=$(for i in $(seq 1 80); do echo "\$v$i = strtoupper( 'line $i' );"; done); for i in $(seq 1 3000); do printf '<?php\n// %d\n%s\n' $i "$body" > $WH/wp-content/plugins/mmm-bulk/f$i.php; done
clean $WH/wp-content/plugins/aaa-swap/aaa-swap.php; clean $WH/wp-content/plugins/zzz-swap/zzz-swap.php; chown -R 33:33 $WH/wp-content/plugins
for v in aaa zzz; do
  F=$WH/wp-content/plugins/$v-swap/$v-swap.php; clean $F; chown 33:33 $F
  (cd /tmp && ee --debug site php-compat $WS --php=8.4 --format=json --output=/root/pcm-out/O4-$v.report.json) < /dev/null > $D/O4-$v.out 2> $D/O4-$v.err & SP=$!
  waitrun ee-php-compat-$WS; sleep 1; printf '%s' "$CANARY" > $F.tmp; chown 33:33 $F.tmp; mv $F.tmp $F; wait $SP; cp /root/pcm-out/O4-$v.report.json $D/O4-$v.report.json 2>/dev/null
  ST=$(jq -r .status $D/O4-$v.out 2>/dev/null | tail -1); SAFE=$(jq -r .safe_to_upgrade $D/O4-$v.out 2>/dev/null | tail -1); CAN=$(canary O4-$v $v-swap.php)
  chk "O4-$v plugin file swapped to legacy code right after the scan started: never positive" 'tool_error null|ok null|ok false' "$ST $SAFE"; info "O4-$v: $ST safe=$SAFE canary=$CAN unlisted=$(jq -c '.cross_check.unlisted // empty' $D/O4-$v.out 2>/dev/null | tail -1 | cut -c1-200) not_checked=$(ncl O4-$v | cut -c1-200)"
done
rm -rf $WH/wp-content/plugins/mmm-bulk $WH/wp-content/plugins/aaa-swap $WH/wp-content/plugins/zzz-swap

# RW (#546 0f0081c1): app/.wp-cli -> releases/1 beside htdocs -> releases/2; WP-CLI loads ~/.wp-cli/packages/vendor/autoload.php from the old release: never positive
wreset; mkdir -p $WA/releases; mv $WH $WA/releases/2; ln -s releases/2 $WH; cp -a $WA/wp-config.php $WA/releases/2/wp-config.php; mkdir -p $WA/releases/1/packages/vendor; plant $WA/releases/1/packages/vendor/autoload.php
rm -rf $WA/.wp-cli; ln -s releases/1 $WA/.wp-cli; chown -R 33:33 $WA; chown -h 33:33 $WH $WA/.wp-cli; info "RW layout: app=[$(ls -A $WA | tr '\n' ' ')] .wp-cli -> $(readlink $WA/.wp-cli) htdocs -> $(readlink $WH)"
neverpos RW1-wpcli-home-link-to-old-release $WS autoload.php
rm -f $WH $WA/.wp-cli; mv $WA/releases/2 $WH; rm -f $WH/wp-config.php; rm -rf $WA/releases; wreset

# WF (#546 0f0081c1): Wordfence wflogs data files rewritten in place during the scan: positive (data-only)
wreset; WFL=$WH/wp-content/wflogs; mkdir -p $WFL $WH/wp-content/plugins/wordfence; printf '<?php\n/*\nPlugin Name: Wordfence Security\nVersion: 8.0.5\n*/\n' > $WH/wp-content/plugins/wordfence/wordfence.php
wfw() { printf "<?php exit('Access denied'); __halt_compiler(); ?>\n******************************************************************\nThis file is used by the Wordfence Web Application Firewall. Read\nmore at https://docs.wordfence.com/en/Web_Application_Firewall_FAQ\n******************************************************************\na:1:{s:4:\"tick\";i:%s;}" "$2" > "$1"; }
for f in attack-data config config-livewaf config-synced config-transient ips rules; do wfw $WFL/$f.php 0; done; chown -R 33:33 $WH/wp-content
( i=0; while [ ! -e /var/tmp/pu-wf-stop ]; do i=$((i+1)); for f in attack-data config config-livewaf config-synced config-transient ips rules; do wfw $WFL/$f.php $i; done; sleep 0.2; done ) & WFP=$!; rm -f /var/tmp/pu-wf-stop
c0=$(stat -c %Z $WFL/config.php); CANF=none pcs WF1-wordfence-wflogs-rewritten-during-scan $WS; c1=$(stat -c %Z $WFL/config.php); touch /var/tmp/pu-wf-stop; wait $WFP; rm -f /var/tmp/pu-wf-stop
chk "WF1 wflogs rewritten during the scan" 1 "$(( c1 > c0 ))"; chk "WF1 Wordfence wflogs rewritten in place during the scan: positive" 'ok true \[\]' "$ST $SAFE $(ncl WF1-wordfence-wflogs-rewritten-during-scan)"; info "WF1: $(det WF1-wordfence-wflogs-rewritten-during-scan)"
wreset

# NH (#546 a1b8fb53): EE --cache site, nginx-helper's bundled Predis exempt only as the stock released pair with phpredis loaded
NH=pu-cache.test; run_ee c-$NH site create $NH --type=wp --cache --title=pu $W; NA=$(A $NH); NHD=$NA/htdocs/wp-content/plugins/nginx-helper
info "NH nginx-helper: version=$(grep -m1 -i '^ *\* *Version:' $NHD/nginx-helper.php 2>/dev/null | tr -d ' *') predis sha256=$(sha256sum < $NHD/admin/predis.php 2>/dev/null | cut -c1-16) guard sha256=$(sha256sum < $NHD/includes/class-nginx-helper.php 2>/dev/null | cut -c1-16) redis ext=$(cd $SITES_DIR/$NH && docker-compose exec -T php php -r 'echo extension_loaded("redis") ? "yes" : "no";' 2>&1 | tail -1)"
cp -a $NHD/admin/predis.php /var/tmp/pu-predis.php; cp -a $NHD/includes/class-nginx-helper.php /var/tmp/pu-guard.php
pos NH1-cache-site-stock-nginx-helper $NH "(EE --cache site, stock nginx-helper)"; ig=$(jq -c '.ignored // empty' $D/NH1-cache-site-stock-nginx-helper.out 2>/dev/null | tail -1)
chk "NH1 JSON ignored names admin/predis.php" 1 "$(echo "$ig" | grep -c 'nginx-helper/admin/predis.php')"; info "NH1: ignored=$ig table: $(cd /tmp && ee site php-compat $NH --php=8.4 < /dev/null 2>&1 | grep -i 'ignored' | head -1 | cut -c1-200)"
printf ' ' >> $NHD/admin/predis.php; CANF=predis.php neverpos NH2-predis-modified $NH predis.php; info "NH2 ignored=$(jq -c '.ignored // empty' $D/NH2-predis-modified.out 2>/dev/null | tail -1)"; cp -a /var/tmp/pu-predis.php $NHD/admin/predis.php
printf '\n// local change\n' >> $NHD/includes/class-nginx-helper.php; CANF=predis.php neverpos NH3-guard-modified $NH predis.php; info "NH3 ignored=$(jq -c '.ignored // empty' $D/NH3-guard-modified.out 2>/dev/null | tail -1)"; cp -a /var/tmp/pu-guard.php $NHD/includes/class-nginx-helper.php
pos NH4-cache-site-restored $NH "(stock pair restored)"
for pp in aaa-pred zzz-pred; do PP=$NA/htdocs/wp-content/plugins/$pp; mkdir -p $PP; printf "<?php\n/*\nPlugin Name: PCM %s\n*/\nif ( ! class_exists( 'Predis\\\\Client' ) ) {\n\trequire __DIR__ . '/predis.php';\n}\n" $pp > $PP/$pp.php; ln $NHD/admin/predis.php $PP/predis.php; chown -R 33:33 $PP
  info "NH5-$pp: hard link inode $(stat -c %i $PP/predis.php) = $(stat -c %i $NHD/admin/predis.php), links $(stat -c %h $PP/predis.php)"; CANF=predis.php neverpos NH5-$pp-hardlinked-predis-required $NH predis.php; info "NH5-$pp ignored=$(jq -c '.ignored // empty' $D/NH5-$pp-hardlinked-predis-required.out 2>/dev/null | tail -1)"; rm -rf $PP; done
pos NH6-cache-site-after-hardlink-cells $NH "(stock pair, no other plugin)"
# NH7+ (#546 after 4094706c): the exemption needs exact releases 2.2.x-2.4.1, nlink 1, no other code naming predis/nginx-helper, redis in CLI and php-fpm -m, no extra mounts
nhv=$(grep -m1 -i '^ *\* *Version:' $NHD/nginx-helper.php | sed 's/.*: *//' | tr -d ' \r'); info "NH7 EE-installed nginx-helper $nhv"
for v in 2.2.0 2.2.5 2.3.0 2.3.5 2.4.0 2.4.1; do (cd $SITES_DIR/$NH && docker-compose exec -T --user=www-data php sh -c "wp plugin install nginx-helper --version=$v --force") > $D/NH7-$v-install.log 2>&1
  got=$(grep -m1 -i '^ *\* *Version:' $NHD/nginx-helper.php | sed 's/.*: *//' | tr -d ' \r'); pos NH7-release-$v $NH "(nginx-helper $got, scoped OK)"
  info "NH7-$v: installed=$got predis=$([ -f $NHD/admin/predis.php ] && echo yes || echo no) ignored=$(jq -c '.ignored // empty' $D/NH7-release-$v.out 2>/dev/null | tail -1 | cut -c1-200)"; done
(cd $SITES_DIR/$NH && docker-compose exec -T --user=www-data php sh -c "wp plugin install nginx-helper --version=$nhv --force") > $D/NH7-restore.log 2>&1; pos NH7-restored-$nhv $NH
nhneg() { CANF=predis.php pcs $1 $NH; chk "$1: not safe, the Predis exemption withdrawn (errors >= 1, ignored [], main 2026-11-26)" 'ok false [1-9][0-9]* \[\]' "$ST $SAFE $ERRS $(jq -c '.ignored // "absent"' $D/$1.out 2>/dev/null | tail -1)"; info "$1: $(det $1) ignored=$(jq -c '.ignored // empty' $D/$1.out 2>/dev/null | tail -1 | cut -c1-160)"; }
PR=$NA/htdocs/wp-content/plugins/pcm-cache-tools; mkdir -p $PR; printf '<?php\n/*\nPlugin Name: PCM Cache Tools\n*/\nfunction pcm_cache_client() {\n\treturn class_exists( "Predis\\\\Client" ) ? "predis" : "phpredis";\n}\n' > $PR/pcm-cache-tools.php; chown -R 33:33 $PR; nhneg NH8-other-plugin-mentions-predis; rm -rf $PR
mkdir -p $PR; printf '<?php\n/*\nPlugin Name: PCM Cache Tools\n*/\n// Purges through Nginx-Helper when it is active.\nfunction pcm_purge() { do_action( "rt_nginx_helper_purge_all" ); }\n' > $PR/pcm-cache-tools.php; chown -R 33:33 $PR; nhneg NH8b-other-plugin-mentions-nginx-helper; rm -rf $PR
ln $NHD/nginx-helper.php /var/tmp/pcm-nh-hardlink; info "NH9 nlink $(stat -c %h $NHD/nginx-helper.php) (other name outside app/)"; nhneg NH9-nginx-helper-file-hardlinked; rm -f /var/tmp/pcm-nh-hardlink
# NH10: N/A (main 2026-11-26): the probe reads redis.so from the fpm master's /proc/1/maps; removing it needs an image rebuild. The redis-absent row is the #546 owner's IT.
info "NH10: N/A, the Predis probe reads redis.so in the php-fpm master's /proc/1/maps; taking it out needs a rebuilt image (redis-absent row covered by the #546 IT)"
# NH11: an accepted extra mount (a clean plugin dir from the host via user-docker-compose)
mkdir -p /srv/pcm-nh/plug; printf '<?php\n/*\nPlugin Name: PCM Mounted\n*/\nfunction pcm_m() { return 1; }\n' > /srv/pcm-nh/plug/pcm-mounted.php; chown -R 33:33 /srv/pcm-nh; mkdir -p $SITES_DIR/$NH/user-docker-compose
printf 'services:\n  php:\n    volumes:\n      - /srv/pcm-nh/plug:/var/www/htdocs/wp-content/plugins/mounted-plug:ro\n' > $SITES_DIR/$NH/user-docker-compose/pcm.yml; run_ee en-$NH site enable $NH --force
info "NH11 php mounts: $(docker inspect -f '{{json .Mounts}}' $(cname $NH)-php-1 2>&1 | jq -c '[.[] | select(.Destination|startswith("/var/www")) | .Destination]' 2>&1)"; nhneg NH11-accepted-extra-mount
rm -rf $SITES_DIR/$NH/user-docker-compose; run_ee en2-$NH site enable $NH --force; pos NH12-after-negatives $NH "(stock, no mount, fresh container)"
nwp() { (cd $SITES_DIR/$NH && docker-compose exec -T --user=www-data php sh -c "wp $1"); }
nroot() { (cd $SITES_DIR/$NH && docker-compose exec -T --user=root php sh -c "$1"); }
# NH13: WordPress's own nginx-helper es_ES language pack (wp-content/languages/plugins/nginx-helper-es_ES.l10n.php): positive
nwp 'language core install es_ES --activate' > $D/NH13-lang.log 2>&1; nwp 'language plugin install nginx-helper es_ES' >> $D/NH13-lang.log 2>&1; L10N=$NA/htdocs/wp-content/languages/plugins/nginx-helper-es_ES.l10n.php
if [ -f $L10N ]; then info "NH13 pack: $(ls -la $NA/htdocs/wp-content/languages/plugins/ | grep nginx-helper | awk '{print $5, $9}' | tr '\n' ' ') sha256=$(sha256sum < $L10N | cut -c1-16) locale=$(nwp 'option get WPLANG' 2>&1 | tail -1)"
  pos NH13-nginx-helper-es_ES-pack $NH "(stock language pack, es_ES active)"; info "NH13 ignored=$(jq -c '.ignored // empty' $D/NH13-nginx-helper-es_ES-pack.out 2>/dev/null | tail -1 | cut -c1-200)"
  cp -a $L10N /var/tmp/pu-l10n.php; sed -i "1s#^<?php#<?php require_once WP_PLUGIN_DIR . '/nginx-helper/admin/predis.php';#" $L10N; info "NH13b first line: $(head -c 120 $L10N)"; nhneg NH13b-pack-with-require; cp -a /var/tmp/pu-l10n.php $L10N
else info "NH13: N/A, no nginx-helper-es_ES.l10n.php after the language install ($(tail -3 $D/NH13-lang.log | tr '\n' ' ' | cut -c1-250))"; fi
nwp 'site switch-language en_US' > /dev/null 2>&1; nwp 'language core uninstall es_ES' > /dev/null 2>&1; rm -rf $NA/htdocs/wp-content/languages; pos NH13r-after-language-cells $NH
# NH14: links into nginx-helper/admin from another plugin or a theme (K0/C1b, C1c, D4): not safe
ZZ=$NA/htdocs/wp-content/plugins/zz; mkdir -p $ZZ; printf "<?php\n/*\nPlugin Name: ZZ\n*/\nrequire __DIR__ . '/p.php';\n" > $ZZ/zz.php; ln -s ../nginx-helper/admin/predis.php $ZZ/p.php; chown -R 33:33 $ZZ; chown -h 33:33 $ZZ/p.php; nhneg NH14-plugin-file-link-to-predis; rm -rf $ZZ
mkdir -p $ZZ; printf "<?php\n/*\nPlugin Name: ZZ\n*/\nforeach ( glob( __DIR__ . '/lib/*.php' ) as \$f ) {\n\trequire_once \$f;\n}\n" > $ZZ/zz.php; ln -s ../nginx-helper/admin $ZZ/lib; chown -R 33:33 $ZZ; chown -h 33:33 $ZZ/lib; nhneg NH14b-plugin-dir-link-to-admin-glob; rm -rf $ZZ
TT=$NA/htdocs/wp-content/themes/t; mkdir -p $TT; printf '/*\nTheme Name: T\n*/\n' > $TT/style.css; printf "<?php\nrequire __DIR__ . '/p.php';\n" > $TT/functions.php; printf '<?php\n' > $TT/index.php; ln -s ../../plugins/nginx-helper/admin/predis.php $TT/p.php; chown -R 33:33 $TT; chown -h 33:33 $TT/p.php; nhneg NH14c-theme-file-link-to-predis; rm -rf $TT
# NH15: php-fpm configuration changed after the master started (an ini touched in the container's conf.d); the extra -d flag needs a changed command line: N/A
info "NH15 -d variant: N/A, starting the fpm master with an extra -d needs a different container command (a user compose override, refused on its own)"
nroot 'touch "${PHP_INI_DIR:-/usr/local/etc/php}"/conf.d/*.ini' > $D/NH15-touch.log 2>&1; info "NH15 ini mtimes after the master: $(nroot 'ls -l --time-style=+%s "${PHP_INI_DIR:-/usr/local/etc/php}"/conf.d/ | tail -3' 2>&1 | tr '\n' ' ' | cut -c1-250) master start $(nroot 'stat -c %Y /proc/1' 2>&1 | tail -1)"
pos NH15-ini-touched-after-fpm-master $NH "(positive: the config-time probe was dropped, covered by the R-PREDIS-TARGET residual, main 2026-11-26)"; (cd $SITES_DIR/$NH && docker-compose restart php) > $D/NH15-restart.log 2>&1; sleep 3; pos NH15r-after-php-restart $NH "(fpm master restarted after the touch)"

# NH16-NH18 (#546 review of 376be47f): code reaching nginx-helper/admin/predis.php by paths the kernel and PHP resolve differently, or a bind mount; admin-tools
nphp() { (cd $SITES_DIR/$NH && docker-compose exec -T --user=www-data php php -r "$1" 2>&1 | tail -1 | cut -c1-160); }
ZZ=$NA/htdocs/wp-content/plugins/zz
mkdir -p $ZZ; printf "<?php\n/*\nPlugin Name: ZZ\n*/\nrequire __DIR__ . '/p.css';\n" > $ZZ/zz.php; ln -s /var/www/htdocs/missing/../wp-content/plugins/nginx-helper/admin/predis.php $ZZ/p.css; chown -R 33:33 $ZZ; chown -h 33:33 $ZZ/p.css
info "NH16 kernel: $(readlink -e $ZZ/p.css > /dev/null && echo resolves || echo dangling); php loads predis via p.css: $(nphp 'require "/var/www/htdocs/wp-content/plugins/zz/p.css"; echo class_exists("Predis\\Client", false) ? "yes" : "no";')"
nhneg NH16-lexical-dotdot-link-to-predis; rm -rf $ZZ
run_ee at-$NH admin-tools enable $NH; AT=$(cd $SITES_DIR/$NH && docker-compose exec -T php sh -c 'for d in /var/www/htdocs/ee-admin/*/; do [ -d "$d" ] && basename "$d" && break; done' 2>/dev/null | tr -d '\r' | head -1); info "NH17 admin-tools enable rc $RC; ee-admin subdir [$AT]"
pos NH17-cache-site-with-admin-tools $NH "(stock --cache site, admin-tools enabled)"
if [ -n "$AT" ]; then mkdir -p $ZZ; printf "<?php\n/*\nPlugin Name: ZZ\n*/\nrequire __DIR__ . '/p.css';\n" > $ZZ/zz.php; ln -s /var/www/htdocs/ee-admin/$AT/../../wp-content/plugins/nginx-helper/admin/predis.php $ZZ/p.css; chown -R 33:33 $ZZ; chown -h 33:33 $ZZ/p.css
  info "NH16b kernel on the host: $(readlink -e $ZZ/p.css > /dev/null && echo resolves || echo dangling); php loads predis via p.css: $(nphp 'require "/var/www/htdocs/wp-content/plugins/zz/p.css"; echo class_exists("Predis\\Client", false) ? "yes" : "no";')"
  nhneg NH16b-link-through-ee-admin-to-predis; rm -rf $ZZ
else info "NH16b: N/A, no directory under ee-admin after admin-tools enable"; fi
run_ee atd-$NH admin-tools disable $NH
# NH18: predis.php bind-mounted onto another plugin's file on the host, seen by php after a restart
mkdir -p $ZZ; printf "<?php\n/*\nPlugin Name: ZZ\n*/\nrequire __DIR__ . '/q.php';\n" > $ZZ/zz.php; : > $ZZ/q.php; chown -R 33:33 $ZZ
if mount --bind $NHD/admin/predis.php $ZZ/q.php 2> $D/NH18-mount.err; then (cd $SITES_DIR/$NH && docker-compose restart php) > $D/NH18-restart.log 2>&1; sleep 3
  info "NH18 host q.php inode $(stat -c %i $ZZ/q.php) = predis $(stat -c %i $NHD/admin/predis.php); container q.php size $(cd $SITES_DIR/$NH && docker-compose exec -T php stat -c %s /var/www/htdocs/wp-content/plugins/zz/q.php 2>&1 | tail -1); php loads predis via q.php: $(nphp 'require "/var/www/htdocs/wp-content/plugins/zz/q.php"; echo class_exists("Predis\\Client", false) ? "yes" : "no";')"
  nhneg NH18-bind-mount-predis-onto-plugin-file; umount $ZZ/q.php; (cd $SITES_DIR/$NH && docker-compose restart php) >> $D/NH18-restart.log 2>&1; sleep 3
else info "NH18: N/A, mount --bind failed on the runner: $(head -c 200 $D/NH18-mount.err)"; fi
rm -rf $ZZ; pos NH18r-after-unmount $NH

# P20-P22 (#546 review of 376be47f): auto_prepend_file forms on php sites
PI=pu-ini.test; run_ee c-$PI site create $PI --type=php; IA=$(A $PI); IH=$IA/htdocs; printf '<?php\necho "hi";\n' > $IH/index.php; chown -R 33:33 $IA
plant $IH/x/canary.php; printf '[PHP] auto_prepend_file=/var/www/htdocs/x/canary.php\n' > $IH/.user.ini; chown -R 33:33 $IH; neverpos P20-user-ini-section-and-prepend-one-line $PI canary.php; rm -f $IH/.user.ini
(cd $SITES_DIR/$PI && docker-compose exec -T --user=root php sh -c 'printf "[PHP] auto_prepend_file=/var/www/htdocs/x/canary.php\n" > "${PHP_INI_DIR:-/usr/local/etc/php}"/conf.d/zz-pcm-p20.ini' && docker-compose restart php) > $D/P20b.log 2>&1; sleep 3
info "P20b fpm sees: $(cd $SITES_DIR/$PI && docker-compose exec -T php php -r 'echo ini_get("auto_prepend_file");' 2>&1 | tail -1)"; neverpos P20b-conf-d-section-and-prepend-one-line $PI canary.php
(cd $SITES_DIR/$PI && docker-compose exec -T --user=root php sh -c 'rm -f "${PHP_INI_DIR:-/usr/local/etc/php}"/conf.d/zz-pcm-p20.ini' && docker-compose restart php) >> $D/P20b.log 2>&1; sleep 3; rm -rf $IH/x
mkdir -p $IA/outside-dir; plant $IA/outside-dir/c.php; printf '<?php\necho "sub";\n' > $IA/outside-dir/index.php; printf 'auto_prepend_file=/var/www/outside-dir/c.php\n' > $IA/outside-dir/.user.ini; ln -s ../outside-dir $IH/sub; chown -R 33:33 $IA; chown -h 33:33 $IH/sub
info "P21 http sub/: $(curl -s -o /dev/null -w '%{http_code}' -H "Host: $PI" http://127.0.0.1/sub/)"; neverpos P21-dir-link-out-with-user-ini-prepend $PI c.php; rm -f $IH/sub; rm -rf $IA/outside-dir
# P23: a quoted section name with ] in it, then the prepend, on one line in .user.ini
plant $IH/x/canary.php; printf '["a]b"] auto_prepend_file=/var/www/htdocs/x/canary.php\n' > $IH/.user.ini; chown -R 33:33 $IH
info "P23 http: code $(curl -s -o /dev/null -w '%{http_code}' -H "Host: $PI" http://127.0.0.1/) body [$(curl -s -H "Host: $PI" http://127.0.0.1/ | head -c 120 | tr '\n' ' ')] (hi = not prepended; 500/empty = the canary was prepended)"
neverpos P23-user-ini-quoted-section-with-bracket $PI canary.php; rm -f $IH/.user.ini; rm -rf $IH/x
# P24: htdocs/m is a user-compose mount of a host dir holding lnk -> /var/www/other; app/other/.user.ini prepends a canary
mkdir -p /srv/pcm-p24/m; printf '<?php\necho "m";\n' > /srv/pcm-p24/m/index.php; ln -s /var/www/other /srv/pcm-p24/m/lnk; chown -R 33:33 /srv/pcm-p24; chown -h 33:33 /srv/pcm-p24/m/lnk
mkdir -p $IA/other; plant $IA/other/c.php; printf '<?php\necho "other";\n' > $IA/other/index.php; printf 'auto_prepend_file=/var/www/other/c.php\n' > $IA/other/.user.ini; chown -R 33:33 $IA/other
mkdir -p $SITES_DIR/$PI/user-docker-compose; printf 'services:\n  php:\n    volumes:\n      - /srv/pcm-p24/m:/var/www/htdocs/m\n' > $SITES_DIR/$PI/user-docker-compose/pcm.yml; run_ee en-$PI site enable $PI --force
info "P24 php mounts: $(docker inspect -f '{{json .Mounts}}' $(cname $PI)-php-1 2>&1 | jq -c '[.[] | select(.Destination|startswith("/var/www")) | .Destination]' 2>&1) http m/lnk/: $(curl -s -o /dev/null -w '%{http_code}' -H "Host: $PI" http://127.0.0.1/m/lnk/)"
neverpos P24-mounted-dir-link-to-app-dir-with-user-ini $PI c.php
rm -rf $SITES_DIR/$PI/user-docker-compose $IA/other /srv/pcm-p24; run_ee en2-$PI site enable $PI --force
# P22 = review fixture fx/r6: Deployer php site, every release has a .user.ini prepending its own boot.php; legacy code only in old release 2
PD=pu-dep.test; run_ee c-$PD site create $PD --type=php --public-dir=current/public; DA=$(A $PD); DH=$DA/htdocs
mkdir -p $DH/releases; mv $DH/current $DH/releases/3; ln -s releases/3 $DH/current; mkdir -p $DH/releases/3/public $DH/releases/2/public
printf '<?php echo 1;\n' > $DH/releases/3/public/index.php; printf '<?php echo 1;\n' > $DH/releases/3/boot.php; printf '<?php echo 1;\n' > $DH/releases/2/public/index.php; plant $DH/releases/2/boot.php
echo 'auto_prepend_file=/var/www/htdocs/releases/3/boot.php' > $DH/releases/3/public/.user.ini; echo 'auto_prepend_file=/var/www/htdocs/releases/2/boot.php' > $DH/releases/2/public/.user.ini; chown -R 33:33 $DA; chown -h 33:33 $DH/current
rec u0-dep $PD > /dev/null; info "P22 http: $(curl -s -H "Host: $PD" http://127.0.0.1/ | head -c 40)"; pos P22-deployer-inert-old-release-user-ini $PD "(live release prepend scanned and clean; old release 2 inert)"; info "P22: $(det P22-deployer-inert-old-release-user-ini) checked=$(jq -c .checked $D/P22-deployer-inert-old-release-user-ini.out 2>/dev/null | tail -1)"

# U23: squizlabs php_codesniffer test fixture (tests/Core/Tokenizers/PHP/DoubleQuotedStringTest.inc, PHPCSStandards 3.x, sha256 d15e4ded) in a plugin
wreset; G=$WH/wp-content/plugins/pcm-phpcs; clean $G/pcm-phpcs.php; mkdir -p $G/vendor/squizlabs/php_codesniffer/tests/Core/Tokenizers/PHP; echo "$DQS_B64" | base64 -d > $G/vendor/squizlabs/php_codesniffer/tests/Core/Tokenizers/PHP/DoubleQuotedStringTest.inc; chown -R 33:33 $G
info "U23 fixture sha256 $(sha256sum < $G/vendor/squizlabs/php_codesniffer/tests/Core/Tokenizers/PHP/DoubleQuotedStringTest.inc | cut -c1-16)"
s0=$(date +%s); CANF=none pcs U23-phpcs-fixture-dqs $WS; w=$(( $(date +%s) - s0 )); t=$(ncl U23-phpcs-fixture-dqs | grep -cE 'DoubleQuotedStringTest\.inc.*(timeout|memory)|(timeout|memory).*DoubleQuotedStringTest\.inc')
chk "U23 phpcs DoubleQuotedStringTest.inc fixture: not tool_error; positive, or can't confirm with a timeout/memory entry naming it" "ok true 0|ok null 1" "$ST $SAFE $t"; chk "U23 scan wall under 300 s (accepted, main 2026-11-26: up to two capped runs)" 1 "$(( w < 300 ))"; info "U23: ${w}s $(det U23-phpcs-fixture-dqs)"
wreset; echo "DONE u0" >> $OUT/done.txt
