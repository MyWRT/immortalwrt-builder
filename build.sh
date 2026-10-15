#!/usr/bin/env bash
# Build ImmortalWrt with the official ImageBuilder for one device.
# Usage: [WIFI_KEY=...] [WIFI_COUNTRY=GB] ./build.sh <device> <version>
#        ./build.sh cm520-79f 25.12.2
#
# Layers, applied in order (later wins):
#   global/packages.list -> devices/<device>/packages.list
#   global/files/        -> devices/<device>/files/
set -euo pipefail

device="${1:?usage: $0 <device> <version>}"
version="${2:?usage: $0 <device> <version>, e.g. 25.12.2}"

root="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
device_dir="${root}/devices/${device}"
[[ -f "${device_dir}/device.conf" ]] || { echo "Unknown device: ${device} (no ${device_dir}/device.conf)" >&2; exit 1; }

TARGET="" PROFILE="" WIFI_DEFAULTS=""
# shellcheck source=/dev/null
source "${device_dir}/device.conf"
[[ -n "${TARGET}" && -n "${PROFILE}" ]] || { echo "${device}/device.conf must set TARGET and PROFILE" >&2; exit 1; }

if [[ "${WIFI_DEFAULTS}" == "y" ]]; then
    wifi_key="${WIFI_KEY:?WIFI_KEY is required for ${device}: ImmortalWrt otherwise ships an open, enabled AP}"
    wifi_country="${WIFI_COUNTRY:-GB}"
    [[ "${#wifi_key}" -ge 8 && "${#wifi_key}" -le 63 && "${wifi_key}" != *"'"* ]] ||
        { echo "WIFI_KEY must be 8-63 chars without single quotes" >&2; exit 1; }
fi

# Merge package layers: 'pkg' adds, '-pkg' removes; the last mention of a name wins.
merge_packages() {
    local -A state=()
    local -a order=() tokens=() result=()
    local file line token name

    for file in "$@"; do
        [[ -f "${file}" ]] || continue
        while IFS= read -r line || [[ -n "${line}" ]]; do
            read -ra tokens <<<"${line%%#*}"
            for token in "${tokens[@]}"; do
                name="${token#-}"
                [[ -v "state[${name}]" ]] || order+=("${name}")
                [[ "${token}" == -* ]] && state["${name}"]="-" || state["${name}"]=""
            done
        done <"${file}"
    done

    for name in "${order[@]}"; do
        result+=("${state[${name}]}${name}")
    done
    echo "${result[*]}"
}

work="${root}/work/${device}"
dl="${root}/work/dl"
out="${root}/output/${device}"
base_url="https://downloads.immortalwrt.org/releases/${version}/targets/${TARGET}"
archive="immortalwrt-imagebuilder-${version}-${TARGET//\//-}.Linux-x86_64.tar.zst"

rm -rf "${work}" "${out}"
mkdir -p "${work}" "${dl}" "${out}"

# Download once per target/version (CI caches work/dl), always verify against upstream sha256sums.
cd "${dl}"
[[ -f "${archive}" ]] || curl -fL --retry 3 -o "${archive}" "${base_url}/${archive}"
curl -fsSL "${base_url}/sha256sums" | awk -v f="${archive}" '$2 == "*" f || $2 == f { print $1 "  " f }' >"${archive}.sha256"
[[ -s "${archive}.sha256" ]] || { echo "No checksum for ${archive}" >&2; exit 1; }
sha256sum -c "${archive}.sha256"

cd "${work}"
mkdir imagebuilder
tar -I zstd -xf "${dl}/${archive}" -C imagebuilder --strip-components=1

# Stage overlay files: global first, device on top.
mkdir files
for layer in "${root}/global/files" "${device_dir}/files"; do
    [[ -d "${layer}" ]] && cp -a "${layer}/." files/
done

# Feed format of this ImageBuilder.
if grep -q '^CONFIG_USE_APK=y' imagebuilder/.config; then
    feeds_file="files/etc/apk/repositories.d/customfeeds.list"
    keys_src="files/etc/apk/keys"
    repos_file="imagebuilder/repositories"
else
    feeds_file="files/etc/opkg/customfeeds.conf"
    keys_src="files/etc/opkg/keys"
    repos_file="imagebuilder/repositories.conf"
fi
packages_arch="$(sed -n 's/^CONFIG_TARGET_ARCH_PACKAGES="\(.*\)"$/\1/p' imagebuilder/.config)"
[[ -n "${packages_arch}" ]] || { echo "CONFIG_TARGET_ARCH_PACKAGES missing in .config" >&2; exit 1; }

# Custom feeds: expand variables in the shipped files (both formats), then prepend the
# active entries of this format to the ImageBuilder's repositories and trust their keys.
for f in files/etc/apk/repositories.d/customfeeds.list files/etc/opkg/customfeeds.conf; do
    [[ -f "${f}" ]] || continue
    sed -i \
        -e "s|\${PACKAGES_ARCH}|${packages_arch}|g" \
        -e "s|\${DISTRIB_ARCH}|${packages_arch}|g" \
        -e "s|\${OPENWRT_VERSION}|${version}|g" \
        -e "s|\${DISTRIB_RELEASE}|${version}|g" \
        -e "s|\${BIG_VERSION}|${version%.*}|g" \
        "${f}"
done
if [[ -f "${feeds_file}" ]]; then
    feeds="$(awk '!/^[[:space:]]*(#|$)/' "${feeds_file}")"
    if [[ -n "${feeds}" ]]; then
        echo "Custom feeds:"$'\n'"${feeds}"
        { printf '%s\n' "${feeds}"; cat "${repos_file}"; } >"${repos_file}.new"
        mv -f "${repos_file}.new" "${repos_file}"
        if [[ -d "${keys_src}" ]]; then cp -f "${keys_src}"/* imagebuilder/keys/; fi
    fi
fi

# board.d runs in preinit (board.json), so `wifi config` uses these defaults whenever it
# generates /etc/config/wireless; a uci-defaults script would race the wifi driver probe.
if [[ "${WIFI_DEFAULTS}" == "y" ]]; then
    mkdir -p files/etc/board.d
    cat >files/etc/board.d/99-mywrt-wireless <<EOF
#!/bin/sh
. /lib/functions/uci-defaults.sh
board_config_update
ucidef_set_country '${wifi_country}'
ucidef_set_wireless all 'MyWRT' 'sae-mixed' '${wifi_key}'
board_config_flush
exit 0
EOF
    chmod 0755 files/etc/board.d/99-mywrt-wireless
fi

packages="$(merge_packages "${root}/global/packages.list" "${device_dir}/packages.list")"
echo "Device: ${device} (${TARGET}, ${PROFILE})"
echo "Packages: ${packages}"

make -C imagebuilder image \
    PROFILE="${PROFILE}" \
    PACKAGES="${packages}" \
    FILES="${work}/files" \
    BIN_DIR="${out}"

ls -lh "${out}"
