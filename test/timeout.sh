#!/bin/bash
# Test that deploys pass G10K_TIMEOUT to g10k as :timeout:, reject bad
# values, and that g10k kills a git command that runs past it.
#
# Usage: test/timeout.sh <container>
#
# Expects the container to have /tmp/puppet.git with a production branch
# and an environments-staging directory, as set up by the smoke tests.

set -e

CONTAINER="${1:?usage: $0 <container>}"
CONTAINER_ENV=/run/s6/container_environment

fail () {
    echo "FAIL: $*"
    exit 1
}

# Set a variable in the container environment, which with-contenv loads
# in place of docker exec -e values (like setting it in compose)
set_env () {
    docker exec "${CONTAINER}" sh -c "printf '%s' '${2}' > ${CONTAINER_ENV}/${1}"
}

unset_env () {
    docker exec "${CONTAINER}" rm -f "${CONTAINER_ENV}/${1}"
}

# Print the config write_g10k_config generates for the given G10K_TIMEOUT
# ("unset" leaves it unset), then its exit status. The value goes in as
# an argument: with-contenv drops docker exec -e values.
config_for () {
    docker exec -u abc -w /config "${CONTAINER}" with-contenv bash -c '
        source /usr/local/lib/push-to-g10k
        if [ "${1}" = unset ]; then unset G10K_TIMEOUT; else G10K_TIMEOUT="${1}"; fi
        write_g10k_config && cat "${r10kconf}"
        echo "rc=$?"
    ' config_for "${1}" 2>&1
}

cleanup () {
    set_env G10K_TIMEOUT 60
    for v in GIT_CONFIG_COUNT GIT_CONFIG_KEY_0 GIT_CONFIG_VALUE_0; do
        unset_env "${v}"
    done
}
trap cleanup EXIT

echo "==> Checking the installed g10k version..."
want=$(docker exec "${CONTAINER}" with-contenv sh -c 'echo "${G10K_VERSION}"')
got=$(docker exec "${CONTAINER}" /usr/local/bin/g10k -version 2>&1)
echo "${got}" | grep -q "${want}" \
    || fail "g10k -version reported '${got}', expected ${want}"
echo "PASS: g10k ${want} installed"

echo "==> Writing the g10k config with the image default..."
out=$(docker exec -u abc -w /config "${CONTAINER}" with-contenv bash -c '
    source /usr/local/lib/push-to-g10k
    write_g10k_config && cat "${r10kconf}"
' 2>&1)
echo "${out}" | grep -qx ":timeout: 60" \
    || fail "default config has no ':timeout: 60': ${out}"
echo "PASS: default timeout is 60"

for v in unset ""; do
    echo "==> Writing the g10k config with G10K_TIMEOUT '${v}'..."
    out=$(config_for "${v}")
    echo "${out}" | grep -qx ":timeout: 60" \
        || fail "G10K_TIMEOUT '${v}' did not fall back to 60: ${out}"
    echo "PASS: G10K_TIMEOUT '${v}' falls back to 60"
done

echo "==> Writing the g10k config with G10K_TIMEOUT=120..."
out=$(config_for 120)
echo "${out}" | grep -qx ":timeout: 120" \
    || fail "G10K_TIMEOUT=120 not written: ${out}"
echo "PASS: G10K_TIMEOUT=120 written"

echo "==> Writing the g10k config with G10K_TIMEOUT=090..."
out=$(config_for 090)
echo "${out}" | grep -qx ":timeout: 90" \
    || fail "G10K_TIMEOUT=090 not written as 90: ${out}"
echo "PASS: G10K_TIMEOUT=090 written as 90"

for bad in 0 00 abc 10s -5; do
    echo "==> Rejecting G10K_TIMEOUT='${bad}'..."
    out=$(config_for "${bad}")
    echo "${out}" | grep -q "G10K_TIMEOUT must be a positive number" \
        && echo "${out}" | grep -qx "rc=1" \
        || fail "G10K_TIMEOUT='${bad}' was not rejected: ${out}"
    echo "PASS: G10K_TIMEOUT='${bad}' rejected"
done

echo "==> Deploying with a bad G10K_TIMEOUT leaves staging alone..."
set_env G10K_TIMEOUT abc
out=$(docker exec -u abc -w /config "${CONTAINER}" \
    /usr/local/lib/push-to-g10k refs/heads/bad_timeout file:///tmp/puppet.git push 2>&1) || true
echo "${out}" | grep -q "G10K_TIMEOUT must be a positive number" \
    || fail "deploy did not report the bad timeout: ${out}"
staged=$(docker exec "${CONTAINER}" sh -c \
    'ls -d /etc/puppetlabs/code/environments-staging/bad_timeout* 2>/dev/null' || true)
[ -z "${staged}" ] || fail "deploy with a bad timeout left ${staged}"
echo "PASS: bad timeout aborted the deploy before staging"

# A remote whose git transport hangs for 60s; g10k must kill it at the
# 3s timeout and fail the deploy. g10k splits git command lines on
# spaces, so the ext:: remote is a script with no arguments.
echo "==> Deploying from a hanging remote with G10K_TIMEOUT=3..."
docker exec "${CONTAINER}" sh -c \
    'printf "#!/bin/sh\nexec sleep 60\n" > /tmp/hang && chmod 755 /tmp/hang'
set_env G10K_TIMEOUT 3
set_env GIT_CONFIG_COUNT 1
set_env GIT_CONFIG_KEY_0 protocol.ext.allow
set_env GIT_CONFIG_VALUE_0 always
start=$(date +%s)
out=$(docker exec -u abc -w /config "${CONTAINER}" \
    /usr/local/lib/push-to-g10k refs/heads/slow ext::/tmp/hang push 2>&1) || true
elapsed=$(( $(date +%s) - start ))
echo "${out}" | tail -5
echo "${out}" | grep -q "g10k failed for branch slow" \
    || fail "hanging remote did not fail the deploy"
echo "${out}" | grep -q "signal: killed" \
    || fail "g10k did not kill the hanging git command"
# At least the timeout, so the deploy didn't fail for some other reason
(( elapsed >= 3 )) || fail "deploy failed after ${elapsed}s, before the 3s timeout"
(( elapsed < 30 )) || fail "deploy took ${elapsed}s; the 3s timeout was not enforced"
echo "PASS: hanging remote killed after ${elapsed}s"
