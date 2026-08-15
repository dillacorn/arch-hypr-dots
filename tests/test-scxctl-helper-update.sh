#!/usr/bin/env bash
set -Eeuo pipefail

runtime="local/share/awtarchy/awtarchy-runtime.sh"

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

printf 'PASS: normal updater provisions the trusted scxctl helper.\n'
