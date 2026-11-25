#!/bin/bash
# Cells for the FABLE-REVIEW-546 blockers/majors. Each: the scan covers the code WordPress/PHP really loads (canary found, not safe) or gives tool_error; never Safe, never no_code_found.
. "$(dirname "$0")/lib.sh"; D=$OUT/fable; mkdir -p $D; cd /tmp
A() { echo $SITES_DIR/$1/app; }
# cover <label> <site> <canary file name>
cover() { CANF=$3 pcs $1 $2; chk "$1: covered (ok+canary) or tool_error, never Safe/no_code_found" 'ok false [2-9]|tool_error null 0' "$ST $SAFE $CAN"; info "$1: $ST safe=$SAFE canary=$CAN argv=$ARGP detail=$(jq -r '.detail // empty' $D/$1.out 2>/dev/null | tail -1 | cut -c1-200)"; }
WS=pfa-wp.test; run_ee c-$WS site create $WS --type=wp --title=pf $W; AP=$(A $WS); H=$AP/htdocs; WPC=$AP/wp-config.php
cp -a $H /var/tmp/pf-pristine; cp -a $WPC /var/tmp/pf-wpconfig.php
reset() { find $H -mindepth 1 -delete; cp -a /var/tmp/pf-pristine/. $H/; cp -a /var/tmp/pf-wpconfig.php $WPC; rm -rf $AP/content $AP/plugins $AP/wp-config-local.php; chown -R 33:33 $H; }
inj() { sed -i "1a $1" "$2"; }
# R0/R19: file-scope const
reset; mkdir -p $H/content; cp -a $H/wp-content/. $H/content/; plant $H/content/plugins/pcm-r0a/pcm-r0a.php; inj "const WP_CONTENT_DIR = '/var/www/htdocs/content';" $WPC; chown -R 33:33 $H; cover R0a-const-content $WS pcm-r0a.php
reset; plant $AP/plugins/pcm-r0b/pcm-r0b.php; inj "const WP_PLUGIN_DIR = '/var/www/plugins';" $WPC; chown -R 33:33 $AP/plugins; cover R0b-const-plugindir $WS pcm-r0b.php
reset; mkdir -p $H/wp; mv $H/* $H/wp/ 2>/dev/null; mkdir -p $H/content; cp -a $H/wp/wp-content/. $H/content/; plant $H/content/plugins/pcm-r0c/pcm-r0c.php
printf '<?php\nrequire __DIR__ . "/wp/wp-blog-header.php";\n' > $H/index.php; cp $WPC $H/wp-config.php; inj "const WP_CONTENT_DIR = __DIR__ . '/content';" $H/wp-config.php; rm -f $WPC; chown -R 33:33 $H; cover R0c-const-subdir $WS pcm-r0c.php
# R1/R22: wp-config.php requires a local config file
reset; mkdir -p $AP/content; cp -a $H/wp-content/. $AP/content/; plant $AP/content/plugins/pcm-r1a/pcm-r1a.php; printf "<?php\ndefine( 'WP_CONTENT_DIR', '/var/www/content' );\n" > $AP/wp-config-local.php
inj "require __DIR__ . '/wp-config-local.php';" $WPC; chown -R 33:33 $AP/content $AP/wp-config-local.php; cover R1a-local-config $WS pcm-r1a.php
reset; printf '%s' "$CANARY" | sed 's#Plugin Name: PCM Canary##' > $AP/wp-config-local.php; inj "require __DIR__ . '/wp-config-local.php';" $WPC; chown 33:33 $AP/wp-config-local.php; cover R1c-local-config-code $WS wp-config-local.php
reset; inj "include __DIR__ . '/config/' . getenv( 'WP_ENV' ) . '.php';" $WPC; mkdir -p $AP/config; printf "<?php\ndefine( 'WP_CONTENT_DIR', '/var/www/content' );\n" > $AP/config/.php; mkdir -p $AP/content; cp -a $H/wp-content/. $AP/content/; plant $AP/content/plugins/pcm-r1d/pcm-r1d.php; chown -R 33:33 $AP/config $AP/content; cover R1d-env-include $WS pcm-r1d.php; rm -rf $AP/config
# R1e: the included config file inside htdocs: scanned (canary found)
reset; printf '%s' "$CANARY" | sed 's#Plugin Name: PCM Canary##' > $H/wp-config-local.php; inj "require __DIR__ . '/htdocs/wp-config-local.php';" $WPC; chown 33:33 $H/wp-config-local.php
CANF=wp-config-local.php pcs R1e-local-config-in-htdocs $WS; chk "R1e unconditional config include (inside htdocs): scanned with canary, or tool_error; never Safe" 'ok false [2-9]|tool_error null 0' "$ST $SAFE $CAN"
# R1f: the accepted local-config form (file_exists-guarded, same literal path, target inside the WP root, config-only content): scanned
reset; printf "<?php\ndefine( 'WP_DEBUG', false );\n" > $H/wp-config-local.php; inj "if ( file_exists( __DIR__ . '/htdocs/wp-config-local.php' ) ) { require_once( __DIR__ . '/htdocs/wp-config-local.php' ); }" $WPC; plant $H/wp-content/plugins/pcm-r1f/pcm-r1f.php; chown -R 33:33 $H
CANF=pcm-r1f.php pcs R1f-local-config-guarded $WS; chk "R1f guarded local config inside the WP root: scanned (accepted form)" 'ok false [2-9]' "$ST $SAFE $CAN"; info "R1f detail: $(jq -r '.detail // empty' $D/R1f-local-config-guarded.out | tail -1 | cut -c1-200)"; info "R1e detail: $(jq -r '.detail // empty' $D/R1e-local-config-in-htdocs.out | tail -1)"
# Common wp-config.php lines must not be refused (plugin canary found)
reset; for l in "define( 'WP_DEBUG', false );" "define( 'WP_MEMORY_LIMIT', '256M' );" "define( 'DISALLOW_FILE_EDIT', true );" "define( 'FS_METHOD', 'direct' );" "define( 'WP_REDIS_HOST', 'global-redis' );" "define( 'WP_CACHE_KEY_SALT', 'x:' );" "define( 'WP_HOME', 'http://' . \$_SERVER['HTTP_HOST'] );" "define( 'WP_CONTENT_URL', 'http://example.test/wp-content' );" "define( 'WP_POST_REVISIONS', 5 );" "define( 'AUTOMATIC_UPDATER_DISABLED', true );" "@ini_set( 'upload_max_filesize', '64M' );"; do inj "$l" $WPC; done
plant $H/wp-content/plugins/pcm-common/pcm-common.php; chown -R 33:33 $H; info "common wp-config head: $(sed -n 1,14p $WPC | tr '\n' ' ' | cut -c1-500)"
CANF=pcm-common.php pcs C1-common-wpconfig $WS; chk "C1 typical wp-config lines: scanned, canary found (not refused)" 'ok false [2-9]' "$ST $SAFE $CAN"; info "C1 detail: $(jq -r '.detail // empty' $D/C1-common-wpconfig.out | tail -1)"
reset; inj "if ( file_exists( __DIR__ . '/wp-config-local.php' ) ) { require __DIR__ . '/wp-config-local.php'; }" $WPC; plant $H/wp-content/plugins/pcm-common/pcm-common.php; chown -R 33:33 $H
CANF=pcm-common.php pcs C2-optional-local-absent $WS; info "C2 optional local config (file absent): $ST safe=$SAFE canary=$CAN detail=$(jq -r '.detail // empty' $D/C2-optional-local-absent.out | tail -1 | cut -c1-200)"
chk "C2 optional local config absent: never Safe" 'ok false|tool_error null' "$ST $SAFE"
reset; inj "require_once __DIR__ . '/vendor/autoload.php';" $WPC; mkdir -p $AP/vendor; printf '<?php\n' > $AP/vendor/autoload.php; plant $H/wp-content/plugins/pcm-common/pcm-common.php; chown -R 33:33 $H $AP/vendor
CANF=pcm-common.php pcs C3-composer-autoload $WS; info "C3 composer autoload in wp-config: $ST safe=$SAFE canary=$CAN detail=$(jq -r '.detail // empty' $D/C3-composer-autoload.out | tail -1 | cut -c1-200)"; chk "C3 composer autoload: never Safe" 'ok false|tool_error null' "$ST $SAFE"; rm -rf $AP/vendor
# R2: WP_CONTENT_DIR to another wp-content: root custom PHP and wp-config.php itself still checked
reset; mkdir -p $H/shared; cp -a $H/wp-content $H/shared/wp-content; inj "define( 'WP_CONTENT_DIR', '/var/www/htdocs/shared/wp-content' );" $WPC; plant $H/custom-endpoint.php; chown -R 33:33 $H; cover R2a-root-endpoint $WS custom-endpoint.php
reset; mkdir -p $H/shared; cp -a $H/wp-content $H/shared/wp-content; inj "define( 'WP_CONTENT_DIR', '/var/www/htdocs/shared/wp-content' ); \$pcm_cfg = create_function( '', 'return 1;' ); each( \$pcm_a );" $WPC; chown -R 33:33 $H; cover R2b-wpconfig-code $WS wp-config.php
# R6: WP in htdocs/wp via index.php; served-root PHP outside it (htdocs/api)
reset; mkdir -p $H/wp; mv $H/* $H/wp/ 2>/dev/null; printf '<?php\nrequire __DIR__ . "/wp/wp-blog-header.php";\n' > $H/index.php; plant $H/api/legacy.php; chown -R 33:33 $H; cover R6-served-root-api $WS legacy.php
# R23: alternative-syntax conditional loader; live WordPress (with the canary) in htdocs/new, a stale copy in htdocs/old
reset; mkdir -p $H/old $H/new; cp -a /var/tmp/pf-pristine/. $H/old/; cp -a /var/tmp/pf-pristine/. $H/new/; find $H -maxdepth 1 -mindepth 1 ! -name old ! -name new -exec rm -rf {} +; rm -rf $H/old/wp-content/plugins/pcm-*; plant $H/new/wp-content/plugins/pcm-r23/pcm-r23.php
printf '<?php if ( getenv( "PCM_OLD" ) ): require __DIR__ . "/old/wp-blog-header.php"; else: require __DIR__ . "/new/wp-blog-header.php"; endif;\n' > $H/index.php; chown -R 33:33 $H; cover R23-alt-syntax $WS pcm-r23.php
printf '<?php if ( getenv( "PCM_OLD" ) ): ?><p>x</p><?php require __DIR__ . "/old/wp-blog-header.php"; endif; require __DIR__ . "/new/wp-blog-header.php";\n' > $H/index.php; cover R23b-alt-syntax-html $WS pcm-r23.php
reset
# R20: index.php in a --public-dir root loading WordPress from outside it, through forms the loader can't follow
P=pfa-pub.test; run_ee c-$P site create $P --type=wp --public-dir=public --title=pf $W; PH=$(A $P)/htdocs; v=$(rec created $P)
mkdir -p $PH/wp; cp -a $PH/public/. $PH/wp/; rm -rf $PH/public/*; plant $PH/wp/wp-content/plugins/pcm-r20/pcm-r20.php
for form in var interp heredoc wpload; do case $form in
  var) printf '<?php\n$f = dirname( __DIR__ ) . "/wp/wp-blog-header.php";\nrequire $f;\n' ;;
  interp) printf '<?php\n$wp = dirname( __DIR__ ) . "/wp";\nrequire "$wp/wp-blog-header.php";\n' ;;
  heredoc) printf '<?php\n$d = dirname( __DIR__ );\nrequire <<<EOT\n$d/wp/wp-blog-header.php\nEOT;\n' ;;
  wpload) printf '<?php\nrequire dirname( __DIR__ ) . "/wp/wp-load.php";\nwp();\nrequire_once ABSPATH . WPINC . "/template-loader.php";\n' ;;
  esac > $PH/public/index.php; chown -R 33:33 $PH; cover R20-$form $P pcm-r20.php; done
# R3: the php container's /var/www comes from another source
R=pfa-mnt.test; run_ee c-$R site create $R --type=wp --title=pf $W; mkdir -p /srv/pfa-project; cp -a $(A $R)/. /srv/pfa-project/; plant /srv/pfa-project/htdocs/wp-content/plugins/pcm-r3/pcm-r3.php; chown -R 33:33 /srv/pfa-project
mkdir -p $SITES_DIR/$R/user-docker-compose; printf 'services:\n  php:\n    volumes:\n      - /srv/pfa-project:/var/www\n' > $SITES_DIR/$R/user-docker-compose/pcm.yml
run_ee en-$R site enable $R --force; info "R3 php mounts: $(docker inspect -f '{{json .Mounts}}' $(cname $R)-php-1 2>&1 | jq -c '[.[] | select(.Destination|startswith("/var/www")) | [.Source,.Destination]]' 2>&1)"; cover R3-var-www-elsewhere $R pcm-r3.php
# R4/R37 and R5: admin-tools on a wp site and on a php site
run_ee at-$WS site restart $WS; plant $H/wp-content/plugins/pcm-r4/pcm-r4.php; chown -R 33:33 $H; run_ee ate-$WS admin-tools enable $WS; info "R4 admin-tools enable rc $RC; mounts $(docker inspect -f '{{json .Mounts}}' $(cname $WS)-php-1 2>&1 | jq -c '[.[] | select(.Destination|startswith("/var/www")) | .Destination]' 2>&1)"
CANF=pcm-r4.php pcs R4-admintools-wp $WS; chk "R4 wp site with admin-tools: scanned, canary found (not refused)" 'ok false [2-9]' "$ST $SAFE $CAN"; info "R4 detail: $(jq -r '.detail // empty' $D/R4-admintools-wp.out | tail -1)"
chk "R4 admin tools not reported as the site's code" 0 "$(jq '[.components[]? | select((.slug|test("ee-admin")) or ([.findings[]?.file] | any(test("ee-admin|phpmyadmin|opcache";"i"))))] | length' $D/R4-admintools-wp.report.json 2>/dev/null || echo 0)"
pce R4-est $WS; chk "R4 estimate with admin-tools" ok "$EST_ST"
Q=pfa-php.test; run_ee c-$Q site create $Q --type=php; plant $(A $Q)/htdocs/legacy/pcm-r5.php; run_ee ate-$Q admin-tools enable $Q
CANF=pcm-r5.php pcs R5-admintools-php $Q; chk "R5 php site with admin-tools: scanned, canary found" 'ok false [2-9]' "$ST $SAFE $CAN"
chk "R5 admin tools not scanned as the site's code (no ee-admin component, file count = the site's)" '0 2' "$(jq '[.components[]? | select(.slug|test("ee-admin"))] | length' $D/R5-admintools-php.report.json 2>/dev/null) $FC"
info "R5 components: $(jq -c '[.components[]? | "\(.type):\(.slug):\(.files)"]' $D/R5-admintools-php.report.json 2>/dev/null | cut -c1-300)"
# R35/R48: no new check may start while a delete runs
X=pfa-del.test; run_ee c-$X site create $X --type=php; plant $(A $X)/htdocs/legacy/pcm-x.php
(cd /tmp && ee site delete $X --yes) > $D/R48-delete.out 2>&1 < /dev/null & DP=$!; n=0; : > $D/R48-attempts.txt
while kill -0 $DP 2>/dev/null; do n=$((n+1)); (cd /tmp && timeout 120 ee site php-compat $X --php=8.4 --format=json) < /dev/null > $D/R48-a$n.out 2>&1; echo "$n rc=$? $(jq -r .status $D/R48-a$n.out 2>/dev/null | tail -1) $(head -c 120 $D/R48-a$n.out | tr '\n' ' ')" >> $D/R48-attempts.txt; done; wait $DP; drc=$?
info "R48 delete rc $drc; $n attempts during the delete: $(cut -c1-160 $D/R48-attempts.txt | tr '\n' ';' | cut -c1-900)"
chk "R48 no check started during the delete gave a verdict or no_code_found" 0 "$(grep -cE ' (ok|no_code_found) ' $D/R48-attempts.txt)"
chk "R48 every check during the delete: busy, tool_error, or the site is gone (Error)" 0 "$(grep -cvE '^[0-9]+ rc=[0-9]+ +(busy|tool_error|Error:) ' $D/R48-attempts.txt)"; info "R48 outcomes: $(awk '{print $3}' $D/R48-attempts.txt | sort | uniq -c | tr '\n' ' ') tool_error detail: $(grep -h -o '"detail":"[^"]*"' $D/R48-a*.out 2>/dev/null | sort -u | head -3 | tr '\n' ' ')"
sleep 3; chk "R48 after the delete: no container, temp dir or control file of the site" ' 0' "$(docker ps -a --format '{{.Names}}' | grep "ee-php-compat-$X" | tr '\n' ' ') $(find /opt/easyengine/tmp/php-compat -name "*$X*" 2>/dev/null | wc -l)"
chk "no scanner containers left (scan and estimate)" 0 "$(docker ps -aq --filter ancestor=$SC:v4.16.0 | wc -l)"
echo "DONE fable" >> $OUT/done.txt
