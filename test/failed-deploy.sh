#!/bin/bash
# Regression test: a failed deploy must leave the live environment intact,
# and the next successful deploy must seed from it and then remove it.
#
# Usage: test/failed-deploy.sh <container>
#
# Expects the container to have /tmp/puppet.git with a production branch
# and an environments-staging directory, as set up by the smoke tests.

set -e

CONTAINER="${1:?usage: $0 <container>}"
LIVE=/etc/puppetlabs/code/environments/production
REMOTE=file:///tmp/puppet.git

fail () {
    echo "FAIL: $*"
    exit 1
}

# Run a deploy the way the webhook does: as abc, from /config
deploy () {
    docker exec -u abc -w /config "${CONTAINER}" \
        /usr/local/lib/push-to-g10k refs/heads/production "${1:-${REMOTE}}" push 2>&1
}

# Replace the production branch's Puppetfile ("good" or "broken")
set_puppetfile () {
    docker exec -e MODE="${1}" "${CONTAINER}" bash -ec '
        rm -rf /tmp/puppet-edit
        git clone -q -b production /tmp/puppet.git /tmp/puppet-edit
        cd /tmp/puppet-edit
        if [ "${MODE}" = broken ]; then
            echo "mod '\''broken'\'', :git => '\''http://127.0.0.1:9/broken.git'\''" >> Puppetfile
            git commit -qam "Add unreachable module"
        else
            git revert --no-edit HEAD > /dev/null
        fi
        git push -q origin production
        rm -rf /tmp/puppet-edit
    '
}

live_target () {
    docker exec "${CONTAINER}" readlink -f "${LIVE}"
}

has_files () {
    docker exec "${CONTAINER}" sh -c "[ -n \"\$(ls -A '${1}' 2>/dev/null)\" ]"
}

# Let any webhook-triggered deploy finish first
for i in $(seq 1 60); do
    docker exec "${CONTAINER}" pgrep -f push-to-g10k > /dev/null || break
    sleep 2
done

echo "==> Deploying production successfully..."
deploy
first=$(live_target)
[ -n "${first}" ] || fail "live symlink missing after deploy"
has_files "${first}" || fail "live environment ${first} is empty"
echo "PASS: live environment is ${first}"

sleep 1
echo "==> Deploying production with an unreachable module..."
set_puppetfile broken
out=$(deploy) || true
echo "${out}"
echo "${out}" | grep -q "g10k failed for branch production" \
    || fail "deploy with unreachable module did not report failure"
[ "$(live_target)" = "${first}" ] \
    || fail "live symlink changed after failed deploy: $(live_target)"
has_files "${first}" \
    || fail "live environment ${first} missing or empty after failed deploy"
echo "PASS: failed deploy left ${first} intact"

sleep 1
echo "==> Deploying production successfully again..."
set_puppetfile good
out=$(deploy)
echo "${out}"
echo "${out}" | grep "^Seeding " | grep -qF " from ${first}" \
    || fail "second deploy was not seeded from ${first}"
second=$(live_target)
[ "${second}" != "${first}" ] || fail "live symlink was not updated"
has_files "${second}" || fail "new live environment ${second} is empty"
docker exec "${CONTAINER}" test ! -e "${first}" \
    || fail "old environment ${first} was not removed"
echo "PASS: redeploy seeded from ${first} and removed it"

sleep 1
echo "==> Deploying production from an unreachable control repo..."
out=$(deploy file:///tmp/missing.git) || true
echo "${out}"
echo "${out}" | grep -q "g10k failed for branch production" \
    || fail "deploy from unreachable control repo did not report failure"
[ "$(live_target)" = "${second}" ] \
    || fail "live symlink changed after failed deploy: $(live_target)"
has_files "${second}" \
    || fail "live environment ${second} missing or empty after failed deploy"
echo "PASS: unreachable control repo left ${second} intact"
