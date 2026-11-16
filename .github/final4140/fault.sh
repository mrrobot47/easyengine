#!/bin/bash
# fault.sh arm|off. arm: a docker-compose wrapper reports 2.20.0 only while ee-update-docker-compose runs (after the image migration), and the
# immutable .backup/docker-compose.backup makes that step throw. int-all copy of release-upgrade-4131/fault.sh: upgrade r2 replaces
# docker-compose only below 2.26.1 (2.26.5 no longer triggers it) and then removes the old backup first ("Failed to remove file").
B=/opt/easyengine/.backup/docker-compose.backup
case $1 in
arm)
  mkdir -p /opt/easyengine/.backup; [ -e $B ] || cp /usr/local/bin/docker-compose $B
  touch -d '2020-01-01' $B; chattr +i $B
  cat > /usr/local/sbin/docker-compose <<'W'
#!/bin/bash
if [ "$1" = version ] && [ "$2" = --short ] && [ "$(grep -oE 'Executing [a-z0-9_-]+' /opt/easyengine/logs/ee.log | tail -1)" = "Executing ee-update-docker-compose" ]; then
  echo "$(date -u +%T) fault fired" >> /var/tmp/f4-fault-fired.txt; echo 2.20.0; exit 0; fi
exec /usr/local/bin/docker-compose "$@"
W
  chmod 0755 /usr/local/sbin/docker-compose ;;
off) chattr -i $B 2>/dev/null; rm -f /usr/local/sbin/docker-compose ;;
esac
echo "fault $1: $(command -v docker-compose) $(docker-compose version --short) $(lsattr $B 2>&1 | cut -c1-22)"
