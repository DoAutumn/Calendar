# Calendar

**English** · [简体中文](README.zh-CN.md)

> A menu-bar clock and month calendar for macOS, with lunar dates, statutory holidays, and makeup workdays.

## Features

- **Menu-bar resident**, no Dock icon (`LSUIElement`)
- **Live clock**: seconds, 24-hour, AM/PM, date, weekday — all configurable
- **Month navigation**: ◀ / ▶ to change months; click the month title to jump back to today
- **Lunar / holidays / makeup days** via [TianAPI](https://www.tianapi.com/) `jiejiari`
  - `休` — statutory holiday
  - `班` — makeup workday
  - On the first lunar day of a month, the lunar month name is shown
- **Reminders**: incomplete items with due dates show as accent dots; hover for titles/times, click to open Reminders
- **API failure falls back to Gregorian-only** (calendar stays usable)
- **Settings window** for time/date display options

## Install

### A — Homebrew

```bash
brew install --cask DoAutumn/tap/doautumn-calendar
```

Upgrade with `brew upgrade --cask doautumn-calendar`.

### B — One-liner

```bash
curl -L -o /tmp/Calendar.app.zip \
  https://github.com/DoAutumn/Calendar/releases/latest/download/Calendar.app.zip \
  && unzip -oq /tmp/Calendar.app.zip -d /Applications/ \
  && xattr -dr com.apple.quarantine "/Applications/Calendar.app" \
  && rm /tmp/Calendar.app.zip \
  && open "/Applications/Calendar.app"
```

### C — Build from source

Requires Xcode Command Line Tools (`swiftc`). No Xcode project needed.

```bash
git clone https://github.com/DoAutumn/Calendar.git
cd Calendar
./build_app.sh                                 # → dist/Calendar.app

open "dist/Calendar.app"
cp -R "dist/Calendar.app" /Applications/
```

## Layout

| File | Role |
|---|---|
| `calendar.swift` | All app logic (single file) |
| `build_app.sh` | Compile, bundle, sign |
| `make_zip.sh` | Zip the built app for Releases |
| `release.sh` | Bump `VERSION`, publish Release, update Homebrew cask |
| `generate_icon.swift` | Draw the app icon |
| `setup_signing.sh` | Optional stable self-signed identity for local rebuilds |

## License

[MIT](LICENSE) — originally by Emil Kreutzman; this rewrite by DoAutumn.
