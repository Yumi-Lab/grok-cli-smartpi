#!/usr/bin/env bash
# Official xAI Grok CLI on Yumi Smart Pi One / SmartPad — 32-bit ARM (armv7l)
#
# One-line install:
#   curl -fsSL https://raw.githubusercontent.com/Yumi-Lab/grok-cli-smartpi/main/install.sh | bash
#
# This script installs:
#   /opt/grok/qemu-aarch64-static   user-mode emulator 7.2 (last 64-on-32 generation)
#   /opt/grok/grok-aarch64          official grok binary (downloaded from x.ai)
#   /usr/local/bin/grok-bin         wrapper (3 cores + nice, H3 anti-overheat)
#   /usr/local/bin/grok             dispatcher (no args + tty → TUI, else real CLI)
#   /usr/local/bin/grok-tui         full interactive TUI (menus, arrows, streaming)
#   /usr/local/bin/grok-chat        minimal REPL
#   /usr/local/bin/grok-live        readable one-shot streaming
#   earlyoom                        anti-freeze memory safety net
#
# See docs/METHODOLOGY.md for the reasoning behind every choice.
set -euo pipefail

RAW="https://raw.githubusercontent.com/Yumi-Lab/grok-cli-smartpi/main"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]:-.}")" 2>/dev/null && pwd || true)"

log()  { printf '\033[1;36m[grok-smartpi]\033[0m %s\n' "$*"; }
fail() { printf '\033[1;31m[grok-smartpi]\033[0m %s\n' "$*" >&2; exit 1; }

[ "$(uname -m)" = "armv7l" ] || fail "This script targets armv7l (detected: $(uname -m)). On 64-bit, use https://x.ai/cli/install.sh"
command -v curl >/dev/null || fail "curl is required"
command -v python3 >/dev/null || fail "python3 is required"

# Fetch a file: local copy from a clone if available, otherwise raw GitHub.
fetch() { # $1 repo-relative path, $2 destination
  if [ -n "$HERE" ] && [ -f "$HERE/$1" ]; then
    sudo install -m755 "$HERE/$1" "$2"
  else
    tmpf=$(mktemp)
    curl -fsSL "$RAW/$1" -o "$tmpf"
    sudo install -m755 "$tmpf" "$2"
    rm -f "$tmpf"
  fi
}

sudo mkdir -p /opt/grok

# 1. QEMU user mode 7.2 (bookworm) — the last generation able to run a 64-bit
#    guest on a 32-bit host (removed in QEMU 10 / Debian trixie).
#    Vendored in the repo: NO dependency on Debian mirrors.
QEMU_SHA256="a26fb51967c49bd100d8d9f4865f643c1a7084cc60de583cde55ac33c62f30a6"
if [ ! -x /opt/grok/qemu-aarch64-static ]; then
  log "Installing qemu-aarch64-static 7.2 (64-on-32)…"
  fetch vendor/qemu-aarch64-static /opt/grok/qemu-aarch64-static
fi
if command -v sha256sum >/dev/null; then
  echo "$QEMU_SHA256  /opt/grok/qemu-aarch64-static" | sha256sum -c --quiet \
    || fail "qemu-aarch64-static checksum mismatch — corrupted download?"
fi

# 2. Official grok binary (static Rust, aarch64).
#    Sources in order: xAI servers → xAI GCS mirror → this repo's Release
#    (backup mirror in case xAI changes its URLs). Pinned version as last resort.
PINNED_VER="0.2.102"
VER="${GROK_VERSION:-$(curl -fsSL --max-time 15 https://x.ai/cli/stable 2>/dev/null | head -1 | tr -d '[:space:]' || true)}"
[ -n "$VER" ] || { VER="$PINNED_VER"; log "x.ai unreachable — using pinned version $VER"; }
log "Downloading grok $VER (linux-aarch64, ~120 MB)…"
tmpb=$(mktemp)
curl -fSL --progress-bar -o "$tmpb" "https://x.ai/cli/grok-${VER}-linux-aarch64" \
  || curl -fSL --progress-bar -o "$tmpb" "https://storage.googleapis.com/grok-build-public-artifacts/cli/grok-${VER}-linux-aarch64" \
  || curl -fSL --progress-bar -o "$tmpb" "https://github.com/Yumi-Lab/grok-cli-smartpi/releases/download/v${VER}/grok-${VER}-linux-aarch64" \
  || fail "Could not download grok (x.ai, GCS and Release mirror all failed)"
sudo install -m755 "$tmpb" /opt/grok/grok-aarch64
rm -f "$tmpb"

# 3. grok-bin: the real CLI, pinned to 3 of 4 cores with low priority.
#    Without this, an agentic task drives the H3 up to ~102 °C → machine freeze.
#    Tunable: GROK_CPUS=0,1 grok …
sudo tee /usr/local/bin/grok-bin >/dev/null <<'EOF'
#!/bin/sh
exec taskset -c "${GROK_CPUS:-0,1,2}" nice -n 5 \
  /opt/grok/qemu-aarch64-static /opt/grok/grok-aarch64 "$@"
EOF
sudo chmod +x /usr/local/bin/grok-bin

#    `grok` dispatcher: no arguments in a terminal → TUI (like the official CLI);
#    with arguments (-p, models, login, agent…) → real CLI. The native TUI
#    would crash under emulation.
sudo tee /usr/local/bin/grok >/dev/null <<'EOF'
#!/bin/sh
if [ $# -eq 0 ] && [ -t 0 ] && [ -t 1 ]; then
  exec /usr/local/bin/grok-tui
fi
exec /usr/local/bin/grok-bin "$@"
EOF
sudo chmod +x /usr/local/bin/grok

# 4. Interfaces: the native TUI crashes under emulation (see methodology),
#    so we ship interfaces built on the headless streaming mode (reliable).
log "Installing grok-tui / grok-chat / grok-live…"
fetch bin/grok-tui  /usr/local/bin/grok-tui
fetch bin/grok-chat /usr/local/bin/grok-chat
fetch bin/grok-live /usr/local/bin/grok-live

# 5. Anti-freeze safety net: kills the largest process before memory exhaustion
#    (1 GB of RAM + SD-card swap = full machine freeze otherwise).
if command -v apt-get >/dev/null; then
  sudo apt-get install -y -qq earlyoom >/dev/null 2>&1 \
    && sudo systemctl enable --now earlyoom >/dev/null 2>&1 \
    && log "earlyoom active" || true
fi

log "Check: $(grok --version)"

cat <<'MSG'

✔ Install complete.

Sign in (grok.com / SuperGrok account, no API key):
    grok login --device-auth
  → open the displayed URL in a browser (any machine), approve the code:
    the CLI detects the authorization by itself.
  (If you get "429 slow_down" on the first try: wait 1 minute and retry.)

Usage:
    grok                      full interactive interface (like the official CLI)
    grok -p "question"        one-shot answer
    grok-live -p "task"       one-shot with readable streaming
    grok models               check the signed-in account

DO NOT:
    grok update               (it would install a binary outside the wrapper —
                               re-run install.sh to update instead)
MSG

# yumi-ai-gateway integration (optional)
if systemctl is-active yumi-ai-gateway >/dev/null 2>&1; then
  cat <<'MSG'
Yumi gateway detected: grok can be used as a CLI provider
(`grok agent stdio/serve` mode). Add grok-cli to MODEL_ROUTING
in /opt/yumi-ai-gateway/.env, then restart the service.
MSG
fi
