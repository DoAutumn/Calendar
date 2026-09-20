# Calendar

[English](README.md) · **简体中文**

> 菜单栏常驻的时钟 + 月历：显示阴历、法定节假日（休）与调休上班日（班）。

## 功能

- **菜单栏常驻**，无 Dock 图标（`LSUIElement`）
- **实时时钟**：可配置秒、24 小时制、AM/PM、日期、星期
- **月历翻页**：◀ / ▶ 切换月份，点击月标题回到本月
- **阴历 / 节假日 / 调休**：通过 [天行数据](https://www.tianapi.com/) `jiejiari` 接口按月拉取
  - `休`：法定节假日
  - `班`：调休需上班
  - 初一显示农历月份名，其余显示农历日
- **提醒事项**：有截止日期的未完成提醒在对应日期显示圆点；悬停看标题与时间，点击打开「提醒事项」
- **接口失败时只显示公历**（不阻塞月历使用）
- **设置窗口**：时间 / 日期显示选项

## 安装

### 方式 A — Homebrew

```bash
brew install --cask DoAutumn/tap/doautumn-calendar
```

更新：`brew upgrade --cask doautumn-calendar`。

### 方式 B — 一行命令安装

```bash
curl -L -o /tmp/Calendar.app.zip \
  https://github.com/DoAutumn/Calendar/releases/latest/download/Calendar.app.zip \
  && unzip -oq /tmp/Calendar.app.zip -d /Applications/ \
  && xattr -dr com.apple.quarantine "/Applications/Calendar.app" \
  && rm /tmp/Calendar.app.zip \
  && open "/Applications/Calendar.app"
```

### 方式 C — 从源码构建

依赖 Xcode 命令行工具（`swiftc`），无需 Xcode 工程。

```bash
git clone https://github.com/DoAutumn/Calendar.git
cd Calendar
./build_app.sh                                 # 产物：dist/Calendar.app

open "dist/Calendar.app"
cp -R "dist/Calendar.app" /Applications/
```

## 文件说明

| 文件 | 作用 |
|---|---|
| `calendar.swift` | 全部逻辑（单文件） |
| `build_app.sh` | 编译 + 打包 + 签名成 `.app` |
| `make_zip.sh` | 把构建好的 App 压成 Release 产物 |
| `release.sh` | 升 `VERSION`、发 Release、同步更新 Homebrew cask |
| `generate_icon.swift` | 生成 App 图标 |
| `setup_signing.sh` | 可选：稳定自签名身份（本地反复重建时用） |

## License

[MIT](LICENSE) — 原作者 Emil Kreutzman；本仓库重写与维护 by DoAutumn.
