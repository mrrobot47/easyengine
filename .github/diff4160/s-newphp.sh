# shellcheck shell=bash
# Shard newphp: PHP 8.1-8.6 sites with the real-world extras the release touches: public-dir, admin-tools (#535), mailhog, New Relic key (IMG-22),
# custom nginx/php config, a user-docker-compose file, pre-4.14 session.sid lines in php.ini (#536 restore), update --php in all directions (SC-61).
HTTP="n81.test|/ n81.test|/pmark.php n81.test|/ee-admin/ n82.test|/ n82.test|/mark.txt n82.test|/pmark.php n83.test|/ n83.test|/pmark.php n83.test|/ee-admin/ n84.test|/ n84.test|/mark.txt n84.test|/pmark.php
n85.test|/ n85.test|/pmark.php n86.test|/ n86.test|/pmark.php np84.test|/mark.txt np84.test|/pmark.php np84.test|/ee-admin/ n81.test|/|https n81.test|/ee-admin/|https n83.test|/|https n83.test|/ee-admin/|https n83a.test|/ n83a.test|/ee-admin/
n83c.test|/ n83c.test|/pmark.php n83c.test|/ee-admin/"
create() {
  st svc-nrd service enable newrelic-daemon
  st c-n81 site create n81.test --type=wp --php=8.1 $W
  st c-n82 site create n82.test --type=wp --php=8.2 --public-dir=public $W
  st c-n83 site create n83.test --type=wp --php=8.3 $W
  st c-n84 site create n84.test --type=wp --php=8.4 --public-dir=app/web $W
  st c-n85 site create n85.test --type=wp --php=8.5 --cache $W
  st c-n86 site create n86.test --type=wp --php=8.6 $W
  st c-np84 site create np84.test --type=php --php=8.4 --public-dir=public
  sh_st marks ". $F/lib.sh; mark n81.test; mark n82.test public; mark n83.test; mark n84.test app/web; mark n85.test; mark n86.test; mark np84.test public
    for s in n81 n83 n85 n86; do phpmark \$s.test $SITES/\$s.test/app/htdocs; done; phpmark n82.test $SITES/n82.test/app/htdocs/public; phpmark n84.test $SITES/n84.test/app/htdocs/app/web; phpmark np84.test $SITES/np84.test/app/htdocs/public"
  st at-n81 admin-tools enable n81.test
  st at-n83 admin-tools enable n83.test
  st at-np84 admin-tools enable np84.test
  st mh-n83 mailhog enable n83.test
  sh_st custom ". $F/lib.sh; custom_conf n81.test; custom_conf n84.test; mkdir -p $SITES/n83.test/user-docker-compose
    printf 'services:\n  php:\n    environment:\n      - DIFF_CUSTOM=from-user-compose\n' > $SITES/n83.test/user-docker-compose/extra.yml
    setkey n82.test $NRKEY; setkey n84.test $NRKEY"
  st en-force-n82 site enable n82.test --force
  st en-force-n84 site enable n84.test --force
  st restart-n83 site restart n83.test
  st reload-n81 site reload n81.test
  sh_st sid ". $F/lib.sh; f=\$(sidini n84.test); printf '\nsession.sid_length = 48\nsession.sid_bits_per_character = 6\n' >> \$f; f=\$(sidini np84.test); printf '\nsession.sid_length = 26\nsession.sid_bits_per_character = 5\n' >> \$f; sidini n84.test; sidini np84.test"
  st bk-n84 site backup n84.test
  st bk-np84 site backup np84.test
}
cmds() {
  st php-n81-84 site update n81.test --php=8.4
  st php-n84-81 site update n84.test --php=8.1
  st php-n85-82 site update n85.test --php=8.2
  st php-n86-83 site update n86.test --php=8.3
  st php-n82-86 site update n82.test --php=8.6
  st php-n83-85 site update n83.test --php=8.5
  st php-np84-82 site update np84.test --php=8.2
  snap after-php1
  st php-n81-81 site update n81.test --php=8.1
  st php-n84-84 site update n84.test --php=8.4
  st php-n83-83 site update n83.test --php=8.3
  st php-n82-82 site update n82.test --php=8.2
  snap after-php2
  sh_st holder-n85 ". $F/lib.sh; holder n85.test"
  st php-n85-held site update n85.test --php=8.4
  sh_st holder-rm "docker rm -f diffhold-n85test; docker inspect -f '{{.State.Status}}' n85test-php-1"
  snap after-held
  st ssl-n81 site update n81.test --ssl=self
  st ssl-n83 site update n83.test --ssl=self
  st alias-n83 site update n83.test --add-alias-domains=n83a.test
  snap after-ssl-alias
  st at-dis-n81 admin-tools disable n81.test
  st dis-n81 site disable n81.test
  st en-n81 site enable n81.test
  st dis-n84 site disable n84.test
  st en-n84 site enable n84.test
  st restart-n82 site restart n82.test
  st reload-n86 site reload n86.test
  snap after-lifecycle
  st rs-n84 site restore n84.test
  st rs-np84 site restore np84.test
  snap after-restore
  st clone-n83 site clone n83.test n83c.test
  st en-n83c site enable n83c.test --force
  st restart-n83c site restart n83c.test
}
