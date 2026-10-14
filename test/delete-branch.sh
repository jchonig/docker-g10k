#!/bin/bash
# Test that a branch delete event removes the live symlink and every
# versioned staging directory for that branch, and leaves other branches.
#
# Usage: test/delete-branch.sh <container>
#
# Expects the container to have /tmp/puppet.git with a production branch
# and an environments-staging directory, as set up by the smoke tests.

set -e

CONTAINER="${1:?usage: $0 <container>}"
CODE=/etc/puppetlabs/code
REMOTE=file:///tmp/puppet.git
ZERO_SHA=0000000000000000000000000000000000000000

fail () {
    echo "FAIL: $*"
    exit 1
}

# Run push-to-g10k the way the webhook does: as abc, from /config
hook () {
    docker exec -u abc -w /config "${CONTAINER}" \
        /usr/local/lib/push-to-g10k "refs/heads/${1}" "${REMOTE}" "${2}" 2>&1
}

staging_dirs () {
    docker exec "${CONTAINER}" sh -c "ls -d ${CODE}/environments-staging/${1}.* 2>/dev/null" || true
}

echo "==> Creating branch delete_me..."
docker exec "${CONTAINER}" git --git-dir=/tmp/puppet.git branch delete_me production

echo "==> Deploying delete_me..."
hook delete_me push
docker exec "${CONTAINER}" test -L "${CODE}/environments/delete_me" \
    || fail "delete_me was not deployed"
[ -n "$(staging_dirs delete_me)" ] || fail "delete_me has no staging directory"

# Simulate a leftover staging directory from an interrupted deploy
docker exec -u abc "${CONTAINER}" mkdir "${CODE}/environments-staging/delete_me.leftover"

production=$(docker exec "${CONTAINER}" readlink -f "${CODE}/environments/production")

echo "==> Sending delete event for delete_me..."
hook delete_me "${ZERO_SHA}"
docker exec "${CONTAINER}" test ! -e "${CODE}/environments/delete_me" \
    && docker exec "${CONTAINER}" test ! -L "${CODE}/environments/delete_me" \
    || fail "live symlink for delete_me still exists"
[ -z "$(staging_dirs delete_me)" ] \
    || fail "staging directories left behind: $(staging_dirs delete_me)"
[ "$(docker exec "${CONTAINER}" readlink -f "${CODE}/environments/production")" = "${production}" ] \
    && docker exec "${CONTAINER}" test -d "${production}" \
    || fail "deleting delete_me disturbed production"
echo "PASS: delete removed delete_me and its staging directories"
