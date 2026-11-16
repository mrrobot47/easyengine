#!/bin/bash
# "host creds -> code" via the runner's non-loopback IP (not whitelisted).
. "$(dirname "$0")/lib.sh"
while read -r h c; do
  [ -z "$h" ] && continue; lbl=$c; [ "$c" = "-" ] && c=""
  printf '%-22s %-6s %s\n' "$h" "$lbl" "$(code "$h" "$c")"
done <<'L'
f4-ms.test -
f4-ms.test u1:p1
a.f4-ms.test -
a.f4-ms.test u1:p1
a.f4-ms.test u3:p3
x.y.f4-ms.test -
shop.f4-ms.test -
shop.f4-ms.test u1:p1
shop.f4-ms.test g:g
f4-php.test -
f4-php.test u3:p3
f4-alias.test -
f4-alias.test u3:p3
foo.f4-wild.test -
foo.f4-wild.test u3:p3
f4-pdb.test -
f4-pdb.test u4:p4
f4-html.test -
f4-html.test g:g
f4-wp.test -
f4-wp.test g:g
L
exit 0
