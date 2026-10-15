#!/usr/bin/env bash
# Print the GitHub Release body for a device built by build.sh.
# Usage: ./release-notes.sh <device> <release-dir>
#   <release-dir> holds the files that will be attached to the release.
set -euo pipefail

device="${1:?usage: $0 <device> <release-dir>}"
release_dir="${2:?usage: $0 <device> <release-dir>}"

root="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
out="${root}/output/${device}"
extra_notes="${root}/devices/${device}/release.md"

# shellcheck source=/dev/null
source "${root}/work/${device}/build.env"

# ImmortalWrt's stock LAN address; build.sh leaves it unchanged.
lan_ip="192.168.1.1"

profiles="${out}/profiles.json"
version_code="$(jq -r '.version_code' "${profiles}")"
commit="${version_code##*-}"
model="$(jq -r --arg p "${PROFILE}" '.profiles[$p].titles[0] | [.vendor, .model] | map(select(. != null)) | join(" ")' "${profiles}")"
manifest="$(ls "${out}"/*.manifest)"

installed() { awk -v p="$1" '$1 == p { found = 1 } END { exit !found }' "${manifest}"; }

cat <<EOF
## ${model} · ImmortalWrt ${VERSION}

- 构建日期 / Build date: $(date -u +%Y-%m-%d)
- 源码 / Source: ImmortalWrt [${version_code}](https://github.com/immortalwrt/immortalwrt/commit/${commit}) · mywrt 软件包 / packages: [MyWRT/immortalwrt-packages-builder](https://github.com/MyWRT/immortalwrt-packages-builder)

### 下载哪个文件 / Which file

| 文件 / File | 用途 / Use |
|---|---|
EOF

for file in "${release_dir}"/*; do
    name="${file##*/}"
    case "${name}" in
        *-factory.*) use="首次刷入：从原厂固件或其他系统刷机 / First install from stock firmware" ;;
        *-sysupgrade.*) use="升级：设备已运行 OpenWrt 或 ImmortalWrt / Upgrade from OpenWrt or ImmortalWrt" ;;
        *.manifest) use="已安装的软件包及版本 / Installed packages and versions" ;;
        sha256sums) use="文件校验 / Checksums" ;;
        *) use="固件镜像 / Firmware image" ;;
    esac
    echo "| \`${name}\` | ${use} |"
done

cat <<EOF

### 默认设置 / Defaults

| 项目 / Item | 默认值 / Default |
|---|---|
| 后台地址 / Web UI | http://${lan_ip} |
| 用户名 / Username | \`root\` |
| 密码 / Password | \`mywrtadmin\` |
EOF

if [[ "${WIFI_DEFAULTS}" == "y" ]]; then
    if [[ "${WIFI_KEY_CUSTOM}" == "y" ]]; then
        key="由构建者设置 / Set by the builder"
    else
        key="\`mywrtwifi\`"
    fi
    echo "| WiFi 名称 / SSID | \`MyWRT\` |"
    echo "| WiFi 密码 / Key | ${key} |"
    echo "| 国家码 / Country | \`${WIFI_COUNTRY}\` |"
    [[ -n "${WIFI_CHANNEL_2G}" ]] && echo "| 2.4 GHz | 信道 / Channel ${WIFI_CHANNEL_2G}${WIFI_HTMODE_2G:+ · ${WIFI_HTMODE_2G}} |"
    [[ -n "${WIFI_CHANNEL_5G}" ]] && echo "| 5 GHz | 信道 / Channel ${WIFI_CHANNEL_5G}${WIFI_HTMODE_5G:+ · ${WIFI_HTMODE_5G}} |"
fi

if [[ "${WIFI_DEFAULTS}" == "y" ]]; then
    change_zh="后台密码和 WiFi 密码" change_en="the admin password and the WiFi key"
else
    change_zh="后台密码" change_en="the admin password"
fi

cat <<EOF

> [!IMPORTANT]
> 首次登录后，请立即修改${change_zh}。所有用户的默认值都相同。
> Change ${change_en} right after the first login. Every image ships the same defaults.

### 内置插件 / Included apps

EOF

awk '$1 ~ /^luci-(app|theme)-/ { printf "- `%s` %s\n", $1, $3 }' "${manifest}"

extras=()
installed luci-app-openclash && extras+=("OpenClash：在 OpenClash 页面中下载 Clash 内核 / Download the Clash core from the OpenClash page")
installed luci-app-passwall2 && extras+=("PassWall2：\`${PKG_MANAGER} update && ${PKG_MANAGER} $([[ "${PKG_MANAGER}" == apk ]] && echo add || echo install) xray-core\`（或 / or \`sing-box\`）")
if installed luci-app-easytier && ! installed easytier; then
    extras+=("EasyTier：\`${PKG_MANAGER} update && ${PKG_MANAGER} $([[ "${PKG_MANAGER}" == apk ]] && echo add || echo install) easytier\`")
fi

if (( ${#extras[@]} > 0 )); then
    printf '\n### 需要另外安装的内核 / Cores to install separately\n\n'
    printf -- '- %s\n' "${extras[@]}"
fi

printf '\n### 说明 / Notes\n\n'
echo "- 已内置 mywrt 软件源，可在「系统 → 软件包」中安装更多插件。"
echo "  The mywrt package feed is preinstalled; install more apps from System → Software."
if installed default-settings-chn; then
    echo "- 时区为 Asia/Shanghai，官方软件源默认使用国内镜像。"
    echo "  Timezone is Asia/Shanghai, and official feeds use a mirror in China."
fi
echo "- 升级时如果保留配置，本固件的默认设置不会覆盖你已有的配置。"
echo "  When upgrading with settings kept, these defaults do not overwrite your existing configuration."

if [[ -f "${extra_notes}" ]]; then
    echo
    cat "${extra_notes}"
fi
