#!/bin/bash
# core#1981: `ee cli update` refuses while a php-compat scan runs (only when the phar has that check). Usage: g-cliupd.sh
. "$(dirname "$0")/lib.sh"; D=$OUT/cliupd; mkdir -p $D; cd /tmp
# phar:// needs a .phar name to open an archive.
cp /usr/local/bin/ee /tmp/pcm-ee.phar
if ! php -r 'echo file_get_contents("phar:///tmp/pcm-ee.phar/php/commands/src/CLI_Command.php");' 2>/dev/null | grep -q 'ee-php-compat-'; then
  info "U N/A: this phar's CLI_Command has no php-compat check (core#1981 not in the build)"; echo "DONE cliupd" >> $OUT/done.txt; exit 0; fi
waitrun() { local i; for i in $(seq 1 600); do [ "$(docker inspect -f '{{.State.Running}}' $1 2>/dev/null)" = true ] && return 0; sleep 0.2; done; return 1; }
B=pu-big.test; run_ee c-$B site create $B --type=php; H=$SITES_DIR/$B/app/htdocs; mkdir -p $H/bulk; body=$(for i in $(seq 1 120); do echo "\$v$i = strtoupper( 'line $i' ) . PHP_EOL;"; done)
for i in $(seq 1 6000); do printf '<?php\n// %d\n%s\n' $i "$body" > $H/bulk/f$i.php; done; chown -R 33:33 $H
m0=$(md5sum /usr/local/bin/ee | cut -d' ' -f1)
(cd /tmp && exec ee site php-compat $B --php=8.4 --format=json) > $D/U-scan.out 2>&1 < /dev/null & P=$!; waitrun ee-php-compat-$B; sleep 1
(cd /tmp && ee cli update --yes) < /dev/null > $D/U-update.out 2>&1; r=$?
info "U update during a scan: rc $r: $(cat $D/U-update.out | tr '\n' ' ' | cut -c1-400)"
chk "U ee cli update refused while a scan runs (rc != 0, names --cancel)" 'refused' "$([ $r != 0 ] && grep -q -- "php-compat $B --cancel" $D/U-update.out && echo refused || echo "rc$r")"
eqs "U ee binary unchanged" "$m0" "$(md5sum /usr/local/bin/ee | cut -d' ' -f1)"
wait $P; chk "U the scan finished normally" 'ok' "$(jq -r .status $D/U-scan.out 2>/dev/null | tail -1)"
echo "DONE cliupd" >> $OUT/done.txt
