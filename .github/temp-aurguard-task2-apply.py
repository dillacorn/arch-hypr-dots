from pathlib import Path

path = Path("bashrc")
text = path.read_text(encoding="utf-8")

marker = "_aur_guard_validate_skipped_integrity() {\n"
if text.count(marker) != 1:
    raise SystemExit(f"expected one skipped-integrity function, found {text.count(marker)}")
if "_aur_guard_verify_signed_metadata_chain()" in text:
    raise SystemExit("signed metadata chain helper already exists")

helper = r'''_aur_guard_verify_signed_metadata_chain() {
  local pkgbase="$1"
  local srcinfo="$2"
  local pkgdir="$3"
  local parsed record local_name proof
  local separator=$'\x1f'

  _AUR_GUARD_CHAIN_VERIFIED_PKGBASE=''
  _AUR_GUARD_CHAIN_VERIFIED_NAMES=''

  [[ -f "$pkgdir/PKGBUILD" && ! -L "$pkgdir/PKGBUILD" ]] || {
    _aur_guard_fail "$pkgbase cannot prove a signed metadata chain without a regular PKGBUILD"
    return 1
  }
  [[ -f "$srcinfo" && ! -L "$srcinfo" ]] || {
    _aur_guard_fail "$pkgbase cannot prove a signed metadata chain without verified .SRCINFO"
    return 1
  }

  if ! parsed=$(python3 - "$srcinfo" "$pkgdir" <<'PY_CHAIN'
import hashlib
import os
import re
import sys
from pathlib import Path
from urllib.parse import urlsplit

srcinfo_path = Path(sys.argv[1])
pkgdir = Path(sys.argv[2])
pkgbuild_path = pkgdir / "PKGBUILD"
separator = "\x1f"

try:
    srcinfo_text = srcinfo_path.read_text(encoding="utf-8")
    pkgbuild_text = pkgbuild_path.read_text(encoding="utf-8")
except (OSError, UnicodeError) as exc:
    raise SystemExit(f"could not read signed-metadata proof inputs: {exc}")

fingerprints = []
sources = {}
source_order = {}
checksums = {}

for raw_line in srcinfo_text.splitlines():
    match = re.match(r"^\s*([^=]+?)\s*=\s*(.*)$", raw_line)
    if not match:
        continue
    key = match.group(1).strip()
    value = match.group(2).strip()
    if key == "validpgpkeys":
        fingerprints.append(value)
        continue
    source_match = re.fullmatch(r"source(_[A-Za-z0-9_]+)?", key)
    if source_match:
        suffix = source_match.group(1) or ""
        source_order.setdefault(suffix, []).append(value)
        continue
    checksum_match = re.fullmatch(r"(b2|sha256|sha384|sha512)sums(_[A-Za-z0-9_]+)?", key)
    if checksum_match:
        algorithm = checksum_match.group(1)
        suffix = checksum_match.group(2) or ""
        checksums.setdefault((suffix, algorithm), []).append(value)

full_fingerprints = [
    value for value in fingerprints
    if re.fullmatch(r"[0-9A-Fa-f]{40}|[0-9A-Fa-f]{64}", value)
]

def local_name(value):
    if "::" in value:
        name = value.split("::", 1)[0]
    else:
        clean = value.split("#", 1)[0].split("?", 1)[0].rstrip("/")
        name = clean.rsplit("/", 1)[-1]
    if not name or name in {".", ".."} or "/" in name or "\\" in name:
        raise SystemExit(f"unsafe local source name in signed metadata chain: {name!r}")
    if any(ord(ch) < 32 or ch == "\x7f" for ch in name):
        raise SystemExit("control character in signed metadata source name")
    return name

def remote_url(value):
    raw = value.split("::", 1)[-1]
    return raw.split("#", 1)[0]

def remote_path(value):
    raw = remote_url(value)
    try:
        return urlsplit(raw).path
    except ValueError:
        return ""

def is_remote(value):
    raw = remote_url(value)
    return bool(re.match(r"^[A-Za-z][A-Za-z0-9+.-]*://", raw))

def is_signature(name):
    return name.endswith((".sig", ".sign", ".asc"))

def signed_name(name):
    for suffix in (".sig", ".sign", ".asc"):
        if name.endswith(suffix):
            return name[:-len(suffix)]
    return name

def source_is_strong(suffix, index):
    for algorithm in ("b2", "sha256", "sha384", "sha512"):
        values = checksums.get((suffix, algorithm), [])
        if index < len(values) and values[index] != "SKIP":
            return True
    return False

source_records = []
by_local = {}
for suffix, values in source_order.items():
    for index, value in enumerate(values):
        name = local_name(value)
        record = {
            "suffix": suffix,
            "index": index,
            "value": value,
            "name": name,
            "path": remote_path(value),
            "remote": is_remote(value),
            "strong": source_is_strong(suffix, index),
        }
        source_records.append(record)
        by_local[name] = record

signature_pairs = []
for record in source_records:
    if not is_signature(record["name"]):
        continue
    target = signed_name(record["name"])
    if target in by_local:
        signature_pairs.append((record, by_local[target]))

# A detached-signature package that is not a metadata chain remains handled by
# the existing direct PGP relationship logic. Only metadata containing a
# strong digest section activates this additional proof path.
metadata_roots = []
for signature_record, target_record in signature_pairs:
    target_file = pkgdir / target_record["name"]
    signature_file = pkgdir / signature_record["name"]
    if not target_file.is_file() or target_file.is_symlink():
        continue
    if not signature_file.is_file() or signature_file.is_symlink():
        continue
    try:
        metadata_text = target_file.read_text(encoding="utf-8")
    except (OSError, UnicodeError):
        continue
    if re.search(r"(?m)^(SHA256|SHA512):\s*$", metadata_text):
        metadata_roots.append((target_record, metadata_text))

if not metadata_roots:
    raise SystemExit(0)

if not full_fingerprints or len(full_fingerprints) != len(fingerprints):
    raise SystemExit("signed metadata chain does not use only full pinned PGP fingerprints")

prepare_match = re.search(r"(?ms)^prepare\s*\(\)\s*\{\s*\n(.*?)^\}", pkgbuild_text)
if not prepare_match:
    raise SystemExit("signed metadata chain has no auditable prepare() verification block")
prepare_body = prepare_match.group(1)
if re.search(r"(^|[;&|()\s])(curl|wget|fetch|aria2c)(?=\s|$)", prepare_body):
    raise SystemExit("signed metadata chain obtains integrity evidence from the network during prepare()")
if re.search(r"(^|[;&|()\s])(eval|source)(?=\s|$)", prepare_body):
    raise SystemExit("signed metadata chain uses dynamic execution in its integrity proof path")
if not re.search(r"\bsha(256|512)sum\b[^\n]*(?:\s-c\b|--check\b)", prepare_body):
    raise SystemExit("signed metadata chain does not fail closed with a strong local checksum check")

def digest_file(file_path, algorithm):
    hasher = hashlib.new(algorithm)
    with file_path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            hasher.update(chunk)
    return hasher.hexdigest().lower()

def release_entries(text):
    found = {}
    algorithm = None
    for line in text.splitlines():
        section = re.fullmatch(r"(SHA256|SHA512):\s*", line)
        if section:
            algorithm = section.group(1).lower()
            continue
        if algorithm and line[:1].isspace():
            parts = line.split()
            if len(parts) >= 3 and re.fullmatch(r"[0-9A-Fa-f]+", parts[0]) and parts[1].isdigit():
                path = parts[2]
                current = found.get(path)
                rank = 2 if algorithm == "sha512" else 1
                if current is None or rank > current[0]:
                    found[path] = (rank, algorithm, parts[0].lower(), int(parts[1]))
            continue
        if line and not line[:1].isspace():
            algorithm = None
    return {key: value[1:] for key, value in found.items()}

def path_matches(source_path, metadata_path):
    source_path = source_path.rstrip("/")
    metadata_path = metadata_path.lstrip("/")
    return bool(source_path) and (source_path == "/" + metadata_path or source_path.endswith("/" + metadata_path))

def regular_local(record):
    candidate = pkgdir / record["name"]
    if not candidate.is_file() or candidate.is_symlink():
        raise SystemExit(f"signed metadata chain source is missing or not a regular file: {record['name']}")
    return candidate

def package_stanzas(text):
    stanza = {}
    for line in text.splitlines() + [""]:
        if not line.strip():
            if stanza:
                yield stanza
                stanza = {}
            continue
        if line[:1].isspace() or ":" not in line:
            continue
        key, value = line.split(":", 1)
        stanza[key.strip()] = value.strip()

needs_chain = [
    record for record in source_records
    if record["remote"] and not record["strong"] and not is_signature(record["name"])
]
for _, target in signature_pairs:
    needs_chain = [record for record in needs_chain if record["name"] != target["name"]]

verified = {}
proofs = {}
matched_any = False

for root_record, root_text in metadata_roots:
    entries = release_entries(root_text)
    root_file = regular_local(root_record)
    for metadata_path, (algorithm, expected_hash, expected_size) in entries.items():
        for record in needs_chain:
            if record["name"] in verified or not path_matches(record["path"], metadata_path):
                continue
            matched_any = True
            candidate = regular_local(record)
            actual_size = candidate.stat().st_size
            actual_hash = digest_file(candidate, algorithm)
            if actual_size != expected_size or actual_hash != expected_hash:
                raise SystemExit(f"signed metadata digest mismatch for {record['name']}")
            verified[record["name"]] = True
            proofs[record["name"]] = f"{root_record['name']} -> {record['name']} {algorithm.upper()}"

            # Debian Packages metadata can authenticate payloads by Filename +
            # Size + SHA256/SHA512. This is generic and independent of pkgbase.
            if record["name"].lower().endswith("packages"):
                try:
                    packages_text = candidate.read_text(encoding="utf-8")
                except (OSError, UnicodeError) as exc:
                    raise SystemExit(f"could not read authenticated Packages metadata: {exc}")
                for stanza in package_stanzas(packages_text):
                    filename = stanza.get("Filename", "")
                    size = stanza.get("Size", "")
                    if not filename or not size.isdigit():
                        continue
                    if stanza.get("SHA512"):
                        payload_algorithm = "sha512"
                        payload_hash = stanza["SHA512"].lower()
                    elif stanza.get("SHA256"):
                        payload_algorithm = "sha256"
                        payload_hash = stanza["SHA256"].lower()
                    else:
                        continue
                    if not re.fullmatch(r"[0-9a-f]+", payload_hash):
                        raise SystemExit("authenticated Packages metadata contains an invalid payload digest")
                    for payload_record in needs_chain:
                        if payload_record["name"] in verified or not path_matches(payload_record["path"], filename):
                            continue
                        payload_file = regular_local(payload_record)
                        if payload_file.stat().st_size != int(size) or digest_file(payload_file, payload_algorithm) != payload_hash:
                            raise SystemExit(f"authenticated Packages payload digest mismatch for {payload_record['name']}")
                        verified[payload_record["name"]] = True
                        proofs[payload_record["name"]] = (
                            f"{root_record['name']} -> {record['name']} -> "
                            f"{payload_record['name']} {payload_algorithm.upper()}"
                        )

if matched_any and not verified:
    raise SystemExit("signed metadata chain matched a remote source but authenticated no file")

for name in sorted(verified):
    safe_proof = proofs[name].replace(separator, " ").replace("\n", " ").replace("\r", " ")
    print(separator.join((name, safe_proof)))
PY_CHAIN
  ); then
    _aur_guard_fail "$pkgbase signed metadata integrity chain could not be proven"
    return 1
  fi

  if [[ -z "$parsed" ]]; then
    return 0
  fi

  _AUR_GUARD_CHAIN_VERIFIED_PKGBASE="$pkgbase"
  while IFS= read -r record; do
    [[ -n "$record" ]] || continue
    IFS="$separator" read -r local_name proof <<< "$record"
    [[ -n "$local_name" && -n "$proof" ]] || {
      _aur_guard_fail "$pkgbase signed metadata verifier returned an invalid proof record"
      _AUR_GUARD_CHAIN_VERIFIED_PKGBASE=''
      _AUR_GUARD_CHAIN_VERIFIED_NAMES=''
      return 1
    }
    if [[ -n "$_AUR_GUARD_CHAIN_VERIFIED_NAMES" ]]; then
      _AUR_GUARD_CHAIN_VERIFIED_NAMES+=$'\n'
    fi
    _AUR_GUARD_CHAIN_VERIFIED_NAMES+="$local_name"
    printf 'AUR Verify: verified %s through pinned PGP-signed metadata chain: %s.\n' \
      "$local_name" "$proof"
  done <<< "$parsed"
}

'''
text = text.replace(marker, helper + marker, 1)

start = text.index("_aur_guard_validate_skipped_integrity() {")
end = text.index("\n_aur_guard_verify_content_addressed_sources() {", start)
func = text[start:end]
header_old = '''_aur_guard_validate_skipped_integrity() {
  local pkgbase="$1"
  local srcinfo="$2"

  if ! awk -F ' = ' '
'''
header_new = '''_aur_guard_validate_skipped_integrity() {
  local pkgbase="$1"
  local srcinfo="$2"
  local chain_verified=''

  if [[ ${_AUR_GUARD_CHAIN_VERIFIED_PKGBASE:-} == "$pkgbase" ]]; then
    chain_verified="${_AUR_GUARD_CHAIN_VERIFIED_NAMES:-}"
  fi

  if ! awk -F ' = ' -v chain_verified="$chain_verified" '
    BEGIN {
      verified_count = split(chain_verified, verified_names, "\\n")
      for (verified_i = 1; verified_i <= verified_count; verified_i++) {
        if (verified_names[verified_i] != "") chain_ok[verified_names[verified_i]] = 1
      }
    }
'''
if func.count(header_old) != 1:
    raise SystemExit("skipped-integrity header did not match expected implementation")
func = func.replace(header_old, header_new, 1)
needle = '''          value = source[key]
          name = local_name(value)

          # Moving Git sources are fetched once, recorded by exact commit, and
'''
replacement = '''          value = source[key]
          name = local_name(value)

          if (chain_ok[name]) continue

          # Moving Git sources are fetched once, recorded by exact commit, and
'''
if func.count(needle) != 1:
    raise SystemExit("skipped-integrity source loop did not match expected implementation")
func = func.replace(needle, replacement, 1)
text = text[:start] + func + text[end:]

early = '''  _aur_guard_validate_skipped_integrity "$pkgbase" "$srcinfo" || {
    _AUR_GUARD_BASE_STATE[$pkgbase]='failed'
    _AUR_GUARD_REQUEST_STATE[$pkg]='failed'
    return 1
  }

'''
if text.count(early) != 1:
    raise SystemExit(f"expected one early skipped-integrity gate, found {text.count(early)}")
text = text.replace(early, "", 1)

tracked = '''  _aur_guard_assert_tracked_files_unchanged "$pkgbase" "$pkgdir" || {
    _AUR_GUARD_BASE_STATE[$pkgbase]='failed'
    _AUR_GUARD_REQUEST_STATE[$pkg]='failed'
    return 1
  }

'''
post = tracked + '''  _AUR_GUARD_CHAIN_VERIFIED_PKGBASE=''
  _AUR_GUARD_CHAIN_VERIFIED_NAMES=''
  _aur_guard_verify_signed_metadata_chain "$pkgbase" "$srcinfo" "$pkgdir" || {
    _AUR_GUARD_BASE_STATE[$pkgbase]='failed'
    _AUR_GUARD_REQUEST_STATE[$pkg]='failed'
    return 1
  }

  _aur_guard_validate_skipped_integrity "$pkgbase" "$srcinfo" || {
    _AUR_GUARD_BASE_STATE[$pkgbase]='failed'
    _AUR_GUARD_REQUEST_STATE[$pkg]='failed'
    return 1
  }

'''
if text.count(tracked) != 1:
    raise SystemExit(f"expected one tracked-file verification block, found {text.count(tracked)}")
text = text.replace(tracked, post, 1)

path.write_text(text, encoding="utf-8")
