#!/bin/bash
# Pull the old stable's images before its install and population, retrying while Docker Hub answers toomanyrequests (an unauthenticated
# runner IP shares the pull limit; run 2's legacy leg lost its population to it). Upgrade-time pulls are left to EasyEngine.
# Usage: prepull.sh <img-versions.json> <scenario>. Skips easyengine/php, and php5.6-8.0 except on the legacy leg.
J=$1; SC=$2; n=0; waited=0
for kv in $(jq -r 'to_entries[] | "\(.key):\(.value)"' "$J"); do
  case ${kv%%:*} in easyengine/php) continue ;; easyengine/php5.6|easyengine/php7.*|easyengine/php8.0) [ "$SC" = legacy ] || continue ;; esac
  for i in $(seq 1 20); do
    out=$(docker pull -q "$kv" 2>&1) && { n=$((n+1)); break; }
    echo "$out" | grep -q toomanyrequests || { echo "INFO | prepull: $kv failed: $(echo $out | cut -c1-200)" >> "$RES"; break; }
    waited=$((waited+60)); sleep 60
  done
done
echo "INFO | prepull: $n images pulled before the old install, $waited s waited on Docker Hub rate limits" | tee -a "$RES"
