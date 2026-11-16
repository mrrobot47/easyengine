#!/bin/bash
# Dumps comparable EE state into dir $1.
. "$(dirname "$0")/lib.sh"; D=$1; mkdir -p $D
db "select key,value from options where key not in ('global-db','self-signed-secret') order by key" > $D/options.txt
db "select id,migration,type from migrations order by id" > $D/migrations.txt
db "select site_url,site_type,php_version,site_enabled,site_ssl,alias_domains,app_sub_type,admin_tools,mailhog_enabled from sites order by site_url" > $D/sites.txt 2>&1
docker ps -a --format '{{.Names}}\t{{.Image}}\t{{.ID}}\t{{.Status}}' | sort > $D/containers.txt
cut -f1,2 $D/containers.txt | grep -v f4-event-dummy > $D/containers-ni.txt
docker images --format '{{.Repository}}:{{.Tag}}\t{{.ID}}' | sort > $D/images.txt
(cd $P/htpasswd && md5sum * 2>/dev/null) > $D/htpasswd.md5
(cd $P/vhost.d && md5sum * 2>/dev/null) > $D/vhostd.md5
(cd $P/vhost.d && md5sum *_acl 2>/dev/null) > $D/acl.md5
(cd $P && stat -c '%n %a %U %Y %s' htpasswd/* vhost.d/*_acl 2>/dev/null) > $D/auth-stat.txt
(cd /opt/easyengine && md5sum services/docker-compose.yml sites/*/docker-compose*.yml 2>/dev/null) > $D/compose.md5
ls -la /opt/easyengine/.backup > $D/dotbackup.txt 2>&1
ls -laR $STAGE > $D/staging.txt 2>&1
md5sum /usr/local/bin/ee > $D/ee.md5
docker-compose version --short > $D/compose-version.txt 2>&1
docker exec services_global-nginx-proxy_1 grep -c 'define "acl"' /app/nginx.tmpl > $D/template-acl-count.txt 2>&1
db "select site_url,command,schedule,user from cron order by 1,2" > $D/cron-rows.txt 2>&1
# Per _acl file: lines holding an entry seeded by seed.sh.
(cd $P/vhost.d && grep -cE "allow ($SEED_ANY);" *_acl 2>/dev/null) > $D/acl-seeded.txt
db "select site_url,ip from auth_ips order by 1,2" > $D/auth-ips.txt 2>&1
cp $CRONCONF $D/cron-config.ini 2>/dev/null
docker inspect -f '{{.State.Status}} {{.RestartCount}} {{.State.StartedAt}}' services_global-cron_1 > $D/cron-state.txt 2>&1
exit 0
