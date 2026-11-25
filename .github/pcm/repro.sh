#!/bin/bash
# Top priority (user's report): wp sites created with --public-dir on an old stable (or the RC), lifecycle operations on the old version,
# upgrade to the RC, then php-compat + the same operations on the RC. Records the DB site_container_fs_path, nginx root and wp-cli.yml after
# every step and the path php-compat passes to the scanner.
# Usage: repro.sh create|ops-old|upgrade|scan|ops-new|layouts
. "$(dirname "$0")/lib.sh"; P=$1; D=$OUT/repro/$P; mkdir -p $D; cd /tmp
P1=pc-cur.test; P2=pc-nest.test; P3=pc-space.test; PD=pc-def.test
# canary location from the DB path (the WordPress directory the site record names) and, failing that, the first wp-content found.
canary_into() { local s=$1 rel wc; rel=$(db "select site_container_fs_path from sites where site_url='$s'" | sed 's#^/var/www/##')
  wc=$SITES_DIR/$s/app/$rel/wp-content; [ -d "$wc" ] || wc=$(find -L $SITES_DIR/$s/app/htdocs -maxdepth 4 -type d -name wp-content | head -1)
  [ -n "$wc" ] && plant "$wc/plugins/pcm-canary/pcm-canary.php"; info "canary for $s in ${wc:-NOWHERE}"; }
ops() { local ph=$1 s=$P1 alt; [ $ph = new ] && alt=8.5 || alt=8.2
  step() { local l=$1; shift; run_ee "$ph-$l" "$@"; local v; v=$(rec "$ph-$l" $s); chk "$ph: after '$l' (rc $RC) $s DB site_container_fs_path" '/var/www/htdocs/current' "$v"
    [ $ph = new ] && expect_found "$ph-$l-scan" $s '/var/www/htdocs/current'; }
  step ssl-self site update $s --ssl=self
  step alias-add site update $s --add-alias-domains=al.$s
  step php-$alt site update $s --php=$alt
  run_ee "$ph-disable" site disable $s; v=$(rec "$ph-disabled" $s); chk "$ph: disabled $s DB path" '/var/www/htdocs/current' "$v"
  [ $ph = new ] && expect_found "$ph-disabled-scan" $s '/var/www/htdocs/current'
  step enable site enable $s
  step restart site restart $s
  step alias-del site update $s --delete-alias-domains=al.$s
  step ssl-off site update $s --ssl=off 
  run_ee "$ph-clone" site clone $s $ph-clone.test; v=$(rec "$ph-clone" $ph-clone.test); chk "$ph: clone (rc $RC) $ph-clone.test DB path" '/var/www/htdocs/current' "$v"
  [ $ph = new ] && [ $RC = 0 ] && expect_found "$ph-clone-scan" $ph-clone.test '/var/www/htdocs/current'
  if (cd /tmp && ee help site backup) > /dev/null 2>&1; then
    run_ee "$ph-backup" site backup $s; info "$ph backup: $(tail -3 $D/$ph-backup.out | tr '\n' ' ')"
    step restore site restore $s
  else info "$ph: no ee site backup in this version"; fi
  rec "$ph-end" $s > /dev/null; }
case $P in
create)
  run_ee create-$P1 site create $P1 --type=wp --public-dir=current --title=pc $W
  run_ee create-$P2 site create $P2 --type=wp --public-dir=current/public --title=pc $W
  run_ee create-$P3 site create $P3 --type=wp --public-dir current --title=pc $W
  run_ee create-$PD site create $PD --type=wp --title=pc $W
  for s in $P1 $P2 $P3 $PD; do v=$(rec create $s); info "created $s db=$v"; canary_into $s; done
  chk "create: $P1 DB site_container_fs_path" '/var/www/htdocs/current' "$(rec x $P1 2>/dev/null)"
  chk "create: $P2 DB site_container_fs_path" '/var/www/htdocs/current/public' "$(rec x $P2 2>/dev/null)"
  info "create: $P3 (--public-dir current, space form) DB path $(rec x $P3 2>/dev/null); create rc $(tail -1 $D/create-$P3.out)" ;;
ops-old) ops old ;;
ops-new) ops new ;;
upgrade)
  upgrade_to "$NEW_PHAR"; reload_scanner
  for s in $P1 $P2 $P3 $PD; do rec upgraded $s > /dev/null; done
  chk "upgrade: $P1 DB site_container_fs_path" '/var/www/htdocs/current' "$(rec x $P1 2>/dev/null)" ;;
scan)
  expect_found scan-$P1 $P1 '/var/www/htdocs/current'
  expect_found scan-$P2 $P2 '/var/www/htdocs/current/public'
  info "scan-$P3: N/A, '--public-dir current' (space form) is refused at create"
  expect_found scan-$PD $PD '/var/www/htdocs'
  # Run as the user did: no site argument, from inside the site directory (and deeper).
  for sub in "" app app/htdocs app/htdocs/current app/htdocs/current/wp-content/plugins; do l=cwd-$(echo "${sub:-root}" | tr / _)
    (cd $SITES_DIR/$P1/$sub && ee --debug site php-compat --php=8.4 --format=json) < /dev/null > $D/$l.out 2> $D/$l.err
    p=$(grep -o "'scan' '[a-z]*' '[^']*'" $D/$l.err | tail -1 | awk -F"'" '{print $6}')
    chk "scan from cwd $SITES_DIR/$P1/$sub: status/site/argv path" "ok $P1 /var/www/htdocs/current" "$(jq -r .status $D/$l.out 2>/dev/null | tail -1) $(jq -r .site $D/$l.out 2>/dev/null | tail -1) $p"; done ;;
layouts)
  # Case (b): the record says /var/www/htdocs but WordPress lives elsewhere. Built on $PD from a pristine copy of its htdocs.
  H=$SITES_DIR/$PD/app/htdocs; cp -a $H /var/tmp/pc-pristine; WPC=$SITES_DIR/$PD/app/wp-config.php; cp -a $WPC /var/tmp/pc-wpconfig.php
  info "layouts: wp-config.php of $PD at $WPC: $([ -f $WPC ] && echo present || echo MISSING)"
  reset_cfg() { cp -a /var/tmp/pc-wpconfig.php $WPC; }
  reset() { find $H -mindepth 1 -delete; }
  # b1: CI/CD release layout, relative link, wp-cli.yml path: current/, wp-config.php above current.
  # realistic (easyengine.io): wp-config.php one level above current, releases/wp-config.php -> ../wp-config.php
  reset_cfg; reset; mkdir -p $H/releases; cp -a /var/tmp/pc-pristine $H/releases/1; mv $WPC $H/wp-config.php; ln -s ../wp-config.php $H/releases/wp-config.php; ln -s releases/1 $H/current
  printf 'path: current/\n' > $H/wp-cli.yml; rm -rf $H/releases/1/wp-content/plugins/pcm-canary; plant $H/releases/1/wp-content/plugins/pcm-canary/pcm-canary.php; chown -R 33:33 $H
  rec b1-cicd-rel $PD > /dev/null; expect_found b1-cicd-rel $PD '/var/www/htdocs(/current)?'
  # b2: same with an absolute link inside the container.
  rm $H/current; ln -s /var/www/htdocs/releases/1 $H/current; chown -h 33:33 $H/current; expect_found b2-cicd-abs $PD '/var/www/htdocs(/current)?'
  # b1d: an old release beside the live one (nginx doesn't serve it): still a real scan
  rm $H/current; ln -s releases/1 $H/current; cp -a $H/releases/1 $H/releases/0; chown -R 33:33 $H; chown -h 33:33 $H/current; expect_found b1d-cicd-old-release $PD '/var/www/htdocs(/current)?'; rm -rf $H/releases/0
  # b1e: shared wp-config: releases/1/wp-config.php -> ../../shared/wp-config.php, no wp-config.php above current
  mkdir -p $H/shared; mv $H/wp-config.php $H/shared/wp-config.php; rm -f $H/releases/wp-config.php; ln -s ../../shared/wp-config.php $H/releases/1/wp-config.php; chown -R 33:33 $H; chown -h 33:33 $H/releases/1/wp-config.php
  expect_found b1e-cicd-shared-wpconfig $PD '/var/www/htdocs(/current)?'
  # b3: whole WordPress in htdocs/blog, wp-cli.yml path: blog/.
  reset_cfg; reset; cp -a /var/tmp/pc-pristine $H/blog; mv $WPC $H/wp-config.php; printf 'path: blog/\n' > $H/wp-cli.yml; chown -R 33:33 $H; expect_found b3-wp-in-blog $PD '/var/www/htdocs/blog'; reset_cfg
  # b4: WordPress core in htdocs/wp, wp-content at the root (giving WordPress its own directory).
  reset_cfg; reset; cp -a /var/tmp/pc-pristine $H/wp; mv $H/wp/wp-content $H/wp-content; chown -R 33:33 $H; expect_guard b4-core-in-wp-noindex $PD
  # b4b: whole WordPress (core + wp-content) in htdocs/wp, htdocs/index.php requires wp/wp-blog-header.php, no wp-cli.yml.
  # realistic: WordPress (with its wp-content) in htdocs/wp, stock loader in htdocs/index.php, wp-config.php where WordPress looks (htdocs/)
  reset_cfg; reset; cp -a /var/tmp/pc-pristine $H/wp; printf '<?php\ndefine( "WP_USE_THEMES", true );\nrequire __DIR__ . "/wp/wp-blog-header.php";\n' > $H/index.php; mv $WPC $H/wp-config.php; chown -R 33:33 $H
  expect_found b4b-wp-subdir-index $PD '/var/www/htdocs/wp'; reset_cfg; rm -f $H/wp-config.php
  # b4c: same with the index.php require written as './wp/wp-blog-header.php' and wp-config.php beside index.php
  reset; cp -a /var/tmp/pc-pristine $H/wp; printf '<?php\nrequire( "./wp/wp-blog-header.php" );\n' > $H/index.php; chown -R 33:33 $H; expect_guard b4c-wp-subdir-index-rel $PD
  # b4d: htdocs/index.php is a link to site/index.php, which loads ./wp/wp-blog-header.php (resolved from the link's real dir)
  reset; mkdir -p $H/site; cp -a /var/tmp/pc-pristine $H/site/wp; printf '<?php\nrequire __DIR__ . "/wp/wp-blog-header.php";\n' > $H/site/index.php; ln -s site/index.php $H/index.php; chown -R 33:33 $H; chown -h 33:33 $H/index.php
  expect_guard b4d-linked-index $PD
  # b1c: CI/CD layout with a CRLF wp-cli.yml
  reset_cfg; reset; mkdir -p $H/releases; cp -a /var/tmp/pc-pristine $H/releases/1; mv $WPC $H/wp-config.php; ln -s ../wp-config.php $H/releases/wp-config.php; ln -s releases/1 $H/current; printf 'path: current/\r\n' > $H/wp-cli.yml; chown -R 33:33 $H
  expect_found b1c-crlf-wpcli $PD '/var/www/htdocs/current'; reset_cfg
  # b5: Bedrock: web/wp core, web/app content, config/ + vendor/ at the root.
  reset_cfg; reset; mkdir -p $H/web $H/config $H/vendor/x; cp -a /var/tmp/pc-pristine $H/web/wp; mv $H/web/wp/wp-content $H/web/app; rm -rf $H/web/app/plugins/pcm-canary
  printf '<?php\nrequire_once dirname( __DIR__ ) . "/vendor/autoload.php";\nrequire_once dirname( __DIR__ ) . "/config/application.php";\nrequire_once ABSPATH . "wp-settings.php";\n' > $H/web/wp-config.php
  printf '<?php\nuse Roots\\WPConfig\\Config;\n$root_dir = dirname( __DIR__ );\n$webroot_dir = $root_dir . "/web";\nConfig::define( "CONTENT_DIR", "/app" );\nConfig::define( "WP_CONTENT_DIR", $webroot_dir . Config::get( "CONTENT_DIR" ) );\nConfig::define( "ABSPATH", $webroot_dir . "/wp/" );\n' > $H/config/application.php; plant $H/web/app/plugins/pcm-canary/pcm-canary.php; chown -R 33:33 $H
  pcs b5-bedrock-htdocs $PD; info "b5 Bedrock under an nginx root of htdocs (not servable as built; real Bedrock is the bedrock group): $ST $(jq -r '.detail // empty' $D/b5-bedrock-htdocs.out | tail -1)"
  # b6: custom WP_CONTENT_DIR: htdocs/content holds the code, no wp-content.
  reset; cp -a /var/tmp/pc-pristine/. $H/; mv $H/wp-content $H/content; reset_cfg; sed -i "1a define( 'WP_CONTENT_DIR', '/var/www/htdocs/content' );" $WPC; chown -R 33:33 $H; expect_guard b6-content-dir $PD
  # b7: worst case: WP_CONTENT_DIR moved to htdocs/content (with the canary) while a clean default wp-content stays behind.
  reset; cp -a /var/tmp/pc-pristine/. $H/; cp -a $H/wp-content $H/content; rm -rf $H/wp-content/plugins/pcm-canary
  reset_cfg; sed -i "1a define( 'WP_CONTENT_DIR', '/var/www/htdocs/content' );" $WPC; chk "b7 wp-config defines WP_CONTENT_DIR" 1 "$(grep -c WP_CONTENT_DIR $WPC)"; chown -R 33:33 $H
  info "b7 WordPress sees WP_CONTENT_DIR=$(wpx $PD "eval 'echo WP_CONTENT_DIR;'" 2>&1 | tail -1) plugins=$(wpx $PD 'plugin list --field=name' 2>&1 | tr '\n' ' ')"
  expect_guard b7-stale-wp-content $PD
  info "b7 verdict text: $(cd /tmp && ee site php-compat $PD --php=8.4 < /dev/null 2>&1 | head -1)"
  # b8: WP_PLUGIN_DIR outside wp-content (htdocs/ext-plugins holds the canary).
  reset; cp -a /var/tmp/pc-pristine/. $H/; mkdir -p $H/ext-plugins; mv $H/wp-content/plugins/pcm-canary $H/ext-plugins/
  reset_cfg; sed -i "1a define( 'WP_PLUGIN_DIR', '/var/www/htdocs/ext-plugins' );" $WPC; chown -R 33:33 $H
  info "b8 WordPress plugins: $(wpx $PD 'plugin list --field=name' 2>&1 | tr '\n' ' ')"; expect_guard b8-plugin-dir $PD
  info "b8 verdict text: $(cd /tmp && ee site php-compat $PD --php=8.4 < /dev/null 2>&1 | head -1)"
  # b8b: WPMU_PLUGIN_DIR elsewhere; b8c: WP_CONTENT_DIR defined twice; b8d: WP_CONTENT_DIR from getenv(); b8e: wp-config renamed constant in a comment only.
  reset_cfg; reset; cp -a /var/tmp/pc-pristine/. $H/; mkdir -p $H/mu-ext; plant $H/mu-ext/pcm-canary.php; sed -i "1a define( 'WPMU_PLUGIN_DIR', '/var/www/htdocs/mu-ext' );" $WPC; chown -R 33:33 $H
  rm -rf $H/wp-content/plugins/pcm-canary; expect_guard b8b-mu-dir $PD
  reset_cfg; reset; cp -a /var/tmp/pc-pristine/. $H/; sed -i "1a define( 'WP_CONTENT_DIR', '/var/www/htdocs/wp-content' ); define( 'WP_CONTENT_DIR', '/var/www/htdocs/x' );" $WPC; chown -R 33:33 $H; expect_guard b8c-twice $PD
  reset_cfg; sed -i "1a define( 'WP_CONTENT_DIR', getenv( 'PCM_CONTENT' ) ?: __DIR__ . '/htdocs/wp-content' );" $WPC; expect_guard b8d-getenv $PD
  reset_cfg; sed -i "1a // define( 'WP_CONTENT_DIR', '/var/www/htdocs/elsewhere' );" $WPC; expect_found b8e-commented $PD '/var/www/htdocs'
  reset_cfg; sed -i "1a define( 'WP_CONTENT_DIR', '/var/www/htdocs/wp-content' );" $WPC; expect_found b8f-explicit-default $PD '/var/www/htdocs'
  reset_cfg; sed -i "1a define( 'WP_CONTENT_DIR', dirname( __FILE__ ) . '/htdocs/wp-content' );" $WPC; expect_found b8g-dirname-default $PD '/var/www/htdocs'
  # b8h: a define after the wp-settings.php bootstrap is ignored (WordPress has already used the default)
  reset_cfg; reset; cp -a /var/tmp/pc-pristine/. $H/; chown -R 33:33 $H; printf "\ndefine( 'WP_CONTENT_DIR', '/var/www/htdocs/elsewhere' );\n" >> $WPC; info "b8h wp-config tail: $(tail -4 $WPC | tr '\n' ' ')"; expect_guard b8h-after-bootstrap $PD
  # b8i: exact concatenation: __DIR__ . 'htdocs/wp-content' (no slash) points to /var/wwwhtdocs/wp-content, which doesn't exist
  reset_cfg; sed -i "1a define( 'WP_CONTENT_DIR', __DIR__ . 'htdocs/wp-content' );" $WPC; expect_guard b8i-concat-noslash $PD
  # b8j: exact concatenation with a suffix: __DIR__ . '/htdocs-shared/content' (outside htdocs, inside app/)
  reset_cfg; mkdir -p $SITES_DIR/$PD/app/htdocs-shared; cp -a $H/wp-content $SITES_DIR/$PD/app/htdocs-shared/content; chown -R 33:33 $SITES_DIR/$PD/app/htdocs-shared
  sed -i "1a define( 'WP_CONTENT_DIR', __DIR__ . '/htdocs-shared/content' );" $WPC; expect_guard b8j-concat-sibling $PD; rm -rf $SITES_DIR/$PD/app/htdocs-shared
  # b9: wp-content a symlink inside the mount (../shared/wp-content, deploy-style): found.
  reset_cfg; reset; cp -a /var/tmp/pc-pristine/. $H/; mkdir -p $H/shared; mv $H/wp-content $H/shared/wp-content; ln -s shared/wp-content $H/wp-content; chown -R 33:33 $H; chown -h 33:33 $H/wp-content
  expect_found b9-wpcontent-link-in $PD '/var/www/htdocs'
  # b10: wp-content a symlink to a host path (dangling inside the scanner): never "no code" or "safe".
  reset; cp -a /var/tmp/pc-pristine/. $H/; mkdir -p /srv/pc-wpc; mv $H/wp-content /srv/pc-wpc/wp-content; ln -s /srv/pc-wpc/wp-content $H/wp-content
  pcs b10-wpcontent-link-host $PD; chk "b10 wp-content -> host path (WordPress can't load it either): never safe" 'ok (false|null)|tool_error null|no_code_found null' "$ST $SAFE"
  info "b10 table: $(cd /tmp && ee site php-compat $PD --php=8.4 < /dev/null 2>&1 | head -1)"; rm -f $H/wp-content; rm -rf /srv/pc-wpc
  # restore
  reset_cfg; reset; cp -a /var/tmp/pc-pristine/. $H/; chown -R 33:33 $H; expect_found b0-restored $PD '/var/www/htdocs' ;;
variants)
  # --public-dir spellings: what is stored, and what php-compat scans.
  i=0; for pd in 'current/' '/current' '/var/www/htdocs/abs' 'web.app' 'a//b' 'deep/er/still/x' '--BARE--'; do i=$((i+1)); s=pv$i.test
    if [ "$pd" = --BARE-- ]; then run_ee cv-$i site create $s --type=wp --public-dir --title=pc $W; else run_ee cv-$i site create $s --type=wp "--public-dir=$pd" --title=pc $W; fi
    v=$(rec "variant[$pd]" $s); info "variant --public-dir=[$pd]: create rc $RC, stored [$v]"
    [ -n "$v" ] || continue; rel=${v#/var/www/}; plant "$SITES_DIR/$s/app/$rel/wp-content/plugins/pcm-canary/pcm-canary.php"; expect_found variant-$i $s "$(echo $v | tr -s /)"; done ;;
esac
echo "DONE repro-$P" >> $OUT/done.txt
