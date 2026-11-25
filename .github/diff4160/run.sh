#!/bin/bash
# run.sh <shard> <side>: side stable|stable2 (A/A control) = 4.15.0 throughout, rc = the RC throughout,
# upgrade = create on 4.15.0, upgrade to the RC the way `ee cli update` does, then the commands on the RC.
# Env: OUT, STABLE_PHAR, RC_PHAR, OLD_DIR (ee-<ver>.phar). Run as root.
SHARD=$1; SIDE=$2
. "$(dirname "$0")/lib.sh"; . "$F/s-$SHARD.sh"; cd /tmp
echo "$SHARD $SIDE" > $OUT/side.txt
# The Hub mirror can serve a stale copy of a re-created tag: pull the release images by digest and tag them (digests.txt: "<image>:<tag> sha256:...").
prepull() { local it d i; while read -r it d; do i=${it%%:*}; for n in 1 2 3; do docker pull -q "$i@$d" > /dev/null 2>&1 && break; sleep 20; done
  docker tag "$i@$d" "$it" && echo "prepulled $it $d" >> $OUT/prepull.txt || echo "PREPULL-FAIL $it $d" >> $OUT/prepull.txt; done < $F/digests.txt; }
# from<ver>-<stable|rc>: create on the older release <ver>, then upgrade to 4.15.0 or to the RC.
first=$STABLE_PHAR; [ "$SIDE" = rc ] && first=$RC_PHAR; [ "$SIDE" = rcold ] && first=$RCOLD_PHAR
case $SIDE in from*-*) first=$OLD_DIR/ee-${SIDE%%-*}.phar; first=${first/ee-from/ee-}; TARGET=$STABLE_PHAR; [ "${SIDE##*-}" = rc ] && TARGET=$RC_PHAR ;; upgrade) TARGET=$RC_PHAR ;; esac
[ "$SIDE" = rc ] && [ -s $F/digests.txt ] && prepull
install -m 0755 "$first" /usr/local/bin/ee
md5sum /usr/local/bin/ee > $OUT/phar-first.md5
ok=0; for i in 1 2 3; do timeout 1500 ee cli info < /dev/null > $OUT/install-$i.txt 2>&1 && { ok=1; break; }
  grep -q toomanyrequests $OUT/install-$i.txt || break; echo "INFRA install rate limit attempt $i" >> $OUT/infra.txt; sleep 180; done
[ $ok = 1 ] || { echo "install failed"; cat $OUT/install-$i.txt; exit 1; }
# Local-only backups: a local-type rclone remote on the runner.
mkdir -p /root/.config/rclone /var/eebackups; printf '[easyengine]\ntype = local\n' > /root/.config/rclone/rclone.conf
st cfg-rclone config set rclone-path easyengine:/var/eebackups
snap init
create
snap created
if [ -n "${TARGET:-}" ]; then
  [ "$TARGET" = "$RC_PHAR" ] && [ -s $F/digests.txt ] && prepull
  T=/tmp/ee_upg.phar; cp "$TARGET" $T; s=$(date +%s)
  { echo '$ php ee_new.phar cli info'; timeout 3000 php $T cli info < /dev/null 2>&1; r=$?; echo "rc=$r"; } > $OUT/steps/upgrade.out
  [ $r = 0 ] && chmod 0755 $T && mv $T /usr/local/bin/ee
  printf 'upgrade\t%s\t%s\tphp rc.phar cli info\n' $r $(( $(date +%s) - s )) >> $OUT/steps.tsv
  md5sum /usr/local/bin/ee > $OUT/phar-after-upgrade.md5
  snap upgraded
fi
cmds
snap final
cp -a /opt/easyengine/logs/ee.log* $OUT/ 2>/dev/null
echo "DONE $SHARD $SIDE"
