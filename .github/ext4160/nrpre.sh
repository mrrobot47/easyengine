#!/bin/bash
# Before the upgrade (on the old stable; on the fresh path on the release): the global New Relic daemon, and a fake 40-char key on the 8.4 site applied with site enable --force.
. "$(dirname "$0")/lib.sh"; cd /tmp; D=$OUT/nr-pre; mkdir -p $D
ND=services_global-newrelic-daemon_1
run_ee enable-daemon $D service enable newrelic-daemon; chk "nr pre: ee service enable newrelic-daemon rc" 0 "$RC"
chk "nr pre: $ND running" running "$(docker inspect -f '{{.State.Status}}' $ND 2>&1)"
info "nr pre: $ND image $(docker inspect -f '{{.Config.Image}}' $ND 2>&1)"
info "nr pre: $K84 .env: $(setkey $K84 $NRKEY)"
run_ee enable-key $D site enable $K84 --force; chk "nr pre: ee site enable $K84 --force rc" 0 "$RC"
chk "nr pre: $K84 / HTTP" 200 "$(hwait $K84)"
eqs "nr pre: $K84 NEWRELIC_LICENSE_KEY in the php container" "$NRKEY" "$(docker exec $(phpc $K84) printenv NEWRELIC_LICENSE_KEY 2>/dev/null)"
info "nr pre: $K84 newrelic modules on the old image: $(nr_mods $K84)"
info "nr pre: $K84 image $(docker inspect -f '{{.Config.Image}}' $(phpc $K84) 2>&1), phpversion('newrelic') $(docker exec $(phpc $K84) php -r 'echo phpversion("newrelic");' 2>&1 | tail -1)"
info "nr pre: $K84 agent: $(nr_connect $K84 $D)"
done_mark nr-pre
exit 0
