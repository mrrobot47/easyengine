#!/bin/bash
# Content checksums: htdocs trees (minus caches and wp-includes/php-ai-client, which the WP-1 repair migration rewrites; wpcore.sh checks it), WP posts/blogs/users, local-db posts, pdb rows, HTTPS of the self-signed site. Usage: content.sh <out>
. "$(dirname "$0")/lib.sh"; O=$1; : > $O
for s in $ALL; do d=/opt/easyengine/sites/$s/app/htdocs; [ -d $d ] || { echo "$s MISSING" >> $O; continue; }
  echo "$s files $(cd $d && find . -type f ! -path './wp-content/cache/*' ! -path './wp-content/upgrade/*' ! -path './wp-includes/php-ai-client/*' -print0 | sort -z | xargs -0 md5sum | md5sum | cut -c1-32) n=$(cd $d && find . -type f ! -path './wp-content/cache/*' ! -path './wp-content/upgrade/*' ! -path './wp-includes/php-ai-client/*' | wc -l)" >> $O; done
q() { docker exec services_global-db_1 sh -c "mariadb -uroot -p\"\$MYSQL_ROOT_PASSWORD\" -N -e \"$1\""; }
for db in f4_ms_test f4_wp_test f4_wpc_test; do
  echo "$db posts $(q "select ID,post_title,post_status,md5(post_content) from $db.wp_posts where post_type<>0x77705f6e617669676174696f6e order by ID" | md5sum | cut -c1-32)" >> $O; done
echo "f4_ms blogs $(q 'select blog_id,domain,path from f4_ms_test.wp_blogs order by 1' | tr '\t\n' ', ')" >> $O
echo "f4_ms users $(q 'select ID,user_login,user_pass from f4_ms_test.wp_users order by 1' | md5sum | cut -c1-32)" >> $O
echo "f4_ldb posts $(docker exec f4-ldbtest-db-1 sh -c 'mariadb -uroot -p"$MYSQL_ROOT_PASSWORD" -N -e "select ID,post_title,post_status,md5(post_content) from f4_ldb_test.wp_posts where post_type<>0x77705f6e617669676174696f6e order by ID"' 2>/dev/null | md5sum | cut -c1-32)" >> $O
echo "f4_pdb marker $(q 'select * from f4_pdb_test.f4_marker order by 1' | tr '\t\n' ', ')" >> $O
echo "pdb page $(curl -s -m 20 --resolve f4-pdb.test:80:127.0.0.1 http://f4-pdb.test/f4-db.php)" >> $O
echo "ssl cert $(echo | openssl s_client -connect 127.0.0.1:443 -servername f4-ssl.test 2>/dev/null | openssl x509 -noout -fingerprint -sha256 2>/dev/null)" >> $O
echo "ssl https $(curl -sk -m 20 -o /dev/null -w '%{http_code}' --resolve f4-ssl.test:443:127.0.0.1 https://f4-ssl.test/f4-marker.txt)" >> $O
exit 0
