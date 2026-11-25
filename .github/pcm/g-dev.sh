#!/bin/bash
# --output naming a device or a /dev link: is the node replaced? Every node is restored afterwards. Usage: g-dev.sh
. "$(dirname "$0")/lib.sh"; D=$OUT/dev; mkdir -p $D; cd /tmp
S=pd-php.test; run_ee c-$S site create $S --type=php; plant $SITES_DIR/$S/app/htdocs/legacy/pcm-canary.php
st() { stat -c '%F %a %U:%G %t,%T' "$1" 2>&1; }
mkfifo /root/pd.fifo; ln -sfn /dev/null /root/pd-null-link.json; ln -sfn /root/pd.fifo /root/pd-fifo-link.json; ln -sfn /root/nope.json /root/pd-dangling.json; mkdir -p /root/pdd
for o in /dev/null /dev/stdout /dev/stderr /dev/zero /dev/full /dev/tty /proc/self/fd/1 /root/pd.fifo /root/pd-null-link.json /root/pd-fifo-link.json /root/pd-dangling.json /dev/shm/pd.json /run/pd.json; do b=$(st $o); l=$(readlink $o)
  (cd /tmp && ee site php-compat $S --php=8.4 --format=json "--output=$o") < /dev/null > $D/o.out 2> $D/o.err; r=$?
  a=$(st $o)
  info "DEV --output=$o: rc $r, before [$b${l:+ -> $l}] after [$a$(readlink $o >/dev/null && echo " -> $(readlink $o)")]; stdout [$(head -c 150 $D/o.out)] err [$(head -c 150 $D/o.err)]"
  case $o in /root/pd-dangling.json) chk "DEV --output over a dangling link: the link is replaced, its target never created" 'absent' "$([ -e /root/nope.json ] && echo present || echo absent)" ;;
    /dev/shm/*|/run/*) info "DEV --output=$o (plain file in a root dir under /dev or /run): rc $r" ;; *) eqs "DEV --output=$o leaves the node as it was" "$b" "$a"; chk "DEV --output=$o refused before the scan (rc, no document)" '1 0' "$r $(grep -c '\"v\":1' $D/o.out)" ;; esac
  # repair
  case $o in
    /dev/null) [ -c /dev/null ] || { rm -f /dev/null; mknod -m 666 /dev/null c 1 3; } ;;
    /dev/zero) [ -c /dev/zero ] || { rm -f /dev/zero; mknod -m 666 /dev/zero c 1 5; } ;;
    /dev/full) [ -c /dev/full ] || { rm -f /dev/full; mknod -m 666 /dev/full c 1 7; } ;;
    /dev/tty) [ -c /dev/tty ] || { rm -f /dev/tty; mknod -m 666 /dev/tty c 5 0; } ;;
    /dev/stdout) [ -L /dev/stdout ] || { rm -f /dev/stdout; ln -s /proc/self/fd/1 /dev/stdout; } ;;
    /dev/stderr) [ -L /dev/stderr ] || { rm -f /dev/stderr; ln -s /proc/self/fd/2 /dev/stderr; } ;;
  esac; done
# what a non-root user sees while /dev/null is a root 0600 file
(cd /tmp && ee site php-compat $S --php=8.4 --format=json --output=/dev/null) < /dev/null > /dev/zero 2>&1
info "DEV non-root write to /dev/null afterwards: $(sudo -u nobody sh -c 'echo x > /dev/null && echo ok' 2>&1)"
[ -c /dev/null ] || { rm -f /dev/null; mknod -m 666 /dev/null c 1 3; }; info "DEV restored: $(st /dev/null) / $(st /dev/stdout)"
echo "DONE dev" >> $OUT/done.txt
