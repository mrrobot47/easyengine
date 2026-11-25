#!/bin/bash
# Fable review r3 (on 50adf0a) cells: T-items. Usage: g-fab3.sh
. "$(dirname "$0")/lib.sh"; D=$OUT/fab3; mkdir -p $D; cd /tmp
A() { echo $SITES_DIR/$1/app; }
inj() { sed -i "1a $1" "$2"; }
notpos() { CANF=$3 pcs $1 $2; chk "$1: never positive (tool_error / can't confirm / canary found)" 'tool_error null [0-9]*|ok null [0-9]*|ok false [2-9][0-9]*' "$ST $SAFE $CAN"; info "$1: $ST safe=$SAFE canary=$CAN detail=$(jq -r '.detail // empty' $D/$1.out 2>/dev/null | tail -1 | cut -c1-250)"; }
realscan() { CANF=$3 pcs $1 $2; chk "$1: real scan (canary found; over-refusal = FAIL)" 'ok false [2-9][0-9]*' "$ST $SAFE $CAN"; info "$1: $ST safe=$SAFE canary=$CAN detail=$(jq -r '.detail // empty' $D/$1.out 2>/dev/null | tail -1 | cut -c1-250)"; }
WS=pf3-wp.test; run_ee c-$WS site create $WS --type=wp --title=pf $W; AP=$(A $WS); H=$AP/htdocs; WPC=$AP/wp-config.php; cp -a $WPC /var/tmp/pf3-wpc.php; cp -a $H /var/tmp/pf3-pristine
plant $H/wp-content/plugins/pcm-t/pcm-t.php; chown -R 33:33 $H
rc() { cp -a /var/tmp/pf3-wpc.php $WPC; }
# must get a real scan
rc; inj "//END Really Simple Security cookie settings" $WPC; inj "@ini_set('session.use_only_cookies', true);" $WPC; inj "@ini_set('session.cookie_secure', true);" $WPC; inj "@ini_set('session.cookie_httponly', true);" $WPC; inj "//Begin Really Simple Security session cookie settings" $WPC
inj "define('RSSSL_KEY', 'Jc8BdPzXc7q2mH1Wf3uYkS9tRnV0eLgA');" $WPC; info "T60 head: $(sed -n 1,9p $WPC | tr '\n' ' ' | cut -c1-400)"; realscan T60-really-simple-security $WS pcm-t.php
rc; for l in "@ini_set( 'upload_max_filesize' , '128M' );" "@ini_set( 'post_max_size', '128M');" "@ini_set( 'memory_limit', '256M' );" "@ini_set( 'max_execution_time', '300' );" "@ini_set( 'max_input_time', '300' );" "define( 'WP_MEMORY_LIMIT', '256M' );"; do inj "$l" $WPC; done; realscan T65-upload-memory-snippet $WS pcm-t.php
rc; printf "<?php\ndefine( 'WP_DEBUG_LOG', false );\n" > $H/wp-config-extra.php; chown 33:33 $H/wp-config-extra.php; inj "require_once __DIR__ . '/htdocs/wp-config-extra.php';" $WPC; realscan T66-require-file-in-htdocs $WS pcm-t.php; rm -f $H/wp-config-extra.php
rc; inj "define( 'AS3CF_SETTINGS', serialize( array( 'provider' => 'aws', 'access-key-id' => 'AKIAEXAMPLE', 'secret-access-key' => 'secret', 'use-server-roles' => false ) ) );" $WPC; realscan T64-as3cf-serialize $WS pcm-t.php
# must never be positive
rc; mkdir -p $AP/elsewhere/plugins/pcm-t90; plant $AP/elsewhere/plugins/pcm-t90/pcm-t90.php; cp -a $H/wp-content/themes $AP/elsewhere/; chown -R 33:33 $AP/elsewhere; rm -rf $H/wp-content/plugins/pcm-t
inj "define( b'WP_CONTENT_DIR', b'/var/www/elsewhere' );" $WPC; notpos T90-binary-string-define $WS pcm-t90.php; rm -rf $AP/elsewhere; plant $H/wp-content/plugins/pcm-t/pcm-t.php; chown -R 33:33 $H
rc; inj "\$base = &\$wp_filter;" $WPC; notpos T23-base-reference $WS pcm-t.php
rc; find $H -mindepth 1 -delete; cp -a /var/tmp/pf3-pristine $H/wp; printf '<?php\ndefine( "WP_USE_THEMES", true );\nrequire __DIR__ . "/wp/wp-blog-header.php";\n' > $H/index.php; mv $WPC $H/wp-config.php
mkdir -p $H/.well-known; plant $H/.well-known/pcm-wk.php; chown -R 33:33 $H; notpos T36-well-known-a2 $WS pcm-wk.php; find $H -mindepth 1 -delete; cp -a /var/tmp/pf3-pristine/. $H/; rc; chown -R 33:33 $H
# T35/T59: --public-dir=current/public on a CI/CD release, canary in the live release outside public/
C=pf3-cp.test; run_ee c-$C site create $C --type=wp --public-dir=current/public --title=pf $W; CH=$(A $C)/htdocs; rec cp-created $C > /dev/null
mkdir -p $CH/releases; mv $CH/current $CH/releases/1; ln -s releases/1 $CH/current; plant $CH/releases/1/lib/x.php
mkdir -p $CH/releases/1/public/wp-content/plugins/pcm-lib; printf '<?php\n/*\nPlugin Name: PCM Lib\n*/\nrequire __DIR__ . "/../../../../lib/x.php";\n' > $CH/releases/1/public/wp-content/plugins/pcm-lib/pcm-lib.php; chown -R 33:33 $CH; chown -h 33:33 $CH/current; rec cp-cicd $C > /dev/null
notpos T35-current-public-lib $C x.php
# T62: Deployer-style shared uploads with a PHP file, on a --public-dir=current CI/CD site: a real scan (not refused)
P=pf3-dep.test; run_ee c-$P site create $P --type=wp --public-dir=current --title=pf $W; PH=$(A $P)/htdocs
mkdir -p $PH/releases $PH/shared/wp-content/uploads/2026/11; mv $PH/current $PH/releases/3; ln -s releases/3 $PH/current; ln -s ../wp-config.php $PH/releases/wp-config.php; rm -rf $PH/releases/3/wp-content/uploads; ln -s ../../../shared/wp-content/uploads $PH/releases/3/wp-content/uploads
plant $PH/shared/wp-content/uploads/2026/11/pcm-up.php; chown -R 33:33 $PH; chown -h 33:33 $PH/current $PH/releases/wp-config.php $PH/releases/3/wp-content/uploads
CANF=pcm-up.php pcs T62-deployer-shared-uploads $P; chk "T62 Deployer shared uploads with PHP: a real scan (not refused)" 'ok (true|false|null)' "$ST $SAFE"; info "T62: $ST safe=$SAFE canary=$CAN detail=$(jq -r '.detail // empty' $D/T62-deployer-shared-uploads.out | tail -1 | cut -c1-200)"
# T0: php site, CRLF .user.ini prepending /var/www/boot.php (canary)
Q=pf3-php.test; run_ee c-$Q site create $Q --type=php; plant $(A $Q)/boot.php; printf 'auto_prepend_file=/var/www/boot.php\r\n' > $(A $Q)/htdocs/.user.ini; chown 33:33 $(A $Q)/htdocs/.user.ini
notpos T0-php-crlf-userini $Q boot.php
# T75: ee site delete during a running estimate succeeds and leaves nothing
X=pf3-del.test; run_ee c-$X site create $X --type=php; XH=$(A $X)/htdocs; mkdir -p $XH/bulk; for i in $(seq 1 20000); do printf '<?php\n// %d\n$a = %d;\n' $i $i > $XH/bulk/f$i.php; done; chown -R 33:33 $XH
(cd /tmp && ee site php-compat $X --php=8.4 --estimate --format=json) > $D/T75-est.out 2>&1 < /dev/null & EP=$!
for i in $(seq 1 100); do [ -n "$(docker ps -q --filter ancestor=$SC:v4.16.0)" ] && break; sleep 0.2; done; sleep 1
run_ee T75-delete site delete $X --yes; drc=$RC; wait $EP; info "T75 delete rc $drc [$(grep -v '^rc=' $D/T75-delete.out | tail -2 | tr '\n' ' ')]; estimate [$(head -c 200 $D/T75-est.out)]"
chk "T75 ee site delete during a running estimate: succeeds, site gone" '0 0' "$drc $(db "select count(*) from sites where site_url='$X'")"; sleep 3
chk "T75 nothing left (scanner containers, temp/control files of the site)" '0 0' "$(docker ps -aq --filter ancestor=$SC:v4.16.0 | wc -l) $(find /opt/easyengine/tmp/php-compat -name "*$X*" 2>/dev/null | wc -l)"
echo "DONE fab3" >> $OUT/done.txt
