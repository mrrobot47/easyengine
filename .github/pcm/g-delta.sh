#!/bin/bash
# Delta-review cells (#546 F1-F7) and scanner r5 cells (dockerfiles#404). Usage: g-delta.sh
. "$(dirname "$0")/lib.sh"; D=$OUT/delta; mkdir -p $D; cd /tmp
A() { echo $SITES_DIR/$1/app; }
inj() { sed -i "1a $1" "$2"; }
# never positive: tool_error, can't confirm, or a scan that finds the canary
refused() { CANF=$3 pcs $1 $2; chk "$1: refused (tool_error)" 'tool_error null' "$ST $SAFE"; info "$1: $ST safe=$SAFE canary=$CAN detail=$(jq -r '.detail // empty' $D/$1.out 2>/dev/null | tail -1 | cut -c1-250)"; }
notpos() { CANF=$3 pcs $1 $2; chk "$1: never positive (tool_error / can't confirm / canary found)" 'tool_error null [0-9]*|ok null [0-9]*|ok false [2-9][0-9]*' "$ST $SAFE $CAN"; info "$1: $ST safe=$SAFE canary=$CAN detail=$(jq -r '.detail // empty' $D/$1.out 2>/dev/null | tail -1 | cut -c1-250)"; }
clean() { pcs $1 $2; chk "$1: clean site stays positive (safe_to_upgrade true)" 'ok true' "$ST $SAFE"; info "$1: $ST safe=$SAFE files=$FC not_checked=$NC detail=$(jq -r '.detail // empty' $D/$1.out 2>/dev/null | tail -1 | cut -c1-250) duration=$(jq -r .duration_s $D/$1.out 2>/dev/null | tail -1)"; }
WS=pdl-wp.test; run_ee c-$WS site create $WS --type=wp --title=pd $W; AP=$(A $WS); H=$AP/htdocs; WPC=$AP/wp-config.php; cp -a $WPC /var/tmp/pdl-wpc.php
rc() { cp -a /var/tmp/pdl-wpc.php $WPC; }
clean D0-clean $WS
# F1: WP_CONTENT_DIR spelled through a link + `..` (lexically the default, really inside uploads)
mkdir -p $H/wp-content/uploads/a/b $H/wp-content/uploads/a/wp-content/plugins/pcm-f1; cp -a $H/wp-content/themes $H/wp-content/uploads/a/wp-content/; plant $H/wp-content/uploads/a/wp-content/plugins/pcm-f1/pcm-f1.php
ln -s wp-content/uploads/a/b $H/L; chown -R 33:33 $H; chown -h 33:33 $H/L
rc; inj "define( 'WP_CONTENT_DIR', '/var/www/htdocs/L/../wp-content' );" $WPC; refused F1a-abs $WS pcm-f1.php
rc; inj "define( 'WP_CONTENT_DIR', ABSPATH . 'L/../wp-content' );" $WPC; refused F1b-abspath $WS pcm-f1.php
rc; inj "define( 'WP_CONTENT_DIR', __DIR__ . '/htdocs/L/../wp-content' );" $WPC; refused F1c-dir $WS pcm-f1.php
rc; rm -f $H/L; rm -rf $H/wp-content/uploads/a
# nested install: htdocs/old with wp-settings.php + wp-includes (+ a plugin with the canary)
mkdir -p $H/old; cp -a $H/wp-settings.php $H/wp-includes $H/wp-admin $H/old/; mkdir -p $H/old/wp-content/plugins/pcm-n; plant $H/old/wp-content/plugins/pcm-n/pcm-n.php; chown -R 33:33 $H/old
refused N1-nested-install $WS pcm-n.php; rm -rf $H/old
# scanner r5: Wordfence wflogs, W3TC cache, CodeMirror test/README, .phar, .tpl
mkdir -p $H/wp-content/wflogs; for f in attack-data config config-livewaf config-synced config-transient ips rules; do printf "<?php exit('Access denied'); __halt_compiler(); ?>\n******************************************************************\nThis file is used by the Wordfence Web Application Firewall. Read\nmore at https://docs.wordfence.com/en/Web_Application_Firewall_FAQ\n******************************************************************\na:3:{s:7:\"version\";s:5:\"1.0.0\";s:4:\"data\";s:20:\"%s\x00\x01\x02binary\";}" "$f" > $H/wp-content/wflogs/$f.php; done
printf '<?php\n/*\nPlugin Name: Wordfence Security\nVersion: 8.0.5\n*/\n' > $H/wp-content/plugins/wordfence.php 2>/dev/null || true; mkdir -p $H/wp-content/plugins/wordfence; mv $H/wp-content/plugins/wordfence.php $H/wp-content/plugins/wordfence/wordfence.php; chown -R 33:33 $H/wp-content
clean R5a-wordfence-wflogs $WS
mkdir -p $H/wp-content/cache/object; for i in $(seq 1 2500); do d=$H/wp-content/cache/object/$(printf '%03d' $((i % 50))); mkdir -p $d; printf '<?php exit; ?>a:1:{s:4:"data";s:%d:"%s";}' 10 "cache$i" > $d/$(printf '%032x' $i).php; done; chown -R 33:33 $H/wp-content/cache
t0=$(date +%s); clean R5b-w3tc-disk-cache $WS; info "R5b wall $(( $(date +%s) - t0 )) s"; rm -rf $H/wp-content/cache/object
P=$H/wp-content/plugins/pcm-cm; mkdir -p $P/assets/codemirror/mode/php; printf '<?php\n/*\nPlugin Name: PCM CodeMirror\n*/\n' > $P/pcm-cm.php
printf '(function() {\n  var mode = CodeMirror.getMode({indentUnit: 2}, "php");\n  MT("simple_test", "[meta <?php] [keyword echo] [string \\"aaa\\"]; [meta ?>]");\n  MT("variable_interpolation_non_alphanumeric", "[meta <?php]", "[keyword echo] [string \\"aaa$~$!$@$#$$$%%$^$&$*$($)$.$<$>$/$\\\\$}$\\\\\\"$:$;$?$|$[[$]]$+$=aaa\\"]", "[meta ?>]");\n})();\n' > $P/assets/codemirror/mode/php/test.js
printf '# PHP mode\n\nUsage:\n\n```\n<?php echo "hi"; ?>\n<?php\n```\n' > $P/assets/codemirror/mode/php/README.md; printf 'Quote: <?php unfinished\n' > $P/README.md; chown -R 33:33 $P
t0=$(date +%s); clean R5c-codemirror-quotes $WS; chk "R5c finished within 300 s (no hang)" 'ok' "$([ $(( $(date +%s) - t0 )) -le 300 ] && echo ok || echo slow)"; rm -rf $P
P=$H/wp-content/plugins/pcm-phar; mkdir -p $P; printf '<?php\n/*\nPlugin Name: PCM Phar\n*/\nrequire "phar://" . __DIR__ . "/lib.phar/index.php";\n' > $P/pcm-phar.php
docker run --rm -v $P:/w -w /w php:8.4-cli php -d phar.readonly=0 -r '$p = new Phar("/w/lib.phar"); $p->addFromString("index.php", "<?php \$x = create_function(\"\", \"return 1;\"); each(\$a);"); $p->setStub("<?php __HALT_COMPILER();");' > $D/phar-build.txt 2>&1 || printf 'not a real phar' > $P/lib.phar
chown -R 33:33 $P; info "R5d phar: $(ls -l $P/lib.phar 2>&1) $(cat $D/phar-build.txt | head -2)"
pcs R5d-phar $WS; chk "R5d a .phar in a plugin: can't confirm (or the code inside reported), never positive" 'ok null|ok false|tool_error null' "$ST $SAFE"; info "R5d: $ST safe=$SAFE not_checked=$(jq -c .not_checked $D/R5d-phar.out 2>/dev/null | tail -1 | cut -c1-200)"; rm -rf $P
P=$H/wp-content/plugins/pcm-tpl; mkdir -p $P/tpl; printf '<?php\n/*\nPlugin Name: PCM Tpl\n*/\ninclude __DIR__ . "/tpl/view.tpl";\n' > $P/pcm-tpl.php; printf '%s' "$CANARY" | sed 's#Plugin Name: PCM Canary##' > $P/tpl/view.tpl; chown -R 33:33 $P
CANF=view.tpl pcs R5e-tpl $WS; chk "R5e .tpl with PHP included by a plugin: scanned (canary found) or never positive" 'ok false [2-9][0-9]*|ok null [0-9]*|tool_error null [0-9]*' "$ST $SAFE $CAN"; chk "R5e .tpl canary found (scanned)" '[2-9][0-9]*' "$CAN"; rm -rf $P
# CI/CD --public-dir=current site: F3 link to the old release inside the live one; F6 WPMU_PLUGIN_DIR default spelled with current/ and no mu-plugins dir
C=pdl-cur.test; run_ee c-$C site create $C --type=wp --public-dir=current --title=pd $W; CH=$(A $C)/htdocs
mkdir -p $CH/releases; mv $CH/current $CH/releases/2; ln -s releases/2 $CH/current; ln -s ../wp-config.php $CH/releases/wp-config.php; chown -h 33:33 $CH/current $CH/releases/wp-config.php
plant $CH/releases/2/wp-content/plugins/pcm-live/pcm-live.php; chown -R 33:33 $CH; CANF=pcm-live.php pcs D1-cicd-live $C; chk "D1 CI/CD live release (baseline): real scan" 'ok false [2-9][0-9]*' "$ST $SAFE $CAN"
rm -rf $CH/releases/2/wp-content/mu-plugins; CCFG=$CH/wp-config.php; cp -a $CCFG /var/tmp/pdl-cur-wpc.php
inj "define( 'WPMU_PLUGIN_DIR', '/var/www/htdocs/current/wp-content/mu-plugins' );" $CCFG; CANF=pcm-live.php pcs F6-wpmu-default-no-dir $C; chk "F6 WPMU_PLUGIN_DIR default (via current/) with no mu-plugins dir: real scan" 'ok false [2-9][0-9]*' "$ST $SAFE $CAN"; info "F6 detail: $(jq -r '.detail // empty' $D/F6-wpmu-default-no-dir.out | tail -1)"; cp -a /var/tmp/pdl-cur-wpc.php $CCFG
rm -rf $CH/releases/2/wp-content/plugins/pcm-live; cp -a $CH/releases/2 $CH/releases/1; plant $CH/releases/1/wp-content/plugins/pcm-old/pcm-old.php; ln -s ../1 $CH/releases/2/old; chown -R 33:33 $CH; chown -h 33:33 $CH/releases/2/old
refused F3-link-to-old-release $C pcm-old.php
info "F3 detail mentions another WordPress install: $(jq -r '.detail // empty' $D/F3-link-to-old-release.out | grep -c 'another WordPress install')"
# V7: newer-than-table rule: WordPress 7.2 on a site running PHP 8.4; target 8.5 positive, target 7.4 can't confirm
T=pdl-72.test; run_ee c-$T site create $T --type=wp --php=8.4 --title=pd $W; TV=$(A $T)/htdocs/wp-includes/version.php
sed -i "s/^\\\$wp_version = '[^']*';/\\\$wp_version = '7.2';/" $TV; info "V7 version.php: $(grep -o "wp_version = '[^']*'" $TV); site php $(db "select php_version from sites where site_url='$T'")"
PCV=8.5 pcs V7-72-on-84-to-85 $T; chk "V7 WordPress 7.2 (PHP 8.4 site) for 8.5: positive" 'ok true' "$ST $SAFE"; info "V7 8.5 wordpress: $(jq -c .wordpress $D/V7-72-on-84-to-85.out 2>/dev/null | tail -1)"
PCV=7.4 pcs V7-72-on-84-to-74 $T; chk "V7 WordPress 7.2 (PHP 8.4 site) for 7.4: can't confirm" 'ok null' "$ST $SAFE"; info "V7 7.4 wordpress: $(jq -c .wordpress $D/V7-72-on-84-to-74.out 2>/dev/null | tail -1); table: $(cd /tmp && ee site php-compat $T --php=7.4 < /dev/null 2>&1 | grep -v '^$' | head -1 | cut -c1-200)"
chk "no scanner containers left" 0 "$(docker ps -aq --filter ancestor=$SC:v4.16.0 | wc -l)"
echo "DONE delta" >> $OUT/done.txt
