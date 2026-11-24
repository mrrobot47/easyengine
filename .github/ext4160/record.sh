#!/bin/bash
# Reads VERSION, img-versions.json and the migration lists of the candidate and the old phar, checks them against the knobs and exports them to $GITHUB_ENV.
# Usage: record.sh <new.phar> <old.phar>. Env: OUT, RES, OLD_VERSION, EXPECT_VERSION (regex), JSON_CHANGED / JSON_ADDED (expected from the git tags' img-versions.json, an independent source).
# Exports EXPECT_NEW_MIGRATIONS (derived: migrations in the new phar and not in the old one).
N=$(realpath "$1"); O=$(realpath "$2"); export LC_ALL=C
r() { php -r 'echo file_get_contents("phar://" . $argv[1] . "/" . $argv[2]);' "$1" "$2"; }
migs() { php -r '$b = "phar://" . $argv[1] . "/"; foreach (new RecursiveIteratorIterator(new Phar($argv[1])) as $f) { $n = substr($f->getPathname(), strlen($b)); if (preg_match("~^(?:vendor/easyengine/[^/]+/)?migrations/(db|container)/([0-9]+_[^/]+\.php)$~", $n, $m)) echo $m[1], "/", $m[2], "\n"; }' "$1" | sort; }
res() { echo "$1 | record: $2 | $3" | tee -a "$RES"; }
eq() { [ "$(echo "$2" | tr ' ' '\n' | sed '/^$/d' | sort)" = "$(echo "$3" | tr ' ' '\n' | sed '/^$/d' | sort)" ] && res PASS "$1" "[$3]" || res FAIL "$1" "exp [$2] got [$3]"; }

NEWV=$(r "$N" VERSION | tr -d '[:space:]'); OLDV=$(r "$O" VERSION | tr -d '[:space:]')
echo "$NEWV" > "$OUT/new-version.txt"; echo "$OLDV" > "$OUT/old-version.txt"
r "$N" img-versions.json > "$OUT/img-versions.json"; r "$O" img-versions.json > "$OUT/img-old.json"
migs "$N" > "$OUT/migrations-new-phar.txt"; migs "$O" > "$OUT/migrations-old-phar.txt"
comm -13 "$OUT/migrations-old-phar.txt" "$OUT/migrations-new-phar.txt" > "$OUT/new-migrations.txt"
jq -r --slurpfile o "$OUT/img-old.json" 'to_entries[] | .key as $k | select(($o[0] | has($k)) and .value != $o[0][$k]) | $k' "$OUT/img-versions.json" | sort > "$OUT/img-changed.txt"
jq -r --slurpfile o "$OUT/img-old.json" 'to_entries[] | .key as $k | select($o[0] | has($k) | not) | $k' "$OUT/img-versions.json" | sort > "$OUT/img-added.txt"
jq -r --slurpfile n "$OUT/img-versions.json" 'to_entries[] | .key as $k | select($n[0] | has($k) | not) | $k' "$OUT/img-old.json" | sort > "$OUT/img-removed.txt"
echo "new $NEWV, old $OLDV; migrations $(wc -l < "$OUT/migrations-old-phar.txt") -> $(wc -l < "$OUT/migrations-new-phar.txt")"

[[ $NEWV =~ ^(${EXPECT_VERSION:-.*})$ ]] && res PASS "candidate VERSION matches EXPECT_VERSION" "$NEWV" || res FAIL "candidate VERSION matches EXPECT_VERSION" "exp ${EXPECT_VERSION} got $NEWV"
[ "$OLDV" = "$OLD_VERSION" ] && res PASS "old phar VERSION = OLD_VERSION" "$OLDV" || res FAIL "old phar VERSION = OLD_VERSION" "exp $OLD_VERSION got $OLDV"
eq "images whose tag changed old -> new phar img-versions.json = JSON_CHANGED (git tags)" "${JSON_CHANGED:-}" "$(tr '\n' ' ' < "$OUT/img-changed.txt")"
eq "images added old -> new phar img-versions.json = JSON_ADDED (git tags)" "${JSON_ADDED:-}" "$(tr '\n' ' ' < "$OUT/img-added.txt")"
eq "images removed from img-versions.json = none" "" "$(tr '\n' ' ' < "$OUT/img-removed.txt")"
echo "INFO | record: migrations new in the candidate ($(wc -l < "$OUT/new-migrations.txt")): $(tr '\n' ' ' < "$OUT/new-migrations.txt")" | tee -a "$RES"
eq "migrations removed from the candidate = none" "" "$(comm -23 "$OUT/migrations-old-phar.txt" "$OUT/migrations-new-phar.txt" | tr '\n' ' ')"
case $NEWV in *nightly*) echo "INFO | record: $NEWV is a -nightly- build: it runs the migration pipeline on every non-cli command" | tee -a "$RES" ;; esac
{
  echo "NEW_VERSION=$NEWV"; echo "OLD_VERSION=$OLDV"
  echo "IMG_JSON=$OUT/img-versions.json"; echo "IMG_OLD_JSON=$OUT/img-old.json"
  echo "EXPECT_NEW_MIGRATIONS=$(tr '\n' ' ' < "$OUT/new-migrations.txt")"
} >> "$GITHUB_ENV"
exit 0
