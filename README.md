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
| `grok` | **Full interactive interface** (like the official one) — arrow-key menus, live streaming, session resume (`ctrl+s`), scrolling (`PgUp/PgDn`), interrupt (`Esc`), permission-mode cycling (`Shift+Tab`) |
| `grok -p "question"` | One-shot answer (full agent mode: reads/writes files, runs commands) |
| `grok-live -p "task"` | One-shot with readable streaming (dimmed reasoning) |
| `grok-chat` | Minimal multi-turn REPL |
| `grok models` | Check the signed-in account and model |

`grok` with no arguments opens the interactive interface (`grok-tui`, built on
headless streaming); with arguments it runs the real CLI (`grok-bin`) — the native
TUI would crash under emulation. ⚠️ **Never run** `grok update` (it would install a
binary outside the wrapper — re-run `install.sh` instead).

## How it works

1. The official grok binary is **static Rust** (static-PIE musl): it emulates
   remarkably well in user mode — `grok --version` answers in ~1.3 s on the H3.
2. QEMU removed "64-bit guest on 32-bit host" emulation in version 10. We ship
   the **qemu-aarch64-static 7.2 from Debian bookworm**, the last generation that
   supports it (vendored in [`vendor/`](vendor/)).
3. A wrapper pins the emulation to **3 cores + low priority**: on all 4 cores, an
   agentic task drives the H3 up to 102 °C (machine freeze). `earlyoom` completes
   the safety net.
4. The native TUI crashes under emulation (64-bit multithreaded atomics are not
   guaranteed in 64-on-32 mode); [`grok-tui`](bin/grok-tui) rebuilds the full
   interface on top of the **headless streaming** mode
   (`--output-format streaming-json`), which is 100 % reliable.

Full details (tested versions, thermal measurements, pitfalls):
[docs/METHODOLOGY.md](docs/METHODOLOGY.md)

## yumi-ai-gateway integration

The CLI plugs into the [Yumi gateway](https://github.com/Yumi-Lab/yumi-ai-gateway)
as a provider: the gateway drives `grok agent stdio/serve` and exposes it as an
OpenAI-compatible API (`/v1/chat/completions`). Add `grok-cli` to `MODEL_ROUTING`
in the `.env`, then restart the service. The installer detects the gateway and
prints the steps.

## Target hardware

Tested on a Yumi SmartPad (Allwinner H3, 4× Cortex-A7 @ 1.2 GHz, 1 GB RAM, Debian
13 trixie armhf). Any armv7l SBC with ≥1 GB RAM should work. Measured performance:
1.3 s startup · `grok models` 12 s · one-shot generation ~40 s · 78 °C thermal
peak (3 cores, 68 °C idle).

## Licensing

- Scripts and interfaces in this repo: MIT (Yumi Lab)
- `vendor/qemu-aarch64-static`: GPL-2.0, extracted as-is from the Debian bookworm
  package (provenance and sources: [vendor/README.md](vendor/README.md))
- The grok binary is downloaded at install time from the official xAI servers
  (it is not redistributed here)
