#!/bin/bash
# Layouts and file sets on sites created with the RC. Usage: g-layouts.sh
. "$(dirname "$0")/lib.sh"; D=$OUT/layouts; mkdir -p $D; cd /tmp
WD=pl-wp.test; MS=pl-msd.test; MD=pl-msub.test; PH=pl-php.test; PP=pl-phppub.test; PC=pl-phpcicd.test; HT=pl-html.test; Z=pl-zero.test; BIG=pl-big.test; CL=pl-clean.test
run_ee c-$WD site create $WD --type=wp --title=pl $W
run_ee c-$CL site create $CL --type=wp --title=pl $W
run_ee c-$MS site create $MS --type=wp --mu=subdir --title=pl $W
run_ee c-$MD site create $MD --type=wp --mu=subdom --title=pl $W
for s in $PH $PC $Z $BIG; do run_ee c-$s site create $s --type=php; done
run_ee c-$PP site create $PP --type=php --public-dir=public
run_ee c-$HT site create $HT --type=html
for s in $WD $CL $MS $MD $PH $PP $PC $Z $BIG $HT; do rec created $s > /dev/null; done
A() { echo $SITES_DIR/$1/app/htdocs; }
# clean default WordPress: safe to upgrade for 8.4
pcs clean $CL; chk "L clean default WP: status/safe/errors" 'ok true 0' "$ST $SAFE $ERRS"; info "clean table: $(cd /tmp && ee site php-compat $CL --php=8.4 < /dev/null 2>&1 | head -1)"
for v in 7.4 8.0 8.5 8.6; do PCV=$v pcs clean-$v $CL; info "clean default WP for $v: $ST safe=$SAFE errors=$ERRS"; done
# default wp with a canary plugin
plant $(A $WD)/wp-content/plugins/pcm-canary/pcm-canary.php; expect_found L-wp-default $WD '/var/www/htdocs'
# multisite
for s in $MS $MD; do plant $(A $s)/wp-content/plugins/pcm-canary/pcm-canary.php; expect_found L-ms-$s $s '/var/www/htdocs'; done
# canary in a theme, an mu-plugin and a drop-in
mkdir -p $(A $WD)/wp-content/themes/pcm-theme; printf '/*\nTheme Name: PCM Theme\n*/\n' > $(A $WD)/wp-content/themes/pcm-theme/style.css
CANF=pcm-theme-fn.php; plant $(A $WD)/wp-content/themes/pcm-theme/pcm-theme-fn.php; pcs L-theme $WD; chk "L theme canary found" '[2-9]|[1-9][0-9]+' "$CAN"
CANF=pcm-mu.php; plant $(A $WD)/wp-content/mu-plugins/pcm-mu.php; pcs L-mu $WD; chk "L mu-plugin canary found" '[2-9]|[1-9][0-9]+' "$CAN"
CANF=db.php; plant $(A $WD)/wp-content/db.php; pcs L-dropin $WD; chk "L drop-in db.php canary found" '[2-9]|[1-9][0-9]+' "$CAN"
unset CANF
# symlinked plugins: inside htdocs (scanned) and outside htdocs (host path, dangling in the container: can't confirm, never safe)
plant $(A $CL)/shared/plug-in/pcm-link-in.php; ln -sfn ../../shared/plug-in $(A $CL)/wp-content/plugins/plug-in; chown -h 33:33 $(A $CL)/wp-content/plugins/plug-in
CANF=pcm-link-in.php pcs L-link-in $CL; chk "L symlinked plugin inside htdocs: canary found (or not safe)" '[2-9]:.*|0:(false|null)' "$CAN:$SAFE"
info "L-link-in not_checked: $(jq -c .not_checked $D/L-link-in.report.json 2>/dev/null)"
# same for a theme and an mu-plugin file linked from htdocs/shared, and a plugin linked from htdocs/vendor (composer)
mkdir -p $(A $CL)/shared/theme-in; printf '/*\nTheme Name: PCM Linked\n*/\n' > $(A $CL)/shared/theme-in/style.css; plant $(A $CL)/shared/theme-in/pcm-theme-link.php
ln -sfn ../../shared/theme-in $(A $CL)/wp-content/themes/theme-in; plant $(A $CL)/shared/pcm-mu-link.php; mkdir -p $(A $CL)/wp-content/mu-plugins; ln -sfn ../../shared/pcm-mu-link.php $(A $CL)/wp-content/mu-plugins/pcm-mu-link.php
plant $(A $CL)/vendor/acme/plug-v/pcm-vendor-link.php; ln -sfn ../../vendor/acme/plug-v $(A $CL)/wp-content/plugins/plug-v; chown -R 33:33 $(A $CL)
pcs L-link-more $CL; for f in pcm-link-in.php pcm-theme-link.php pcm-mu-link.php pcm-vendor-link.php; do chk "L linked from inside htdocs, $f: reported (or the verdict isn't safe)" '[2-9]:.*|0:(false|null)' "$(canary L-link-more $f):$SAFE"; done
rm -rf $(A $CL)/wp-content/plugins/plug-in $(A $CL)/wp-content/plugins/plug-v $(A $CL)/wp-content/themes/theme-in $(A $CL)/wp-content/mu-plugins/pcm-mu-link.php $(A $CL)/shared $(A $CL)/vendor
mkdir -p /opt/pc-ext/plug-out; plant /opt/pc-ext/plug-out/pcm-link-out.php; ln -sfn /opt/pc-ext/plug-out $(A $CL)/wp-content/plugins/plug-out
pcs L-link-out $CL; chk "L symlinked plugin outside htdocs (dangling in container): status/safe (never true)" 'ok (false|null)|tool_error null' "$ST $SAFE"
info "L-link-out not_checked: $(jq -c .not_checked $D/L-link-out.report.json 2>/dev/null | cut -c1-300)"; rm -f $(A $CL)/wp-content/plugins/plug-out
# empty mu-plugins dir and 0-byte drop-ins on the clean site: still safe
mkdir -p $(A $CL)/wp-content/mu-plugins; : > $(A $CL)/wp-content/object-cache.php; : > $(A $CL)/wp-content/advanced-cache.php; chown -R 33:33 $(A $CL)/wp-content
pcs L-empty-dropins $CL; chk "L empty mu-plugins + 0-byte drop-ins: status/safe" 'ok true' "$ST $SAFE"
# non-.php PHP code included by a plugin
for e in inc phtml module install theme engine php5 php7 phps; do plant $(A $WD)/wp-content/plugins/pcm-ext/pcm-x.$e; done
printf '<?php\n/*\nPlugin Name: PCM Ext\n*/\nforeach ( glob( __DIR__ . "/pcm-x.*" ) as $f ) { include $f; }\n' > $(A $WD)/wp-content/plugins/pcm-ext/pcm-ext.php; chown 33:33 $(A $WD)/wp-content/plugins/pcm-ext/pcm-ext.php
pcs L-ext $WD
for e in inc phtml module install theme engine php5 php7; do chk "L legacy code in .$e (included by the plugin) reported" '[2-9]|[1-9][0-9]+' "$(canary L-ext pcm-x.$e)"; done
rm -rf $(A $WD)/wp-content/plugins/pcm-ext
# odd file names, each a canary
O=$(A $WD)/wp-content/plugins/pcm-odd; mkdir -p "$O"
for n in 'sp ace.php' $'new\nline.php' $'bad\xff\xfename.php' '-dash.php' '--report=full.php' ' lead.php' 'trail .php' 'semi;colon.php' 'quote"q.php' "apos'q.php" 'star*.php' 'utf8-ünï.php' $'esc\e[31m.php' 'a.b.c.php' '.hidden.php' 'UPPER.PHP'; do printf '%s' "$CANARY" > "$O/$n"; done
printf '<?php\n/*\nPlugin Name: PCM Odd\n*/\n' > "$O/pcm-odd.php"; chown -R 33:33 "$O"; chmod -R a+rX "$O"
pcs L-odd $WD; n=$(jq '[.components[]? | select(.slug=="pcm-odd") | .findings[] | select(.type=="ERROR")] | length' $D/L-odd.report.json 2>/dev/null)
chk "L odd names: errors in pcm-odd (15 .php canaries x 2; UPPER.PHP is not .php)" '3[0-9]' "$n"
info "L-odd files reported: $(jq -c '[.components[]? | select(.slug=="pcm-odd") | .findings[] | .file] | unique' $D/L-odd.report.json 2>/dev/null | cut -c1-600)"
info "L-odd table (cleaned names): $(cd /tmp && ee site php-compat $WD --php=8.4 < /dev/null 2>&1 | grep -a -E 'dash|esc|bad' | head -6 | cat -v | tr '\n' ' ')"
chk "L UPPER.PHP canary reported (PHP runs it if included)" '[1-9][0-9]*' "$(canary L-odd UPPER.PHP)"
rm -rf "$O"
# php sites
plant $(A $PH)/legacy/pcm-canary.php; expect_found L-php $PH '/var/www/htdocs'
plant $(A $PP)/public/pcm-canary.php; CANF=pcm-src.php plant $(A $PP)/src/pcm-src.php; expect_found L-php-public $PP '/var/www/htdocs/public'
CANF=pcm-src.php pcs L-php-public-src $PP; chk "L php --public-dir: code outside the public dir (src/) scanned" '[2-9]|[1-9][0-9]+' "$CAN"
mkdir -p $(A $PC)/releases/1 $(A $PC)/releases/2; plant $(A $PC)/releases/1/pcm-old.php; plant $(A $PC)/releases/2/pcm-canary.php; ln -sfn releases/2 $(A $PC)/current
expect_found L-php-cicd $PC '/var/www/htdocs(/current)?'
# Accepted (main, 22:5x): nginx serves htdocs, so releases/1 is in scope; the verdict must not be Safe.
chk "L php CI/CD (record says htdocs): old release in scope, never Safe" 'ok false|tool_error null' "$ST $SAFE"; info "L php CI/CD old-release canary errors: $(canary L-php-cicd pcm-old.php)"
# zero PHP files
rm -f $(A $Z)/*.php; echo hi > $(A $Z)/index.html; pcs L-zero $Z; chk "L php site with zero PHP files: status" 'no_code_found' "$ST"
info "L-zero table: $(cd /tmp && ee site php-compat $Z --php=8.4 < /dev/null 2>&1 | head -2 | tr '\n' ' ')"
# html refused
(cd /tmp && ee site php-compat $HT --php=8.4) < /dev/null > $D/html.out 2>&1; chk "L html site refused rc" 1 "$?"; has "L html refusal message" "supports wp and php sites" "$(cat $D/html.out)"
(cd /tmp && ee site php-compat $HT --php=8.4 --format=json) < /dev/null > $D/html-json.out 2> $D/html-json.err; info "html json: stdout [$(cat $D/html-json.out)] stderr [$(cat $D/html-json.err | tr '\n' ' ')]"
# large vendor + thousands of files: 20,000 files in a plugin vendor/, canary deep inside
V=$(A $BIG)/vendor; mkdir -p $V; body=$(for i in $(seq 1 40); do echo "\$v$i = strtoupper( 'x$i' );"; done)
for d in $(seq 1 100); do mkdir -p $V/pkg$d/src; for i in $(seq 1 200); do printf '<?php\nnamespace P%d;\n%s\n' $d "$body" > $V/pkg$d/src/C$i.php; done; done
plant $V/pkg77/src/deep/deeper/pcm-canary.php; chown -R 33:33 $(A $BIG); n=$(find $(A $BIG) -name '*.php' | wc -l); info "L big: $n php files, $(du -sh $(A $BIG) | cut -f1)"
s0=$(date +%s); expect_found L-big $BIG '/var/www/htdocs'; info "L big scan wall $(( $(date +%s) - s0 )) s, duration_s $(jq -r .duration_s $D/L-big.out)"
chk "L big: files_checked + not_checked = find count" "$n" "$(( ${FC:-0} + ${NC:-0} ))"
info "L big estimate: $(cat $D/L-big-est.out | cut -c1-300)"
lo=$(jq -r .estimated_seconds_low $D/L-big-est.out | tail -1); hi=$(jq -r .estimated_seconds_high $D/L-big-est.out | tail -1); du=$(jq -r .duration_s $D/L-big.out | tail -1)
chk "L big: scan duration within the estimate's range (F6)" 'in' "$([ "$du" -ge "$lo" ] 2>/dev/null && [ "$du" -le "$hi" ] && echo in || echo "out[$du not in $lo-$hi]")"
pcs L-big-t1 $BIG --timeout=1; chk "L big --timeout=1: status, no verdict" 'tool_error null' "$ST $SAFE"; has "L big --timeout=1 detail" "timed out after 1 s" "$(cat $D/L-big-t1.out)"
chk "L big --timeout=1: no report written" absent "$([ -e $D/L-big-t1.report.json ] && echo present || echo absent)"
chk "L leftovers after --timeout=1: containers / temp dirs" ' 0' "$(docker ps -a --format '{{.Names}}' | grep '^ee-php-compat-' | tr '\n' ' ') $(find /opt/easyengine/tmp/php-compat -mindepth 2 -maxdepth 2 -not -path "*/php-compat/.*" 2>/dev/null | wc -l)"
echo "DONE layouts" >> $OUT/done.txt
