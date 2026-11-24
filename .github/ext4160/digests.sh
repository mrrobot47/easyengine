#!/bin/bash
# End of job: every local image tagged easyengine/<n>:v4.16.0 has the GO.env digest of <n>; no image, compose file or container names a superseded digest.
. "$(dirname "$0")/lib.sh"; L=digests
docker images -aq | sort -u | xargs -r docker image inspect -f '{{.Id}} {{json .RepoTags}} {{json .RepoDigests}}' | sort > $OUT/image-digests.txt
n=0; while read -r id tags digs; do
  for t in $(echo "$tags" | jq -r '.[]' 2>/dev/null | grep -E '^easyengine/[^:]+:v4\.16\.0$'); do i=${t%%:*}; i=${i#easyengine/}; n=$((n+1)); e=$(dg $i)
    chk "$L: $t has its GO digest" yes "$([ -n "$e" ] && echo "$digs" | jq -r '.[]' | grep -qx "easyengine/$i@$e" && echo yes || echo "no[$digs]")"; done
done < $OUT/image-digests.txt
# Unchanged v4.15.0 pins with a GO.env digest (php8.5, php8.6): same check.
while read -r id tags digs; do
  for t in $(echo "$tags" | jq -r '.[]' 2>/dev/null | grep -E '^easyengine/php8\.[56]:v4\.15\.0$'); do i=${t%%:*}; i=${i#easyengine/}; e=$(awk -v i="$i" '$1=="DIGEST15" && $2==i {print $3; exit}' "$KN")
    [ -n "$e" ] && chk "$L: $t has its GO digest" yes "$(echo "$digs" | jq -r '.[]' | grep -qx "easyengine/$i@$e" && echo yes || echo "no[$digs]")"; done
done < $OUT/image-digests.txt
chk "$L: local easyengine/*:v4.16.0 images checked" '[1-9][0-9]*' "$n"
info "$L: v4.16.0 images present: $(grep -oE 'easyengine/[^:"]+:v4\.16\.0' $OUT/image-digests.txt | sort -u | tr '\n' ' ')"
c=$(grep -cE "$OLD_DIGESTS" $OUT/image-digests.txt); chk "$L: images with a superseded digest ($OLD_DIGESTS)" "0 of [0-9]+ images" "$c of $(wc -l < $OUT/image-digests.txt) images"
c=$( { grep -lE "$OLD_DIGESTS" $SITES_DIR/*/docker-compose*.yml /opt/easyengine/services/docker-compose.yml 2>/dev/null || true; } | wc -l); chk "$L: compose files naming a superseded digest" 0 "$c"
c=$(docker ps -aq | xargs -r docker inspect -f '{{.Name}} {{.Image}}' | while read -r nm im; do img_digests "$im" | grep -qE "$OLD_DIGESTS" && echo "$nm"; done | tr '\n' ' '); chk "$L: containers on an image with a superseded digest" "" "$c"
done_mark digests
exit 0
