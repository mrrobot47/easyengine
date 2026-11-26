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
preset

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

# NH (#546 a1b8fb53): EE --cache site, nginx-helper's bundled Predis exempt only as the stock released pair with phpredis loaded
NH=pu-cache.test; run_ee c-$NH site create $NH --type=wp --cache --title=pu $W; NA=$(A $NH); NHD=$NA/htdocs/wp-content/plugins/nginx-helper
info "NH nginx-helper: version=$(grep -m1 -i '^ *\* *Version:' $NHD/nginx-helper.php 2>/dev/null | tr -d ' *') predis sha256=$(sha256sum < $NHD/admin/predis.php 2>/dev/null | cut -c1-16) guard sha256=$(sha256sum < $NHD/includes/class-nginx-helper.php 2>/dev/null | cut -c1-16) redis ext=$(cd $SITES_DIR/$NH && docker-compose exec -T php php -r 'echo extension_loaded("redis") ? "yes" : "no";' 2>&1 | tail -1)"
cp -a $NHD/admin/predis.php /var/tmp/pu-predis.php; cp -a $NHD/includes/class-nginx-helper.php /var/tmp/pu-guard.php
pos NH1-cache-site-stock-nginx-helper $NH "(EE --cache site, stock nginx-helper)"; ig=$(jq -c '.ignored // empty' $D/NH1-cache-site-stock-nginx-helper.out 2>/dev/null | tail -1)
chk "NH1 JSON ignored names admin/predis.php" 1 "$(echo "$ig" | grep -c 'nginx-helper/admin/predis.php')"; info "NH1: ignored=$ig table: $(cd /tmp && ee site php-compat $NH --php=8.4 < /dev/null 2>&1 | grep -i 'ignored' | head -1 | cut -c1-200)"
printf ' ' >> $NHD/admin/predis.php; CANF=predis.php neverpos NH2-predis-modified $NH predis.php; info "NH2 ignored=$(jq -c '.ignored // empty' $D/NH2-predis-modified.out 2>/dev/null | tail -1)"; cp -a /var/tmp/pu-predis.php $NHD/admin/predis.php
printf '\n// local change\n' >> $NHD/includes/class-nginx-helper.php; CANF=predis.php neverpos NH3-guard-modified $NH predis.php; info "NH3 ignored=$(jq -c '.ignored // empty' $D/NH3-guard-modified.out 2>/dev/null | tail -1)"; cp -a /var/tmp/pu-guard.php $NHD/includes/class-nginx-helper.php
pos NH4-cache-site-restored $NH "(stock pair restored)"

# U23: squizlabs php_codesniffer test fixture (tests/Core/Tokenizers/PHP/DoubleQuotedStringTest.inc, PHPCSStandards 3.x, sha256 d15e4ded) in a plugin
wreset; G=$WH/wp-content/plugins/pcm-phpcs; clean $G/pcm-phpcs.php; mkdir -p $G/vendor/squizlabs/php_codesniffer/tests/Core/Tokenizers/PHP; echo "$DQS_B64" | base64 -d > $G/vendor/squizlabs/php_codesniffer/tests/Core/Tokenizers/PHP/DoubleQuotedStringTest.inc; chown -R 33:33 $G
info "U23 fixture sha256 $(sha256sum < $G/vendor/squizlabs/php_codesniffer/tests/Core/Tokenizers/PHP/DoubleQuotedStringTest.inc | cut -c1-16)"
s0=$(date +%s); CANF=none pcs U23-phpcs-fixture-dqs $WS; w=$(( $(date +%s) - s0 )); t=$(ncl U23-phpcs-fixture-dqs | grep -cE 'DoubleQuotedStringTest\.inc.*(timeout|memory)|(timeout|memory).*DoubleQuotedStringTest\.inc')
chk "U23 phpcs DoubleQuotedStringTest.inc fixture: not tool_error; positive, or can't confirm with a timeout/memory entry naming it" "ok true 0|ok null 1" "$ST $SAFE $t"; chk "U23 scan wall under 240 s" 1 "$(( w < 240 ))"; info "U23: ${w}s $(det U23-phpcs-fixture-dqs)"
wreset; echo "DONE u0" >> $OUT/done.txt
