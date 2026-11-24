# shellcheck shell=bash
# Shard phphtml: php and html sites, with and without (nested) public-dir, with-db/local-db, cache, ssl self, aliases.
HTTP="p1.test|/ p1.test|/pmark.php p2.test|/mark.txt p2.test|/pmark.php p2.test|/ee-admin/ p2a.test|/mark.txt p3.test|/mark.txt p3.test|/pmark.php p4.test|/pmark.php p5.test|/pmark.php
p6.test|/pmark.php|https p6.test|/ p6a.test|/pmark.php|https p2c.test|/mark.txt p2c.test|/pmark.php p2.test|/pmark.php|https
h1.test|/mark.txt h2.test|/mark.txt h2a.test|/mark.txt h3.test|/mark.txt h3.test|/ h4.test|/mark.txt|https h4.test|/mark.txt h4a.test|/mark.txt|https h5.test|/mark.txt h5a.test|/mark.txt h2c.test|/mark.txt h2.test|/mark.txt|https h2.test|/f.txt p2.test|/f.txt"
create() {
  st c-p1 site create p1.test --type=php
  st c-p2 site create p2.test --type=php --public-dir=public --with-db
  st c-p3 site create p3.test --type=php --public-dir=a/b/c
  st c-p4 site create p4.test --type=php --with-db --local-db --public-dir=web
  st c-p5 site create p5.test --type=php --cache --php=8.3
  st c-p6 site create p6.test --type=php --ssl=self --alias-domains=p6a.test --php=8.1
  st c-h1 site create h1.test --type=html
  st c-h2 site create h2.test --type=html --public-dir=public
  st c-h3 site create h3.test --type=html --public-dir=x/y
  st c-h4 site create h4.test --type=html --ssl=self --alias-domains=h4a.test
  st c-h5 site create h5.test --type=html --alias-domains=h5a.test
  sh_st marks ". $F/lib.sh; mark p1.test; mark p2.test public; mark p3.test a/b/c; mark p4.test web; mark p5.test; mark p6.test; mark h1.test; mark h2.test public; mark h3.test x/y; mark h4.test; mark h5.test
    H=$SITES; phpmark p1.test \$H/p1.test/app/htdocs; phpmark p2.test \$H/p2.test/app/htdocs/public; phpmark p3.test \$H/p3.test/app/htdocs/a/b/c; phpmark p4.test \$H/p4.test/app/htdocs/web
    phpmark p5.test \$H/p5.test/app/htdocs; phpmark p6.test \$H/p6.test/app/htdocs
    echo f-p2 > \$H/p2.test/app/htdocs/public/f.txt; echo f-h2 > \$H/h2.test/app/htdocs/public/f.txt; chmod 644 \$H/p2.test/app/htdocs/public/f.txt \$H/h2.test/app/htdocs/public/f.txt"
  st at-p2 admin-tools enable p2.test
  st mh-p1 mailhog enable p1.test
  sh_st custom-p3 ". $F/lib.sh; custom_conf p3.test"
  st reload-p3 site reload p3.test
  st bk-p2 site backup p2.test
  st bk-h2 site backup h2.test
}
cmds() {
  st ssl-p2 site update p2.test --ssl=self
  st ssl-h2 site update h2.test --ssl=self
  snap after-ssl
  st alias-add-p2 site update p2.test --add-alias-domains=p2a.test
  st alias-add-h2 site update h2.test --add-alias-domains=h2a.test
  st alias-del-h5 site update h5.test --delete-alias-domains=h5a.test
  st alias-add-h4 site update h4.test --add-alias-domains=h4b.test
  snap after-alias
  st dis-p3 site disable p3.test
  st dis-h3 site disable h3.test
  snap disabled
  st en-p3 site enable p3.test
  st en-h3 site enable h3.test
  st dis-p4 site disable p4.test
  st en-p4 site enable p4.test
  st restart-p2 site restart p2.test
  st reload-h2 site reload h2.test
  st restart-p4-php site restart p4.test --php
  snap after-lifecycle
  st clone-p2 site clone p2.test p2c.test
  st clone-h2 site clone h2.test h2c.test
  snap after-clone
  sh_st break "echo CHANGED > $SITES/p2.test/app/htdocs/public/f.txt; echo CHANGED > $SITES/h2.test/app/htdocs/public/f.txt"
  st rs-p2 site restore p2.test
  st rs-h2 site restore h2.test
  snap after-restore
  st php-p2-81 site update p2.test --php=8.1
  st php-p3-86 site update p3.test --php=8.6
  st php-p6-84 site update p6.test --php=8.4
  st php-p4-74 site update p4.test --php=7.4
  snap after-php
  st php-p2-85 site update p2.test --php=8.5
  st del-p3 site delete p3.test --yes
  st del-h3 site delete h3.test --yes
  st del-p2c site delete p2c.test --yes
}
