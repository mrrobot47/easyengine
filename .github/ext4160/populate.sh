#!/bin/bash
# Sites, a subsite, aliases, admin-tools + mailhog and cron jobs on the installed old stable (or the release on the fresh path). Every option used exists on 4.14.0.
. "$(dirname "$0")/lib.sh"; cd /tmp; fails=0
c() { ee "$@" </dev/null; local r=$?; echo "RC=$r ee $*"; [ $r -eq 0 ] || { echo "CREATE-FAIL ee $*"; fails=$((fails+1)); }; }
c site create $W81 --type=wp --php=8.1 --title=u6wp81 $W
c site create $W82 --type=wp --php=8.2 --title=u6wp82 $W
c site create $MUD --type=wp --php=8.2 --mu=subdir --title=u6mud $W
c site create $W83 --type=wp --php=8.3 --title=u6wp83 $W
c site create $W84 --type=wp --php=8.4 --cache --title=u6wp84 $W
c site create $K84 --type=wp --php=8.4 --title=u6key84 $W
c site create $W85 --type=wp --php=8.5 --title=u6wp85 $W
[ -n "$HAS86" ] && c site create $W86 --type=wp --php=8.6 --title=u6wp86 $W
c site create $SW --type=wp --php=8.4 --title=u6sw $W
c site create $PHPS --type=php --php=8.4 --alias-domains=$PHPA
c site create $HTML --type=html --alias-domains=$HTMLA
c site create $LDB --type=wp --php=8.4 --local-db --title=u6ldb $W
echo "<?php echo 'ok-$PHPS ', PHP_VERSION;" > $SITES_DIR/$PHPS/app/htdocs/index.php
echo "ok-$HTML" > $SITES_DIR/$HTML/app/htdocs/index.html
chmod 644 $SITES_DIR/$PHPS/app/htdocs/index.php $SITES_DIR/$HTML/app/htdocs/index.html
for s in $ENABLED; do [ $s = $HTML ] || put_probes $s; done
wpx $MUD "site create --slug=sub1 --title=u6sub1" || { echo "CREATE-FAIL $MUD subsite"; fails=$((fails+1)); }
wpx $LDB "post create --post_title=u6-ldb-marker --post_status=publish --post_content=u6" || { echo "CREATE-FAIL ldb marker post"; fails=$((fails+1)); }
c admin-tools enable $W84
c mailhog enable $W84
c cron create $W84 --command='wp cron event run --due-now' --schedule='@every 10m'
c cron create host --command='date' --schedule='@every 1h'
echo "population failures: $fails"; exit $fails
