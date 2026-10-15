English | [简体中文](README_ZH.md)

# immortalwrt-builder

Build ImmortalWrt firmware for specific routers with the official ImageBuilder: stock kernel, a short package list, and China-friendly defaults. One GitHub Actions workflow builds every device under `devices/`.

## About

The official ImageBuilder only lets you add packages and files. This repository keeps that model and stacks small changes on top of each device's official profile:

- No custom kernel and no repacking of images. The output is the stock `factory` / `sysupgrade` format and upgrades normally.
- You only list packages to add or remove. Profile defaults come from upstream.
- Settings are applied on first boot by `uci-defaults` scripts.

Supported devices:

| Directory | Device | Target |
|---|---|---|
| `cm520-79f` | MobiPromo CM520-79F | `ipq40xx/generic` |

## What the image changes

| Area | Change |
|---|---|
| Region | `default-settings-chn`: timezone `Asia/Shanghai`, Chinese LuCI, mirror for official feeds |
| NTP | China servers first (NTSC, SJTU, cn.pool), then Cloudflare / PTB / Netnod; DHCP-provided servers ignored |
| LuCI | shadcn is the default theme; argon is also installed. Both use the login backgrounds in `global/files/www/` |
| Extra feed | The [mywrt](https://mywrt.awayfrom.cn) feed and its signing key, active at build time and on the device |
| SSH | dropbear listens on `lan` only |
| Root password | `mywrtadmin` if the root password is empty |
| Hostname | `MyWRT-XXXX`, where `XXXX` is the end of the first Ethernet MAC address |
| Wi-Fi | SSID `MyWRT`, WPA2/WPA3 (`sae-mixed`). Key: `WIFI_KEY`, default `mywrtwifi`. Country: `device.conf`, else `WIFI_COUNTRY`, else `AU`. Channel and mode per band from `device.conf` (CM520: 2.4 GHz channel 6 HT20, 5 GHz channel 149 VHT80 / 802.11ac) |

The scripts that change region, NTP, SSH, password, hostname and theme run only on a fresh flash. A sysupgrade that keeps settings skips them.

## Usage

### GitHub Actions

1. Fork the repository.
2. Optionally add the repository secret `WIFI_KEY` (8–63 characters, no single quote; default `mywrtwifi`) and the repository variable `WIFI_COUNTRY` (default `AU`; a device's `device.conf` overrides it).
3. Run **Actions → Build ImmortalWrt → Run workflow**, then pick a device (or `all`) and a release. Keep **release** checked to publish, or clear it for a test build.
4. With **release** checked, the images go to a GitHub Release tagged `ImmortalWrt_<device>_<version>_<YYYY.MM>`. Rebuilding in the same month updates that release. The release notes list the default address, credentials, Wi-Fi settings, included apps and which file to flash. With **release** cleared, download the `immortalwrt-<version>-<device>` workflow artifact instead.

   Both contain `*-squashfs-factory.*`, `*-squashfs-sysupgrade.bin`, the package manifest and `sha256sums`.

### Local

Requires an x86_64 Linux host with the [ImageBuilder prerequisites](https://openwrt.org/docs/guide-user/additional-software/imagebuilder#prerequisites), plus `curl` and `zstd`.

```bash
./build.sh cm520-79f 25.12.2
WIFI_KEY='your-wifi-key' ./build.sh cm520-79f 25.12.2
```

Images land in `output/<device>/`. Downloads are cached in `work/dl/`.

## Customizing

Settings come in four layers. When the same item appears twice, the later layer wins:

```
global/packages.list  →  devices/<device>/packages.list
global/files/         →  devices/<device>/files/
```

- **`packages.list`** takes one or more names per line, and `#` starts a comment. `pkg` installs a package. `-pkg` removes it, including profile defaults. For each name, the last mention wins.
- **`files/`** is copied into the image root. A file in a device's `files/` replaces the global file at the same path.
- **`files/etc/uci-defaults/`** holds scripts that run once on first boot. To skip a script after a sysupgrade that keeps settings, start it with `[ -f /etc/backup/installed_packages.txt ] && exit 0`.

### Adding a device

1. Look up the device in `https://downloads.immortalwrt.org/releases/<version>/targets/<target>/profiles.json` and note its target and profile name.
2. Create `devices/<name>/device.conf`:

   ```sh
   TARGET="ipq40xx/generic"
   PROFILE="mobipromo_cm520-79f"
   WIFI_DEFAULTS="y"     # omit for devices without Wi-Fi
   WIFI_COUNTRY="AU"     # optional, overrides the global WIFI_COUNTRY
   WIFI_CHANNEL_2G="6"   # optional channel and mode per band, set once on first boot
   WIFI_HTMODE_2G="HT20"
   WIFI_CHANNEL_5G="149"
   WIFI_HTMODE_5G="VHT80"
   ```

3. Optionally add `devices/<name>/packages.list`, `devices/<name>/files/`, and `devices/<name>/release.md` (appended to the release notes, e.g. flashing steps).
4. Add `<name>` to the `device` options in `.github/workflows/build.yml`.

Packages from the mywrt feed exist only for the architectures that [MyWRT/immortalwrt-packages-builder](https://github.com/MyWRT/immortalwrt-packages-builder) builds. To see what a feed offers, open its `index.json` (25.12) or `Packages.gz` (24.10).

## Notes

- **The Wi-Fi key and root password are inside the image.** The defaults `mywrtwifi` and `mywrtadmin` are public and appear in the release notes. A custom `WIFI_KEY` is never printed, but anyone who can download the image can read it. Change both after the first boot.
- Channel and mode are applied by `/etc/hotplug.d/ieee80211/20-mywrt-radio` once per radio, right after the radio is first detected. Later changes in LuCI are kept, and a sysupgrade that keeps settings does not reapply them.
- If the mywrt feed has no directory for a device's architecture, the build only prints a warning, but `apk update` on the device reports errors for that feed.

## License

[MIT](LICENSE)
