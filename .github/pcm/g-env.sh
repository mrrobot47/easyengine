#!/bin/bash
# Environment faults. Usage: g-env.sh nonet|olddigest|disk|tmp|dockerrestart|kill
. "$(dirname "$0")/lib.sh"; P=$1; D=$OUT/env-$P; mkdir -p $D; cd /tmp
A() { echo $SITES_DIR/$1/app/htdocs; }
S=pe-php.test; B=pe-big.test
setup() { if ! db "select site_url from sites" | grep -qx $S; then run_ee c-$S site create $S --type=php; plant $(A $S)/legacy/pcm-canary.php
  run_ee c-$B site create $B --type=php; H=$(A $B); mkdir -p $H/bulk; body=$(for i in $(seq 1 120); do echo "\$v$i = strtoupper( 'line $i' ) . PHP_EOL;"; done)
  for i in $(seq 1 5000); do printf '<?php\n// %d\n%s\n' $i "$body" > $H/bulk/f$i.php; done; plant $H/legacy/pcm-canary.php; chown -R 33:33 $H; fi; }
left() { echo "$(docker ps -a --format '{{.Names}}' | grep '^ee-php-compat-' | tr '\n' ' ')|$(find /opt/easyengine/tmp/php-compat -mindepth 2 -maxdepth 2 -not -path "*/php-compat/.*" 2>/dev/null | wc -l)"; }
waitrun() { local i; for i in $(seq 1 600); do [ "$(docker inspect -f '{{.State.Running}}' $1 2>/dev/null)" = true ] && return 0; sleep 0.2; done; return 1; }
setup
case $P in
nonet)
  # Scanner present, registry unreachable (refused, then silently dropped): a check must still run from the local copy, without a long stall.
  pcs E-warm $S
  for mode in REJECT DROP; do iptables -I OUTPUT -p tcp --dport 443 -j $mode; iptables -I DOCKER-USER -p tcp --dport 443 -j $mode 2>/dev/null
    t0=$(date +%s); pcs E-present-$mode $S; t=$(( $(date +%s) - t0 ))
    chk "E scanner present, registry $mode: status/safe" 'ok false' "$ST $SAFE"; chk "E scanner present, registry $mode: wall time <= 90 s" 'ok' "$([ $t -le 90 ] && echo ok || echo "${t}s")"
    info "E present/$mode took $t s; pull lines: $(grep -i 'pull' $D/E-present-$mode.err | head -3 | cut -c1-200 | tr '\n' ' ')"
    iptables -D OUTPUT -p tcp --dport 443 -j $mode; iptables -D DOCKER-USER -p tcp --dport 443 -j $mode 2>/dev/null; done
  # Registry unreachable: outbound TCP 443 rejected (an /etc/hosts override stuck in the resolver in run 45371962575).
  docker rmi $(docker images -q $SC) > /dev/null 2>&1
  iptables -I OUTPUT -p tcp --dport 443 -j REJECT; ip6tables -I OUTPUT -p tcp --dport 443 -j REJECT 2>/dev/null
  iptables -I DOCKER-USER -p tcp --dport 443 -j REJECT 2>/dev/null
  pcs E-nonet $S; chk "E scanner missing + registry unreachable: rc/status/safe" '0 tool_error null' "$RC $ST $SAFE"; has "E pull failure detail" "image pull failed" "$(cat $D/E-nonet.out)"
  info "E nonet table: $(cd /tmp && ee site php-compat $S --php=8.4 < /dev/null 2>&1 | head -2 | tr '\n' ' ') (took $(jq -r .duration_s $D/E-nonet.out))"
  pce E-nonet-est $S; chk "E estimate, registry unreachable" tool_error "$EST_ST"
  chk "E leftovers after the failed pull" '\|0' "$(left)"
  iptables -D OUTPUT -p tcp --dport 443 -j REJECT; ip6tables -D OUTPUT -p tcp --dport 443 -j REJECT 2>/dev/null; iptables -D DOCKER-USER -p tcp --dport 443 -j REJECT 2>/dev/null
  reload_scanner; pcs E-net-back $S; chk "E scan once the registry is back" 'ok false' "$ST $SAFE" ;;
olddigest)
  pcs E-first $S; good=$(docker image inspect -f '{{.Id}}' $SC:v4.16.0)
  [ -f /var/tmp/pcm-scanner.tar.gz ] || chk "E pinned scanner is the v4.16.0 r5 registry image (3101273a)" 'yes' "$(docker image inspect -f '{{join .RepoDigests " "}}' $SC:v4.16.0 | grep -q 3101273ae081d58589848075773d255684b010a1c41fb7c6841e35ffcfbe0e24 && echo yes || echo "no[$(docker image inspect -f '{{join .RepoDigests " "}}' $SC:v4.16.0)]")" info "E pinned image id $good digests $(docker image inspect -f '{{join .RepoDigests " "}}' $SC:v4.16.0)"
  docker rmi $SC:v4.16.0 > /dev/null; docker pull -q $SC@sha256:2a315c56fa5642b96d18dc83e86f0d7850b0ed16ad7525463db349e74890c887 > $D/old-pull.txt 2>&1; info "E old digest pull: $(cat $D/old-pull.txt | tail -1)"
  docker tag $SC@sha256:2a315c56fa5642b96d18dc83e86f0d7850b0ed16ad7525463db349e74890c887 $SC:v4.16.0
  old=$(docker image inspect -f '{{.Id}}' $SC:v4.16.0); docker events --filter type=container --format '{{.Actor.Attributes.image}} {{.Action}} {{.ID}}' > $D/events.txt & EV=$!
  docker tag $SC:v4.16.0 $SC:v4.15.0-dev
  pcs E-old $S; kill $EV; info "E scan with the early v4.16.0 image ($old) present: status $ST; ran $(grep -m1 ' create ' $D/events.txt)"
  [ -f /var/tmp/pcm-scanner.tar.gz ] || chk "E early v4.16.0 scanner (2a315c56) under the pinned tag: refreshed by the check" 'refreshed' "$(docker image inspect -f '{{join .RepoDigests " "}}' $SC:v4.16.0 | grep -q 2a315c56 && echo "still-early" || echo refreshed)"
  info "E early v4.16.0 scanner present: tag now $(docker image inspect -f "{{.Id}}" $SC:v4.16.0), pinned build $good (EE checks the tag only)"
  info "E scanner tags after: $(docker images --format '{{.Repository}}:{{.Tag}} {{.ID}}' $SC | tr '\n' ' ')"; reload_scanner ;;
disk)
  pcs E-warm $S
  # /out on a tiny filesystem: the spool can't be written
  mkdir -p /opt/easyengine/tmp/php-compat; mount -t tmpfs -o size=64k,mode=0700 tmpfs /opt/easyengine/tmp/php-compat
  pcs E-tiny $B; chk "E /out full: rc/status/safe" '0 tool_error null' "$RC $ST $SAFE"; info "E tiny /out detail: $(jq -r .detail $D/E-tiny.out | tail -1)"
  chk "E leftovers after a full /out" '\|0' "$(left)"; umount /opt/easyengine/tmp/php-compat
  # host disk nearly full
  avail=$(df --output=avail -k / | tail -1); fallocate -l $(( (avail - 30*1024) * 1024 )) /var/tmp/pc-fill 2>/dev/null; info "E disk filled: $(df -h / | tail -1)"
  pcs E-full $B; chk "E host disk full: never a verdict without a report (status in ok|tool_error, report present when ok)" 'ok:present|tool_error:absent' "$ST:$([ -s $D/E-full.report.json ] && echo present || echo absent)"
  info "E full disk: $(head -c 300 $D/E-full.out)"; rm -f /var/tmp/pc-fill; chk "E leftovers after a full disk" '\|0' "$(left)"
  pcs E-after-disk $S; chk "E scan after the disk is freed" 'ok false' "$ST $SAFE" ;;
tmp)
  pcs E-warm $S
  chattr +i /opt/easyengine/tmp/php-compat; pcs E-immut $S; chk "E php-compat tmp immutable: status" 'tool_error' "$ST"; info "E immutable: $(head -c 300 $D/E-immut.out)"; chattr -i /opt/easyengine/tmp/php-compat
  mount --bind -o ro /opt/easyengine/tmp /opt/easyengine/tmp 2>/dev/null || { mount --bind /opt/easyengine/tmp /opt/easyengine/tmp; mount -o remount,ro,bind /opt/easyengine/tmp; }
  pcs E-ro $S; chk "E tmp read-only: status" 'tool_error' "$ST"; info "E ro: $(head -c 300 $D/E-ro.out)"; umount /opt/easyengine/tmp
  chmod 0777 /opt/easyengine/tmp/php-compat; pcs E-mode $S; info "E php-compat dir 0777: status $ST, mode after $(stat -c %a /opt/easyengine/tmp/php-compat)"
  chown 1000 /opt/easyengine/tmp/php-compat; pcs E-owner $S; info "E php-compat dir owned by uid 1000: status $ST $(jq -r .detail $D/E-owner.out | tail -1)"; chown 0 /opt/easyengine/tmp/php-compat
  mv /opt/easyengine/tmp /opt/easyengine/tmp.real; ln -s /opt/easyengine/tmp.real /opt/easyengine/tmp; pcs E-link $S; info "E tmp is a symlink: status $ST $(jq -r .detail $D/E-link.out | tail -1)"; rm /opt/easyengine/tmp; mv /opt/easyengine/tmp.real /opt/easyengine/tmp
  rm -rf /opt/easyengine/tmp; pcs E-gone $S; chk "E tmp removed: recreated and scan ok" 'ok false' "$ST $SAFE" ;;
dockerrestart)
  pcs E-warm $S; (cd /tmp && ee site php-compat $B --php=8.4 --format=json --output=/root/e-dr.json) < /dev/null > $D/E-dr.out 2> $D/E-dr.err & PA=$!
  waitrun ee-php-compat-$B; sleep 2; systemctl restart docker; wait $PA; ra=$?
  info "E docker restart mid-scan: rc $ra [$(cat $D/E-dr.out | tr '\n' ' ')] stderr [$(tail -3 $D/E-dr.err | tr '\n' ' ')]"
  chk "E docker restart mid-scan: rc/status (no verdict)" '0 tool_error' "$ra $(jq -r .status $D/E-dr.out 2>/dev/null | tail -1)"
  chk "E docker restart: no --output file" absent "$([ -e /root/e-dr.json ] && echo present || echo absent)"
  sleep 10; chk "E leftovers after docker restart" '\|0' "$(left)"; info "E services after restart: $(docker ps --format '{{.Names}} {{.Status}}' | grep services_ | tr '\n' ';')"
  pcs E-after-dr $B; chk "E scan after docker restart" 'ok false' "$ST $SAFE" ;;
kill)
  pcs E-warm $S
  for sig in KILL TERM INT; do (cd /tmp && exec ee site php-compat $B --php=8.4 --format=json --output=/root/e-k.json) < /dev/null > $D/E-k-$sig.out 2>&1 & PA=$!
    waitrun ee-php-compat-$B; sleep 2; pid=$(pgrep -f "site php-compat $B" | head -1); kill -$sig $pid; wait $PA 2>/dev/null; sleep 2
    info "E SIG$sig ee mid-scan: [$(head -c 300 $D/E-k-$sig.out | tr '\n' ' ')] leftovers [$(left)]"
    [ $sig != KILL ] && chk "E SIG$sig: the scan cleaned up (container, temp dir)" '\|0' "$(left)"
    if [ $sig = KILL ]; then pcs E-k-busy $B; chk "E after SIGKILL, the orphaned container still runs: next scan" busy "$ST"
      (cd /tmp && ee site php-compat $B --cancel --format=json) < /dev/null > $D/E-k-cancel.out 2>&1; chk "E --cancel removes the orphan" 'cancelled' "$(jq -r .status $D/E-k-cancel.out | tail -1)"; chk "E leftovers after the orphan cancel" '\|0' "$(left)"; fi
    chk "E SIG$sig: no --output file" absent "$([ -e /root/e-k.json ] && echo present || echo absent)"; done
  # killed and left alone: the next scan clears what the killed run left
  (cd /tmp && exec ee site php-compat $S --php=8.4 --format=json) < /dev/null > /dev/null 2>&1 & PA=$!; waitrun ee-php-compat-$S; kill -9 $(pgrep -f "site php-compat $S" | head -1); sleep 20
  info "E killed small scan, left alone: $(left)"; pcs E-k-next $S; chk "E next scan after a killed one" 'ok false' "$ST $SAFE"; chk "E leftovers afterwards" '\|0' "$(left)" ;;
esac
echo "DONE env-$P" >> $OUT/done.txt
