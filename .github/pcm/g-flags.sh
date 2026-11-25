#!/bin/bash
# Site names and flags. Usage: g-flags.sh names|flags|cancel
. "$(dirname "$0")/lib.sh"; P=$1; D=$OUT/$P; mkdir -p $D; cd /tmp
A() { echo $SITES_DIR/$1/app/htdocs; }
LONG=pcm-$(printf 'a%.0s' $(seq 1 59)).test; MAX64=$(printf 'a%.0s' $(seq 1 59)).test
case $P in
names)
  for s in pc-a-b-c.test a.b.c.pcm.test sub.pcn.test xn--bcher-kva.test $LONG $MAX64; do run_ee c-$s site create $s --type=php
    [ $RC = 0 ] || { info "N create $s failed: $(tail -3 $D/c-$s.out | tr '\n' ' ')"; continue; }
    plant $(A $s)/legacy/pcm-canary.php; expect_found N-$s $s '/var/www/htdocs'
    eqs "N $s json site" "$s" "$(jq -r .site $D/N-$s.out 2>/dev/null | tail -1)"
    has "N $s container name in docker run" "'--name' 'ee-php-compat-$s'" "$(grep -o "'--name' '[^']*'" $D/N-$s.err | tail -1)"
    has "N $s temp dir in docker run" "/opt/easyengine/tmp/php-compat/$s/" "$(grep -o "src=/opt/easyengine/tmp/php-compat/[^,]*" $D/N-$s.err | tail -1)"
    has "N $s table names the site" "$s" "$(cd /tmp && ee site php-compat $s --php=8.4 < /dev/null 2>&1 | head -1)"
    (cd $SITES_DIR/$s && ee site php-compat --php=8.4 --format=json) < /dev/null > $D/N-cwd-$s.out 2>&1; eqs "N $s from its directory without the argument: status site" "ok $s" "$(jq -r '"\(.status) \(.site)"' $D/N-cwd-$s.out 2>/dev/null | tail -1)"
  done
  for s in 'bücher.test' 'PCUP.test' 'pc_under.test' 'http://pc-url.test/' 'pc-trail.test.'; do run_ee c-x site create "$s" --type=php; info "N create [$s] rc $RC: $(grep -v '^rc=' $D/c-x.out | tail -2 | tr '\n' ' ')"
    if [ $RC = 0 ]; then n=$(db "select site_url from sites order by id desc limit 1"); pcs N-odd-$(echo $n | tr -cd 'a-z0-9.-') "$n"; info "N [$s] stored as [$n]: php-compat status $ST"; fi; done
  # the name given differently from how it is stored
  for g in PC-A-B-C.TEST http://pc-a-b-c.test https://pc-a-b-c.test/ pc-a-b-c.test/; do (cd /tmp && ee site php-compat "$g" --php=8.4 --format=json) < /dev/null > $D/N-alias.out 2>&1
    info "N given [$g]: rc $? $(head -c 200 $D/N-alias.out | tr '\n' ' ')"; done
  # two sites whose names appear in one cwd: no guess
  mkdir -p $(A pc-a-b-c.test)/a.b.c.pcm.test; (cd $(A pc-a-b-c.test)/a.b.c.pcm.test && ee site php-compat --php=8.4 --format=json) < /dev/null > $D/N-cwd2.out 2>&1
  info "N cwd holding two site names: rc $? $(head -c 300 $D/N-cwd2.out | tr '\n' ' ')" ;;
flags)
  S=pf-php.test; run_ee c-$S site create $S --type=php; plant $(A $S)/legacy/pcm-canary.php
  for v in 5.6 7.0 7.2 7.3 7.4 8.0 8.1 8.2 8.3 8.4 8.5 8.6; do PCV=$v pcs F-php-$v $S
    case $v in 5.6|7.*) chk "F --php=$v: status, safe (create_function/each only deprecated before 8.0)" 'ok true' "$ST $SAFE" ;; *) chk "F --php=$v: status/safe/canary" 'ok false [2-9]' "$ST $SAFE $CAN" ;; esac
    info "F --php=$v warnings $(jq -r .warnings $D/F-php-$v.out | tail -1)"; done
  for v in 8.7 7 8 abc '' 7.1 8.10 08.4 '8.4 ' ' 8.4' 8.4.1 latest 9.0 -1; do (cd /tmp && ee site php-compat $S "--php=$v" --format=json) < /dev/null > $D/F-bad.out 2> $D/F-bad.err; r=$?
    chk "F --php=[$v] refused: rc, no document" '1 0' "$r $(grep -c '"v":1' $D/F-bad.out)"; info "F --php=[$v] message: $(cat $D/F-bad.out $D/F-bad.err | head -2 | tr '\n' ' ')"; done
  (cd /tmp && ee site php-compat $S --format=json) < /dev/null > $D/F-nophp.out 2>&1; chk "F no --php refused" 1 "$?"
  (cd /tmp && ee site php-compat $S --php) < /dev/null > $D/F-phpbare.out 2>&1; chk "F bare --php refused" 1 "$?"
  for f in yaml csv ids count '' JSON; do (cd /tmp && ee site php-compat $S --php=8.4 "--format=$f") < /dev/null > $D/F-fmt.out 2>&1; chk "F --format=[$f] refused" 1 "$?"; done
  (cd /tmp && ee site php-compat $S --php=8.4 --format=table) < /dev/null > $D/F-table.out 2>&1; has "F table first line names the site and target" "$S" "$(head -1 $D/F-table.out)"; info "F table first line: $(head -1 $D/F-table.out)"
  has "F table static-analysis line last" "This is static analysis" "$(tail -1 $D/F-table.out)"
  # --output
  install -d -m 0700 /root/pco; ok() { pcs F-out-ok $S; mv -f $D/F-out-ok.report.json /dev/null 2>/dev/null; }
  out() { local l=$1 o=$2 want=$3; (cd /tmp && ee site php-compat $S --php=8.4 --format=json "--output=$o") < /dev/null > $D/F-o-$l.out 2> $D/F-o-$l.err; local r=$?
    if [ $want = ok ]; then chk "F --output=$o accepted: rc status report=path" "0 ok $o" "$r $(jq -r '"\(.status) \(.report)"' $D/F-o-$l.out 2>/dev/null | tail -1)"; chk "F --output=$o mode/owner" '600 root:root' "$(stat -c '%a %U:%G' "$o" 2>&1)"
    else chk "F --output=$o refused: rc, no document" '1 0' "$r $(grep -c '"v":1' $D/F-o-$l.out)"; info "F --output=$o message: $(cat $D/F-o-$l.out $D/F-o-$l.err | head -1)"; fi; }
  out root /root/pco/r.json ok; out tmp /tmp/pco-r.json ok
  echo old > /root/pco/exist.json; out exist /root/pco/exist.json ok
  echo keep > /root/pco/target.txt; ln -sfn /root/pco/target.txt /root/pco/link.json; out link /root/pco/link.json ok; eqs "F --output over a symlink: target untouched, link replaced" "keep file" "$(cat /root/pco/target.txt) $(stat -c %F /root/pco/link.json | cut -d' ' -f2)"
  out rel rel.json no; out dir /root/pco no; out slash /root/pco/x/ no; out missing /root/nope/r.json no; out dot /root/pco/. no
  out sitecode $(A $S)/report.json no; chk "F --output in the site's public code dir: nothing written" absent "$([ -e $(A $S)/report.json ] && echo present || echo absent)"
  install -d -m 0777 /var/tmp/pcww; out ww /var/tmp/pcww/r.json no; out devnull /dev/null no; out proc /proc/self/pcm.json no
  out comma '/root/pco/a,b.json' ok; out space '/root/pco/a b.json' ok; out nl $'/root/pco/a\nb.json' no; out esc $'/root/pco/a\e[31mb.json' no
  # --timeout
  for t in 0 -1 abc 1.5 1e3 1000000000 ' 5' '5 '; do (cd /tmp && ee site php-compat $S --php=8.4 "--timeout=$t") < /dev/null > $D/F-t.out 2>&1; chk "F --timeout=[$t] refused" 1 "$?"; done
  (cd /tmp && ee site php-compat $S --php=8.4 --timeout) < /dev/null > $D/F-tb.out 2>&1; chk "F bare --timeout refused" 1 "$?"
  pcs F-t999 $S --timeout=999999999; chk "F --timeout=999999999 accepted" 'ok false' "$ST $SAFE"
  for x in '--output=/root/pco/e.json' '--timeout=10'; do (cd /tmp && ee site php-compat $S --php=8.4 --estimate "$x") < /dev/null > $D/F-ex.out 2>&1; chk "F --estimate with $x refused" 1 "$?"; done
  pce F-est $S; chk "F estimate status" ok "$EST_ST"; info "F estimate table: $(cd /tmp && ee site php-compat $S --php=8.4 --estimate < /dev/null 2>&1 | head -1)"
  # unknown flag, unknown site, positional extras
  for a in '--foo' 'nosuch.test' "$S extra"; do (cd /tmp && ee site php-compat $a --php=8.4) < /dev/null > $D/F-u.out 2>&1; info "F [$a] rc $? $(head -2 $D/F-u.out | tr '\n' ' ')"; done ;;
cancel)
  B=pk-big.test; B2=pk-big2.test; for s in $B $B2; do run_ee c-$s site create $s --type=php; done
  body=$(for i in $(seq 1 120); do echo "\$v$i = strtoupper( 'line $i of a generated fixture file' ) . PHP_EOL;"; done)
  for s in $B $B2; do H=$(A $s); mkdir -p $H/bulk; for i in $(seq 1 5000); do printf '<?php\n// %d\n%s\n' $i "$body" > $H/bulk/f$i.php; done; plant $H/legacy/pcm-canary.php; chown -R 33:33 $H; done
  N=ee-php-compat-$B
  waitrun() { local i; for i in $(seq 1 600); do [ "$(docker inspect -f '{{.State.Running}}' $1 2>/dev/null)" = true ] && return 0; sleep 0.2; done; return 1; }
  # nothing running
  (cd /tmp && ee site php-compat $B --cancel --format=json) < /dev/null > $D/K-nr.out 2>&1; chk "K --cancel nothing running" '0 not_running' "$? $(jq -r .status $D/K-nr.out | tail -1)"
  # same site twice: busy; estimate beside a scan: ok; two sites at once: both ok
  (cd /tmp && ee site php-compat $B --php=8.4 --format=json) < /dev/null > $D/K-a.out 2>&1 & PA=$!
  (cd /tmp && ee site php-compat $B2 --php=8.4 --format=json) < /dev/null > $D/K-b.out 2>&1 & PB=$!
  waitrun $N; sleep 1
  (cd /tmp && ee site php-compat $B --php=8.5 --format=json) < /dev/null > $D/K-busy.out 2>&1; chk "K same site twice: second rc/status" '0 busy' "$? $(jq -r .status $D/K-busy.out | tail -1)"
  (cd /tmp && ee site php-compat $B --php=8.4 --estimate --format=json) < /dev/null > $D/K-est.out 2>&1; chk "K estimate beside a running scan" '0 ok' "$? $(jq -r .status $D/K-est.out | tail -1)"
  (cd /tmp && ee site php-compat $B --php=8.4 --estimate --format=json) < /dev/null > $D/K-e1.out 2>&1 & PE=$!; sleep 0.5
  (cd /tmp && ee site php-compat $B --php=8.4 --estimate --format=json) < /dev/null > $D/K-e2.out 2>&1; wait $PE; info "K two estimates at once: $(jq -r .status $D/K-e1.out | tail -1) / $(jq -r .status $D/K-e2.out | tail -1)"
  wait $PA; ra=$?; wait $PB; rb=$?
  chk "K two sites scanned at once: rc/status/safe each" '0 ok false 0 ok false' "$ra $(jq -r '"\(.status) \(.safe_to_upgrade)"' $D/K-a.out | tail -1) $rb $(jq -r '"\(.status) \(.safe_to_upgrade)"' $D/K-b.out | tail -1)"
  # cancel mid-scan (json + table), during the first-use pull, after the scan finished, during an estimate
  for f in json table; do rm -f /root/k-$f.json; (cd /tmp && ee site php-compat $B --php=8.4 --format=$f --output=/root/k-$f.json) < /dev/null > $D/K-s-$f.out 2>&1 & PA=$!
    waitrun $N; sleep 2; t0=$(date +%s.%N); (cd /tmp && ee site php-compat $B --cancel --format=$f) < /dev/null > $D/K-c-$f.out 2>&1; rc=$?; t1=$(date +%s.%N); wait $PA; ra=$?
    info "K cancel $f: cancel took $(awk "BEGIN{print $t1-$t0}") s; scan [$(cat $D/K-s-$f.out | tr '\n' ' ')] cancel [$(cat $D/K-c-$f.out | tr '\n' ' ')]"
    chk "K cancel mid-scan ($f): rc scan/cancel, output file, container" '0 0 absent gone' "$ra $rc $([ -e /root/k-$f.json ] && echo present || echo absent) $(docker inspect $N >/dev/null 2>&1 && echo left || echo gone)"; done
  pcs K-after $B; (cd /tmp && ee site php-compat $B --cancel --format=json) < /dev/null > $D/K-after-c.out 2>&1; chk "K cancel after a finished scan" not_running "$(jq -r .status $D/K-after-c.out | tail -1)"
  (cd /tmp && ee site php-compat $B --php=8.4 --estimate --format=json) < /dev/null > $D/K-est2.out 2>&1 & PE=$!; sleep 1
  (cd /tmp && ee site php-compat $B --cancel --format=json) < /dev/null > $D/K-est-c.out 2>&1; wait $PE; info "K cancel during estimate: cancel $(jq -r .status $D/K-est-c.out | tail -1), estimate $(jq -r .status $D/K-est2.out | tail -1)"
  for x in '--php=8.4' '--estimate' '--output=/root/x.json' '--timeout=5' '--timeout'; do (cd /tmp && ee site php-compat $B --cancel $x) < /dev/null > $D/K-x.out 2>&1; chk "K --cancel with $x refused" 1 "$?"; done
  # cancel during the first-use pull
  docker rmi $(docker images -q $SC) > /dev/null 2>&1; (cd /tmp && ee site php-compat $B2 --php=8.4 --format=json) < /dev/null > $D/K-pull.out 2>&1 & PA=$!; sleep 2
  (cd /tmp && ee site php-compat $B2 --cancel --format=json) < /dev/null > $D/K-pull-c.out 2>&1; wait $PA
  info "K cancel during the pull: scan [$(cat $D/K-pull.out | tr '\n' ' ')] cancel [$(cat $D/K-pull-c.out)] images now [$(docker images --format '{{.Repository}}:{{.Tag}}' $SC | tr '\n' ' ')]"
  reload_scanner; pcs K-after-pull $B2; chk "K scan after a cancelled pull" 'ok false' "$ST $SAFE"
  chk "K leftovers: containers / temp dirs / cancel files" ' 0 0' "$(docker ps -a --format '{{.Names}}' | grep '^ee-php-compat-' | tr '\n' ' ') $(find /opt/easyengine/tmp/php-compat -mindepth 2 -maxdepth 2 -not -path "*/php-compat/.*" 2>/dev/null | wc -l) $(ls -A /opt/easyengine/tmp/php-compat | grep -c '^\.cancel-[^.]*\.test$')" ;;
esac
echo "DONE $P" >> $OUT/done.txt
