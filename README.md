# Grok CLI for Yumi Smart Pi One (32-bit ARM)

The **official xAI Grok CLI** running on **Allwinner H3 / armv7l** (Smart Pi One,
Yumi SmartPad) — a platform the official installer rejects (`Unsupported architecture`).

Sign in with a **grok.com / SuperGrok account** (no API key required),
real-time streaming, full interactive interface, resumable sessions.

```
╭──────────────────────────────────────────────────────────────╮
│  ⠀⠀⣼⡿⠁…   Grok Build Beta  0.2.102 · armv7 (qemu)          │
│  ⠀⠀⣿⡇⠀…   Grok 4.5 is here!                                │
│  ⠀⢠⠞⠁…    › New session                            enter    │
│  ⠐⠁⠀⠀…      Resume session                         ctrl+s   │
╰──────────────────────────────────────────────────────────────╯
```

## Install

```bash
curl -fsSL https://raw.githubusercontent.com/Yumi-Lab/grok-cli-smartpi/main/install.sh | bash
```

Then sign in with your grok.com account (headless, no local browser needed):

```bash
grok login --device-auth
```

An `accounts.x.ai` URL plus a short code are displayed: open the URL on any
machine, approve — the CLI detects the authorization by itself.

## Usage

| Command | Purpose |
|---|---|
| `grok` | **The NATIVE interactive TUI** — the official interface, stable on the fork engine (falls back to the legacy [`grok-tui`](bin/grok-tui) on 7.2-only setups or with `GROK_TUI=python`) |
| `grok -p "question"` | One-shot answer through the **warm daemon**: ~3-4 s once warm instead of ~41 s cold (`GROK_DAEMON=0` for the old direct behaviour) |
| `grok-daemon status\|stop` | Inspect / stop the warm agent daemon (stops itself after 10 min idle) |
| `grok-live -p "task"` | One-shot with readable streaming (dimmed reasoning) |
| `grok-chat` | Minimal multi-turn REPL |
| `grok models` | Check the signed-in account and model |

Engine selection: the Yumi **qemu fork 9.2.4** is the default; `GROK_QEMU=7.2`
forces the vendored 7.2 (also the automatic fallback when the fork is absent).
⚠️ **Never run** `grok update` (it would install a binary outside the wrapper —
re-run `install.sh` instead).

## Updating (OTA)

- **Check:** `grok-check-update` prints one JSON line —
  `{"cli":"grok","installed":"0.2.102","latest":"0.2.103","update_available":true}`.
  This is the probe the [Yumi AI Gateway](https://github.com/Yumi-Lab/yumi-ai-gateway)
  console polls for its update badge.
- **Update:** re-run `install.sh` — that IS the updater: it exits fast when
  already newest (`GROK_FORCE=1` to reinstall, `GROK_VERSION=x.y.z` to pin) and
  writes the installed version to `/opt/grok/VERSION`.
- **Privileges:** root/sudo for the *first* install only. Updates run as any
  user that owns `/opt/grok` — the gateway service user updates without sudo
  (the `/usr/local/bin` wrappers are version-independent and only rewritten
  when their content actually changes).

## How it works

1. The official grok binary is **static Rust** (static-PIE musl): it emulates
   remarkably well in user mode — `grok --version` answers in ~1.3 s on the H3.
2. QEMU removed "64-bit guest on 32-bit host" emulation in version 10. Two
   engines are installed: the **[Yumi qemu fork
   9.2.4](https://github.com/Yumi-Lab/qemu-64on32-smartpi)** (default — 16
   patches restoring *correct* 64-bit atomics on Cortex-A7, which is what makes
   the native TUI and long multithreaded runs stable) and the
   **qemu-aarch64-static 7.2 from Debian bookworm** (vendored in
   [`vendor/`](vendor/), fallback via `GROK_QEMU=7.2`).
3. A wrapper runs the emulation at **low priority on all 4 cores** (default
   `GROK_CPUS=0,1,2,3`). Watch thermals on sustained agentic loads — a 4-core
   run once drove the H3 up to 102 °C (machine freeze); set `GROK_CPUS=0,1` to
   throttle without reinstalling. `earlyoom` completes the safety net.
4. A cold one-shot pays ~33 s of local bootstrap (config, plugins, session
   store) under emulation. [`grok-daemon`](bin/grok-daemon) keeps one
   `grok agent stdio` process warm (ACP over a unix socket, fresh session per
   prompt, pre-warmed in the background) so `grok -p` answers in **~3-4 s +
   generation** once warm. It stops itself after 10 min idle.
5. On 7.2 the native TUI crashes (torn 64-bit atomics); the legacy
   [`grok-tui`](bin/grok-tui) rebuilt on **headless streaming**
   (`--output-format streaming-json`) remains installed as the fallback
   interface.

Full details (tested versions, thermal measurements, pitfalls):
[docs/METHODOLOGY.md](docs/METHODOLOGY.md)

## Target hardware & measured performance

Tested on a Yumi SmartPad (Allwinner H3, 4× Cortex-A7 @ 1.2 GHz, 1 GB RAM, Debian
13 trixie armhf). Any armv7l SBC with ≥ 1 GB RAM should work. Measured performance
(2 cores unless noted): startup 1.3-1.8 s · `grok models` ~14 s · cold one-shot
bootstrap ~41 s · **warm one-shot through the daemon ~3-4 s + generation** ·
native TUI 30+ min stable on the fork engine · warm daemon ~85-100 MB resident ·
68 °C idle, 78 °C thermal peak on 2 cores (`GROK_CPUS=0,1`; default is all 4).

On 1 GB of RAM with SD-card swap, memory exhaustion freezes the machine before the
kernel OOM killer reacts — the installer enables **earlyoom**. Rule on the pad: one
heavy CLI at a time.

## Sister projects (same board, other CLIs)

- [claude-code-smartpi](https://github.com/Yumi-Lab/claude-code-smartpi) — official
  Anthropic Claude Code, native (pinned to the last pure-JS npm release).
- [kimi-cli-smartpi](https://github.com/Yumi-Lab/kimi-cli-smartpi) — Moonshot Kimi
  CLI, native Python via uv.
- [kimi-code-smartpi](https://github.com/Yumi-Lab/kimi-code-smartpi) — Moonshot Kimi
  Code CLI (the TypeScript successor to kimi-cli), native via npm + Node 22.
- [vibe-cli-smartpi](https://github.com/Yumi-Lab/vibe-cli-smartpi) — official Mistral
  Vibe CLI, native Python via uv.

All five are driven together by the [Yumi AI
Gateway](https://github.com/Yumi-Lab/yumi-ai-gateway).

## Licensing

- Scripts and interfaces in this repo: MIT (Yumi Lab)
- `vendor/qemu-aarch64-static`: GPL-2.0, extracted as-is from the Debian bookworm
  package (provenance and sources: [vendor/README.md](vendor/README.md))
- The grok binary is downloaded at install time from the official xAI servers
  (it is not redistributed here)
