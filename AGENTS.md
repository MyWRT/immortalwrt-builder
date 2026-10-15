# AGENTS.md

Builds ImmortalWrt images per device with the official ImageBuilder. `build.sh` is the whole build; `.github/workflows/build.yml` runs it once per device and publishes the result. `release-notes.sh` writes the Release body from `work/<device>/build.env` (written by `build.sh`), `profiles.json` and the manifest; a `devices/<name>/release.md` is appended when present. The user-facing layer rules are in `README.md`.

## Verifying changes

- Static checks: `bash -n build.sh release-notes.sh`, `shellcheck build.sh release-notes.sh` and `actionlint .github/workflows/build.yml`.
- Real builds run on GitHub Actions: push, then `gh workflow run build.yml -f device=<name> -f version=<release> -f release=false`. `release=false` uploads a workflow artifact; the default publishes a GitHub Release, which only the user decides. The local disk is short on space, so local ImageBuilder/SDK runs and container pulls happen only when the user asks for them.
- Package availability: read the feed index (`index.json` for 25.12, `Packages.gz` for 24.10). Official feeds live at `https://downloads.immortalwrt.org/releases/<version>/packages/<arch>/<feed>/`, and the mywrt feed at `https://mywrt.awayfrom.cn/packages-<major.minor>/<arch>/mywrt/`. HTML directory listings are incomplete; use the index only.
- The mywrt feed only has the architectures in the build matrix of `../immortalwrt-packages-builder/.github/workflows/build-packages-release.yml`. A device on a new architecture needs that matrix extended first.

## Conventions

- Each device's profile defaults come from upstream `profiles.json`. `packages.list` holds only the delta.
- `uci-defaults` scripts that set preferences start with `[ -f /etc/backup/installed_packages.txt ] && exit 0`, so they run on a fresh flash only. They are named `99-*` so they run after the package scripts. `99-ntp` replaces the NTP list that `default-settings-chn` sets, on purpose.
- Wi-Fi defaults go through the generated `/etc/board.d/99-mywrt-wireless` (`ucidef_set_wireless`). A `uci-defaults` script would run before the wifi driver has created `/etc/config/wireless`. board.json has no channel/htmode defaults, so those come from the generated `/etc/hotplug.d/ieee80211/20-mywrt-radio`, which runs after `10-wifi-detect` and marks each radio with `mywrt_defaults=1`.
- `WIFI_COUNTRY` precedence: `device.conf` > env/workflow variable > `AU`.
- Comments are one line and explain why, never what.
- `README.md` and `README_ZH.md` are translations of each other. Change both in the same commit.
- The images under `global/files/www/` are excluded from the MIT license.
