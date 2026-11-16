# shellcheck shell=bash
# Shared settings for the v4.14.0 lane A upgrade test (sourced). Versions come from the workflow (read from the phars), not from literals here.
F=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
MS=f4-ms.test
WPSITES="f4-ms.test f4-wp.test f4-wpc.test f4-ldb.test"
PHPSITES="f4-ms.test f4-wp.test f4-wpc.test f4-ldb.test f4-pdb.test f4-php.test f4-p74.test f4-p80.test f4-p81.test f4-p83.test f4-p84.test f4-p85.test f4-ssl.test"
# Disabled before the upgrade (seed.sh); not in ALL (not served).
OFF=f4-off.test
HTML="shop.f4-ms.test f4-html.test"
ALL="$PHPSITES $HTML"
IP=${RUNNER_IP:?RUNNER_IP not set}
OLD_VERSION=${OLD_VERSION:-}
NEW_VERSION=${NEW_VERSION:-}
EE_LOG=/opt/easyengine/logs/ee.log
P=/opt/easyengine/services/nginx-proxy
STAGE=/opt/easyengine/.backup/auth-wildcard-staging
CRONCONF=/opt/easyengine/services/cron/conf/config.ini
PROXY=services_global-nginx-proxy_1
# Whitelist entries seeded on the old version (seed.sh): nginx rejects SEED_BAD; SEED_NORM is valid for nginx but gets a normalized prefix.
SEED_BAD='198\.51\.100\.9/99|192\.0\.2\.20/33'
SEED_NORM='203\.0\.113\.0/024'
SEED_ANY="$SEED_BAD|$SEED_NORM"
ts() { date -u +%T.%N | cut -c1-12; }
code()  { curl -s -m 20 -o /dev/null -w '%{http_code}' --resolve "$1:80:$IP"  "http://$1${3:-/}"  ${2:+-u "$2"}; }
codes() { curl -sk -m 20 -o /dev/null -w '%{http_code}' --resolve "$1:443:$IP" "https://$1${3:-/}" ${2:+-u "$2"}; }
lcode() { curl -s -m 20 -o /dev/null -w '%{http_code}' --resolve "$1:80:127.0.0.1" "http://$1${2:-/}"; }
db() { sqlite3 /opt/easyengine/db/ee.sqlite "$@"; }
cname() { echo "$1" | tr -d .; }
# Lines matching $1 in every ee.log, rotated and compressed ones included.
eelog_count() { zgrep -h -- "$1" /opt/easyengine/logs/ee.log* 2>/dev/null | wc -l; }
# chk <label> <expected-regex> <actual>; appends to $RES.
chk() { local r=FAIL; [[ "$3" =~ ^($2)$ ]] && r=PASS; echo "$r | $1 | exp $2 | got $3" | tee -a "${RES:-/dev/null}"; }
info() { echo "INFO | $*" | tee -a "${RES:-/dev/null}"; }
