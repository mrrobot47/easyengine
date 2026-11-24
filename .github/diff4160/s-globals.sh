# shellcheck shell=bash
# Shard globals: cron, service, admin-tools, log, auth, shell, mailhog, config, cli on two sites.
HTTP="g1.test|/ g1.test|/ee-admin/ g2.test|/pmark.php g1.test|/mark.txt"
create() {
  st c-g1 site create g1.test --type=wp $W
  st c-g2 site create g2.test --type=php --php=8.2
  sh_st marks ". $F/lib.sh; mark g1.test; mark g2.test; phpmark g2.test $SITES/g2.test/app/htdocs"
}
cmds() {
  st cli-version cli version
  st cli-info cli info
  st cli-check-update cli check-update
  st help help
  for c in site cron service admin-tools log auth shell mailhog config cli; do st help-$c help $c; done
  for c in create update delete enable disable info list restart reload clone backup restore ssl-info refresh clean; do st help-site-$c help site $c; done
  st cron-c1 cron create g1.test --command='wp cron event run --due-now' --schedule='@every 10m'
  st cron-c2 cron create host --command='date' --schedule='@daily'
  st cron-c3-user0 cron create g2.test --command='id -u' --schedule='@hourly' --user=0
  st cron-c4-empty cron create g2.test --command='' --schedule='@hourly'
  st cron-c5-blank cron create g2.test --command='   ' --schedule='@hourly'
  st cron-c6-user cron create g2.test --command='id -un' --schedule='@hourly' --user=www-data
  st cron-list cron list --all
  st cron-list-g1 cron list g1.test
  st cron-upd1 cron update 1 --schedule='@every 20m'
  st cron-upd3-user0 cron update 3 --user=0 --command='id -u'
  st cron-upd2-empty cron update 2 --command=''
  st cron-upd2 cron update 2 --command='date -u'
  st cron-run3 cron run-now 3
  st cron-run1 cron run-now 1
  snap after-cron
  st cron-del2 cron delete 2
  st cron-del9 cron delete 99
  st svc-restart-proxy service restart nginx-proxy
  st svc-reload-proxy service reload nginx-proxy
  st svc-restart-db service restart mariadb
  st svc-restart-redis service restart redis
  st svc-en-nrd service enable newrelic-daemon
  st svc-dis-nrd service disable newrelic-daemon
  st svc-refresh service refresh nginx-proxy
  snap after-service
  st at-en admin-tools enable g1.test
  st at-en-again admin-tools enable g1.test
  st at-dis admin-tools disable g1.test
  st at-en2 admin-tools enable g1.test --force
  st log-g1 log show g1.test --n=2
  st log-cli log show --cli --n=0
  st auth-create-g auth create global --user=diffu --pass=diffp4160
  st auth-create-s auth create g1.test --user=situ --pass=sitp4160
  st auth-list-g auth list global
  st auth-list-s auth list g1.test
  st auth-wl auth create global --ip=10.9.9.9
  st auth-update auth update global --user=diffu --pass=diffp4160b
  st auth-del-s auth delete g1.test --user=situ
  st auth-del-wl auth delete global --ip=10.9.9.9
  snap after-auth
  st shell-wp shell g1.test --command='wp option get blogname'
  st shell-php shell g2.test --command='php -r "echo PHP_VERSION;"'
  st shell-nginx shell g1.test --service=nginx --command='nginx -v'
  st shell-root shell g2.test --user=root --command='id -u'
  st mh-en mailhog enable g1.test
  st mh-status mailhog status g1.test
  st mh-dis mailhog disable g1.test
  st mh-status2 mailhog status g1.test
  st cfg-set config set diff-key diff-value
  st cfg-get config get diff-key
  st cfg-list config list
  st cfg-unset config unset diff-key
  st cfg-get2 config get diff-key
  st site-list site list
  st site-list-json site list --format=json
  st site-info-g1 site info g1.test
  st ssl-info-none site ssl-info g1.test
}
