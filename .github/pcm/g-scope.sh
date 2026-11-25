#!/bin/bash
# Cells for the scanner scope PR (dockerfiles#400): WordPress-dir scope, upgrade-temp-backup, php code beside htdocs, dot dirs, bad-link roots, files rewritten or deleted mid-scan.
. "$(dirname "$0")/lib.sh"; D=$OUT/scope; mkdir -p $D; cd /tmp
A() { echo $SITES_DIR/$1/app/htdocs; }
waitrun() { local i; for i in $(seq 1 600); do [ "$(docker inspect -f '{{.State.Running}}' $1 2>/dev/null)" = true ] && return 0; sleep 0.2; done; return 1; }
S=ps-wp.test; run_ee c-$S site create $S --type=wp --title=ps $W; H=$(A $S)
pcs S0-clean $S; chk "S0 clean default WP still safe (core not scanned)" 'ok true' "$ST $SAFE"; info "S0 components: $(jq -c '[.components[] | "\(.type):\(.slug)"]' $D/S0-clean.report.json)"
CANF=pcm-forum.php; plant $H/forum/pcm-forum.php; pcs S1-forum $S; chk "S1 code in htdocs/forum (beside WordPress) found" '[2-9]:false' "$CAN:$SAFE"; info "S1 component: $(jq -c '[.components[] | select(.errors>0) | "\(.type):\(.slug)"]' $D/S1-forum.report.json)"; rm -rf $H/forum
CANF=pcm-loose.php; plant $H/pcm-loose.php; pcs S2-loose $S; chk "S2 loose file in the WordPress dir found" '[2-9]:false' "$CAN:$SAFE"; rm -f $H/pcm-loose.php
CANF=pcm-utb.php; plant $H/wp-content/upgrade-temp-backup/plugins/old/pcm-utb.php; pcs S3-utb $S; chk "S3 wp-content/upgrade-temp-backup scanned (web-reachable rollback copies): not safe" '[2-9][0-9]*:false' "$CAN:$SAFE"; chk "S3 finding path shows upgrade-temp-backup" 1 "$(jq '[.components[]?.findings[]? | select(.file|test("upgrade-temp-backup/.*pcm-utb.php"))] | length > 0 | if . then 1 else 0 end' $D/S3-utb.report.json 2>/dev/null)"; rm -rf $H/wp-content/upgrade-temp-backup
CANF=pcm-dotwp.php; plant $SITES_DIR/$S/app/.wp-cli/cache/pcm-dotwp.php; pcs S4-dot $S; chk "S4 www-data home dot dir (.wp-cli) with code: can't confirm, or scanned" 'ok:null:0|ok:false:[2-9][0-9]*' "$ST:$SAFE:$CAN"; rm -rf $SITES_DIR/$S/app/.wp-cli/cache/pcm-dotwp.php
# core modified with legacy code stays out of scope (core is WordPress', not the site's)
cp $H/wp-includes/version.php /var/tmp/ps-version.php; printf '\n$pcm_core = create_function( "", "return 1;" );\n' >> $H/wp-includes/version.php; CANF=version.php pcs S5-core $S; chk "S5 edited core file not scanned" '0:true' "$CAN:$SAFE"; cp /var/tmp/ps-version.php $H/wp-includes/version.php
# S11: a plugin file symlinked to a file inside wp-includes (core): recorded; never double counted, never an error from core
mkdir -p $H/wp-content/plugins/linkcore; printf '<?php\n/*\nPlugin Name: Link Core\n*/\n' > $H/wp-content/plugins/linkcore/linkcore.php
ln -s ../../../wp-includes/version.php $H/wp-content/plugins/linkcore/core-version.php; plant $H/wp-includes/pcm-in-includes.php; ln -s ../../../wp-includes/pcm-in-includes.php $H/wp-content/plugins/linkcore/pcm-in-includes.php; chown -R 33:33 $H/wp-content/plugins/linkcore
CANF=pcm-in-includes.php pcs S11-linkcore $S; info "S11 plugin links into wp-includes: $ST safe=$SAFE errors=$ERRS canary=$CAN components=$(jq -c '[.components[] | select(.slug=="linkcore") | {files,errors,f:[.findings[].file]}]' $D/S11-linkcore.report.json 2>/dev/null) not_checked=$(jq -c .not_checked $D/S11-linkcore.report.json 2>/dev/null)"
info "S11 by design: anything under wp-includes/ or wp-admin/ is core, also when a plugin links to it (canary:safe $CAN:$SAFE)"
rm -rf $H/wp-content/plugins/linkcore $H/wp-includes/pcm-in-includes.php
# S12: a deep link out of htdocs into the app sibling (app/src), reached from a plugin dir: found once
plant $SITES_DIR/$S/app/src/plug/pcm-sib.php; ln -s ../../../src/plug $H/wp-content/plugins/sib; chown -h 33:33 $H/wp-content/plugins/sib
CANF=pcm-sib.php pcs S12-sibling $S; chk "S12 plugin linked to app/src beside htdocs: canary found exactly once, or tool_error (code outside the WP root)" '2:false|0:null' "$CAN:$SAFE"
info "S12 components: $(jq -c '[.components[] | select(.errors>0) | "\(.type):\(.slug):\(.errors)"]' $D/S12-sibling.report.json 2>/dev/null)"; rm -f $H/wp-content/plugins/sib; rm -rf $SITES_DIR/$S/app/src
unset CANF
# php: code beside htdocs (/var/www/src), dot dirs skipped, dangling htdocs
P=ps-php.test; run_ee c-$P site create $P --type=php; PA=$SITES_DIR/$P/app
CANF=pcm-src.php; plant $PA/src/pcm-src.php; pcs S6-beside $P; chk "S6 php code beside htdocs (app/src) found" '[2-9]:false' "$CAN:$SAFE"; info "S6 components: $(jq -c '[.components[] | "\(.type):\(.slug)"]' $D/S6-beside.report.json)"
rm -rf $PA/src; CANF=pcm-comp.php; plant $PA/.composer/vendor/x/pcm-comp.php; pcs S7-dot $P; chk "S7 php .composer with code: can't confirm, or scanned" 'ok:null:0|ok:false:[2-9][0-9]*' "$ST:$SAFE:$CAN"; rm -rf $PA/.composer; rm -rf $PA/src
mkdir -p $PA/src/lib; plant $PA/src/lib/pcm-deep.php; ln -s ../src/lib $PA/htdocs/deeplib; CANF=pcm-deep.php pcs S7b-deep $P; chk "S7b php htdocs/deeplib -> ../src/lib (app sibling): found exactly once" '2:false' "$CAN:$SAFE"; rm -f $PA/htdocs/deeplib; rm -rf $PA/src
mv $PA/htdocs $PA/htdocs.real; ln -s /nonexistent/htdocs $PA/htdocs; pcs S8-dangling $P; chk "S8 php htdocs a dangling link: can't confirm or tool_error, not no_code_found" 'ok null|tool_error null' "$ST $SAFE"; rm $PA/htdocs; mv $PA/htdocs.real $PA/htdocs
mv $H/wp-content /srv/ps-wpc; ln -s /srv/ps-wpc $H/wp-content; pcs S9-wpc-host $S; chk "S9 wp-content -> host path: can't confirm or tool_error, not no_code_found" 'ok null|tool_error null' "$ST $SAFE"; rm $H/wp-content; mv /srv/ps-wpc $H/wp-content
# files rewritten / deleted between the listing and their batch (zz* sort last)
B=ps-big.test; run_ee c-$B site create $B --type=php; BH=$(A $B); mkdir -p $BH/bulk; body=$(for i in $(seq 1 120); do echo "\$v$i = strtoupper( 'line $i' ) . PHP_EOL;"; done)
for i in $(seq 1 6000); do printf '<?php\n// %d\n%s\n' $i "$body" > $BH/bulk/f$i.php; done; printf '<?php\necho 1;\n' > $BH/zz-rewrite.php; printf '<?php\necho 2;\n' > $BH/zz-delete.php; chown -R 33:33 $BH
(cd /tmp && ee site php-compat $B --php=8.4 --format=json --output=/root/pcm-out/S10.json) > $D/S10.out 2>&1 < /dev/null & P1=$!; waitrun ee-php-compat-$B; sleep 3
printf '%s' "$CANARY" > $BH/zz-rewrite.php; rm -f $BH/zz-delete.php; wait $P1; cp /root/pcm-out/S10.json $D/S10.report.json 2>/dev/null
info "S10 result: $(head -c 300 $D/S10.out); not_checked: $(jq -c .not_checked $D/S10.report.json 2>/dev/null)"
chk "S10 rewritten mid-scan: checked as it is then (canary found)" '[2-9]' "$(canary S10 zz-rewrite.php)"
chk "S10 deleted mid-scan: not_checked unreadable, verdict not safe" '1 (false|null)' "$(jq '[.not_checked[] | select(.file|endswith("zz-delete.php"))] | length' $D/S10.report.json 2>/dev/null) $(jq -r .safe_to_upgrade $D/S10.out | tail -1)"
echo "DONE scope" >> $OUT/done.txt
