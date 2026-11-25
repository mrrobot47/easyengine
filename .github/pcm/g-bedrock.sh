#!/bin/bash
# Bedrock on a site created with --public-dir=web (the way it is served), and the user's exact command from inside a CI/CD layout. Usage: g-bedrock.sh
. "$(dirname "$0")/lib.sh"; D=$OUT/bedrock; mkdir -p $D; cd /tmp
S=pb-bedrock.test; run_ee c-$S site create $S --type=wp --public-dir=web --title=pb $W; rec created $S > /dev/null
H=$SITES_DIR/$S/app/htdocs; info "pb layout before: $(cd $H && find . -maxdepth 2 | sort | tr '\n' ' ' | cut -c1-600); wp-config: $(ls $SITES_DIR/$S/app/htdocs/*.php $SITES_DIR/$S/app/*.php 2>/dev/null | tr '\n' ' ')"
# Bedrock: web/wp = core, web/app = content, web/wp-config.php loads config/application.php, vendor/ at the root.
cp -a $H/web /var/tmp/pb-web; rm -rf $H/web; mkdir -p $H/web $H/config $H/vendor/roots
cp -a /var/tmp/pb-web $H/web/wp; mv $H/web/wp/wp-content $H/web/app; rm -f $H/web/wp/wp-config.php
plant $H/web/app/plugins/pcm-canary/pcm-canary.php
printf '<?php\nrequire_once dirname( __DIR__ ) . "/config/application.php";\nrequire_once ABSPATH . "wp-settings.php";\n' > $H/web/wp-config.php
printf '<?php\nuse Roots\\WPConfig\\Config;\n$root_dir = dirname( __DIR__ );\n$webroot_dir = $root_dir . "/web";\nConfig::define( "CONTENT_DIR", "/app" );\nConfig::define( "WP_CONTENT_DIR", $webroot_dir . Config::get( "CONTENT_DIR" ) );\nConfig::define( "ABSPATH", $webroot_dir . "/wp/" );\n' > $H/config/application.php
printf '<?php\ndefine( "WP_USE_THEMES", true );\nrequire __DIR__ . "/wp/wp-blog-header.php";\n' > $H/web/index.php
[ -f $H/wp-config.php ] && mv $H/wp-config.php /var/tmp/pb-old-wp-config.php; chown -R 33:33 $H
info "pb layout after: $(cd $H && find . -maxdepth 2 | sort | tr '\n' ' ' | cut -c1-600)"
expect_guard B-bedrock $S
# Bedrock with plain define()s (no Config class)
printf '<?php\ndefine( "WP_CONTENT_DIR", dirname( __DIR__ ) . "/web/app" );\ndefine( "ABSPATH", dirname( __DIR__ ) . "/web/wp/" );\n' > $H/config/application.php; expect_guard B-bedrock-define $S
# Bedrock with application.php below app/ (config/application.php beside a loader elsewhere) and conditional defines
printf '<?php\nif ( getenv( "X" ) ) define( "WP_CONTENT_DIR", "/var/www/htdocs/web/app" );\n' > $H/config/application.php; expect_guard B-cond-unbraced $S
printf '<?php\nif ( getenv( "X" ) ) { define( "WP_CONTENT_DIR", "/var/www/htdocs/web/app" ); }\n' > $H/config/application.php; expect_guard B-cond-braced $S
printf '<?php\ngetenv( "X" ) && define( "WP_CONTENT_DIR", "/var/www/htdocs/web/app" );\n' > $H/config/application.php; expect_guard B-cond-and $S
printf '<?php\ndefined( "WP_CONTENT_DIR" ) or define( "WP_CONTENT_DIR", "/var/www/htdocs/web/app" );\n' > $H/config/application.php; expect_guard B-cond-or $S
# The user's exact command: no site argument, run from inside htdocs/current of a CI/CD layout whose row says /var/www/htdocs.
U=pb-user.test; run_ee c-$U site create $U --type=wp --title=pb $W; UH=$SITES_DIR/$U/app/htdocs
cp -a $UH /var/tmp/pb-user; find $UH -mindepth 1 -delete; mkdir -p $UH/releases; cp -a /var/tmp/pb-user $UH/releases/7; ln -s releases/7 $UH/current; printf 'path: current/\n' > $UH/wp-cli.yml
mv $SITES_DIR/$U/app/wp-config.php $UH/wp-config.php; ln -s ../wp-config.php $UH/releases/wp-config.php
plant $UH/releases/7/wp-content/plugins/pcm-canary/pcm-canary.php; chown -R 33:33 $UH; rec user $U > /dev/null
for sub in "" app/htdocs app/htdocs/current; do l=user-cwd-$(echo "${sub:-root}" | tr / _)
  (cd $SITES_DIR/$U/$sub && ee site php-compat --php=8.4 --format=json) < /dev/null > $D/$l.txt 2>&1
  chk "user's command from $SITES_DIR/$U/$sub: status/site/safe (no site argument)" "ok $U false" "$(jq -r '"\(.status) \(.site) \(.safe_to_upgrade)"' $D/$l.txt 2>/dev/null | tail -1)"; done
(cd $SITES_DIR/$U/app/htdocs/current && ee site php-compat --php=8.4) < /dev/null > $D/user-table.txt 2>&1; has "user's command, table names the site" "$U" "$(head -1 $D/user-table.txt)"
(cd $SITES_DIR/$U/app/htdocs/current && ee --debug site php-compat --php=8.4 --format=json) < /dev/null > $D/user-dbg.out 2> $D/user-dbg.err
info "user's command, docker argv: $(grep -o "'scan' '[a-z]*' '[^']*'" $D/user-dbg.err | tail -1); warning lines: $(grep -i 'warning' $D/user-dbg.err | head -3 | tr '\n' ' ')"
echo "DONE bedrock" >> $OUT/done.txt
