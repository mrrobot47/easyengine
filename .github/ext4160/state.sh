#!/bin/bash
# Dumps comparable EE state into dir $1: containers (ID, StartedAt, image), images, DB tables, compose and php config hashes, php facts, HTTP, ee site list/info, cron.
. "$(dirname "$0")/lib.sh"; D=$1; mkdir -p $D/compose $D/info
for c in $(docker ps -aq); do docker inspect -f '{{.Name}}	{{.Id}}	{{.State.Status}}	{{.State.StartedAt}}	{{.RestartCount}}	{{.Config.Image}}	{{.Image}}' $c; done | sed 's#^/##' | sort > $D/containers.txt
docker images --format '{{.Repository}}:{{.Tag}}	{{.ID}}' | sort > $D/images.txt
db "select key,value from options where key not in ('global-db','self-signed-secret') order by key" > $D/options.txt
db "select id,migration,type from migrations order by id" > $D/migrations.txt
db "select site_url,site_type,php_version,site_enabled,site_ssl,site_ssl_wildcard,cache_nginx_browser,cache_nginx_fullpage,cache_mysql_query,cache_app_object,cache_host,db_host,alias_domains,app_sub_type,admin_tools,mailhog_enabled from sites order by site_url" > $D/sites.txt 2>&1
db "select * from sites order by site_url" > $D/sites-full.txt 2>&1
db "select * from site_meta order by site_url, meta_key" > $D/site_meta.txt 2>&1
db "select id,site_url,command,schedule,user from cron order by id" > $D/cron-db.txt 2>&1
for s in $ENABLED; do cp $SITES_DIR/$s/docker-compose.yml $D/compose/$s.yml 2>/dev/null; done
(cd /opt/easyengine && md5sum services/docker-compose.yml sites/*/docker-compose*.yml 2>/dev/null) > $D/compose.md5
(cd $SITES_DIR && for s in $ENABLED; do find -L ./$s/config/php -type f -print0; done | LC_ALL=C sort -z | xargs -0 md5sum) > $D/php-config.md5 2>/dev/null
for s in $ENABLED; do docker inspect $(phpc $s) >/dev/null 2>&1 && echo "$s $(php_line $s $D)"; done > $D/php.txt
docker exec $PROXY nginx -v > $D/nginx-v.txt 2>&1
set -- $URLS; while [ $# -ge 2 ]; do echo "$1 $2 $(hcode $1 $2)"; shift 2; done > $D/http.txt
for s in $WPS; do echo "$s /wp-login.php $(hcode $s /wp-login.php)"; done >> $D/http.txt
for s in $ENABLED; do [ $s = $HTML ] || echo "$s $(fpm $s)"; done > $D/fpm.txt
cp /opt/easyengine/services/cron/conf/config.ini $D/cron-config.ini 2>/dev/null
ee cli version > $D/cli-version.txt 2>&1
ee site list > $D/site-list.txt 2>&1
for s in $ENABLED; do ee site info $s > $D/info/$s.txt 2>&1; done
ee cron list --all > $D/cron-list.txt 2>&1
echo "$W84 /ee-admin/ $(hcode $W84 /ee-admin/)" > $D/admin-http.txt
cat $D/http.txt $D/php.txt
exit 0
