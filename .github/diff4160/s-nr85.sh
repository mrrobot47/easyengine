# shellcheck shell=bash
# Shard nr85: PHP 8.5 with a New Relic key (php8.5 moves to v4.16.0 with the new entrypoint): created with the key, an app name set by
# hand in newrelic.ini, and a php85.zip-origin config after `update --php=8.5` from 8.4 with the key.
HTTP="k85.test|/pmark.php k85b.test|/pmark.php k84.test|/pmark.php"
nrini() { echo "$(dirname $(sidini $1))/conf.d/newrelic.ini"; }
create() {
  st svc-nrd service enable newrelic-daemon
  st c-k85 site create k85.test --type=wp --php=8.5 $W
  st c-k85b site create k85b.test --type=php --php=8.5
  st c-k84 site create k84.test --type=wp --php=8.4 $W
  sh_st marks ". $F/lib.sh; for s in k85 k84; do phpmark \$s.test $SITES/\$s.test/app/htdocs; done; phpmark k85b.test $SITES/k85b.test/app/htdocs
    for s in k85 k85b k84; do setkey \$s.test $NRKEY; done
    f=\$(dirname \$(sidini k85b.test))/conf.d/newrelic.ini; ls -l \$f; sed -i 's/^newrelic.appname *=.*/newrelic.appname = \"Hand Set App\"/' \$f; grep -n appname \$f"
  for s in k85 k85b k84; do st en-force-$s site enable $s.test --force; done
}
cmds() {
  st restart-k85 site restart k85.test
  st restart-k85b site restart k85b.test --php
  st php-k84-85 site update k84.test --php=8.5
  snap after-php85
  sh_st ini-k84 ". $F/lib.sh; f=\$(dirname \$(sidini k84.test))/conf.d/newrelic.ini; ls -l \$f 2>&1; grep -vE '^;|^\$' \$f 2>&1 | sed 's/license = .*/license = <set>/'"
  st en-force-k84 site enable k84.test --force
  st restart-k84 site restart k84.test
  sh_st restarts "for c in k85test-php-1 k85btest-php-1 k84test-php-1; do echo \$c \$(docker inspect -f '{{.State.Status}} restarts={{.RestartCount}}' \$c); done"
}
