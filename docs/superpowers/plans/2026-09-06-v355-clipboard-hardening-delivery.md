# v3.5.5 Clipboard Hardening Delivery Plan

Goal: land the already-tested clipboard ImageMagick resource bounds on current `main` and make stable `v3.5.5` updates receive the same hardened script without moving the published tag.

- Reapply the final clipboard hardening from PR #149 on top of current `main`.
- Preserve the tested limits: first frame only, 256 MiB memory/map, 512 MiB disk, 2 second render timeout, 1 second kill escalation.
- Preserve the lazy thumbnail cache/fallback behavior.
- Add the final clipboard hash to managed history while retaining prior known clipboard hashes.
- Add a tag-scoped `v3.5.5` runtime repair that patches the extracted immutable release source and its managed-history data before `build_target_home`.
- Do not move or recreate the `v3.5.5` tag.
- Keep issue #150 separate; it has no implementation ready to merge.
- Require the clipboard regression, runtime-delivery regression, full PR CI, and merged-main push CI before editing the existing v3.5.5 release body.
