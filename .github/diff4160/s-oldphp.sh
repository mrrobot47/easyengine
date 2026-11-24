# shellcheck shell=bash
# Shard oldphp: PHP 5.6-8.0 (images unchanged by the release): create, serve, one update --php each way.
HTTP="o56.test|/pmark.php o70.test|/pmark.php o72.test|/pmark.php o73.test|/pmark.php o74.test|/pmark.php o74.test|/mark.txt o80.test|/pmark.php ow74.test|/ ow74.test|/pmark.php ow80.test|/ ow80.test|/pmark.php"
create() {
  for v in 5.6 7.0 7.2 7.3 8.0; do st c-o${v/./} site create o${v/./}.test --type=php --php=$v; done
  st c-o74 site create o74.test --type=php --php=7.4 --public-dir=public --with-db
  st c-ow74 site create ow74.test --type=wp --php=7.4 $W
  st c-ow80 site create ow80.test --type=wp --php=8.0 --cache $W
  sh_st marks ". $F/lib.sh; for s in o56 o70 o72 o73 o80 ow74 ow80; do mark \$s.test; phpmark \$s.test $SITES/\$s.test/app/htdocs; done; mark o74.test public; phpmark o74.test $SITES/o74.test/app/htdocs/public"
}
cmds() {
  st php-o56-74 site update o56.test --php=7.4
  st php-o74-81 site update o74.test --php=8.1
  st php-ow80-84 site update ow80.test --php=8.4
  st php-ow74-80 site update ow74.test --php=8.0
  snap after-php-up
  st php-o74-74 site update o74.test --php=7.4
  st php-ow80-80 site update ow80.test --php=8.0
  st php-o73-56 site update o73.test --php=5.6
  st restart-o70 site restart o70.test
  st dis-o72 site disable o72.test
  st en-o72 site enable o72.test
}
