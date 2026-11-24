# shellcheck shell=bash
# Shard edge: real-world combinations mainly for the upgrade path (php8.1-8.4 sites recreated): a site disabled across the upgrade,
# public-dir + admin-tools, ssl self + aliases + admin-tools, user-docker-compose + proxy-cache, local-db + admin-tools, a New Relic key,
# custom nginx/php config, a cron job with --user=0, and a backup taken before the upgrade restored after it.
HTTP="e1.test|/mark.txt e1.test|/ee-admin/ e2.test|/ e2.test|/pmark.php e3.test|/mark.txt|https e3.test|/pmark.php|https e3a.test|/mark.txt|https e3b.test|/mark.txt|https e3.test|/ee-admin/|https e3c.test|/mark.txt|https
e4.test|/ e4.test|/pmark.php e4.test|/ee-admin/ e5.test|/ e5.test|/pmark.php e5.test|/ee-admin/ e4c.test|/ e4c.test|/ee-admin/ e2.test|/f.txt e4.test|/|https e4.test|/ee-admin/|https"
create() {
  st svc-nrd service enable newrelic-daemon
  st c-e1 site create e1.test --type=wp --php=8.2 --public-dir=public $W
  st c-e2 site create e2.test --type=wp --php=8.4 --cache $W
  st c-e3 site create e3.test --type=php --php=8.1 --public-dir=web --ssl=self --alias-domains=e3a.test,e3b.test
  st c-e4 site create e4.test --type=wp --php=8.3 --cache --proxy-cache=on $W
  st c-e5 site create e5.test --type=wp --php=8.4 --local-db $W
  sh_st marks ". $F/lib.sh; mark e1.test public; mark e2.test; mark e3.test web; mark e4.test; mark e5.test
    phpmark e2.test $SITES/e2.test/app/htdocs; phpmark e3.test $SITES/e3.test/app/htdocs/web; phpmark e4.test $SITES/e4.test/app/htdocs; phpmark e5.test $SITES/e5.test/app/htdocs
    echo MARK-f-e2-orig > $SITES/e2.test/app/htdocs/f.txt; chmod 644 $SITES/e2.test/app/htdocs/f.txt"
  for s in e1 e3 e4 e5; do st at-$s admin-tools enable $s.test; done
  st mh-e2 mailhog enable e2.test
  sh_st custom ". $F/lib.sh; custom_conf e2.test; custom_conf e3.test; setkey e2.test $NRKEY; mkdir -p $SITES/e4.test/user-docker-compose
    printf 'services:\n  php:\n    environment:\n      - DIFF_CUSTOM=from-user-compose\n' > $SITES/e4.test/user-docker-compose/extra.yml
    f=\$(sidini e2.test); printf '\nsession.sid_length = 48\n' >> \$f; grep -n 'session.sid' \$f"
  st en-force-e2 site enable e2.test --force
  st en-force-e4 site enable e4.test --force
  st reload-e3 site reload e3.test
  st cron-e2-u0 cron create e2.test --command='id -u' --schedule='@hourly' --user=0
  st cron-e4 cron create e4.test --command='wp option get home' --schedule='@daily'
  st bk-e2 site backup e2.test
  st dis-e1 site disable e1.test
}
cmds() {
  st en-e1 site enable e1.test
  sh_st cron-run-e2 ". $F/lib.sh; i=\$(db \"select id from cron where site_url='e2.test' and command like '%id -u%'\"); db \"select site_url, user, command from cron where id=\$i\"; ee cron run-now \$i < /dev/null; echo rc=\$?"
  st rs-e2 site restore e2.test
  snap after-enable
  st alias-add-e3 site update e3.test --add-alias-domains=e3c.test
  st alias-del-e3 site update e3.test --delete-alias-domains=e3b.test
  st ssl-e4 site update e4.test --ssl=self
  st php-e2-83 site update e2.test --php=8.3
  st php-e5-81 site update e5.test --php=8.1
  snap after-update
  st dis-e5 site disable e5.test
  st en-e5 site enable e5.test
  st restart-e3 site restart e3.test
  st clone-e4 site clone e4.test e4c.test
  st at-dis-e1 admin-tools disable e1.test
  st php-e1-84 site update e1.test --php=8.4
}
