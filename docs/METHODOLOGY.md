# Full methodology — official Grok CLI on 32-bit ARM

How to run a CLI distributed only as 64-bit binaries (x86_64/aarch64) on a SoC
that can only execute 32-bit code (Allwinner H3, Cortex-A7, armv7l).
Reference document: every choice below was tested on a Yumi SmartPad
(quad-core H3 @ 1.2 GHz, 1 GB RAM, Debian 13 trixie armhf) on 2026-07-17.

## 1. The problem

- The Cortex-A7 is **32-bit only** (ARMv7-A): no native aarch64 execution is
  possible, unlike 64-bit SoCs (H5, A53…) which can boot a 32-bit OS.
- The official installer (`curl https://x.ai/cli/install.sh | bash`) runs a
  `case $(uname -m)` that only accepts `x86_64|amd64` and `arm64|aarch64` → exit 1.
- No alternative distribution: no npm package, no official Docker image, no
  32-bit build. The source code is published (github.com/xai-org/grok-build,
  Apache 2.0, Rust) but an armv7 build is unrealistic: unported dependencies
  (aws-lc-sys, dav1d, jemalloc) and a toolchain pinned to x86_64/aarch64 only.

## 2. The key discovery: the binary is static Rust

```
$ file grok-0.2.102-linux-aarch64
ELF 64-bit LSB executable, ARM aarch64, statically linked, stripped   (~119 MB)
$ strings … | grep rustc   → /rustc/…/library/alloc/src/string.rs
```

A **static Rust binary (static-PIE musl)** is the best possible candidate for
user-mode emulation: no dynamic libraries to provide, and no JS runtime that
reserves tens of GB of virtual address space (unlike Bun/Node-compiled CLIs,
which cannot be emulated inside a 32-bit address space).

## 3. QEMU user mode: which version works

QEMU's linux-user mode runs a foreign-architecture binary by translating
instructions and syscalls, without a full VM. However, "64-bit guest on 32-bit
host" support was **removed in QEMU 10.0** (April 2025) — the Debian trixie
`qemu-user-static` package no longer ships `qemu-aarch64-static` on armhf.

Versions tested on the H3 (grok 0.2.102 binary):

| QEMU | Origin (armhf) | `--version` | headless `-p` | native TUI |
|---|---|---|---|---|
| 5.2 | Debian bullseye | ✔ | ✔ | ✖ ENOSYS |
| **7.2** | **Debian bookworm** | ✔ | **✔ reliable** | ✖ ENOSYS |
| 8.2 | Ubuntu ports | ✔ | ✖ silent/unstable | ✖ segfault |
| 9.2 | Ubuntu ports | ✔ | ✖ internal SIGSEGV | ✖ segfault |
| 10.0 | Debian trixie | — | — | 64-on-32 removed |

→ **7.2 bookworm is the pick**, vendored in `vendor/` (Debian pool URLs die at
every point release). Extracted without installing:
`dpkg-deb -x qemu-user-static_7.2+…_armhf.deb …`, then copy the single binary.

Why the native TUI fails everywhere:
- ENOSYS ("os error 38") on 7.2: the TUI switches the terminal to raw mode via
  ioctls (`TCGETS2`, used by rustix) that qemu ≤ 7.2 does not translate.
- Segfault on 8.2/9.2 (which do have those ioctls) after 2–5 min of JIT:
  64-on-32 does not guarantee **64-bit multithreaded atomics** — documented by
  QEMU as "best effort" — and TUI rendering is the most multithreaded path in
  the program.
- The headless modes (`-p`, `models`, `agent stdio/serve`), which are less
  concurrent, are stable on 7.2 (no crash observed in real use).

## 4. Installed layout

```
/opt/grok/qemu-aarch64-static      QEMU 7.2 user mode (vendor/)
/opt/grok/grok-aarch64             official binary (downloaded from x.ai at install)
/usr/local/bin/grok-bin            #!/bin/sh
                                   exec taskset -c ${GROK_CPUS:-0,1,2,3} nice -n 5 \
                                     /opt/grok/qemu-aarch64-static /opt/grok/grok-aarch64 "$@"
/usr/local/bin/grok                dispatcher: no args + tty → grok-tui, else grok-bin
/usr/local/bin/grok-tui            replacement TUI (Python, headless streaming)
/usr/local/bin/grok-chat|grok-live auxiliary interfaces
```

The official binary is downloaded directly (the x.ai installer rejects armv7l
but the artifacts are public): `https://x.ai/cli/grok-<version>-linux-aarch64`,
stable version from `https://x.ai/cli/stable`, GCS mirror
`grok-build-public-artifacts`, plus a fallback mirror in this repo's Releases.

## 5. Authentication (grok.com account, no API key)

`grok login --device-auth`: the official device-code flow for headless machines.
It prints an `accounts.x.ai` URL plus a short code; approve from any browser and
the CLI polls until confirmed. Credentials live in `~/.grok/auth.json`
(30 days, automatic refresh).

Pitfalls:
- The first call is sometimes rejected with `429 slow_down` → wait ~1 min, retry.
- When driving it remotely through tmux: end the command with `; sleep 99999`,
  otherwise the pane dies with the process and the output is lost.

## 6. Thermals and memory (vital on a 1 GB H3)

Measured incident: an agentic task (`--always-approve`) saturating all 4 cores
under emulation drove the SoC to **102 °C → full machine freeze** (the SmartPad
chassis throttles from 75 °C; passive trips at 75/80/85/90 °C). Separately, two
simultaneous qemu instances exhaust the 1 GB of RAM, and SD-card swap freezes
the machine before the OOM killer can act.

Countermeasures installed:
- Wrapper `taskset -c ${GROK_CPUS:-0,1,2,3} nice -n 5` — all 4 cores by default;
  throttle without reinstalling with `GROK_CPUS=0,1 grok …` (measured peak 78 °C
  on 2 cores, 68 °C idle — the 102 °C freeze was a 4-core agentic run, so keep
  an eye on temperature for long unattended loads).
- `earlyoom`: kills the largest process before memory exhaustion.
- Operating rule: one heavy instance at a time (`pgrep qemu-aarch64` before
  launching one), and bound batch workloads
  (`systemd-run --scope -p MemoryMax=600M`, `timeout`).

## 7. The interface: grok-tui

The `--output-format streaming-json` mode emits JSONL events token by token:
`{"type":"thought","data":…}` (reasoning), `{"type":"text",…}` (answer),
`{"type":"end","stopReason":…,"sessionId":…,"usage":{…}}`.

`grok-tui` (Python, stdlib only) rebuilds the official TUI experience on top of
this stream — design lifted from grok 0.2.102 (macOS): truecolor palette
(`#141414` background, layered grays, `#e0af68` gold), braille logo, top bar
(path + context counter fed by `usage`), timestamped user band,
`◆ Thought for Xs`, `Worked for Xs.`, boxed input with the model in the border,
an animated braille spinner status line while working, and a `Ctrl+X` keyboard
shortcuts panel.

Keyboard driving: arrows (menus, history), Enter, Esc (interrupt the turn),
PgUp/PgDn (transcript scroll), ctrl+s (Resume session — list from
`grok sessions list`, resume via `-r <sessionId>`), Shift+Tab (permission-mode
cycle), ctrl+q (quit).

Three implementation choices worth knowing:
- **Permission modes (Shift+Tab)**: `always-approve` (default — tools
  auto-approved; in headless there is no approval screen, so without it any
  tool-using turn ends `cancelled`), `plan` (`--permission-mode plan`, thinks
  without executing), `normal` (tools blocked). Start with `--safe` to default
  to `normal`.
- **Session tracking via `sessionId`** (taken from the `end` event) rather than
  `-c`: "continue the latest session in this directory" can be hijacked by any
  other grok process running on the machine.
- Behavior depends on `~/.grok/config.toml`: a machine with existing hooks or
  plugins can auto-approve tools regardless of flags. Always validate
  permission-mode behavior on a clean profile.

## 8. Maintenance

- **Updating grok**: re-run `install.sh` (never `grok update`, which would
  install a binary outside the wrapper into `~/.grok/bin`).
- **Never upgrade the vendored qemu beyond 7.2** (see the table in §3).
- Check thermal health after heavy use:
  `cat /sys/class/thermal/thermal_zone0/temp`.
