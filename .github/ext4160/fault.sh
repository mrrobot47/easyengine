#!/bin/bash
# Fault injectors for the failure legs: a docker-compose wrapper in /usr/local/sbin (ahead of /usr/local/bin in PATH) that keys on the
# last "Executing|Reverting <step>" line of ee.log (RevertableStepProcessor debug lines), so it acts only inside one upgrade step.
# Usage: fault.sh late|mid <site>|site <site>|off
#   late:  `docker-compose version --short` says 2.20.0 while ee-update-docker-compose runs (after the image migration), and the
#          immutable .backup/docker-compose.backup makes update_docker_compose() throw when it removes it (int-all faillate).
#   mid:   when upgrade-<site>-containers runs, block Docker Hub (block.sh on) and then run the real compose: that site's php image
#          pull fails for real, after the globals and earlier sites were recreated. Rollback steps (Reverting) are not touched.
#   site:  when upgrade-<site>-containers runs, `docker-compose up` exits 1 (images present: a non-pull failure after the pulls).
#   off:   removes the wrapper and the immutable flag, and turns the block off.
D=$(cd "$(dirname "$0")" && pwd); B=/opt/easyengine/.backup/docker-compose.backup; W=/usr/local/sbin/docker-compose; FIRED=/var/tmp/ext-fault-fired.txt
wrapper() { # $1 = mode, $2 = site
  cat > $W <<WR
#!/bin/bash
MODE=$1; SITE=$2; BLOCK=$D/block.sh; FIRED=$FIRED
WR
  cat >> $W <<'WR'
last=$(grep -oE '(Executing|Reverting) [^ ]+' /opt/easyengine/logs/ee.log 2>/dev/null | tail -1)
case $MODE in
late)
  if [ "$1" = version ] && [ "$2" = --short ] && [ "$last" = "Executing ee-update-docker-compose..." ]; then
    echo "$(date -u +%T.%N) late fault fired" >> $FIRED; echo 2.20.0; exit 0; fi ;;
mid)
  if [ "$last" = "Executing upgrade-$SITE-containers..." ] && [ ! -e /var/tmp/ext-block/mid-done ]; then
    touch /var/tmp/ext-block/mid-done; bash $BLOCK on >> $FIRED 2>&1; echo "$(date -u +%T.%N) mid fault fired (Docker Hub blocked) at: docker-compose $*" >> $FIRED; fi ;;
site)
  if [ "$last" = "Executing upgrade-$SITE-containers..." ] && [[ " $* " == *" up "* ]]; then
    echo "$(date -u +%T.%N) site fault fired: docker-compose $* in $PWD" >> $FIRED; echo "injected fault: docker-compose up refused for $SITE" >&2; exit 1; fi ;;
esac
exec /usr/local/bin/docker-compose "$@"
WR
  chmod 0755 $W; }
mkdir -p /var/tmp/ext-block
case $1 in
late)
  mkdir -p /opt/easyengine/.backup; [ -e $B ] || cp /usr/local/bin/docker-compose $B
  chattr +i $B; wrapper late ;;
mid) rm -f /var/tmp/ext-block/mid-done; wrapper mid "$2" ;;
site) wrapper site "$2" ;;
off) chattr -i $B 2>/dev/null; rm -f $W; bash $D/block.sh off ;;
esac
hash -r
echo "fault $1 ${2:-}: $(command -v docker-compose) $(/usr/local/bin/docker-compose version --short) backup $(lsattr $B 2>&1 | cut -c1-22)"
