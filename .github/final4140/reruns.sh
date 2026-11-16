#!/bin/bash
# Re-runs after the upgrade: plain commands, then two nightly-style runs (options.version reset, so the whole migration pipeline runs again). Usage: reruns.sh <dir> <label>
. "$(dirname "$0")/lib.sh"; D=$1; L=$2; mkdir -p $D; cd /tmp
bash $F/state.sh $D/before; : > $D/ee.log.part; : > $D/cmds.txt
run() { local mk=$(eelog_mark) s=$(date +%s.%N); ee "$@" > /dev/null 2> $D/err.txt; local rc=$?
  echo "ee $* rc=$rc $(awk "BEGIN{printf \"%.1f\", $(date +%s.%N) - $s}")s stderr=$(head -c 150 $D/err.txt | tr '\n' ' ')" >> $D/cmds.txt
  eelog_since "$mk" >> $D/ee.log.part; return $rc; }
bad=0
for c in "cli info" "site list" "site info f4-ms.test" "auth list f4-ms.test" "cli info"; do run $c || bad=1; done
for i in 1 2; do db "update options set value='${NEW_VERSION}-nightly-rerun$i' where key='version'"; run cli info || bad=1
  chk "$L: nightly-style run $i: version back to $NEW_VERSION" "$NEW_VERSION" "$(db "select value from options where key='version'")"; done
bash $F/state.sh $D/after; cat $D/cmds.txt
chk "$L: all re-runs exit 0" 0 $bad
# A -nightly- phar (e.g. a PR-CI build) runs the pipeline on every command (Runner::maybe_trigger_migration), so the 5 plain runs count too.
case $NEW_VERSION in *nightly*) np=7 ;; *) np=2 ;; esac
chk "$L: migration pipeline ran in the nightly-style runs" $np "$(grep -c 'Executing ee-docker-image-migrations' $D/ee.log.part)"
for f in containers.txt htpasswd.md5 vhostd.md5 compose.md5 migrations.txt dotbackup.txt; do
  if [ $f = containers.txt ]; then a=$(cut -f1-3 $D/before/$f | grep -v f4-event); b=$(cut -f1-3 $D/after/$f | grep -v f4-event); else a=$(cat $D/before/$f); b=$(cat $D/after/$f); fi
  [ "$a" = "$b" ] && chk "$L: $f unchanged" same same || chk "$L: $f unchanged" same DIFF; done
chk "$L: options unchanged (except version)" same "$(diff <(grep -v '^version|' $D/before/options.txt) <(grep -v '^version|' $D/after/options.txt) >/dev/null && echo same || echo DIFF)"
chk "$L: 0 Migrating/stage/promote/reload/recreate lines" 0 "$(grep -cE 'Migrating:|Staged the wildcard|Promoted the staged|Executing reload-(site|support)-nginx|Executing (upgrade|enable-support-containers)-' $D/ee.log.part)"
info "$L: pulls in the re-runs: $(grep -oE 'docker pull [^ ]+' $D/ee.log.part | sort | uniq -c | tr '\n' ' ')"
