#!/bin/bash
# Builds the population with the installed old ee, then adds content. GLOBAL_AUTH=1 adds global auth g:g.
. "$(dirname "$0")/lib.sh"; cd /tmp
W="--admin-user=admin --admin-email=a@example.com --admin-pass=Adm1nPass413x"
fails=0
c() { ee "$@" </dev/null; local r=$?; echo "RC=$r ee $*"; [ $r -eq 0 ] || { echo "CREATE-FAIL ee $*"; fails=$((fails+1)); }; }
c site create shop.f4-ms.test --type=html
c site create f4-ms.test --type=wp --mu=subdom --title=f4ms $W
c site create f4-wp.test --type=wp --title=f4wp $W
c site create f4-wpc.test --type=wp --cache --title=f4wpc $W
c site create f4-ldb.test --type=wp --local-db --title=f4ldb $W
c site create f4-pdb.test --type=php --with-db
c site create f4-php.test --type=php '--alias-domains=f4-alias.test,*.f4-wild.test'
c site create f4-p74.test --type=php --php=7.4
c site create f4-p80.test --type=php --php=8.0
c site create f4-p81.test --type=php --php=8.1
c site create f4-p83.test --type=php --php=8.3
c site create f4-p84.test --type=php --php=8.4
c site create f4-p85.test --type=php --php=8.5
c site create f4-off.test --type=wp --cache --title=f4off $W
c site create f4-ssl.test --type=php --ssl=self
c site create f4-html.test --type=html
c auth create f4-ms.test --user=u1 --pass=p1
c auth create f4-php.test --user=u3 --pass=p3
c auth create f4-pdb.test --user=u4 --pass=p4
c auth create f4-ms.test --ip=198.51.100.7
c auth create f4-php.test --ip=198.51.100.8
c auth update global --ip=192.0.2.10
[ "${GLOBAL_AUTH:-0}" = 1 ] && c auth create global --user=g --pass=g
c admin-tools enable f4-ms.test
c mailhog enable f4-ms.test
c cron create f4-wp.test --command='wp option get siteurl' --schedule='@every 10m'
# Optional: the global newrelic-daemon service (its image changes in 4.14.0); a failure only drops it from the population.
ee service enable newrelic-daemon </dev/null; echo "RC=$? ee service enable newrelic-daemon (optional)"
# Content: marker + 300 KB blob everywhere, a post on each WP site, subsite a., a table + page on pdb.
for s in $ALL; do d=/opt/easyengine/sites/$s/app/htdocs; echo "f4 marker $s" > $d/f4-marker.txt; head -c 300000 /dev/urandom > $d/f4-blob.bin; chmod 644 $d/f4-marker.txt $d/f4-blob.bin; done
for s in f4-ms.test f4-wp.test f4-wpc.test f4-ldb.test; do
  c shell $s "--command=wp post create --post_title='f4 post $s' --post_status=publish --post_content='content of $s'"; done
c shell f4-ms.test '--command=wp site create --slug=a --title=f4a'
printf 'create table if not exists f4_pdb_test.f4_marker (id int primary key, v varchar(20)); insert into f4_pdb_test.f4_marker values (1,"f4-one"),(2,"f4-two");\n' | docker exec -i services_global-db_1 sh -c 'mariadb -uroot -p"$MYSQL_ROOT_PASSWORD" -N' || { echo "CREATE-FAIL pdb table"; fails=$((fails+1)); }
U=$(db "select db_user from sites where site_url='f4-pdb.test'"); PW=$(db "select db_password from sites where site_url='f4-pdb.test'")
cat > /opt/easyengine/sites/f4-pdb.test/app/htdocs/f4-db.php <<PHP
<?php \$m = new mysqli('global-db', '$U', '$PW', 'f4_pdb_test'); \$r = \$m->query('select v from f4_marker order by id'); while (\$x = \$r->fetch_row()) { echo \$x[0], " "; }
PHP
chmod 644 /opt/easyengine/sites/f4-pdb.test/app/htdocs/f4-db.php
echo "pdb page: $(curl -s --resolve f4-pdb.test:80:127.0.0.1 http://f4-pdb.test/f4-db.php)"
for s in $ALL; do grep -qE "[[:space:]]$s([[:space:]]|\$)" /etc/hosts || echo "127.0.0.1 $s" >> /etc/hosts; done
echo "population failures: $fails"; exit $fails
