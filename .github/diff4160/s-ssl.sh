# shellcheck shell=bash
# Shard ssl: custom certificates (create, update, a failing update with the re-run hint of site-command#529, paths with a space and a quote), ssl-info, ssl off.
HTTP="c1.test|/mark.txt|https c2.test|/mark.txt|https c2.test|/mark.txt c3.test|/mark.txt|https c3.test|/mark.txt"
K=/root/diffcerts
create() {
  sh_st certs "mkdir -p \"$K/dir with space\" \"$K/it's\"; for s in c1 c2 c3; do openssl req -x509 -newkey rsa:2048 -nodes -days 30 -subj /CN=\$s.test -addext subjectAltName=DNS:\$s.test,DNS:www.\$s.test -keyout $K/\$s.key -out $K/\$s.crt 2>/dev/null; done
    cp $K/c2.key \"$K/dir with space/c2.key\"; cp $K/c2.crt \"$K/dir with space/c2.crt\"; cp $K/c3.key \"$K/it's/c3.key\"; cp $K/c3.crt \"$K/it's/c3.crt\"; ls -R $K"
  st c-c1 site create c1.test --type=html --ssl=custom --ssl-key=$K/c1.key --ssl-crt=$K/c1.crt
  st c-c2 site create c2.test --type=html
  st c-c3 site create c3.test --type=php
  sh_st marks ". $F/lib.sh; mark c1.test; mark c2.test; mark c3.test"
}
cmds() {
  st ssl-c2-custom-space site update c2.test --ssl=custom "--ssl-key=$K/dir with space/c2.key" "--ssl-crt=$K/dir with space/c2.crt"
  st ssl-c3-bad site update c3.test --ssl=custom "--ssl-key=$K/it's/c3.key" "--ssl-crt=$K/c1.crt"
  snap after-custom
  st ssl-c3-good site update c3.test --ssl=custom "--ssl-key=$K/it's/c3.key" "--ssl-crt=$K/it's/c3.crt"
  st ssl-info-c1 site ssl-info c1.test
  st ssl-info-c3 site ssl-info c3.test
  st ssl-renew-c1 site ssl-renew c1.test
  st ssl-off-c2 site update c2.test --ssl=off
  st ssl-self-c2 site update c2.test --ssl=self
}
