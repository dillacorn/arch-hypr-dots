#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf -- "$TMP"' EXIT

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  exit 1
}

home="${TMP}/home"
mkdir -p \
  "$home/.local/bin" \
  "$home/.local/share/awtarchy" \
  "$home/.local/share/awtarchy-quickshell" \
  "$home/.local/state/awtarchy-quickshell"

cp "$ROOT/local/bin/awtarchy" "$home/.local/bin/awtarchy"
chmod 0755 "$home/.local/bin/awtarchy"

cat >"$home/.local/share/awtarchy/awtarchy-runtime.sh" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
chmod 0755 "$home/.local/share/awtarchy/awtarchy-runtime.sh"

cat >"$home/.local/bin/awtarchy-quickshell" <<'EOF'
#!/usr/bin/env bash
# Temporary branch-only maintenance command for the Quickshell migration.
exit 0
EOF
chmod 0755 "$home/.local/bin/awtarchy-quickshell"

printf '%s\n' legacy-runtime >"$home/.local/share/awtarchy-quickshell/marker"
printf '%s\n' 'tag=quickshell-conversion-testing' >"$home/.local/state/awtarchy-quickshell/command-version"
printf '%s\n' '{"disableNumlockAtSessionStart":true}' >"$home/.local/state/awtarchy-quickshell/quick-settings-tweaks.json"

first_output="$(
  HOME="$home" USER="$(id -un)" AWTARCHY_SKIP_UPDATE_CHECK=1 \
    "$home/.local/bin/awtarchy" clean-backups
)"

grep -Fq 'Removed obsolete awtarchy-quickshell testing command state.' <<<"$first_output" \
  || fail 'first cleanup did not report removal'
[[ ! -e "$home/.local/bin/awtarchy-quickshell" ]] \
  || fail 'retired launcher was not removed'
[[ ! -e "$home/.local/share/awtarchy-quickshell" ]] \
  || fail 'retired runtime data was not removed'
[[ ! -e "$home/.local/state/awtarchy-quickshell/command-version" ]] \
  || fail 'retired command-version state was not removed'
[[ -f "$home/.local/state/awtarchy-quickshell/quick-settings-tweaks.json" ]] \
  || fail 'production Quickshell state was incorrectly removed'

second_output="$(
  HOME="$home" USER="$(id -un)" AWTARCHY_SKIP_UPDATE_CHECK=1 \
    "$home/.local/bin/awtarchy" clean-backups
)"

! grep -Fq 'Removed obsolete awtarchy-quickshell testing command state.' <<<"$second_output" \
  || fail 'cleanup reported removal again after obsolete state was already gone'
[[ -f "$home/.local/state/awtarchy-quickshell/quick-settings-tweaks.json" ]] \
  || fail 'production Quickshell state disappeared on the second run'

printf 'Awtarchy legacy cleanup test passed.\n'
