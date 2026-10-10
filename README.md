<div align="center">

<img width="100%" alt="header" src="https://capsule-render.vercel.app/api?type=waving&height=210&text=Nestbuxbot%20Bot&fontAlign=50&fontAlignY=36&fontSize=56&desc=Auto%20Tasks%20%7C%20Reward%20Ads%20%7C%20Bonus%20Spins%20%7C%20Spin%20And%20Win%20%7C%20Multi-Account&descAlign=50&descAlignY=58"/>

<img alt="typing" src="https://readme-typing-svg.demolab.com?font=Inter&size=18&duration=3000&pause=650&center=true&vCenter=true&width=900&lines=Auto+Complete+Tasks+%7C+Claim+Every+Open+Channel+And+Link;Auto+Reward+Ads+%7C+Collect+Every+Coin+Slot;Auto+Bonus+Spins+%7C+Watch+And+Convert+Into+Wheel+Turns;Auto+Spin+And+Win+%7C+Spend+Every+Available+Spin;Proxy+Support+%7C+Multi-Account"/>

<p>
  <img alt="elixir" src="https://img.shields.io/badge/Elixir-1.14+-4B275F?logo=elixir&logoColor=white"/>
  <img alt="platform" src="https://img.shields.io/badge/Platform-Nestbuxbot%20Miniapp-111111"/>
  <img alt="multi-account" src="https://img.shields.io/badge/Multi--Account-Supported-111111"/>
  <img alt="proxy" src="https://img.shields.io/badge/Proxy-Supported-111111"/>
  <img alt="author" src="https://img.shields.io/badge/by-Yuurisandesu-111111"/>
</p>

<p>
  <b>Nestbuxbot Bot</b> is a full automation bot for the Nestbuxbot Telegram Miniapp.<br/>
  It handles the complete daily cycle: channel and partner tasks, reward advertisements, bonus spin advertisements, the Spin and Win wheel, and the account summary, all running automatically across multiple accounts with proxy support and a live countdown between cycles.<br/>
  Built and distributed by <b>Yuurisandesu</b>.
</p>

</div>

---

## Table of Contents

- [Requirements](#requirements)
- [Installation](#installation)
- [Configuration](#configuration)
- [Running the Bot](#running-the-bot)
- [Features](#features)
- [File Structure](#file-structure)
- [Disclaimer](#disclaimer)

---

## Requirements

- Elixir `1.14+` (Erlang/OTP 25 or newer)
- No package manager, no Hex, no external dependency

---

## Installation

**Clone the repository:**

```bash
git clone https://github.com/Yuurisan-N1/Nestbuxbot-Miniapp.git
cd Nestbuxbot-Miniapp
```

Nothing to install. HTTP, TLS and JSON ship inside the package.

---

## Configuration

### 1. Accounts (data.txt)

Fill `data.txt` with Telegram WebApp `initData` for each account, one per line:

```
user=%7B%22id%22...&hash=abc123
user=%7B%22id%22...&hash=def456
```

Each line is one account. Accounts are processed one by one, never in parallel.

### 2. Proxies (proxy.txt)

Optional. One proxy per line, matched to the account at the same position:

```
http://user:pass@host:port
http://host:port
```

Leave the file empty to run without a proxy.

### 3. Settings (config.json)

```json
{
  "settings": {
    "sleep_seconds": 3600
  }
}
```

`sleep_seconds` is the pause between automation cycles.

---

## Running the Bot

Linux and macOS:

```bash
elixir bot.exs
```

Windows:

```bat
run_pc.bat
```

Stop the bot by closing the window, or on Linux and macOS with `kill <pid>`.

---

## Features

- **Auto Tasks** claims every published task that is still open, including channel joins and partner links, and reports each attempt the moment the server answers.
- **Auto Reward Ads** watches the coin advertisement slots and collects the daily allowance until the server reports the limit.
- **Auto Bonus Spins** watches the spin advertisement slots and converts each one into a wheel turn.
- **Auto Spin and Win** spends every available spin on the wheel and reports the reward of each turn.
- **Force Join Detection** detects the required channel gate and reports it clearly instead of failing silently.
- **Device Identity** generates a random device fingerprint per account, cached in `device.json`, so every account keeps one stable identity.
- **Multi Account** processes any number of accounts sequentially in a single run.
- **Proxy Support** round robin proxies by account index, with masked proxy output in the log.
- **Live Countdown** every wait is printed in place and erased when it reaches zero.

---

## File Structure

```
Nestbuxbot-Miniapp/
├── bot.exs           # the automation loop
├── config.json       # settings
├── data.txt          # one initData per line
├── proxy.txt         # optional proxies
├── run_pc.bat        # Windows launcher
├── LICENSE
├── README.md
└── utils/
    ├── banner.ex
    └── json.ex
```

`device.json` is created automatically at the first run and is never shipped with the package.

---

## Disclaimer

This project is provided for educational purposes only. Use it at your own risk.
The authors are not responsible for any account restriction or loss that results from using it.

---

<div align="center">

Made with care by <b>Yuurisandesu</b>

</div>
