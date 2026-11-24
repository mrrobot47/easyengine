#!/bin/bash
# Rearrange a freshly created wp site into a layout EE doesn't record (it only knows site_container_fs_path). Usage: layout.sh current|subdir <site>
#   current: site created with --public-dir=current; WordPress moves to htdocs/releases/1 and `current` becomes a relative symlink to it
#            (CI/CD deploy style); wp-config.php (EE keeps it one level above the public dir) is symlinked into the release, as deploy tools share it.
#   subdir:  "Giving WordPress its own directory": core in htdocs/wp/, htdocs/index.php loads wp/wp-blog-header.php, siteurl = /wp, and a
#            copy of EE's /var/www/wp-config.php in htdocs (WordPress looks one level above ABSPATH; WP-CLI refuses a require shim).
. "$(dirname "$0")/lib.sh"; M=$1; S=$2
cd $SITES_DIR/$S || exit 1
case $M in
current) docker-compose exec -T --user=www-data php sh -e <<'SH'
cd /var/www/htdocs
mkdir -p releases; mv current releases/1; ln -s releases/1 current
[ -e wp-config.php ] && ln -s ../../wp-config.php releases/1/wp-config.php
ls -la /var/www/htdocs /var/www/htdocs/releases/1 | head -40
SH
;;
subdir) docker-compose exec -T --user=www-data php sh -e <<SH
cd /var/www/htdocs
mkdir wp
for f in * ; do case "\$f" in wp|wp-content|f5*.php) continue ;; esac; mv "\$f" wp/; done
sed 's#/wp-blog-header.php#/wp/wp-blog-header.php#' wp/index.php > index.php
if [ -e /var/www/wp-config.php ]; then cp -p /var/www/wp-config.php wp-config.php; fi
wp --path=/var/www/htdocs/wp option update siteurl http://$S/wp
ls -la /var/www/htdocs | head -30
SH
;;
esac
