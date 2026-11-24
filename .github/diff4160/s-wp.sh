# shellcheck shell=bash
# Shard wp: WordPress variants (plain, cache, public-dir, nested public-dir, ssl self + aliases, local-db, proxy-cache, multisite subdir/subdom).
HTTP="w1.test|/ w1.test|/mark.txt w2.test|/ w3.test|/ w3.test|/mark.txt w3.test|/pmark.php w3.test|/ee-admin/ w3a.test|/mark.txt w4.test|/ w4.test|/mark.txt w4.test|/pmark.php
w5.test|/|https w5.test|/ w5a.test|/mark.txt|https w5b.test|/mark.txt|https w5c.test|/mark.txt|https w6.test|/ w6.test|/mark.txt w6.test|/ee-admin/ w7.test|/ w8.test|/ w8.test|/sub1/ w9.test|/ sub1.w9.test|/
w1.test|/|https w3.test|/|https w3.test|/ee-admin/|https w3c.test|/ w3c.test|/mark.txt w3c.test|/ee-admin/ w3c.test|/|https w6c.test|/ w6c.test|/mark.txt w6c.test|/ee-admin/ w1.test|/pmark.php w3.test|/f.txt w8.test|/f.txt w3.test|/f.txt|https"
create() {
  st c-w1 site create w1.test --type=wp $W
  st c-w2 site create w2.test --type=wp --cache $W
  st c-w3 site create w3.test --type=wp --public-dir=public $W
  st c-w4 site create w4.test --type=wp --public-dir=current/web --cache $W
  st c-w5 site create w5.test --type=wp --ssl=self --alias-domains=w5a.test,w5b.test $W
  st c-w6 site create w6.test --type=wp --local-db --public-dir=public $W
  st c-w7 site create w7.test --type=wp --proxy-cache=on --cache $W
  st c-w8 site create w8.test --type=wp --mu=subdir --cache $W
  st c-w9 site create w9.test --type=wp --mu=subdom $W
  sh_st mu-w8 ". $F/lib.sh; wpx w8.test 'site create --slug=sub1 --title=sub1'"
  sh_st mu-w9 ". $F/lib.sh; wpx w9.test 'site create --slug=sub1 --title=sub1'"
  sh_st marks ". $F/lib.sh; mark w1.test; mark w2.test; mark w3.test public; mark w4.test current/web; mark w5.test; mark w6.test public; mark w7.test; mark w8.test; mark w9.test
    phpmark w1.test $SITES/w1.test/app/htdocs; phpmark w3.test $SITES/w3.test/app/htdocs/public; phpmark w4.test $SITES/w4.test/app/htdocs/current/web
    echo MARK-f-w3-orig > $SITES/w3.test/app/htdocs/public/f.txt; echo MARK-f-w8-orig > $SITES/w8.test/app/htdocs/f.txt; chmod 644 $SITES/w3.test/app/htdocs/public/f.txt $SITES/w8.test/app/htdocs/f.txt"
  st at-w3 admin-tools enable w3.test
  st at-w6 admin-tools enable w6.test
  st mh-w3 mailhog enable w3.test
  sh_st custom-w4 ". $F/lib.sh; custom_conf w4.test"
  st reload-w4 site reload w4.test
  st bk-w3 site backup w3.test
  st bk-w8 site backup w8.test
}
cmds() {
  st ssl-w1 site update w1.test --ssl=self
  st ssl-w3 site update w3.test --ssl=self
  snap after-ssl
  st alias-add-w3 site update w3.test --add-alias-domains=w3a.test
  st alias-add-w5 site update w5.test --add-alias-domains=w5c.test
  st alias-del-w5 site update w5.test --delete-alias-domains=w5b.test
  snap after-alias
  st alias-del-w3 site update w3.test --delete-alias-domains=w3a.test
  st dis-w4 site disable w4.test
  snap w4-disabled
  st en-w4 site enable w4.test
  st dis-w6 site disable w6.test
  st en-w6 site enable w6.test
  st restart-w2 site restart w2.test
  st restart-w3-nginx site restart w3.test --nginx
  st reload-w7 site reload w7.test
  st clean-w7 site clean w7.test
  st pc-off-w7 site update w7.test --proxy-cache=off
  st pc-on-w2 site update w2.test --proxy-cache=on
  st refresh-w5 site refresh w5.test
  snap after-lifecycle
  st clone-w3 site clone w3.test w3c.test
  st clone-w6 site clone w6.test w6c.test
  st en-w3c site enable w3c.test --force
  st ssl-w3c site update w3c.test --ssl=self
  snap after-clone
  sh_st break-w3 "echo MARK-f-CHANGED > $SITES/w3.test/app/htdocs/public/f.txt; echo MARK-f-CHANGED > $SITES/w8.test/app/htdocs/f.txt"
  st rs-w3 site restore w3.test
  st rs-w8 site restore w8.test
  snap after-restore
  st php-w1-84 site update w1.test --php=8.4
  st php-w3-82 site update w3.test --php=8.2
  st php-w4-86 site update w4.test --php=8.6
  snap after-php
  st php-w3-85 site update w3.test --php=8.5
  st at-dis-w3 admin-tools disable w3.test
  st dis-w3 site disable w3.test
  st en-w3 site enable w3.test
  st at-en-w3 admin-tools enable w3.test
  st del-w4 site delete w4.test --yes
  st del-w3c site delete w3c.test --yes
  st del-w6 site delete w6.test --yes
}
