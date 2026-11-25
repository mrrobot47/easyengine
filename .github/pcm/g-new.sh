#!/bin/bash
# Cells for site-command#546: user-compose mounts, nohup + HUP, valueless flags, delete/restore during a scan, app link to an old Docker root.
. "$(dirname "$0")/lib.sh"; D=$OUT/new; mkdir -p $D; cd /tmp
A() { echo $SITES_DIR/$1/app/htdocs; }
left() { echo "$(docker ps -a --format '{{.Names}}' | grep '^ee-php-compat-' | tr '\n' ' ')|$(find /opt/easyengine/tmp/php-compat -mindepth 2 -maxdepth 2 2>/dev/null | grep -v '/\.' | wc -l)"; }
waitrun() { local i; for i in $(seq 1 600); do [ "$(docker inspect -f '{{.State.Running}}' $1 2>/dev/null)" = true ] && return 0; sleep 0.2; done; return 1; }
bigsite() { local s=$1 H; run_ee c-$s site create $s --type=php; H=$(A $s); mkdir -p $H/bulk; body=$(for i in $(seq 1 120); do echo "\$v$i = strtoupper( 'line $i' ) . PHP_EOL;"; done)
  for i in $(seq 1 5000); do printf '<?php\n// %d\n%s\n' $i "$body" > $H/bulk/f$i.php; done; plant $H/legacy/pcm-canary.php; chown -R 33:33 $H; }
# 1. user-compose mounts below /var/www
M=pn-mount.test; run_ee c-$M site create $M --type=wp --title=pn $W
mkdir -p /srv/pcm/plug /srv/pcm/whole; plant /srv/pcm/plug/pcm-mounted.php; chown -R 33:33 /srv/pcm
mkdir -p $SITES_DIR/$M/user-docker-compose
printf 'services:\n  php:\n    volumes:\n      - /srv/pcm/plug:/var/www/htdocs/wp-content/plugins/mounted-plug:ro\n' > $SITES_DIR/$M/user-docker-compose/pcm.yml
run_ee en-$M site enable $M --force; info "N1 php mounts: $(docker inspect -f '{{json .Mounts}}' $(cname $M)-php-1 2>&1 | jq -c '[.[] | select(.Destination|startswith("/var/www")) | [.Source,.Destination]]' 2>&1)"
CANF=pcm-mounted.php pcs N1-mount $M; chk "N1 user-compose mount of a plugin: canary found (or no verdict)" '[2-9]:false|0:null' "$CAN:$SAFE"; info "N1 detail: $(jq -r '.detail // empty' $D/N1-mount.out)"
run_ee dis-$M site disable $M; pcs N1-disabled $M; chk "N1 disabled site with a user-compose mount: no verdict" 'tool_error null' "$ST $SAFE"; info "N1 disabled detail: $(jq -r '.detail // empty' $D/N1-disabled.out)"
# F9 variants on the disabled site: never a PHP fatal; code mounted below /var/www (or anything unjudgeable) → no verdict; nothing below /var/www → a normal scan
f9() { local l=$1 want=$2; rm -f $SITES_DIR/$M/user-docker-compose/*.yml; cat > $SITES_DIR/$M/user-docker-compose/pcm.yml
  pcs N1-f9-$l $M; chk "F9 disabled + compose [$l]: status (no fatal)" "$want" "$ST"; chk "F9 [$l] no PHP fatal" 0 "$(grep -c 'Fatal error' $D/N1-f9-$l.err)"; info "F9 [$l] detail: $(jq -r '.detail // empty' $D/N1-f9-$l.out | tail -1)"; }
f9 flow tool_error <<'Y'
services:
  php:
    volumes: ["/srv/pcm/plug:/var/www/htdocs/wp-content/plugins/mounted-plug:ro"]
Y
f9 anchor tool_error <<'Y'
x-pcm: &pcmvol /srv/pcm/plug:/var/www/htdocs/wp-content/plugins/mounted-plug:ro
services:
  php:
    volumes:
      - *pcmvol
Y
f9 envvar tool_error <<'Y'
services:
  php:
    volumes:
      - ${PCM_SRC:-/srv/pcm/plug}:/var/www/htdocs/wp-content/plugins/mounted-plug:ro
Y
f9 longform tool_error <<'Y'
services:
  php:
    volumes:
      - type: bind
        source: /srv/pcm/plug
        target: /var/www/htdocs/wp-content/plugins/mounted-plug
        read_only: true
Y
f9 comment ok <<'Y'
services:
  php:
    volumes:
      # - /srv/pcm/plug:/var/www/htdocs/wp-content/plugins/mounted-plug:ro
      - /srv/pcm/logs:/var/log/pcm
Y
f9 outside ok <<'Y'
services:
  php:
    environment:
      - PCM_X=1
    volumes:
      - /srv/pcm/plug:/opt/pcm-plug:ro
Y
f9 otherservice 'ok|tool_error' <<'Y'
services:
  nginx:
    volumes:
      - /srv/pcm/plug:/var/www/htdocs/wp-content/plugins/mounted-plug:ro
Y
f9 quoted tool_error <<'Y'
services:
  "php":
    volumes:
      - "/srv/pcm/plug:/var/www/htdocs/wp-content/plugins/mounted-plug:ro"
Y
f9 tabs-crlf tool_error < <(printf 'services:\r\n  php:\r\n    volumes:\r\n      - /srv/pcm/plug:/var/www/htdocs/wp-content/plugins/mounted-plug:ro\r\n')
rm -f $SITES_DIR/$M/user-docker-compose/*.yml; printf 'services:\n  php:\n    volumes:\n      - /srv/pcm/plug:/var/www/htdocs/wp-content/plugins/mounted-plug:ro\n' > $SITES_DIR/$M/user-docker-compose/pcm.yml
run_ee en2-$M site enable $M
# long-form target: on the running site: the mount is followed (canary found)
rm -f $SITES_DIR/$M/user-docker-compose/*.yml; printf 'services:\n  php:\n    volumes:\n      - type: bind\n        source: /srv/pcm/plug\n        target: /var/www/htdocs/wp-content/plugins/mounted-plug\n        read_only: true\n' > $SITES_DIR/$M/user-docker-compose/pcm.yml
run_ee en2b-$M site enable $M --force; CANF=pcm-mounted.php pcs N1-longform-run $M; chk "F9 long-form mount on the running site: canary found" '[2-9]:false' "$CAN:$SAFE"
# a mount of a single host file over a plugin file
plant /srv/pcm/single.php; mkdir -p $(A $M)/wp-content/plugins/fileplug; printf '<?php\n/*\nPlugin Name: File Plug\n*/\n' > $(A $M)/wp-content/plugins/fileplug/fileplug.php; : > $(A $M)/wp-content/plugins/fileplug/single.php; chown -R 33:33 $(A $M)/wp-content/plugins/fileplug
printf 'services:\n  php:\n    volumes:\n      - /srv/pcm/single.php:/var/www/htdocs/wp-content/plugins/fileplug/single.php:ro\n' > $SITES_DIR/$M/user-docker-compose/pcm2.yml
run_ee en3-$M site enable $M --force; CANF=single.php pcs N1-file $M; chk "N1 user-compose mount of one file: canary found (or no verdict)" '[2-9]:false|0:null' "$CAN:$SAFE"
# the whole htdocs from a host directory
cp -a $(A $M)/. /srv/pcm/whole/; rm -rf /srv/pcm/whole/wp-content/plugins/pcm-canary; plant /srv/pcm/whole/wp-content/plugins/whole/pcm-whole.php; chown -R 33:33 /srv/pcm/whole
rm -f $SITES_DIR/$M/user-docker-compose/*.yml; printf 'services:\n  php:\n    volumes:\n      - /srv/pcm/whole:/var/www/htdocs\n' > $SITES_DIR/$M/user-docker-compose/pcm.yml
run_ee en4-$M site enable $M --force; CANF=pcm-whole.php pcs N1-whole $M; chk "N1 htdocs bind-mounted from the host: host code found (or no verdict)" '[2-9]:false|0:null' "$CAN:$SAFE"; info "N1 whole detail: $(jq -r '.detail // empty' $D/N1-whole.out)"
# a mount outside wp-content on a wp site (htdocs/extra): no verdict
mkdir -p /srv/pcm/extra $(A $M)/extra; plant /srv/pcm/extra/pcm-extra.php; chown -R 33:33 /srv/pcm/extra $(A $M)/extra
rm -f $SITES_DIR/$M/user-docker-compose/*.yml; printf 'services:\n  php:\n    volumes:\n      - /srv/pcm/extra:/var/www/htdocs/extra\n' > $SITES_DIR/$M/user-docker-compose/pcm.yml
run_ee en6-$M site enable $M --force; CANF=pcm-extra.php pcs N1-extra $M; chk "N1 mount outside wp-content on a wp site: found or no verdict" '[2-9]:false|0:null' "$CAN:$SAFE"; info "N1 extra: $ST $(jq -r '.detail // empty' $D/N1-extra.out)"
# docker ps failing (shim on PATH) while docker run works: no verdict
cat > /usr/local/bin/docker <<'SH'
#!/bin/sh
case " $* " in *" ps "*io.easyengine.site*) echo "simulated ps failure" >&2; exit 1 ;; esac
exec /usr/bin/docker "$@"
SH
chmod +x /usr/local/bin/docker; CANF=pcm-extra.php pcs N1-psfail $M; chk "N1 docker ps failing: no verdict" 'tool_error null' "$ST $SAFE"; info "N1 ps failure detail: $(jq -r '.detail // empty' $D/N1-psfail.out)"; rm -f /usr/local/bin/docker
rm -rf $SITES_DIR/$M/user-docker-compose; run_ee en5-$M site enable $M --force
# 2. nohup + HUP; HUP without nohup
B=pn-big.test; bigsite $B; N=ee-php-compat-$B
(cd /tmp && nohup ee site php-compat $B --php=8.4 --format=json > $D/N2-nohup.out 2> $D/N2-nohup.err < /dev/null) & sleep 0.5
waitrun $N; sleep 1; pid=$(pgrep -f "site php-compat $B" | head -1); kill -HUP $pid; wait; chk "N2 nohup + HUP: the scan finishes" 'ok false' "$(jq -r '"\(.status) \(.safe_to_upgrade)"' $D/N2-nohup.out 2>/dev/null | tail -1)"
(cd /tmp && exec ee site php-compat $B --php=8.4 --format=json) > $D/N2-hup.out 2> $D/N2-hup.err < /dev/null & P=$!; waitrun $N; sleep 1; kill -HUP $(pgrep -f "site php-compat $B" | head -1); wait $P; r=$?; sleep 2
info "N2 HUP without nohup: rc $r out [$(cat $D/N2-hup.out | tr '\n' ' ')] err [$(tail -2 $D/N2-hup.err | tr '\n' ' ')]"; chk "N2 HUP without nohup: the scan finishes (HUP ignored)" 'ok false' "$(jq -r '"\(.status) \(.safe_to_upgrade)"' $D/N2-hup.out 2>/dev/null | tail -1)"; chk "N2 HUP without nohup: nothing left" '\|0' "$(left)"
(cd /tmp && exec ee site php-compat $B --php=8.4) > $D/N2-term.out 2>&1 < /dev/null & P=$!; waitrun $N; sleep 1; kill -TERM $(pgrep -f "site php-compat $B" | head -1); wait $P; info "N2 SIGTERM wording: $(cat $D/N2-term.out | tr '\n' ' ')"
# estimate stopped with SIGTERM / Ctrl-C: its container is removed
for sig in TERM INT; do (cd /tmp && exec ee site php-compat $B --php=8.4 --estimate --format=json) > $D/N2-est-$sig.out 2>&1 < /dev/null & P=$!
  for i in $(seq 1 100); do [ -n "$(docker ps -q --filter ancestor=$SC:v4.16.0)" ] && break; sleep 0.2; done; sleep 0.5
  kill -$sig $(pgrep -f "php-compat $B --php=8.4 --estimate" | head -1) 2>/dev/null; wait $P; sleep 3
  chk "N2 estimate stopped by SIG$sig: no scanner container left" 0 "$(docker ps -aq --filter ancestor=$SC:v4.16.0 | wc -l)"; info "N2 estimate SIG$sig: $(head -c 200 $D/N2-est-$sig.out | tr '\n' ' ')"; done
(cd /tmp && ee site php-compat $B --php=8.4 --estimate --format=json) > $D/N2-est-ok.out 2>&1 < /dev/null; chk "N2 a finished estimate leaves no container" '0 ok' "$(docker ps -aq --filter ancestor=$SC:v4.16.0 | wc -l) $(jq -r .status $D/N2-est-ok.out 2>/dev/null | tail -1)"
# 3. valueless / boolean-looking flags
for a in '--cancel=false' '--cancel=' '--cancel=0' '--estimate=' '--estimate=false' '--estimate=0'; do (cd /tmp && ee site php-compat $B --php=8.4 $a --format=json) < /dev/null > $D/N3.out 2>&1; r=$?
  chk "N3 [$a] refused (rc, no document)" '1 0' "$r $(grep -c '"v":1' $D/N3.out)"; info "N3 [$a]: $(head -2 $D/N3.out | tr '\n' ' ')"; done
# 4. delete during a scan
X=pn-del.test; bigsite $X; (cd /tmp && exec ee site php-compat $X --php=8.4 --format=json) > $D/N4-scan.out 2>&1 < /dev/null & P=$!; waitrun ee-php-compat-$X; sleep 1
run_ee N4-delete site delete $X --yes; wait $P; info "N4 delete during a scan: delete rc $RC; scan [$(cat $D/N4-scan.out | tr '\n' ' ' | cut -c1-300)]"
chk "N4 delete during a scan: delete rc / scan status" '0 (cancelled|tool_error)' "$RC $(jq -r .status $D/N4-scan.out 2>/dev/null | tail -1)"
chk "N4 after delete: containers / temp dirs / control files of the site" ' 0 0' "$(docker ps -a --format '{{.Names}}' | grep "ee-php-compat-$X" | tr '\n' ' ') $(find /opt/easyengine/tmp/php-compat -name "*$X*" 2>/dev/null | wc -l) $(db "select count(*) from sites where site_url='$X'")"
# 4b. a check started while a delete runs: never a verdict on a half-deleted site
X2=pn-del2.test; bigsite $X2; (cd /tmp && ee site delete $X2 --yes) > $D/N4b-del.out 2>&1 < /dev/null & P=$!; sleep 1
(cd /tmp && ee site php-compat $X2 --php=8.4 --format=json) > $D/N4b-scan.out 2>&1 < /dev/null; r=$?; wait $P
info "N4b scan during delete: rc $r [$(head -c 300 $D/N4b-scan.out | tr '\n' ' ')] delete [$(tail -2 $D/N4b-del.out | tr '\n' ' ')]"
chk "N4b scan started during a delete: not an ok verdict" 'not-ok' "$(jq -r .status $D/N4b-scan.out 2>/dev/null | tail -1 | grep -qx ok && echo ok || echo not-ok)"; chk "N4b leftovers" '\|0' "$(left)"
# 5. restore during a scan
Y=pn-rs.test; bigsite $Y; run_ee N5-backup site backup $Y; (cd /tmp && exec ee site php-compat $Y --php=8.4 --format=json) > $D/N5-scan.out 2>&1 < /dev/null & P=$!; waitrun ee-php-compat-$Y; sleep 1
run_ee N5-restore site restore $Y; wait $P; info "N5 restore during a scan: restore rc $RC [$(grep -v '^rc=' $D/N5-restore.out | tail -3 | tr '\n' ' ')]; scan [$(cat $D/N5-scan.out | tr '\n' ' ' | cut -c1-300)]"
chk "N5 restore during a scan: restore rc / scan status (no verdict on code being replaced)" '0 (cancelled|tool_error)|1 ok' "$RC $(jq -r .status $D/N5-scan.out 2>/dev/null | tail -1)"
chk "N5 leftovers" '\|0' "$(left)"; pcs N5-after $Y; chk "N5 scan after the restore" 'ok false' "$ST $SAFE"
# 5b. a scan, estimate or cancel while a restore runs: tool_error "a restore of the site is running" (checks looped for the whole restore)
Y2=pn-rs2.test; bigsite $Y2; for i in $(seq 1 15000); do printf '<?php\n// x %d\n' $i > $(A $Y2)/bulk/g$i.php; done; chown -R 33:33 $(A $Y2); run_ee N5b-backup site backup $Y2
(cd /tmp && ee site restore $Y2) > $D/N5b-restore.out 2>&1 < /dev/null & RP=$!; n=0; : > $D/N5b-attempts.txt
while kill -0 $RP 2>/dev/null; do n=$((n+1)); k=$(( n % 3 )); case $k in 1) a="--php=8.4";; 2) a="--php=8.4 --estimate";; 0) a="--cancel";; esac
  (cd /tmp && timeout 120 ee site php-compat $Y2 $a --format=json) < /dev/null > $D/N5b-a$n.out 2>&1; st=$(jq -r .status $D/N5b-a$n.out 2>/dev/null | tail -1)
  alive=$(kill -0 $RP 2>/dev/null && echo during || echo after); echo "$n [$a] $alive $st $(jq -r '.detail // empty' $D/N5b-a$n.out 2>/dev/null | tail -1 | cut -c1-100)" >> $D/N5b-attempts.txt; done; wait $RP; rrc=$?
info "N5b restore rc $rrc; $n attempts: $(cut -c1-150 $D/N5b-attempts.txt | tr '\n' ';' | cut -c1-1200)"
chk "N5b at least one check ran while the restore ran" '[1-9][0-9]*' "$(grep -c ' during ' $D/N5b-attempts.txt)"
chk "N5b no check during the restore gave a verdict, estimate or no_code_found" 0 "$(grep ' during ' $D/N5b-attempts.txt | grep -cE ' during (ok|no_code_found|not_running|cancelled) ')"
info "N5b statuses during the restore: $(grep ' during ' $D/N5b-attempts.txt | awk '{print $4}' | sort | uniq -c | tr '\n' ' ')"
chk "N5b restore rc" 0 "$rrc"; chk "N5b leftovers" '\|0' "$(left)"
# 6. app link to an old Docker root
Z=pn-app.test; run_ee c-$Z site create $Z --type=php; plant $(A $Z)/legacy/pcm-canary.php; real=$(readlink $SITES_DIR/$Z/app)
ln -sfn "/old-docker-root/volumes/$(basename $(dirname $real))/_data" $SITES_DIR/$Z/app; info "N6 app -> $(readlink $SITES_DIR/$Z/app) (was $real)"
pcs N6-app $Z; chk "N6 app link to an old Docker root: found via docker volume inspect" 'ok false [2-9]' "$ST $SAFE $CAN"; ln -sfn "$real" $SITES_DIR/$Z/app
chk "no scanner containers left at the end" 0 "$(docker ps -aq --filter ancestor=$SC:v4.16.0 | wc -l)"
echo "DONE new" >> $OUT/done.txt
