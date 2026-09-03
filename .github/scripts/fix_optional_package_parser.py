#!/usr/bin/env python3
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
RECONCILER = ROOT / "local/share/awtarchy/awtarchy-package-reconcile.sh"


def replace_once(old: str, new: str) -> None:
    text = RECONCILER.read_text()
    count = text.count(old)
    if count != 1:
        raise SystemExit(f"{RECONCILER}: expected one match, found {count}")
    RECONCILER.write_text(text.replace(old, new, 1))


replace_once(
    '''runtime_array_lines() {
  local name="$1"
  awk -v name="$name" '
    $0 ~ "^declare -a " name "=\\\\(" { inside=1; next }
    inside && /^[[:space:]]*\\)[[:space:]]*$/ { exit }
    inside {
      line=$0
      sub(/^[[:space:]]+/, "", line)
      sub(/[[:space:]]+$/, "", line)
      if (line != "" && line !~ /^#/) print line
    }
  ' "$RUNTIME"
}
''',
    '''runtime_array_lines() {
  local name="$1"
  awk -v name="$name" '
    $0 ~ "^declare -a " name "=\\\\(" {
      line=$0
      sub("^.*=\\\\(", "", line)
      if (line ~ /\\)[[:space:]]*$/) {
        sub(/\\)[[:space:]]*$/, "", line)
        sub(/^[[:space:]]+/, "", line)
        sub(/[[:space:]]+$/, "", line)
        if (line != "" && line !~ /^#/) print line
        exit
      }
      inside=1
      next
    }
    inside && /^[[:space:]]*\\)[[:space:]]*$/ { exit }
    inside {
      line=$0
      sub(/^[[:space:]]+/, "", line)
      sub(/[[:space:]]+$/, "", line)
      if (line != "" && line !~ /^#/) print line
    }
  ' "$RUNTIME"
}
''',
)

replace_once(
    '''  case "$pkg" in
    zathura-pdf-mupdf)
      package_installed zathura-pdf-poppler
      ;;
    zathura-pdf-poppler)
      package_installed zathura-pdf-mupdf
      ;;
    *)
      return 1
      ;;
  esac
''',
    '''  case "$pkg" in
    zathura-pdf-mupdf)
      package_installed zathura-pdf-poppler
      ;;
    zathura-pdf-poppler)
      package_installed zathura-pdf-mupdf
      ;;
    gamescope|gamescope-git)
      package_installed gamescope || package_installed gamescope-git
      ;;
    *)
      return 1
      ;;
  esac
''',
)

print("Fixed runtime catalog parsing and native package equivalents.")
