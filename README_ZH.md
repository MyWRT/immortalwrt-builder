[English](README.md) | 简体中文

# immortalwrt-builder

用官方 ImageBuilder 为指定路由器构建 ImmortalWrt 固件：官方内核、精简的软件包列表、适合中国使用的默认设置。一个 GitHub Actions 工作流负责构建 `devices/` 下的所有设备。

## 简介

官方 ImageBuilder 只能增加软件包和文件。本仓库沿用这种方式，在每台设备的官方 profile 之上做少量修改：

- 不改内核，不重新打包镜像。产出的是官方格式的 `factory` / `sysupgrade` 镜像，可以正常升级。
- 只需要写要增加或删除的软件包，默认软件包由官方 profile 提供。
- 系统设置由首次开机时执行的 `uci-defaults` 脚本完成。

已支持的设备：

| 目录 | 设备 | 平台 |
|---|---|---|
| `cm520-79f` | MobiPromo CM520-79F | `ipq40xx/generic` |

## 镜像里改了什么

| 项目 | 修改 |
|---|---|
| 地区 | `default-settings-chn`：时区 `Asia/Shanghai`、中文界面、官方软件源改用国内镜像 |
| NTP | 国内服务器在前（国家授时中心、上海交大、cn.pool），之后是 Cloudflare / PTB / Netnod；不使用 DHCP 下发的服务器 |
| LuCI | 默认主题为 shadcn，同时安装 argon。两者都使用 `global/files/www/` 里的登录背景图 |
| 软件源 | 加入 [mywrt](https://mywrt.awayfrom.cn) 软件源和签名公钥，构建时和设备上都能用 |
| SSH | dropbear 只监听 `lan` |
| root 密码 | root 密码为空时设为 `mywrtadmin` |
| 主机名 | `MyWRT-XXXX`，`XXXX` 取自第一个网口 MAC 地址的末尾 |
| WiFi | SSID `MyWRT`，WPA2/WPA3（`sae-mixed`）。密码取自 `WIFI_KEY`，默认 `mywrtwifi`。国家码优先取 `device.conf`，其次 `WIFI_COUNTRY`，都没有时为 `AU`。各频段的信道和模式取自 `device.conf`（CM520：2.4 GHz 信道 6、HT20；5 GHz 信道 149、VHT80 即 802.11ac） |

修改地区、NTP、SSH、密码、主机名和主题的脚本只在全新刷机时执行，保留配置升级时会跳过。

## 使用方法

### GitHub Actions

1. Fork 本仓库。
2. 可选：添加仓库 secret `WIFI_KEY`（8–63 个字符，不能包含单引号，默认 `mywrtwifi`）和仓库变量 `WIFI_COUNTRY`（默认 `AU`，设备的 `device.conf` 里设置的值优先）。
3. 打开 **Actions → Build ImmortalWrt → Run workflow**，选择设备（或 `all`）和版本。要发布就保持勾选 **release**，只想试构建就取消勾选。
4. 勾选 **release** 时，镜像会发布到 tag 为 `ImmortalWrt_<设备>_<版本>_<年.月>` 的 GitHub Release，同一个月内重新构建会更新这个 Release。Release 说明里列出了后台地址、用户名和密码、WiFi 设置、内置插件，以及该刷哪个文件。取消勾选时，改为下载名为 `immortalwrt-<版本>-<设备>` 的 Artifact。

   两种方式里都有 `*-squashfs-factory.*`、`*-squashfs-sysupgrade.bin`、软件包清单和 `sha256sums`。

### 本地构建

需要一台 x86_64 Linux 主机，装好 [ImageBuilder 依赖](https://openwrt.org/docs/guide-user/additional-software/imagebuilder#prerequisites)，以及 `curl` 和 `zstd`。

```bash
./build.sh cm520-79f 25.12.2
WIFI_KEY='你的WiFi密码' ./build.sh cm520-79f 25.12.2
```

镜像输出到 `output/<设备>/`，下载的文件缓存在 `work/dl/`。

## 自定义

设置分四层。同一项出现两次时，以后面一层为准：

```
global/packages.list  →  devices/<设备>/packages.list
global/files/         →  devices/<设备>/files/
```

- **`packages.list`**：每行写一个或多个包名，`#` 后面是注释。写 `pkg` 表示安装，写 `-pkg` 表示删除，对官方默认包同样有效。同一个包名以最后一次出现为准。
- **`files/`**：复制到镜像的根目录。设备 `files/` 里的文件会覆盖全局同路径的文件。
- **`files/etc/uci-defaults/`**：首次开机时执行一次的脚本。如果不希望在保留配置升级后再次执行，在脚本开头写上 `[ -f /etc/backup/installed_packages.txt ] && exit 0`。

### 添加设备

1. 在 `https://downloads.immortalwrt.org/releases/<版本>/targets/<平台>/profiles.json` 里找到设备，记下平台和 profile 名称。
2. 新建 `devices/<名称>/device.conf`：

   ```sh
   TARGET="ipq40xx/generic"
   PROFILE="mobipromo_cm520-79f"
   WIFI_DEFAULTS="y"     # 没有 WiFi 的设备不写这一行
   WIFI_COUNTRY="AU"     # 可选，覆盖全局的 WIFI_COUNTRY
   WIFI_CHANNEL_2G="6"   # 可选，各频段的信道和模式，首次开机时设置一次
   WIFI_HTMODE_2G="HT20"
   WIFI_CHANNEL_5G="149"
   WIFI_HTMODE_5G="VHT80"
   ```

3. 按需添加 `devices/<名称>/packages.list`、`devices/<名称>/files/` 和 `devices/<名称>/release.md`（附加到 Release 说明末尾，比如写刷机步骤）。
4. 在 `.github/workflows/build.yml` 的 `device` 选项里加上 `<名称>`。

mywrt 源只提供 [MyWRT/immortalwrt-packages-builder](https://github.com/MyWRT/immortalwrt-packages-builder) 构建过的架构。要查看源里有哪些包，打开对应目录下的 `index.json`（25.12）或 `Packages.gz`（24.10）。

## 注意事项

- **WiFi 密码和 root 密码都在镜像里。** 默认的 `mywrtwifi` 和 `mywrtadmin` 是公开的，也会写在 Release 说明里。自定义的 `WIFI_KEY` 不会出现在说明里，但任何拿到镜像的人都能读出来。首次开机后请修改这两个密码。
- 信道和模式由 `/etc/hotplug.d/ieee80211/20-mywrt-radio` 设置：每个无线芯片首次被识别时设置一次。之后在 LuCI 里的修改会保留，保留配置升级也不会重新设置。
- 如果 mywrt 源里没有某台设备的架构，构建时只会给出警告，但设备上执行 `apk update` 会对这个源报错。

## 许可证

[MIT](LICENSE)
