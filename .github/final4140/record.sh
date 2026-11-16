#!/bin/bash
# Reads VERSION, img-versions.json and the migration lists of the old and new phars, derives the expectations (changed images, new migrations), checks them against the knobs and exports them to $GITHUB_ENV.
# Usage: record.sh <new.phar> <old.phar>. Env: OUT, RES, OLD_VERSION, EXPECT_VERSION, EXPECT_CHANGED_IMAGES, EXPECT_NEW_MIGRATIONS (both optional, space separated).
N=$1; O=$2; export LC_ALL=C
r() { php -r 'echo file_get_contents("phar://" . $argv[1] . "/" . $argv[2]);' "$1" "$2"; }
migs() { php -r '$b = "phar://" . $argv[1] . "/"; foreach (new RecursiveIteratorIterator(new Phar($argv[1])) as $f) { $n = substr($f->getPathname(), strlen($b)); if (preg_match("~^(?:vendor/easyengine/[^/]+/)?migrations/(db|container)/([0-9]+_[^/]+\.php)$~", $n, $m)) echo $m[1], "/", $m[2], "\n"; }' "$1" | sort; }
res() { echo "$1 | record: $2 | $3" | tee -a "$RES"; }
eq() { [ "$(echo "$2" | tr ' ' '\n' | sed '/^$/d' | sort)" = "$(echo "$3" | tr ' ' '\n' | sed '/^$/d' | sort)" ] && res PASS "$1" "$3" || res FAIL "$1" "exp [$2] got [$3]"; }

NEWV=$(r "$N" VERSION | tr -d '[:space:]'); OLDV=$(r "$O" VERSION | tr -d '[:space:]')
echo "$NEWV" > "$OUT/new-version.txt"; echo "$OLDV" > "$OUT/old-version.txt"
r "$N" img-versions.json > "$OUT/img-versions.json"; r "$O" img-versions.json > "$OUT/img-old.json"
migs "$N" > "$OUT/migrations-new-phar.txt"; migs "$O" > "$OUT/migrations-old-phar.txt"
comm -13 "$OUT/migrations-old-phar.txt" "$OUT/migrations-new-phar.txt" > "$OUT/new-migrations.txt"
jq -r --slurpfile o "$OUT/img-old.json" 'to_entries[] | select(.value != ($o[0][.key] // "")) | .key' "$OUT/img-versions.json" | sort > "$OUT/img-changed.txt"
echo "new $NEWV, old $OLDV; migrations $(wc -l < "$OUT/migrations-old-phar.txt") -> $(wc -l < "$OUT/migrations-new-phar.txt")"; cat "$OUT/new-migrations.txt" "$OUT/img-changed.txt"

[[ $NEWV =~ ^(${EXPECT_VERSION:-.*})$ ]] && res PASS "phar VERSION matches EXPECT_VERSION" "$NEWV" || res FAIL "phar VERSION matches EXPECT_VERSION" "exp ${EXPECT_VERSION} got $NEWV"
[ "$OLDV" = "$OLD_VERSION" ] && res PASS "old phar VERSION = OLD_VERSION" "$OLDV" || res FAIL "old phar VERSION = OLD_VERSION" "exp $OLD_VERSION got $OLDV"
[ -n "${EXPECT_CHANGED_IMAGES:-}" ] && eq "images changed in img-versions.json = EXPECT_CHANGED_IMAGES" "$EXPECT_CHANGED_IMAGES" "$(tr '\n' ' ' < "$OUT/img-changed.txt")"
[ -n "${EXPECT_NEW_MIGRATIONS:-}" ] && eq "migrations new in the phar = EXPECT_NEW_MIGRATIONS" "$EXPECT_NEW_MIGRATIONS" "$(tr '\n' ' ' < "$OUT/new-migrations.txt")"
case $NEWV in *nightly*) echo "INFO | record: $NEWV is a -nightly- build (PR CI?): not the lock build the tag ships, and it migrates on every command" | tee -a "$RES" ;; esac
{
  echo "NEW_VERSION=$NEWV"; echo "OLD_VERSION=$OLDV"
  echo "NEW_MD5=$(md5sum "$N" | cut -d' ' -f1)"; echo "OLD_MD5=$(md5sum "$O" | cut -d' ' -f1)"
  echo "IMG_JSON=$OUT/img-versions.json"; echo "IMG_OLD_JSON=$OUT/img-old.json"; echo "NEW_MIGS=$OUT/new-migrations.txt"
} >> "$GITHUB_ENV"
exit 0
