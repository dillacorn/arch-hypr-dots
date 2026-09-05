from hashlib import sha256
from pathlib import Path


def replace_once(path: str, old: str, new: str, label: str) -> None:
    p = Path(path)
    text = p.read_text(encoding="utf-8")
    count = text.count(old)
    if count != 1:
        raise SystemExit(f"{label}: expected one match in {path}, found {count}")
    p.write_text(text.replace(old, new, 1), encoding="utf-8")


workflow = ".github/workflows/validate-awtarchy.yml"
replace_once(
    workflow,
    '''          bash -n tests/test-battery-charge-limit-detection.sh\n          bash -n tests/test-battery-care-control.sh\n          bash -n tests/test-battery-care-annotated-range.sh\n''',
    '''          bash -n tests/test-battery-charge-limit-detection.sh\n          bash -n tests/test-battery-care-control.sh\n          bash -n tests/test-battery-care-compatibility.sh\n          bash -n tests/test-battery-care-detector-profiles.sh\n          bash -n tests/test-battery-care-vendor-semantics.sh\n          bash -n tests/test-battery-care-write-gating.sh\n          bash -n tests/test-battery-care-annotated-range.sh\n''',
    "permanent CI Bash syntax coverage",
)
replace_once(
    workflow,
    '''            tests/test-battery-charge-limit-detection.sh \\\n            tests/test-battery-care-annotated-range.sh \\\n''',
    '''            tests/test-battery-charge-limit-detection.sh \\\n            tests/test-battery-care-compatibility.sh \\\n            tests/test-battery-care-detector-profiles.sh \\\n            tests/test-battery-care-vendor-semantics.sh \\\n            tests/test-battery-care-write-gating.sh \\\n            tests/test-battery-care-annotated-range.sh \\\n''',
    "permanent CI ShellCheck coverage",
)
replace_once(
    workflow,
    '''          bash tests/test-battery-charge-limit-detection.sh\n          sudo bash tests/test-battery-care-control.sh\n          bash tests/test-battery-care-annotated-range.sh\n''',
    '''          bash tests/test-battery-charge-limit-detection.sh\n          sudo bash tests/test-battery-care-control.sh\n          bash tests/test-battery-care-compatibility.sh\n          bash tests/test-battery-care-detector-profiles.sh\n          bash tests/test-battery-care-vendor-semantics.sh\n          bash tests/test-battery-care-write-gating.sh\n          bash tests/test-battery-care-annotated-range.sh\n''',
    "permanent CI execution coverage",
)

manifest = Path("local/share/awtarchy/quickshell-managed-history.sha256")
manifest_text = manifest.read_text(encoding="utf-8")
entries = []
for source, installed in (
    (
        "config/hypr/scripts/quickshell_battery_care.sh",
        ".config/hypr/scripts/quickshell_battery_care.sh",
    ),
    (
        "config/quickshell/awtarchy/BatteryCareCard.qml",
        ".config/quickshell/awtarchy/BatteryCareCard.qml",
    ),
):
    digest = sha256(Path(source).read_bytes()).hexdigest()
    line = f"{digest}\t{installed}"
    if line not in manifest_text:
        entries.append(line)

if entries:
    if manifest_text and not manifest_text.endswith("\n"):
        manifest_text += "\n"
    manifest_text += "\n# 2026-09-05 TLP battery compatibility hardening current hashes.\n"
    manifest_text += "\n".join(entries) + "\n"
    manifest.write_text(manifest_text, encoding="utf-8")
