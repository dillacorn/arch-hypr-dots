from pathlib import Path
import re

runtime = Path("local/share/awtarchy/awtarchy-runtime.sh")
text = runtime.read_text(encoding="utf-8")
match = re.search(r'("Utilities:)([^"]+)(")', text)
if not match:
    raise SystemExit("Utilities package group missing from runtime")
packages = match.group(2).split()
if "upower" not in packages:
    insert_at = packages.index("qt6ct") + 1 if "qt6ct" in packages else 0
    packages.insert(insert_at, "upower")
    text = text[:match.start()] + match.group(1) + " ".join(packages) + match.group(3) + text[match.end():]
runtime.write_text(text, encoding="utf-8")

installer = Path("awtarchy-install.sh")
text = installer.read_text(encoding="utf-8")
marker = "# Quickshell battery integration requires the UPower daemon."
if marker not in text:
    anchor = "# AUR defaults: Waybar-git and wlogout are no longer part of Awtarchy."
    if anchor not in text:
        raise SystemExit("installer package-transform anchor missing")
    block = '''# Quickshell battery integration requires the UPower daemon.
utility_match = re.search(r'("Utilities:)([^"]+)(")', text)
if not utility_match:
    raise SystemExit("ERROR: could not locate Utilities package group")
utility_packages = utility_match.group(2).split()
if "upower" not in utility_packages:
    insert_at = utility_packages.index("qt6ct") + 1 if "qt6ct" in utility_packages else 0
    utility_packages.insert(insert_at, "upower")
text = text[:utility_match.start()] + utility_match.group(1) + " ".join(utility_packages) + utility_match.group(3) + text[utility_match.end():]

'''
    text = text.replace(anchor, block + anchor, 1)
installer.write_text(text, encoding="utf-8")
