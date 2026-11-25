#!/bin/bash
# Results quality: old wordpress.org plugin versions with known PHP 7/8 breakage, compared with PHPCS run directly on the same tree. Usage: g-quality.sh
. "$(dirname "$0")/lib.sh"; D=$OUT/quality; mkdir -p $D/zips; cd /tmp
Q=pq-wp.test; run_ee c-$Q site create $Q --type=wp --title=pq $W
PL=$SITES_DIR/$Q/app/htdocs/wp-content/plugins
for z in contact-form-7.3.0 nextgen-gallery.1.9.13 wp-super-cache.0.9.9 woocommerce.1.6.6 akismet.2.5.0 google-sitemap-generator.3.2.9 really-simple-captcha.1.0 wordpress-importer.0.6 tinymce-advanced.3.4.9 wp-mail-smtp.0.9.1 duplicate-post.2.6 regenerate-thumbnails.2.2.4; do
  slug=${z%%.[0-9]*}; curl -fsSL --retry 3 "https://downloads.wordpress.org/plugin/$z.zip" -o $D/zips/$z.zip || { info "Q download $z failed"; continue; }
  rm -rf "$PL/$slug"; (cd $PL && 7z x -y -bd $D/zips/$z.zip > /dev/null) || info "Q unzip $z failed"; done
chown -R 33:33 $PL; find $PL -name '*.php' | wc -l > $D/php-count.txt; info "Q plugins: $(ls $PL | tr '\n' ' '), $(cat $D/php-count.txt) php files"
for v in 8.4 8.0 7.4; do PCV=$v pcs Q-$v $Q; IMG=$(docker images --format '{{.Repository}}:{{.Tag}}' $SC | head -1); info "Q php-compat $v: $(head -c 400 $D/Q-$v.out)"
  # direct PHPCS (the image's own toolchain), per plugin directory, same standard/target/annotation handling, no batching or EE plumbing
  docker run --rm --network none --user 33:33 -v $PL:/p:ro --entrypoint php $IMG -d memory_limit=2G /opt/compat-scanner/vendor/squizlabs/php_codesniffer/bin/phpcs \
    --standard=PHPCompatibilityWP --runtime-set testVersion $v --extensions=php --no-cache -q --ignore-annotations --report=json /p > $D/direct-$v.json 2> $D/direct-$v.err
  for slug in $(ls $PL); do
    ec=$(jq --arg s "$slug" '[.components[]? | select(.slug==$s or .slug==($s+".php")) | .errors] | add // 0' $D/Q-$v.report.json 2>/dev/null)
    ed=$(jq --arg p "/p/$slug" '[.files | to_entries[] | select((.key|startswith($p+"/")) or .key==$p) | .value.messages[] | select(.type=="ERROR") | select(.source|startswith("Internal.")|not)] | length' $D/direct-$v.json 2>/dev/null)
    fc=$(jq --arg s "$slug" '[.components[]? | select(.slug==$s or .slug==($s+".php")) | .files] | add // 0' $D/Q-$v.report.json 2>/dev/null)
    fd=$(jq --arg p "/p/$slug" '[.files | keys[] | select(startswith($p+"/"))] | length' $D/direct-$v.json 2>/dev/null)
    chk "Q $v $slug: php-compat errors = direct PHPCS errors (files ee/direct $fc/$fd)" "$ed" "$ec"; done
  info "Q $v not_checked: $(jq -c '.not_checked' $D/Q-$v.report.json 2>/dev/null | cut -c1-400)"; done
chk "Q 8.4: verdict on legacy plugins" 'ok false' "$(jq -r '"\(.status) \(.safe_to_upgrade)"' $D/Q-8.4.out | tail -1)"
(cd /tmp && ee site php-compat $Q --php=8.4) < /dev/null > $D/Q-table.txt 2>&1; info "Q table head: $(head -12 $D/Q-table.txt | tr '\n' ' ' | cut -c1-900)"
# known removed functions in this set, by grep (independent of PHPCS): each must be reported for 8.0+
for fn in create_function each mysql_connect ereg split get_magic_quotes_gpc; do g=$(grep -rlE "(^|[^a-zA-Z0-9_>:$])$fn\s*\(" $PL --include=*.php | wc -l)
  r=$(jq --arg f "$fn" '[.components[]?.findings[]? | select(.source|test("\\." + $f + "D|\\." + $f + "Deprecated|\\." + $f + "Removed";"i"))] | length' $D/Q-8.4.report.json 2>/dev/null)
  info "Q grep $fn( in $g files; php-compat 8.4 findings with that sniff: $r"; done
echo "DONE quality" >> $OUT/done.txt
