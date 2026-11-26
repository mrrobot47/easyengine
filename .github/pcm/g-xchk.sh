#!/bin/bash
# Cross-check redesign (2026-11-25): every code file under app/ is in the scanner's manifest or not_checked, else can't confirm.
# X*: former exemptions with a canary the scanner may not list; E*: near-misses of the three exact exempt shapes; K*: kernel path resolution; P*: must stay positive.
. "$(dirname "$0")/lib.sh"; D=$OUT/xchk; mkdir -p $D; cd /tmp
command -v rsync > /dev/null || apt-get install -y -qq rsync > /dev/null 2>&1
git config --global --add safe.directory '*'
ncl() { jq -c '.not_checked // [] | map(tostring)' "$D/$1.report.json" 2>/dev/null || jq -c '.not_checked // [] | map(tostring)' "$D/$1.out" 2>/dev/null | tail -1; }
# xc <label> <site> <canary basename> <dir token>: can't confirm or tool_error (pre-scan layout check, main 2026-11-25) naming the file or its dir, or scanned (canary found).
xc() { local l=$1 s=$2 f=$3 t=${4:-$3} L; CANF=$f pcs $l $s; L=$( { ncl $l; grep -a '^{' "$D/$l.out" | tail -1; } | grep -cF -e "$f" -e "$t" | awk '{print ($1>0)}')
  chk "$l: never positive; can't confirm or tool_error with it named (not_checked or detail), or scanned (canary found)" 'ok null L=1 C=0|tool_error null L=1 C=0|ok false L=[01] C=[2-9][0-9]*' "$ST $SAFE L=$L C=$CAN"
  info "$l: $ST safe=$SAFE canary=$CAN detail=$(jq -r '.detail // empty' $D/$l.out 2>/dev/null | tail -1 | cut -c1-200) not_checked=$(ncl $l | cut -c1-300)"; }
notpos() { CANF=$3 pcs $1 $2; chk "$1: never positive (tool_error / can't confirm / canary found)" 'tool_error null [0-9]*|ok null [0-9]*|ok false [2-9][0-9]*' "$ST $SAFE $CAN"; info "$1: $ST safe=$SAFE canary=$CAN detail=$(jq -r '.detail // empty' $D/$1.out 2>/dev/null | tail -1 | cut -c1-250) not_checked=$(ncl $1 | cut -c1-300)"; }
pos() { CANF=none pcs $1 $2; chk "$1: positive (ok true, nothing unchecked)${3:+ $3}" 'ok true \[\]' "$ST $SAFE $(ncl $1)"; [ "$SAFE" = true ] || info "$1: $ST safe=$SAFE detail=$(jq -r '.detail // empty' $D/$1.out 2>/dev/null | tail -1 | cut -c1-250) not_checked=$(ncl $1 | cut -c1-400)"; }
CLEAN='<?php
/*
Plugin Name: PCM Clean
*/
function pcm_clean() { return 1; }
'
clean() { mkdir -p "$(dirname "$1")"; printf '%s' "$CLEAN" > "$1"; }
X=px-wp.test; run_ee c-$X site create $X --type=wp --title=px $W; AP=$SITES_DIR/$X/app; H=$AP/htdocs; chown -R 33:33 $AP
info "fresh app/: $(cd $AP && find . -maxdepth 2 | sort | tr '\n' ' ' | cut -c1-600)"
# app/ is a link to the site's docker volume: snapshot its contents, not the link
rm -rf /var/tmp/px-app; mkdir -p /var/tmp/px-app; cp -a $AP/. /var/tmp/px-app/; [ -L /var/tmp/px-app ] && exit 1
reset() { rsync -a --delete /var/tmp/px-app/ $AP/; chown -R 33:33 $AP; [ -z "$(cd $AP && find . -name 'pcm-*' -o -name '.pcm*' | head -1)" ] || info "reset left: $(cd $AP && find . -name 'pcm-*' | head -3 | tr '\n' ' ')"; }

# --- must stay positive
pos P0-fresh $X
wpx $X 'plugin install hello-dolly' > $D/P1-wpcli.log 2>&1; wpx $X 'plugin delete hello-dolly' >> $D/P1-wpcli.log 2>&1; wpx $X 'core verify-checksums' >> $D/P1-wpcli.log 2>&1
info "P1 wp-cli: $(tail -3 $D/P1-wpcli.log | tr '\n' ' ' | cut -c1-200); dot entries: $(cd $AP && find . -maxdepth 4 -name '.*' | sort | tr '\n' ' ' | cut -c1-400)"; pos P1-wpcli-cache $X "(WP-CLI caches in app/.wp-cli)"
reset; (cd $H && git init -q && git -c user.email=a@example.com -c user.name=pcm add -A && git -c user.email=a@example.com -c user.name=pcm commit -qm init); chown -R 33:33 $H; info "P2 htdocs repo HEAD $(git -C $H rev-parse --short HEAD 2>&1) objects $(find $H/.git/objects -type f | wc -l)"; pos P2-htdocs-git-repo $X
reset; G=$H/wp-content/plugins/pcm-git; clean $G/pcm-git.php; mkdir -p $G/.github/workflows; printf 'on: push\n' > $G/.github/workflows/ci.yml; printf 'root = true\n' > $G/.editorconfig; printf '{"name":"acme/pcm-git"}\n' > $G/composer.json
(cd $G && git init -q && git -c user.email=a@example.com -c user.name=pcm add -A && git -c user.email=a@example.com -c user.name=pcm commit -qm init); chown -R 33:33 $H; pos P3-plugin-git-clone $X
reset; mkdir -p $H/.well-known/acme-challenge; printf 'tok.en\n' > $H/.well-known/acme-challenge/AbC123; printf 'Contact: mailto:a@example.com\n' > $H/.well-known/security.txt; chown -R 33:33 $H; pos P4-well-known-non-code $X
reset; mkdir -p $AP/.composer/cache/files/acme $AP/.cache/wp-cli $AP/.npm/_logs $AP/.wp-cli; head -c 2048 /dev/urandom > $AP/.composer/cache/files/acme/x.zip; printf '{"require":{}}\n' > $AP/.composer/composer.json
printf '{}\n' > $AP/.cache/wp-cli/x.json; printf 'log\n' > $AP/.npm/_logs/x.log; printf 'path: /var/www/htdocs\n' > $AP/.wp-cli/config.yml; chown -R 33:33 $AP; pos P5-home-dot-dirs-non-code $X "(.wp-cli/config.yml path: /var/www/htdocs)"
printf 'path: htdocs\n' > $AP/.wp-cli/config.yml; chown 33:33 $AP/.wp-cli/config.yml; CANF=none pcs P5r-relative-path-config $X; chk "P5r .wp-cli/config.yml path: htdocs (WP-CLI resolves it from the config's dir, a non-existent WordPress): tool_error naming config.yml (fails closed)" 'tool_error null 1' "$ST $SAFE $(jq -r '.detail // empty' $D/P5r-relative-path-config.out 2>/dev/null | tail -1 | grep -cF '.wp-cli/config.yml')"
reset; printf '<?php $upgrading = %s; ?>' "$(date +%s)" > $H/.maintenance; chown 33:33 $H/.maintenance; CANF=none pcs P6-maintenance-flag $X; chk "P6 clean .maintenance (PHP WordPress loads): positive, or can't confirm naming it (acceptable, reported)" 'ok true|ok null 1' "$ST $SAFE$([ "$SAFE" = null ] && echo " $( { ncl P6-maintenance-flag; grep -a '^{' $D/P6-maintenance-flag.out | tail -1; } | grep -cF .maintenance | awk '{print ($1>0)}')")"; info "P6: $ST safe=$SAFE not_checked=$(ncl P6-maintenance-flag | cut -c1-200)"
reset; mkdir -p $H/wp-content/themes/twentytwentyfive/node_modules/acme; printf 'module.exports=1;\n' > $H/wp-content/themes/twentytwentyfive/node_modules/acme/index.js; chown -R 33:33 $H; pos P7-theme-node-modules-js $X

# clean twins: dot-named PHP plugins ship, clean code reached through links
reset; G=$H/wp-content/plugins/pcm-dev; clean $G/pcm-dev.php; printf '<?php\nreturn ( new PhpCsFixer\\Config() )->setRules( array() );\n' > $G/.php-cs-fixer.dist.php
printf '<?php\nnamespace PHPSTORM_META {\n\toverride( \\pcm_clean(0), map( array( "" => "@" ) ) );\n}\n' > $G/.phpstorm.meta.php; mkdir -p $G/vendor/acme; printf '<?php\nreturn array();\n' > $G/vendor/acme/.php_cs.dist; chown -R 33:33 $H; pos P8-plugin-dot-named-php $X "(.php-cs-fixer.dist.php, .phpstorm.meta.php)"
reset; mkdir -p $AP/src/plug; clean $AP/src/plug/sib.php; ln -s ../../../src/plug $H/wp-content/plugins/sib; chown -R 33:33 $AP; chown -h 33:33 $H/wp-content/plugins/sib; pos P9-clean-plugin-linked-to-app-sibling $X
reset; mkdir -p $AP/.wp-cli/packages/vendor/acme/cmd/src; printf '<?php\nnamespace Acme;\nclass Cmd { public function __invoke() { return 1; } }\n' > $AP/.wp-cli/packages/vendor/acme/cmd/src/Cmd.php; printf '<?php\nreturn array();\n' > $AP/.wp-cli/packages/vendor/autoload.php; chown -R 33:33 $AP
CANF=none pcs P10-wp-cli-package-clean $X; chk "P10 clean WP-CLI package tree in app/.wp-cli/packages: can't confirm or tool_error, naming .wp-cli (fail closed)" 'ok null 1|tool_error null 1' "$ST $SAFE $( { ncl P10-wp-cli-package-clean; grep -a '^{' $D/P10-wp-cli-package-clean.out | tail -1; } | grep -cF .wp-cli | awk '{print ($1>0)}')"; info "P10: $ST safe=$SAFE not_checked=$(ncl P10-wp-cli-package-clean | cut -c1-200)"

# --- former exemptions: a canary code file must not leave the site positive
c() { reset; plant "$2"; chown -R 33:33 $AP; xc "$1" $X "$(basename "$2")" "$3"; }
c X1-composer-vendor $AP/.composer/vendor/acme/pcm-x1.php .composer
c X2-wpcli-packages $AP/.wp-cli/packages/vendor/acme/pcm-x2.php .wp-cli
c X3-cache $AP/.cache/pcm-x3.php .cache
c X4-any-app-dot-dir $AP/.pcmhidden/pcm-x4.php .pcmhidden
c X5-well-known $H/.well-known/pcm-x5.php .well-known
c X6-acme-challenge $H/.well-known/acme-challenge/pcm-x6.php .well-known
c X7-htdocs-dot-dir $H/.hidden/pcm-x7.php .hidden
reset; clean $H/wp-content/plugins/pcm-dd/pcm-dd.php; plant $H/wp-content/plugins/pcm-dd/.lib/pcm-x8.php; chown -R 33:33 $H; xc X8-plugin-dot-dir $X pcm-x8.php .lib
reset; clean $H/wp-content/plugins/pcm-df/pcm-df.php; plant $H/wp-content/plugins/pcm-df/.pcm-x9.php; chown -R 33:33 $H; xc X9-plugin-dotfile $X .pcm-x9.php .pcm-x9
c X10-wp-content-dot-dir $H/wp-content/.pcm/pcm-x10.php .pcm/
c X11-beside-htdocs $AP/pcm-x11.php pcm-x11
c X12-beside-htdocs-subdir $AP/lib/pcm-x12.php lib/
c X13-beside-htdocs-inc $AP/pcm-x13.inc pcm-x13
c X14-beside-htdocs-phtml $AP/pcm-x14.phtml pcm-x14
c X1u-composer-upper-PHP $AP/.composer/vendor/acme/pcm-x1u.PHP .composer
c X1s-composer-php7 $AP/.composer/vendor/acme/pcm-x1s.php7 .composer
c X1m-composer-module $AP/.composer/vendor/acme/pcm-x1m.module .composer
c X15-wp-config-old $AP/wp-config-old.php wp-config-old
c X16-htdocs-git-php $H/.git/hooks/pcm-x16.php .git
reset; clean $H/wp-content/plugins/pcm-nm/pcm-nm.php; plant $H/wp-content/plugins/pcm-nm/node_modules/acme/pcm-x17.php; chown -R 33:33 $H; xc X17-node-modules-php $X pcm-x17.php node_modules
c X18-cache-dir-code $H/wp-content/cache/pcm-x18.php cache/
c X19-upgrade-dir-code $H/wp-content/upgrade/pcm-x19.php upgrade/
reset; rm -rf $H/wp-content/cache; mkdir -p $AP/shared/cache; ln -s ../../shared/cache $H/wp-content/cache; plant $AP/shared/cache/pcm-x21.php; chown -R 33:33 $AP; chown -h 33:33 $H/wp-content/cache; xc X21-linked-cache-to-shared $X pcm-x21.php cache
reset; rm -rf $H/wp-content/uploads; mkdir -p $AP/shared/uploads/2026/11; ln -s ../../shared/uploads $H/wp-content/uploads; plant $AP/shared/uploads/2026/11/pcm-x22.php; chown -R 33:33 $AP; chown -h 33:33 $H/wp-content/uploads; xc X22-linked-uploads-plain-site $X pcm-x22.php uploads

# --- near-misses of the exact exempt shapes
reset; cp -a $AP/wp-config.php $H/wp-config.php; chown 33:33 $H/wp-config.php; pos E7-imported-wpconfig-unused-app-wpconfig $X "(exempt shape)"
printf '\n$pcm_f = create_function( "", "return 1;" );\n' >> $AP/wp-config.php; CANF=wp-config.php pcs E7b-unused-app-wpconfig-legacy $X; info "E7b unused app/wp-config.php with legacy code (exempt by design?): $ST safe=$SAFE canary=$CAN detail=$(jq -r '.detail // empty' $D/E7b-unused-app-wpconfig-legacy.out | tail -1 | cut -c1-200)"
reset; printf '\n$pcm_f = create_function( "", "return 1;" );\neach( $pcm_a );\n' >> $AP/wp-config.php
printf "<?php\nrequire __DIR__ . '/../wp-config.php';\n" > $H/wp-config.php; chown 33:33 $H/wp-config.php $AP/wp-config.php; notpos E7c-htdocs-wpconfig-requires-app-wpconfig $X wp-config.php
reset; cp -a $AP/wp-config.php $H/wp-config.php; plant $AP/wp-config-extra.php; chown -R 33:33 $AP; xc E7d-imported-plus-app-extra $X wp-config-extra.php wp-config-extra
# E8/E8b record only: wp-admin/ and wp-includes/ are the disclosed "Not checked: WordPress core files" area (main, 2026-11-25)
rec8() { reset; plant "$2"; chown -R 33:33 $H; CANF=$(basename "$2") pcs $1 $X; info "$1 (record only, core area): $ST safe=$SAFE canary=$CAN not_checked=$(ncl $1 | cut -c1-200)"; }
rec8 E8-non-core-file-in-wp-admin $H/wp-admin/pcm-e8.php; rec8 E8b-non-core-file-in-wp-includes $H/wp-includes/pcm-e8b.php
# Y1 (extended coverage, main 2026-11-25): WP in htdocs/wp, stock index.php loading wp/wp-blog-header.php, wp-config.php copied to htdocs/, app/wp-config.php left unused: real scan
y1() { reset; mkdir -p $H/wp; (cd $H && for e in * .[!.]*; do [ "$e" = wp ] || [ ! -e "$e" ] || mv "$e" wp/; done); sed 's#/wp-blog-header.php#/wp/wp-blog-header.php#' $H/wp/index.php > $H/index.php; cp -a $AP/wp-config.php $H/wp-config.php; chown -R 33:33 $AP; }
y1; info "Y1 layout: htdocs=[$(ls -A $H | tr '\n' ' ')] index.php require: $(grep -n 'require' $H/index.php | tr '\n' ' ') http=$(curl -s -o /dev/null -w '%{http_code}' -H 'Host: px-wp.test' http://127.0.0.1/)"
pos Y1-wp-subdir-stock-index-copied-wpconfig $X "(real scan, app/wp-config.php unused)"; info "Y1: checked=$(jq -c .checked $D/Y1-wp-subdir-stock-index-copied-wpconfig.out 2>/dev/null | tail -1) cross_check=$(jq -c .cross_check $D/Y1-wp-subdir-stock-index-copied-wpconfig.out 2>/dev/null | tail -1 | cut -c1-200)"
y1; plant $H/wp/wp-content/plugins/pcm-y1/pcm-y1.php; chown -R 33:33 $H; CANF=pcm-y1.php pcs Y1c-wp-subdir-canary $X; chk "Y1c same layout with a canary plugin: scanned, canary found" 'ok false [2-9][0-9]*' "$ST $SAFE $CAN"; info "Y1c: $ST safe=$SAFE canary=$CAN detail=$(jq -r '.detail // empty' $D/Y1c-wp-subdir-canary.out 2>/dev/null | tail -1 | cut -c1-200)"
# Y2/Y3 (#546 review F1/F2): EE's unused app/wp-config.php holds legacy code and becomes reachable, or is stale beside a moved root: never positive
LEG='\n$pcm_f = create_function( "", "return 1;" );\neach( $pcm_a );\n'
neverpos() { CANF=${3:-wp-config.php} pcs $1 $2; chk "$1: never positive (tool_error / can't confirm / not safe)" 'tool_error null|ok null|ok false' "$ST $SAFE"
  info "$1: $ST safe=$SAFE errors=$ERRS canary=$CAN http=$(curl -s -o /dev/null -w '%{http_code}' -H "Host: $2" http://127.0.0.1/${4:-}) detail=$(jq -r '.detail // empty' $D/$1.out 2>/dev/null | tail -1 | cut -c1-200) error_files=$(jq -c '[.components[]?.findings[]? | select(.type=="ERROR") | .file] | unique' $D/$1.report.json 2>/dev/null | cut -c1-200) unlisted=$(jq -c '.cross_check.unlisted // empty' $D/$1.out 2>/dev/null | tail -1 | cut -c1-200)"; }
y1; printf "$LEG" >> $AP/wp-config.php; ln -s ../wp-config.php $H/x.php; chown -h 33:33 $H/x.php; neverpos Y2-htdocs-link-to-app-wpconfig $X wp-config.php x.php
y1; printf "$LEG" >> $AP/wp-config.php; mkdir -p $H/sub; ln -s /var/www/wp-config.php $H/sub/x.php; chown -R 33:33 $H/sub; chown -h 33:33 $H/sub/x.php; neverpos Y2b-sub-abs-link-to-app-wpconfig $X wp-config.php sub/x.php
y1; mv $H/wp-config.php $H/wp/wp-config.php; printf "$LEG" >> $AP/wp-config.php; ln -s ../wp-config.php $H/x.php; chown -h 33:33 $H/x.php; neverpos Y2c-config-in-wp-root-plus-link $X wp-config.php x.php
reset; mkdir -p $AP/releases; mv $H $AP/releases/2; ln -s releases/2 $H; cp -a $AP/wp-config.php $AP/releases/wp-config.php; printf "$LEG" >> $AP/wp-config.php; chown -R 33:33 $AP; chown -h 33:33 $H
info "Y3 layout: app=[$(ls -A $AP | tr '\n' ' ')] htdocs -> $(readlink $H) releases=[$(ls -A $AP/releases | tr '\n' ' ')]"; neverpos Y3-htdocs-link-to-release-stale-app-wpconfig $X wp-config.php
rm -f $H; mv $AP/releases/2 $H; rm -rf $AP/releases
# Y3b: same link, the root's own clean releases/2/wp-config.php (web and wp --path load it), stale app/wp-config.php with legacy code: positive
y3b() { reset; mkdir -p $AP/releases; mv $H $AP/releases/2; ln -s releases/2 $H; cp -a $AP/wp-config.php $AP/releases/2/wp-config.php; printf "$LEG" >> $AP/wp-config.php; chown -R 33:33 $AP; chown -h 33:33 $H; }
y3b; info "Y3b WordPress loads: $(wpx $X "eval 'echo ABSPATH;'" 2>&1 | tail -1) http=$(curl -s -o /dev/null -w '%{http_code}' -H 'Host: px-wp.test' http://127.0.0.1/)"; pos Y3b-release-root-own-config-stale-app-wpconfig $X "(root config loaded, app/wp-config.php stale)"
# Y3c (record only): Y3b plus the Y3 parent config app/releases/wp-config.php (unloaded, clean)
y3b; cp -a $AP/releases/2/wp-config.php $AP/releases/wp-config.php; chown 33:33 $AP/releases/wp-config.php; CANF=none pcs Y3c-root-and-parent-config $X; info "Y3c (record only): $ST safe=$SAFE detail=$(jq -r '.detail // empty' $D/Y3c-root-and-parent-config.out 2>/dev/null | tail -1 | cut -c1-200) unlisted=$(jq -c '.cross_check.unlisted // empty' $D/Y3c-root-and-parent-config.out 2>/dev/null | tail -1 | cut -c1-200)"
rm -f $H; mv $AP/releases/2 $H; rm -f $H/wp-config.php; rm -rf $AP/releases
# Z (#546 58fa1dad): code-named links leaving the site's files, WP-CLI require/inherit, links into live core: never positive
y1; printf "$LEG" >> $AP/wp-config.php; mkdir -p $AP/.wp-cli/packages/vendor; ln -s ../../../../www/wp-config.php $AP/.wp-cli/packages/vendor/autoload.php; chown -R 33:33 $AP/.wp-cli; chown -h 33:33 $AP/.wp-cli/packages/vendor/autoload.php
info "Z1 link resolves in the container to: $(cd $SITES_DIR/$X && docker-compose exec -T php readlink -f /var/www/.wp-cli/packages/vendor/autoload.php 2>&1 | tail -1)"; neverpos Z1-wpcli-autoload-link-to-app-wpconfig $X wp-config.php
reset; mkdir -p $H/wp-includes/dl; plant $H/wp-includes/dl/pcm-z2.php; ln -s ../../wp-includes/dl $H/wp-content/plugins/dl; chown -R 33:33 $H; chown -h 33:33 $H/wp-content/plugins/dl; neverpos Z2-plugin-link-into-wp-includes $X pcm-z2.php
y1; printf "$LEG" >> $AP/wp-config.php; printf 'path: wp\nrequire:\n  - /var/www/wp-config.php\n' > $H/wp-cli.yml; chown 33:33 $H/wp-cli.yml; neverpos Z3-wpcli-yml-require-app-wpconfig $X wp-config.php
y1; printf "$LEG" >> $AP/wp-config.php; mkdir -p $AP/.wp-cli; printf 'require:\n  - /var/www/wp-config.php\n' > $AP/.wp-cli/config.yml; chown -R 33:33 $AP/.wp-cli; neverpos Z3b-home-wpcli-config-require $X wp-config.php
y1; printf "$LEG" >> $AP/wp-config.php; printf 'path: wp\ninherit: /var/www/pcm-z3c.yml\n' > $H/wp-cli.local.yml; printf 'require:\n  - /var/www/wp-config.php\n' > $AP/pcm-z3c.yml; chown -R 33:33 $AP; neverpos Z3c-wpcli-local-inherit-require $X wp-config.php
# must stay positive: a plugin carrying a dangling non-code link (node_modules/.bin style)
reset; G=$H/wp-content/plugins/pcm-dang; clean $G/pcm-dang.php; mkdir -p $G/node_modules/.bin; ln -s ../acme/bin/cli.js $G/node_modules/.bin/acme; chown -R 33:33 $G; chown -h 33:33 $G/node_modules/.bin/acme; CANF=none pcs P13-plugin-dangling-noncode-link $X; chk "P13 plugin with a dangling node_modules/.bin link: not positive, the link named unreadable in not_checked (accepted, main 2026-11-25)" 'ok null 1' "$ST $SAFE $(ncl P13-plugin-dangling-noncode-link | grep -cF 'node_modules/.bin/acme')"
reset; G=$H/wp-content/plugins/pcm-dang; clean $G/pcm-dang.php; ln -s gone.php $G/link.php; chown -R 33:33 $G; chown -h 33:33 $G/link.php; CANF=none pcs P13b-plugin-dangling-code-link $X; chk "P13b plugin with a dangling link.php: not positive, the link named unreadable in not_checked" 'ok null 1' "$ST $SAFE $(ncl P13b-plugin-dangling-code-link | grep -cF 'link.php')"; info "P13b: $ST safe=$SAFE not_checked=$(ncl P13b-plugin-dangling-code-link | cut -c1-200) detail=$(jq -r '.detail // empty' $D/P13b-plugin-dangling-code-link.out 2>/dev/null | tail -1 | cut -c1-200)"

C=px-cur.test; run_ee c-$C site create $C --type=wp --public-dir=current --title=px $W; CA=$SITES_DIR/$C/app; CH=$CA/htdocs
mkdir -p $CH/releases $CH/shared/uploads; mv $CH/current $CH/releases/175; ln -s releases/175 $CH/current; ln -s ../wp-config.php $CH/releases/wp-config.php; rm -rf $CH/releases/175/wp-content/uploads; ln -s ../../../shared/uploads $CH/releases/175/wp-content/uploads
cp -a $CH/releases/175 $CH/releases/174; chown -R 33:33 $CA; chown -h 33:33 $CH/current $CH/releases/wp-config.php $CH/releases/175/wp-content/uploads $CH/releases/174/wp-content/uploads; rec cur-cicd $C > /dev/null
rm -rf /var/tmp/px-cur; mkdir -p /var/tmp/px-cur; cp -a $CA/. /var/tmp/px-cur/; creset() { rsync -a --delete /var/tmp/px-cur/ $CA/; chown -R 33:33 $CA; }
pos E0-cicd $C "(old release 174 beside live 175)"
creset; info "P12 EE's own wp-cli.yml: [$(tr '\n' ' ' < $CH/wp-cli.yml)]"; pos P12-ee-public-dir-wpcli-yml $C "(EE's --public-dir wp-cli.yml, path: only)"
plant $CH/releases/174/wp-content/plugins/pcm-old/pcm-e2.php; chown -R 33:33 $CH; CANF=pcm-e2.php pcs E2-old-release-legacy $C; chk "E2 legacy code only in an old release (not served): positive (exempt shape)" 'ok true' "$ST $SAFE"; info "E2: canary=$CAN not_checked=$(ncl E2-old-release-legacy | cut -c1-200)"
ln -s releases/174 $CH/previous; chown -h 33:33 $CH/previous; CANF=pcm-e2.php pcs E2p-previous-pointer-wp $C; chk "E2p wp CI/CD, htdocs/previous -> releases/174 with legacy code there: positive (release pointer, shape a)" 'ok true' "$ST $SAFE"; info "E2p: canary=$CAN not_checked=$(ncl E2p-previous-pointer-wp | cut -c1-200) unlisted=$(jq -c '.cross_check.unlisted // empty' $D/E2p-previous-pointer-wp.out 2>/dev/null | tail -1 | cut -c1-200)"; rm -f $CH/previous
cc() { creset; plant "$2"; chown -R 33:33 $CA; xc "$1" $C "$(basename "$2")" "$3"; }
cc E3-stray-file-in-releases $CH/releases/pcm-e3.php pcm-e3
cc E4-htdocs-root-beside-current $CH/pcm-e4.php pcm-e4
cc E5-shared-lib-unlinked $CH/shared/lib/pcm-e5.php shared/
cc E6-app-beside-htdocs-cicd $CA/pcm-e6.php pcm-e6
creset; mkdir -p $CH/shared/uploads/2026/11; printf '<?php\n// Silence is golden.\n' > $CH/shared/uploads/2026/11/index.php; chown -R 33:33 $CH; pos P11-clean-php-in-shared-uploads-cicd $C
creset; plant $CH/shared/uploads/2026/11/pcm-e9.php; chown -R 33:33 $CA; xc E9-shared-uploads-cicd $C pcm-e9.php uploads
# releases present but nginx root is htdocs (default public dir): old releases are served, so not exempt
reset; mkdir -p $H/releases/1/lib; plant $H/releases/1/lib/pcm-e10.php; chown -R 33:33 $H; notpos E10-releases-under-plain-root $X pcm-e10.php

# --- kernel path resolution
P=$H/wp-content/plugins
reset; mkdir -p $AP/deep/a/b $AP/deep/a/pkr; plant $AP/deep/a/pkr/pcm-k1.php; clean $P/pkr/pkr.php; ln -s ../../../deep/a/b $P/s; ln -s s/../pkr $P/pk; chown -R 33:33 $AP; chown -h 33:33 $P/s $P/pk
info "K1 kernel: $(readlink -f $P/pk); lexical: $P/pkr"; notpos K1-link-dotdot-through-link $X pcm-k1.php
reset; mkdir -p $AP/deep/c/d; cp -a $H/wp-content $AP/deep/c/wp-content; plant $AP/deep/c/wp-content/plugins/pcm-k2/pcm-k2.php; ln -s ../deep/c/d $H/wpx; chown -R 33:33 $AP; chown -h 33:33 $H/wpx
sed -i "1a define( 'WP_CONTENT_DIR', '/var/www/htdocs/wpx/../wp-content' );" $AP/wp-config.php; info "K2 WordPress sees: $(wpx $X "eval 'echo WP_CONTENT_DIR, \" \", realpath(WP_CONTENT_DIR);'" 2>&1 | tail -1)"; notpos K2-wp-content-dir-dotdot-through-link $X pcm-k2.php
reset; plant $AP/deep/abs/pabs/pcm-k3.php; ln -s /var/www/deep/abs/pabs $P/pabs; chown -R 33:33 $AP; chown -h 33:33 $P/pabs; notpos K3-absolute-container-path-link $X pcm-k3.php
reset; plant $AP/deep/k5/pcm-k5.php; ln -s /var/www/htdocs/../deep/k5 $P/pk5; chown -R 33:33 $AP; chown -h 33:33 $P/pk5; notpos K5-absolute-link-with-dotdot $X pcm-k5.php
reset; ln -s loop $P/loop; ln -s ../../../../.. $P/up; chown -h 33:33 $P/loop $P/up; s=$(date +%s); CANF=none pcs K4-loop-and-root-link $X; w=$(( $(date +%s) - s ))
chk "K4 self-loop and a link to the container's / in plugins: completes (ok or tool_error)" 'ok null|tool_error null|ok true' "$ST $SAFE"; chk "K4 wall under 120 s" 1 "$(( w < 120 ))"; info "K4: $ST safe=$SAFE ${w}s detail=$(jq -r '.detail // empty' $D/K4-loop-and-root-link.out | tail -1 | cut -c1-200) not_checked=$(ncl K4-loop-and-root-link | cut -c1-200)"
reset; echo "DONE xchk" >> $OUT/done.txt
