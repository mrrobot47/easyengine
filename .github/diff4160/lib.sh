# shellcheck shell=bash
# Release differential (v4.16.0 RC vs stable 4.15.0): shared helpers. Every scenario runs the same steps on every side; outputs, rc and
# state snapshots are captured raw and normalised/diffed offline. No set -e: a failed step is data.
export LC_ALL=C
F=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
OUT=${OUT:?}; SITES=/opt/easyengine/sites; SVC=/opt/easyengine/services; PROXY=services_global-nginx-proxy_1
mkdir -p "$OUT/steps" "$OUT/snap"
W="--admin-user=admin --admin-email=a@example.com --admin-pass=Adm1nPass4160d"
db() { sqlite3 /opt/easyengine/db/ee.sqlite "$@"; }
cname() { echo "$1" | tr -d .; }
ts() { date -u +%T; }
# st <id> <ee args...>: one ee call, stdin closed, 20 min cap. Output in steps/<id>.out, rc and seconds in steps.tsv.
st() { local id=$1 s e r o; shift; o=$OUT/steps/$id.out; [ -e "$o" ] && { id=$id-dup$RANDOM; o=$OUT/steps/$id.out; }
  s=$(date +%s); { echo "\$ ee $*"; timeout 1200 ee "$@" < /dev/null 2>&1; r=$?; echo "rc=$r"; } > "$o"; e=$(date +%s)
  printf '%s\t%s\t%s\tee %s\n' "$id" "$r" "$((e - s))" "$*" >> "$OUT/steps.tsv"
  grep -qiE 'toomanyrequests|TLS handshake timeout|i/o timeout|net/http: request canceled' "$o" && echo "INFRA $id" >> "$OUT/infra.txt"
  echo "[$(ts)] $id rc=$r ($((e - s)) s) ee $*"; return 0; }
# sh_st <id> <shell command>: a non-ee step (wp-cli, file edits), captured the same way.
sh_st() { local id=$1 r; shift; { echo "\$ $*"; timeout 600 bash -c "$*" < /dev/null 2>&1; r=$?; echo "rc=$r"; } > "$OUT/steps/$id.out"
  printf '%s\t%s\t-\tsh %s\n' "$id" "$r" "$*" >> "$OUT/steps.tsv"; echo "[$(ts)] $id rc=$r sh"; return 0; }
# wpx <site> <wp args>: WP-CLI as www-data in the site's php service.
wpx() { (cd "$SITES/$1" && docker-compose exec -T --user=www-data php sh -c "wp $2"); }
# Public-dir markers: a distinct file at every level from htdocs down to the public dir, so the served one tells where the webroot is.
mark() { local s=$1 p=${2:-} d=$SITES/$1/app/htdocs lvl=root; echo "MARK-$s-htdocs" > $d/mark.txt
  if [ -n "$p" ]; then local acc=; for part in ${p//\// }; do acc=$acc/$part; mkdir -p $d$acc; echo "MARK-$s-${acc#/}" > $d$acc/mark.txt; done; fi
  chown --reference=$d $d/mark.txt; [ -n "$p" ] && chown -R --reference=$d $d/${p%%/*}; chmod 644 $(find $d -maxdepth 6 -name mark.txt) 2>/dev/null; return 0; }
# PHP marker page in the webroot: prints a marker, the PHP version, the docroot and a custom ini value.
phpmark() { local s=$1 web=$2; cat > $web/pmark.php <<PHP
<?php header('Content-Type: text/plain'); echo 'PMARK-$s ', PHP_VERSION, ' docroot=', \$_SERVER['DOCUMENT_ROOT'], ' mem=', ini_get('memory_limit'), ' sid_len=', var_export(ini_get('session.sid_length'), true), ' nr=', extension_loaded('newrelic') ? 1 : 0, ' redis=', extension_loaded('redis') ? 1 : 0;
PHP
  chmod 644 $web/pmark.php; chown --reference=$web $web/pmark.php; }
# http <host> <path> [https]: code, Location, the first MARK/PMARK token or <title>, X-Diff-Custom header.
http() { local h=$1 p=${2:-/} sc=${3:-http} port=80 hd bd c; [ "$sc" = https ] && port=443; hd=$(mktemp); bd=$(mktemp)
  local i; for i in 1 2 3; do c=$(curl -sk -m 25 -D $hd -o $bd -w '%{http_code}' --resolve "$h:$port:127.0.0.1" "$sc://$h$p"); [ "$c" != 000 ] && break; echo "$sc://$h$p 000 attempt $i" >> $OUT/http-retries.txt; sleep 5; done
  echo "$sc://$h$p $c loc=$(tr -d '\r' < $hd | awk 'tolower($1)=="location:"{print $2}' | tail -1) custom=$(tr -d '\r' < $hd | awk 'tolower($1)=="x-diff-custom:"{print $2}' | tail -1) body=$(grep -aoE '(P?MARK-[^ <]*( [0-9.]+ docroot=[^ ]* mem=[^ ]* sid_len=[^ ]* nr=[01] redis=[01])?)|<title>[^<]*</title>' $bd | head -1)"
  rm -f $hd $bd; }
# snap <label>: comparable state. Raw values; normalisation happens offline.
snap() { local L=$1 D=$OUT/snap/$1 s c t; mkdir -p $D/sites $D/ctr; sleep 3
  for t in $(db ".tables"); do db -header "select * from $t order by 1,2" > $D/db-$t.txt 2>&1; done
  docker ps -a --format '{{.Names}}' | sort | while read -r c; do
    docker inspect -f '{{.Name}}	{{.Config.Image}}	{{.State.Status}}	{{index .Config.Labels "com.docker.compose.project.config_files"}}' $c | sed 's#^/##'
    { docker inspect -f '{{range .Mounts}}{{.Type}} {{.Name}} {{.Source}} -> {{.Destination}} rw={{.RW}}{{println}}{{end}}' $c | sort
      echo "--- env"; docker inspect -f '{{range .Config.Env}}{{println .}}{{end}}' $c | sort
      echo "--- networks"; docker inspect -f '{{range $k, $v := .NetworkSettings.Networks}}{{println $k}}{{end}}' $c | sort
      echo "--- image digests"; docker image inspect -f '{{join .RepoDigests " "}}' "$(docker inspect -f '{{.Image}}' $c)"; } > $D/ctr/$c.txt 2>&1
    [ "$(docker inspect -f '{{.State.Status}}' $c)" = running ] || docker logs --tail 30 $c > $D/ctr/$c.notrunning.log 2>&1
    # Effective PHP facts (CLI reads the same conf.d as FPM): New Relic settings, AVIF encode.
    case $c in *-php-1) [ "$(docker inspect -f '{{.State.Status}}' $c)" = running ] && docker exec $c php -r '
      echo "nr_loaded=", extension_loaded("newrelic") ? 1 : 0, "\n";
      foreach (["newrelic.cross_application_tracer.enabled","newrelic.distributed_tracing_enabled","newrelic.span_events_enabled","newrelic.application_logging.enabled","newrelic.application_logging.forwarding.enabled","newrelic.application_logging.metrics.enabled","newrelic.appname"] as $k) echo $k, "=", var_export(ini_get($k), true), "\n";
      echo "license_set=", (ini_get("newrelic.license") !== false && ini_get("newrelic.license") !== "" && ini_get("newrelic.license") !== "REPLACE_WITH_REAL_KEY") ? 1 : 0, "\n";
      if (class_exists("Imagick")) { try { $i = new Imagick(); $i->newImage(4, 4, "red"); $i->setImageFormat("avif"); echo "avif_encode=", strlen($i->getImageBlob()) > 0 ? "ok" : "empty", "\n"; } catch (Throwable $e) { echo "fail ", get_class($e), "\n"; } } else { echo "avif_encode=no-imagick\n"; }' > $D/ctr/$c.phpfacts.txt 2>&1 ;; esac
  done > $D/containers.txt
  docker images --format '{{.Repository}}:{{.Tag}}' | sort > $D/images.txt
  for s in $(ls $SITES 2>/dev/null); do mkdir -p $D/sites/$s
    (cd $SITES/$s && for f in docker-compose*.yml .env wp-cli.yml app/wp-cli.yml; do [ -f $f ] && { echo "=== $f"; cat $f; }; done
      for f in $(find -L user-docker-compose config -type f 2>/dev/null | grep -vE '\.(gz|log|pem|key|crt)$|/php\.ini(-development|-production)?$' | sort); do echo "=== $f"; cat $f; done
      echo "=== php.ini md5 / sid lines"; for f in $(find -L config/php -name php.ini 2>/dev/null); do echo "$f $(md5sum < $f | cut -c1-32)"; grep -nE '^\s*session\.sid' $f; done
      echo "=== tree"; find . -maxdepth 4 \( -path ./app/htdocs/wp-content -o -path ./app/htdocs/wp-includes -o -path ./app/htdocs/wp-admin -o -path ./logs -o -path '*/wp-includes' -o -path '*/wp-admin' -o -path '*/wp-content' \) -prune -o -printf '%M %u:%g %p %l\n' | sort -k3) > $D/sites/$s/files.txt 2>&1
    docker exec $(cname $s)-nginx-1 nginx -T > $D/sites/$s/nginx-T.txt 2> $D/sites/$s/nginx-T.err
  done
  (cd $SVC && for f in docker-compose.yml cron/conf/config.ini; do [ -f $f ] && { echo "=== $f"; cat $f; }; done
    echo "=== nginx-proxy tree"; find nginx-proxy -maxdepth 2 \( -path nginx-proxy/certs -o -path nginx-proxy/vhost.d -o -path nginx-proxy/htpasswd -o -path nginx-proxy/conf.d \) -prune -o -printf '%M %p\n' | sort
    for d in vhost.d conf.d htpasswd; do for f in $(find nginx-proxy/$d -type f 2>/dev/null | sort); do echo "=== $f"; cat $f; done; done
    echo "=== certs"; for f in $(find nginx-proxy/certs -name '*.crt' 2>/dev/null | sort); do echo "$f $(openssl x509 -in $f -noout -subject -ext subjectAltName 2>&1 | tr '\n' ' ')"; done) > $D/services.txt 2>&1
  docker exec $PROXY nginx -T > $D/proxy-nginx-T.txt 2> $D/proxy-nginx-T.err
  for u in $HTTP; do IFS='|' read -r h p sc <<< "$u"; http $h $p $sc; done > $D/http.txt
  ee site list < /dev/null > $D/site-list.txt 2>&1
  for s in $(ls $SITES 2>/dev/null); do echo "### $s"; ee site info $s < /dev/null 2>&1; done > $D/site-info.txt
  ee cron list --all < /dev/null > $D/cron-list.txt 2>&1
  ee cli version < /dev/null > $D/cli-version.txt 2>&1
  echo "[$(ts)] snap $L"; }
# cid <command substring>: id of the first cron job whose command contains it.
cid() { local q=${1//\'/\'\'}; db "select id from cron where command like '%$q%' order by id limit 1"; }
# sidini <site>: the php.ini in the site's php config.
sidini() { find -L $SITES/$1/config/php -name php.ini | head -1; }
# setkey <site> <key>: NEWRELIC_LICENSE_KEY in the site's .env.
setkey() { local e=$SITES/$1/.env; if grep -q '^NEWRELIC_LICENSE_KEY=' $e; then sed -i "s/^NEWRELIC_LICENSE_KEY=.*/NEWRELIC_LICENSE_KEY=$2/" $e; else echo "NEWRELIC_LICENSE_KEY=$2" >> $e; fi; }
NRKEY=0123456789abcdef0123456789abcdef01234567
# custom_conf <site>: a user nginx include and a php ini override, as real sites have.
custom_conf() { local s=$1 d=$SITES/$1/config
  mkdir -p $d/nginx/custom; echo 'add_header X-Diff-Custom on always;' > $d/nginx/custom/user.conf
  echo 'memory_limit = 321M' > $d/php/php/conf.d/zz-diff.ini 2>/dev/null || echo "custom_conf: no conf.d for $s"; }
# holder <site>: a running container mounting the site's php config volume (the real-holder refusal of site update --php).
holder() { local v; v=$(docker volume ls -q | grep -x "$(cname $1)_config_php" | head -1); docker run -d --name diffhold-$(cname $1) -v $v:/x:ro alpine:3.20 sleep 600; }
