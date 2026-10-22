#!/bin/bash
# Test that a successful deploy prunes environments, and leftover staging
# directories, whose branch no longer exists on the remote.
#
# Usage: test/prune.sh <container>
#
# Expects the container to have /tmp/puppet.git with a production branch
# and an environments-staging directory, as set up by the smoke tests.

set -e

CONTAINER="${1:?usage: $0 <container>}"
CODE=/etc/puppetlabs/code
STAGING="${CODE}/environments-staging"
REMOTE=file:///tmp/puppet.git

fail () {
    echo "FAIL: $*"
    exit 1
}

# Set PRUNE_ENVIRONMENTS in the container environment, which with-contenv
# loads in place of docker exec -e values (like setting it in compose)
set_prune () {
    docker exec "${CONTAINER}" sh -c \
        "printf '%s' '${1}' > /run/s6/container_environment/PRUNE_ENVIRONMENTS"
}

# Deploy a branch the way the webhook does: as abc, from /config
deploy () {
    set_prune "${2}"
    docker exec -u abc -w /config "${CONTAINER}" \
        /usr/local/lib/push-to-g10k "refs/heads/${1}" "${REMOTE}" push 2>&1
}

git_remote () {
    docker exec "${CONTAINER}" git --git-dir=/tmp/puppet.git "$@"
}

exists () {
    docker exec "${CONTAINER}" sh -c "[ -e '${1}' ] || [ -L '${1}' ]"
}

# Environment exists: live symlink and its target are present
has_env () {
    docker exec "${CONTAINER}" test -d "${CODE}/environments/${1}/"
}

# Nothing is left of an environment, live or staging
gone () {
    ! exists "${CODE}/environments/${1}" \
        && [ -z "$(docker exec "${CONTAINER}" sh -c "ls -d ${STAGING}/${1} ${STAGING}/${1}.* 2>/dev/null" || true)" ]
}

# Record notifications: with no .apprise.yml, push-to-g10k runs ./notify
docker exec -u abc "${CONTAINER}" sh -c '
    printf "#!/bin/sh\necho \"\$@\" >> /tmp/notify.log\n" > /config/notify
    chmod +x /config/notify
'
cleanup () {
    docker exec "${CONTAINER}" rm -f /config/notify /tmp/notify.log
    docker exec "${CONTAINER}" pkill -f "sleep 120" || true
    set_prune dry-run
}
trap cleanup EXIT

echo "==> Deploying production, keep-me, drop_me and locked_one..."
for b in keep-me drop_me locked_one; do
    git_remote branch "${b}" production
done
for b in production keep-me drop_me locked_one; do
    deploy "${b}" no > /dev/null
done
for e in production keep_me drop_me locked_one; do
    has_env "${e}" || fail "${e} was not deployed"
done

# A staging directory left by a failed deploy before the readlink -f fix
docker exec -u abc "${CONTAINER}" mkdir "${STAGING}/orphan.20261001000000"

echo "==> Deleting drop_me and locked_one from the remote..."
git_remote branch -D drop_me locked_one > /dev/null

echo "==> Deploying keep-me with PRUNE_ENVIRONMENTS=dry-run..."
out=$(deploy keep-me dry-run)
echo "${out}" | grep "prune" || true
for e in drop_me locked_one orphan; do
    echo "${out}" | grep -q "^Would prune environment ${e} " \
        || fail "dry run did not report ${e}"
done
echo "${out}" | grep -q "prune environment \(production\|keep_me\) " \
    && fail "dry run would prune a live branch"
has_env drop_me || fail "dry run removed drop_me"
exists "${STAGING}/orphan.20261001000000" || fail "dry run removed orphan"
echo "PASS: dry run only reported drop_me, locked_one and orphan"

echo "==> Pruning with an unreachable remote..."
set_prune yes
out=$(docker exec -u abc -w /config "${CONTAINER}" with-contenv bash -c '
    source /usr/local/lib/push-to-g10k
    REMOTE=file:///tmp/missing.git
    prune_environments keep_me
' 2>&1)
echo "${out}" | grep -q "not pruning" \
    || fail "unreachable remote did not report it was not pruning: ${out}"
has_env drop_me || fail "unreachable remote pruned drop_me"
echo "PASS: unreachable remote pruned nothing"

echo "==> Pruning while a deploy holds locked_one's lock..."
docker exec -d -u abc "${CONTAINER}" flock "${STAGING}/.locked_one.lock" sleep 120
sleep 2
docker exec "${CONTAINER}" rm -f /tmp/notify.log
out=$(deploy keep-me yes)
echo "${out}" | grep -i "prune" || true
gone drop_me || fail "drop_me was not pruned"
gone orphan || fail "orphan staging directory was not pruned"
has_env locked_one || fail "locked_one was pruned while locked"
echo "${out}" | grep -q "locked_one is locked by a deploy" \
    || fail "locked_one was not reported as locked"
for e in production keep_me; do
    has_env "${e}" || fail "${e} was pruned"
done
notes=$(docker exec "${CONTAINER}" cat /tmp/notify.log)
echo "${notes}"
# One for the keep_me deploy, one listing everything pruned
[ "$(echo "${notes}" | wc -l | tr -d ' ')" = 2 ] \
    && echo "${notes}" | grep -q "^0 drop_me,orphan " \
    || fail "expected one notification listing drop_me,orphan"
echo "PASS: pruned drop_me and orphan, kept locked_one, sent one notification"

echo "==> Pruning after the lock is released..."
docker exec "${CONTAINER}" pkill -f "sleep 120"
sleep 1
deploy keep-me yes | grep -i "prune" || true
gone locked_one || fail "locked_one was not pruned after its lock was released"
has_env keep_me || fail "keep_me was pruned"
echo "PASS: pruned locked_one once unlocked"

echo "==> Pruning from cron, with no deploy, after a branch is deleted..."
[ "$(docker exec "${CONTAINER}" cat "${STAGING}/.remote")" = "${REMOTE}" ] \
    || fail "the last deploy did not record its remote"
docker exec "${CONTAINER}" run-parts --test /etc/periodic/hourly \
    | grep -q '/prune-environments$' \
    || fail "run-parts would not run prune-environments"
git_remote branch cron_drop production
deploy cron_drop no > /dev/null
has_env cron_drop || fail "cron_drop was not deployed"
git_remote branch -D cron_drop > /dev/null
set_prune yes
LOG_OFFSET=$(docker logs "${CONTAINER}" 2>&1 | wc -l | tr -d ' ')
docker exec "${CONTAINER}" /etc/periodic/hourly/prune-environments
out=$(docker logs "${CONTAINER}" 2>&1 | tail -n +$((LOG_OFFSET + 1)))
echo "${out}"
gone cron_drop || fail "cron did not prune cron_drop"
for e in production keep_me; do
    has_env "${e}" || fail "cron pruned ${e}"
done
echo "${out}" | grep -q "^Pruned environment cron_drop$" \
    || fail "cron's prune did not reach the container log"
echo "PASS: cron pruned cron_drop and logged it"
