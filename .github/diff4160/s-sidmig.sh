# shellcheck shell=bash
# Shard sidmig: PHP 8.4 sites created on 4.13.3 (php.ini with the shipped session.sid lines, one with user values), then upgraded
# to 4.15.0 (shipped migration) or to the RC (the refactored one, site-command#536). Same post-state expected.
HTTP="s84w.test|/pmark.php s84p.test|/pmark.php s83w.test|/pmark.php slw.test|/pmark.php"
sidini() { find -L $SITES/$1/config/php -name php.ini | head -1; }
create() {
  st c-s84w site create s84w.test --type=wp --php=8.4 $W
  st c-s84p site create s84p.test --type=php --php=8.4
  st c-s83w site create s83w.test --type=wp --php=8.3 $W
  st c-slw site create slw.test --type=wp --php=latest $W
  sh_st marks ". $F/lib.sh; for s in s84w s84p s83w slw; do phpmark \$s.test $SITES/\$s.test/app/htdocs; done
    f=\$(sidini s84p.test); sed -i -E 's/^session\.sid_length *=.*/session.sid_length = 40/' \$f; grep -n 'session.sid' \$f; grep -n 'session.sid' \$(sidini s84w.test)"
  st restart-s84p site restart s84p.test --php
}
cmds() {
  st restart-all-s84w site restart s84w.test
  st php-s83w-84 site update s83w.test --php=8.4
}
