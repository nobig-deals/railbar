# RailBar

A lightweight macOS menu bar app for monitoring your [Railway](https://railway.app) deployments at a glance.

![macOS 14+](https://img.shields.io/badge/macOS-14%2B-blue)
![Swift 6](https://img.shields.io/badge/Swift-6-orange)
![License: MIT](https://img.shields.io/badge/License-MIT-green)

## Features

- Live deployment status for all your Railway projects and services
- Menu bar icon changes based on overall health (running, building, errors)
- Ticker rotates through actively deploying services
- Adaptive polling that respects Railway API rate limits
- API token stored securely in macOS Keychain

## Install

### Download

Grab the latest `.dmg` from [Releases](../../releases), open it, and drag **RailBar** to your Applications folder.

### Build from source

Requires Xcode 16+ and [XcodeGen](https://github.com/yonaskolb/XcodeGen).

```bash
git clone https://github.com/michalcerny/railbar.git
cd railbar
xcodegen generate
open RailBar.xcodeproj
```

Then press **Cmd+R** in Xcode to build and run.

## Setup

1. Get an API token from [Railway Account Settings](https://railway.app/account/tokens)
2. Launch RailBar — click the train icon in your menu bar
3. Open **Settings** and paste your token

## How it works

RailBar polls the Railway GraphQL API every 30 seconds (adjusts automatically when rate limits are low). It fetches all your projects, services, and their latest deployment status, then displays a summary in the menu bar.

| Icon | Meaning |
|------|---------|
| Train | All services running normally |
| Rotating arrows | Deployments in progress |
| Exclamation triangle | API error |
| X circle | One or more services failed/crashed |

## License

MIT
