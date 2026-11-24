#!/bin/bash
# Local: download a run's artifacts and print each leg's counts and FAIL lines. Usage: local-fetch.sh <run-id> <label>
R=$1; D=/root/workspace/behat/ci/runs/ext-4160/$2-$R; mkdir -p $D
gh run download $R -R mrrobot47/easyengine -D $D > /dev/null 2>&1
for r in $D/*/results.txt; do l=$(basename $(dirname $r)); echo "== $l: $(grep -c '^PASS' $r) PASS $(grep -c '^FAIL' $r) FAIL $(grep -c '^KNOWN' $r) KNOWN"; grep '^FAIL' $r | cut -c1-400 | head -${MAXF:-25}; done
