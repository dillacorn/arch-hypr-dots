# Third-Party Notices

This file records third-party material redistributed or adapted by Awtarchy. It does not change the MIT license for Awtarchy-authored work, and it does not relicense third-party material.

## Wiremix reference configuration

`config/wiremix/wiremix.toml` is adapted from the documented reference configuration in [tsowell/wiremix](https://github.com/tsowell/wiremix/blob/main/wiremix.toml), with Awtarchy-specific defaults, bindings, and comments.

Wiremix is by Thomas Sowell and contributors and is available under [MIT OR Apache-2.0](https://github.com/tsowell/wiremix/blob/main/Cargo.toml). Its upstream license texts are [LICENSE-MIT](https://github.com/tsowell/wiremix/blob/main/LICENSE-MIT) and [LICENSE-APACHE](https://github.com/tsowell/wiremix/blob/main/LICENSE-APACHE).

## Theme palettes

The Catppuccin-derived colors in `config/hypr/themes/catppuccin-frappé`, `crimson_red`, `electric_blue`, and `obsidian_night` are based on the [Catppuccin palette](https://github.com/catppuccin/palette). Catppuccin is Copyright © 2021-present Catppuccin Org and is distributed under the [MIT License](https://github.com/catppuccin/palette/blob/main/LICENSE).

The colors in `config/hypr/themes/gruvbox` are based on [morhetz/gruvbox](https://github.com/morhetz/gruvbox), authored by Pavel Pertsev (`morhetz`) and contributors. Gruvbox identifies its license as [MIT/X11](https://github.com/morhetz/gruvbox#license).

## Adapted desktop-entry metadata

The following launchers retain upstream application names, descriptions, translations, and action metadata while adapting execution for Awtarchy:

- `local/share/applications/htop.desktop` — [htop](https://github.com/htop-dev/htop/blob/main/htop.desktop), GPL-2.0-or-later
- `local/share/applications/btop.desktop` — [btop++](https://github.com/aristocratos/btop/blob/main/btop.desktop), Apache-2.0
- `local/share/applications/micro.desktop` — [micro](https://github.com/micro-editor/micro/tree/master/assets/packaging), MIT
- `local/share/applications/steam.desktop` — Steam launcher metadata and translations; Steam and related marks belong to Valve Corporation

The Awtarchy-specific `Exec` integration and surrounding local configuration remain Awtarchy-authored. Application names and trademarks belong to their respective owners.

## First-party Awtarchy media

`awtarchy_geology.png`, `awtarchy_space.png`, and `config/hypr/sounds/awtarchy-login.mp3` are first-party Awtarchy assets, not unresolved third-party material.
