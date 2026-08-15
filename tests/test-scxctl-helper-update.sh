#!/usr/bin/env bash
set -Eeuo pipefail

runtime="local/share/awtarchy/awtarchy-runtime.sh"
helper="local/libexec/awtarchy/scxctl-helper"

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  exit 1
}

require_literal() {
  local needle="$1"
  grep -Fq -- "$needle" "$runtime" || fail "missing updater helper repair contract: $needle"
}

require_literal 'repair_scxctl_update_helper()'
require_literal 'local destination="/usr/local/libexec/awtarchy/scxctl-helper"'
require_literal "local source=\"\${repo_dir}/local/libexec/awtarchy/scxctl-helper\""
require_literal "sudo /usr/bin/install -d -m 0755 -o root -g root \"\$destination_dir\""
require_literal "sudo /usr/bin/install -m 0755 -o root -g root \"\$source\" \"\$temporary\""
require_literal "sudo /usr/bin/bash -n \"\$temporary\""
require_literal "sudo /usr/bin/mv -Tf -- \"\$temporary\" \"\$destination\""
require_literal "repair_scxctl_update_helper \"\$repo_dir\""
require_literal "source_hash=\"\$(/usr/bin/sha256sum \"\$source\" | /usr/bin/awk '{print \$1}')\""
require_literal "installed_hash=\"\$(sudo /usr/bin/sha256sum \"\$temporary\" | /usr/bin/awk '{print \$1}')\""

# scxctl 1.1+ parses scheduler options such as --performance and -f as
# scxctl options unless the scheduler argument string is attached to --args.
# The trusted helper accepts the UI's structured five-field form, validates it,
# then must normalize only the final scxctl argv to --args=VALUE.
tmpd="$(mktemp -d)"
trap 'rm -rf -- "$tmpd"' EXIT
fixture="${tmpd}/scxctl-helper"
fake_scxctl="${tmpd}/scxctl"
log="${tmpd}/argv.log"

sed "s|^SCXCTL=.*|SCXCTL=\"${fake_scxctl}\"|" "$helper" >"$fixture"
cat >"$fake_scxctl" <<'EOF_SCXCTL'
#!/usr/bin/env bash
set -Eeuo pipefail
printf '%s\n' "$@" >"${AWTARCHY_TEST_SCXCTL_LOG:?}"
EOF_SCXCTL
chmod 0755 "$fixture" "$fake_scxctl"

AWTARCHY_TEST_SCXCTL_LOG="$log" "$fixture" \
  switch --sched lavd --args --performance
printf '%s\n' switch --sched lavd '--args=--performance' >"${tmpd}/expected-lavd.log"
cmp -s "$log" "${tmpd}/expected-lavd.log" \
  || fail 'trusted helper did not attach LAVD scheduler arguments to --args'

AWTARCHY_TEST_SCXCTL_LOG="$log" "$fixture" \
  start --sched tickless --args '-f,5000,-s,5000'
printf '%s\n' start --sched tickless '--args=-f,5000,-s,5000' >"${tmpd}/expected-tickless.log"
cmp -s "$log" "${tmpd}/expected-tickless.log" \
  || fail 'trusted helper did not attach Tickless scheduler arguments to --args'

printf 'PASS: normal updater provisions the trusted scxctl helper and preserves scheduler arguments.\n'
