#!/bin/bash
# Allowlist (#546 r3) cells that must still get a real scan (over-refusal = FAIL), plus refusals that must be tool_error, never Safe.
. "$(dirname "$0")/lib.sh"; D=$OUT/allow; mkdir -p $D; cd /tmp
A() { echo $SITES_DIR/$1/app; }
scan_ok() { CANF=$3 pcs $1 $2; chk "$1: real scan, canary found (over-refusal = FAIL)" 'ok false [2-9]' "$ST $SAFE $CAN"; [ "$ST" = ok ] || info "$1 REFUSED: $(jq -r '.detail // empty' $D/$1.out 2>/dev/null | tail -1 | cut -c1-300)"; }
refuse() { CANF=$3 pcs $1 $2; chk "$1: tool_error (or a scan that finds the canary), never Safe" 'tool_error null 0|ok false [2-9]' "$ST $SAFE $CAN"; info "$1: $ST $(jq -r '.detail // empty' $D/$1.out 2>/dev/null | tail -1 | cut -c1-250)"; }
inj() { sed -i "1a $1" "$2"; }
WS=pal-wp.test; run_ee c-$WS site create $WS --type=wp --title=pa $W; AP=$(A $WS); H=$AP/htdocs; WPC=$AP/wp-config.php; cp -a $WPC /var/tmp/pal-wpconfig.php
plant $H/wp-content/plugins/pcm-al/pcm-al.php; chown -R 33:33 $H; info "EE wp-config.php: $(grep -v '^\s*$' $WPC | grep -v '^\s*//' | tr '\n' ' ' | cut -c1-900)"
rc() { cp -a /var/tmp/pal-wpconfig.php $WPC; }
scan_ok A0-default $WS pcm-al.php
# salts containing <? and ?> ; guarded WP_DEBUG ; defined() || define() ; common salts with quotes
rc; inj "define( 'AUTH_KEY', 'a<?b?>c<?php d<?=e' ); define( 'SECURE_AUTH_SALT', 'x\"y\\\\z' );" $WPC; scan_ok A1-salts-short-tag-chars $WS pcm-al.php
rc; inj "if ( ! defined( 'WP_DEBUG' ) ) { define( 'WP_DEBUG', false ); }" $WPC; scan_ok A2a-guarded-define-braced $WS pcm-al.php
rc; inj "if ( ! defined( 'WP_DEBUG' ) ) define( 'WP_DEBUG', false );" $WPC; scan_ok A2b-guarded-define-unbraced $WS pcm-al.php
rc; inj "defined( 'WP_DEBUG' ) || define( 'WP_DEBUG', false );" $WPC; scan_ok A2c-defined-or-define $WS pcm-al.php
rc; inj "define( 'WP_DEBUG', getenv( 'WP_DEBUG' ) === 'true' ); define( 'DB_HOST', isset( \$_ENV['DB_HOST'] ) ? \$_ENV['DB_HOST'] : 'db' );" $WPC; scan_ok A2d-env-values $WS pcm-al.php
rc; inj "\$table_prefix = 'wp_';" $WPC; scan_ok A2e-table-prefix $WS pcm-al.php
rc; inj "\$memcached_servers = array( 'default' => array( '127.0.0.1:11211' ) );" $WPC; scan_ok A2f-memcached-servers $WS pcm-al.php
rc; inj "\$pcm = 1;" $WPC; refuse A2g-other-variable $WS pcm-al.php
rc; inj "function pcm_x() { return 1; }" $WPC; refuse A2h-function $WS pcm-al.php
rc; inj "?><p>hi</p><?php" $WPC; refuse A2i-inline-html $WS pcm-al.php
# Wordfence (.user.ini as Wordfence writes it, quoted) and NinjaFirewall
rc; printf '; Wordfence WAF\nauto_prepend_file = %s\n; END Wordfence WAF\n' "'/var/www/htdocs/wordfence-waf.php'" > $H/.user.ini
printf "<?php\n// Before removing this file, please verify the PHP ini setting \`auto_prepend_file\` does not point to this.\nif (file_exists('/var/www/htdocs/wp-content/plugins/wordfence/waf/bootstrap.php')) {\n\tdefine(\"WFWAF_LOG_PATH\", '/var/www/htdocs/wp-content/wflogs/');\n\tinclude_once '/var/www/htdocs/wp-content/plugins/wordfence/waf/bootstrap.php';\n}\n" > $H/wordfence-waf.php; chown 33:33 $H/.user.ini $H/wordfence-waf.php
scan_ok A4a-wordfence-quoted $WS pcm-al.php; info "A4a components: $(jq -c '[.components[]? | "\(.type):\(.slug):\(.files)"]' $D/A4a-wordfence-quoted.report.json 2>/dev/null | cut -c1-300)"
printf 'auto_prepend_file = /var/www/htdocs/wordfence-waf.php\n' > $H/.user.ini; scan_ok A4b-wordfence-unquoted $WS pcm-al.php
printf 'auto_prepend_file = "/var/www/htdocs/wordfence-waf.php"\n' > $H/.user.ini; scan_ok A4c-wordfence-dquoted $WS pcm-al.php
CANF=wordfence-waf.php; printf '%s' "$CANARY" | sed 's#Plugin Name: PCM Canary##' > $H/wordfence-waf.php; chown 33:33 $H/wordfence-waf.php; CANF=wordfence-waf.php pcs A4d-wordfence-code $WS; chk "A4d legacy code in wordfence-waf.php is reported (or tool_error), never Safe" 'ok false [2-9]|tool_error null 0' "$ST $SAFE $CAN"; unset CANF; rm -f $H/wordfence-waf.php
mkdir -p $H/wp-content/nfwlog; printf '<?php\n// NinjaFirewall\nif ( ! defined( "NFW_STATUS" ) ) { define( "NFW_STATUS", 1 ); }\n' > $H/wp-content/nfwlog/ninjafirewall.php; printf 'auto_prepend_file = /var/www/htdocs/wp-content/nfwlog/ninjafirewall.php\n' > $H/.user.ini; chown -R 33:33 $H/wp-content/nfwlog $H/.user.ini
scan_ok A4e-ninjafirewall $WS pcm-al.php
mkdir -p $AP/evil; plant $AP/evil/evil.php; printf 'auto_prepend_file = /var/www/evil/evil.php\n' > $H/.user.ini; refuse A4f-prepend-outside $WS evil.php; rm -rf $AP/evil $H/.user.ini $H/wp-content/nfwlog
printf 'auto_append_file = /var/www/htdocs/x.php\n' > $H/.user.ini; refuse A4g-append $WS pcm-al.php; rm -f $H/.user.ini
# EE --public-dir=current site converted to a CI/CD release with the shared, symlinked wp-config.php (easyengine.io), + Wordfence there, + admin-tools
C=pal-cur.test; run_ee c-$C site create $C --type=wp --public-dir=current --title=pa $W; CH=$(A $C)/htdocs; rec cur-created $C > /dev/null
plant $CH/current/wp-content/plugins/pcm-al/pcm-al.php; chown -R 33:33 $CH; scan_ok A3a-public-dir-current $C pcm-al.php
run_ee at0-$C admin-tools enable $C; scan_ok A5a0-admintools-public-dir-plain $C pcm-al.php; pce A5a0-est $C; chk "A5a0 estimate with admin-tools on a plain --public-dir site" ok "$EST_ST"
mkdir -p $CH/releases $CH/shared/uploads; mv $CH/current $CH/releases/175; ln -s releases/175 $CH/current; ln -s ../wp-config.php $CH/releases/wp-config.php; rm -rf $CH/releases/175/wp-content/uploads; ln -s ../../../shared/uploads $CH/releases/175/wp-content/uploads
cp -a $CH/releases/175 $CH/releases/174; chown -R 33:33 $CH; chown -h 33:33 $CH/current $CH/releases/wp-config.php $CH/releases/175/wp-content/uploads; rec cur-cicd $C > /dev/null
scan_ok A3b-cicd-shared-wpconfig $C pcm-al.php; info "A3b argv $ARGP"
printf "auto_prepend_file = '/var/www/htdocs/current/wordfence-waf.php'\n" > $CH/releases/175/.user.ini; printf '<?php\n// wordfence\n' > $CH/releases/175/wordfence-waf.php; chown 33:33 $CH/releases/175/.user.ini $CH/releases/175/wordfence-waf.php
scan_ok A4h-wordfence-on-cicd $C pcm-al.php; rm -f $CH/releases/175/.user.ini $CH/releases/175/wordfence-waf.php
info "admin-tools on $C: rc $RC; mounts $(docker inspect -f '{{json .Mounts}}' $(cname $C)-php-1 2>&1 | jq -c '[.[] | .Destination]' 2>&1)"
scan_ok A5a-admintools-public-dir-cicd $C pcm-al.php; pce A5a-est $C; chk "A5a estimate with admin-tools on the CI/CD --public-dir site" ok "$EST_ST"
P=pal-php.test; run_ee c-$P site create $P --type=php --public-dir=public; plant $(A $P)/htdocs/public/pcm-php.php; run_ee at-$P admin-tools enable $P
scan_ok A5b-admintools-php-public $P pcm-php.php; chk "A5b ee-admin not scanned" 0 "$(jq '[.components[]? | select(.slug|test("ee-admin"))] | length' $D/A5b-admintools-php-public.report.json 2>/dev/null)"
# PHP 8.6 sites (php86.zip config)
S6=pal-86.test; run_ee c-$S6 site create $S6 --type=wp --php=8.6 --title=pa $W; info "8.6 wp create rc $RC; php image $(docker inspect -f '{{.Config.Image}}' $(cname $S6)-php-1 2>&1)"
plant $(A $S6)/htdocs/wp-content/plugins/pcm-al/pcm-al.php; chown -R 33:33 $(A $S6)/htdocs; scan_ok A6a-wp-php86 $S6 pcm-al.php; PCV=8.6 scan_ok A6b-wp-php86-target86 $S6 pcm-al.php
S7=pal-86p.test; run_ee c-$S7 site create $S7 --type=php --php=8.6; plant $(A $S7)/htdocs/legacy/pcm-al.php; scan_ok A6c-php-php86 $S7 pcm-al.php
# EE --vip config (if the option works here)
V=pal-vip.test; run_ee c-$V site create $V --type=wp --vip --title=pa $W
if [ $RC = 0 ]; then plant $(A $V)/htdocs/wp-content/plugins/pcm-al/pcm-al.php; chown -R 33:33 $(A $V)/htdocs; scan_ok A7-vip $V pcm-al.php; else info "A7 --vip site create failed (rc $RC): $(grep -v '^rc=' $D/c-$V.out | tail -2 | tr '\n' ' ' | cut -c1-200)"; fi
# Scoped verdict + WordPress core gate (#546 075970cd)
J() { jq -r "$1" $D/$2.out 2>/dev/null | tail -1; }
rm -rf $H/wp-content/plugins/pcm-al; rc; rm -f $H/.user.ini; pcs V1-normal $WS
chk "V1 normal site for 8.4: positive verdict (safe_to_upgrade true)" 'ok true 0' "$ST $SAFE $ERRS"
chk "V1/V4 positive verdict with not_checked empty (scanner-only list; the core note lives elsewhere)" '0 true' "$(J '.not_checked|length' V1-normal) $SAFE"
chk "V1/V4 core note present under wordpress or a notes field" 'yes' "$(jq -e '(.wordpress.version // empty) != null or (.notes // empty) != null' $D/V1-normal.out > /dev/null 2>&1 && echo yes || echo no)"; info "V1 not_checked, notes, wordpress: $(jq -c '.not_checked, .notes, .wordpress' $D/V1-normal.out 2>/dev/null | tr '\n' ' ')"
chk "V1 wordpress.supports true, files_not_checked 0" 'true 0' "$(J .wordpress.supports V1-normal) $(J .files_not_checked V1-normal)"
info "V1 json: $(head -c 700 $D/V1-normal.out | tr '\n' ' ')"; info "V1 table: $(cd /tmp && ee site php-compat $WS --php=8.4 < /dev/null 2>&1 | grep -v '^$' | head -4 | tr '\n' '|')"
PCV=8.6 pcs V2-current-wp-86 $WS; chk "V2 current WordPress for 8.6: can't confirm (null), core supports null" 'ok null null' "$ST $SAFE $(J .wordpress.supports V2-current-wp-86)"
info "V2 table: $(cd /tmp && ee site php-compat $WS --php=8.6 < /dev/null 2>&1 | grep -v '^$' | head -3 | tr '\n' '|')"
O=pal-old.test; run_ee c-$O site create $O --type=wp --title=pa $W
for ver in 4.9.26 5.9.10; do (cd $SITES_DIR/$O && docker-compose exec -T --user=www-data php sh -c "wp core download --version=$ver --force --skip-content") > $D/V3-dl-$ver.out 2>&1
  info "V3 core download $ver: $(tail -1 $D/V3-dl-$ver.out); version.php: $(grep -o "wp_version = '[^']*'" $(A $O)/htdocs/wp-includes/version.php)"
  pcs V3-old-wp-$ver $O; chk "V3 WordPress $ver for 8.4: not safe, supports false, minimum 6.7" 'ok false false 6.7' "$ST $SAFE $(J .wordpress.supports V3-old-wp-$ver) $(J .wordpress.minimum V3-old-wp-$ver)"
  t=$(cd /tmp && ee site php-compat $O --php=8.4 < /dev/null 2>&1); has "V3 $ver table carries the update hint" "update WordPress to at least 6.7" "$t"; info "V3 $ver table: $(echo "$t" | grep -v '^$' | head -4 | tr '\n' '|')"; done
PCV=7.2 pcs V3c-old-wp-72 $O; info "V3c WordPress 5.9 for 7.2: $ST safe=$SAFE supports=$(J .wordpress.supports V3c-old-wp-72)"
chk "V3c WordPress 5.9 for 7.2 (supported range 5.6-8.1): positive" 'ok true true' "$ST $SAFE $(J .wordpress.supports V3c-old-wp-72)"
# V5: WordPress newer than EE's table, and nightly/RC version strings (version.php rewritten on the normal site)
VP=$H/wp-includes/version.php; cp -a $VP /var/tmp/pal-version.php
for v in 7.2 7.3-alpha-65773 7.3-alpha-65773-src 7.1-RC2 7.1.1 6.9.1-beta1; do cp -a /var/tmp/pal-version.php $VP; sed -i "s/^\\\$wp_version = '[^']*';/\\\$wp_version = '$v';/" $VP
  l=V5-$(echo $v | tr -c 'a-z0-9.\n' '-'); pcs $l-84 $WS; info "V5 $v for 8.4: $ST safe=$SAFE wordpress=$(jq -c .wordpress $D/$l-84.out 2>/dev/null | tail -1) table: $(cd /tmp && ee site php-compat $WS --php=8.4 < /dev/null 2>&1 | grep -v '^$' | head -1 | cut -c1-200)"
  case $v in 7.2*|7.3*) chk "V5 WordPress $v (newer than the table) on a PHP 8.5 site, for 8.4 (below the site's PHP): can't confirm" 'ok null' "$ST $SAFE"
      PCV=8.5 pcs $l-85 $WS; chk "V5 WordPress $v (newer than the table) for 8.5 (the site's PHP): positive" 'ok true' "$ST $SAFE" ;;
    *) chk "V5 WordPress $v for 8.4: positive (ok true)" 'ok true' "$ST $SAFE" ;; esac
  case $v in 7.2*|7.3*) chk "V5 WordPress $v: wordpress.table_newest set" '.+' "$(jq -r '.wordpress.table_newest // empty' $D/$l-85.out 2>/dev/null | tail -1)" ;; esac
  PCV=8.6 pcs $l-86 $WS; chk "V5 WordPress $v for 8.6: can't confirm" 'ok null' "$ST $SAFE"; done
cp -a /var/tmp/pal-version.php $VP; chown 33:33 $VP
# V6: more than 10 not_checked entries: stdout capped at 10 + not_checked_more, report keeps all
mkdir -p $H/wp-content/plugins/pcm-many; printf '<?php\n/*\nPlugin Name: PCM Many\n*/\n' > $H/wp-content/plugins/pcm-many/pcm-many.php
# dangling inside the plugin (a link leaving the site's files is tool_error since #546 58fa1dad, V6b)
for i in $(seq 1 13); do ln -s missing$i.php $H/wp-content/plugins/pcm-many/gone$i.php; done; chown -R 33:33 $H/wp-content/plugins/pcm-many; chown -h 33:33 $H/wp-content/plugins/pcm-many/gone*.php
pcs V6-many-not-checked $WS; info "V6: $ST safe=$SAFE not_checked=$(J '.not_checked|length' V6-many-not-checked) more=$(J .not_checked_more V6-many-not-checked) files_not_checked=$NC report=$(jq '.not_checked|length' $D/V6-many-not-checked.report.json 2>/dev/null)"
chk "V6 13 dangling .php links: can't confirm, stdout not_checked 10 + not_checked_more 3, report 13" 'ok null 10 3 13' "$ST $SAFE $(J '.not_checked|length' V6-many-not-checked) $(J .not_checked_more V6-many-not-checked) $(jq '.not_checked|length' $D/V6-many-not-checked.report.json 2>/dev/null)"
ln -s /nonexistent/gone-out.php $H/wp-content/plugins/pcm-many/gone-out.php; chown -h 33:33 $H/wp-content/plugins/pcm-many/gone-out.php; pcs V6b-link-leaving-site $WS; chk "V6b a .php link leaving the site's files: tool_error naming it" 'tool_error null 1' "$ST $SAFE $(jq -r '.detail // empty' $D/V6b-link-leaving-site.out 2>/dev/null | tail -1 | grep -cF gone-out.php)"; rm -f $H/wp-content/plugins/pcm-many/gone-out.php
rm -rf $H/wp-content/plugins/pcm-many
chk "no scanner containers left" 0 "$(docker ps -aq --filter ancestor=$SC:v4.16.0 | wc -l)"
echo "DONE allow" >> $OUT/done.txt
