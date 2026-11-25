#!/bin/bash
# Site options, lifecycle and PHP versions on sites created with the RC. Usage: g-life.sh opts|phpver
. "$(dirname "$0")/lib.sh"; P=$1; D=$OUT/life-$P; mkdir -p $D; cd /tmp
A() { echo $SITES_DIR/$1/app/htdocs; }
case $P in
opts)
  run_ee c1 site create po-cache.test --type=wp --cache --title=po $W
  run_ee c2 site create po-ssl.test --type=wp --ssl=self --title=po $W
  run_ee c3 site create po-alias.test --type=wp --alias-domains=al1.po-alias.test,al2.po-alias.test --title=po $W
  run_ee c4 site create po-ldb.test --type=wp --local-db --title=po $W
  run_ee c5 site create po-pubssl.test --type=wp --public-dir=current --ssl=self --cache --title=po $W
  run_ee c6 site create po-php.test --type=php --local-db --cache --ssl=self
  for s in po-cache.test po-ssl.test po-alias.test po-ldb.test po-pubssl.test po-php.test; do v=$(rec created $s); rel=${v#/var/www/}
    t=$(db "select site_type from sites where site_url='$s'"); [ $t = wp ] && f=$SITES_DIR/$s/app/$rel/wp-content/plugins/pcm-canary/pcm-canary.php || f=$(A $s)/legacy/pcm-canary.php
    plant $f; expect_found O-$s $s "$v"; done
  # alias domain given instead of the site name
  (cd /tmp && ee site php-compat al1.po-alias.test --php=8.4 --format=json) < /dev/null > $D/O-alias-name.out 2>&1; info "O alias domain as the site argument: rc $? $(head -c 200 $D/O-alias-name.out)"
  # disabled
  run_ee dis site disable po-cache.test; expect_found O-disabled po-cache.test '/var/www/htdocs'; run_ee en site enable po-cache.test
  # clone (wp default and public-dir) and backup/restore (local rclone remote)
  run_ee cl1 site clone po-cache.test po-cl1.test; [ $RC = 0 ] && expect_found O-clone po-cl1.test '/var/www/htdocs'
  run_ee cl2 site clone po-pubssl.test po-cl2.test; [ $RC = 0 ] && expect_found O-clone-pub po-cl2.test '/var/www/htdocs/current'; rec cl2 po-cl2.test > /dev/null
  run_ee bk site backup po-pubssl.test; info "O backup: $(tail -3 $D/bk.out | tr '\n' ' ')"
  rm -rf $SITES_DIR/po-pubssl.test/app/htdocs/current/wp-content/plugins/pcm-canary
  run_ee rs site restore po-pubssl.test; info "O restore: $(tail -3 $D/rs.out | tr '\n' ' ')"; rec restored po-pubssl.test > /dev/null
  expect_found O-restored po-pubssl.test '/var/www/htdocs/current'
  run_ee bk2 site backup po-php.test; run_ee rs2 site restore po-php.test; expect_found O-restored-php po-php.test '/var/www/htdocs'
  # site deleted while a scan of it runs, then a new site of the same name
  run_ee del site delete po-ssl.test --yes; run_ee re site create po-ssl.test --type=php; pcs O-recreated po-ssl.test; chk "O recreated same-name site scans" 'ok' "$ST"
  info "O .cancel lock files left: $(ls -A /opt/easyengine/tmp/php-compat 2>/dev/null | tr '\n' ' ')" ;;
phpver)
  for v in 5.6 7.0 7.2 7.3 7.4 8.0 8.1 8.6; do s=pv${v/./}.test; run_ee c-$s site create $s --type=php --php=$v
    [ $RC = 0 ] || { info "V create --php=$v failed: $(tail -3 $D/c-$s.out | tr '\n' ' ')"; continue; }
    plant $(A $s)/legacy/pcm-canary.php; PCV=8.4 expect_found V-$s-84 $s '/var/www/htdocs'
    PCV=$v pcs V-$s-own $s; info "V $s scanned for its own $v: $ST safe=$SAFE errors=$ERRS"
    done
  for v in 7.4 8.0; do s=pw${v/./}.test; run_ee c-$s site create $s --type=wp --php=$v --title=pv $W; [ $RC = 0 ] || { info "V wp --php=$v create failed"; continue; }
    plant $(A $s)/wp-content/plugins/pcm-canary/pcm-canary.php; expect_found V-$s $s '/var/www/htdocs'; done ;;
esac
echo "DONE life-$P" >> $OUT/done.txt
