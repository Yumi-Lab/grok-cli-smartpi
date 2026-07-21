#!/usr/bin/env bash
# Official xAI Grok CLI on Yumi Smart Pi One / SmartPad — 32-bit ARM (armv7l)
#
# One-line install (also the UPDATER — re-run any time to move to the newest):
#   curl -fsSL https://raw.githubusercontent.com/Yumi-Lab/grok-cli-smartpi/main/install.sh | bash
#
# This script installs:
#   /opt/grok/qemu-aarch64-static   user-mode emulator 7.2 (fallback engine)
#   /opt/grok/qemu-aarch64-fork     Yumi qemu fork 9.2.4 (DEFAULT engine: correct
#                                   64-bit atomics → the native grok TUI is stable)
#   /opt/grok/QEMU_FORK_VERSION     installed fork tag
#   /opt/grok/grok-aarch64          official grok binary (downloaded from x.ai)
#   /opt/grok/VERSION               installed version (read by grok-check-update)
#   /usr/local/bin/grok-bin         wrapper (4 cores + nice; GROK_CPUS to throttle,
#                                   GROK_QEMU=7.2 to force the old engine)
#   /usr/local/bin/grok             dispatcher (no args + tty → native TUI;
#                                   `grok -p "q"` → warm daemon; else real CLI)
#   /usr/local/bin/grok-daemon      warm agent daemon (~3-4 s per prompt once warm
#                                   instead of ~41 s cold; idle timeout 10 min)
#   /usr/local/bin/grok-tui         legacy Python TUI (kept as fallback)
#   /usr/local/bin/grok-chat        minimal REPL
#   /usr/local/bin/grok-live        readable one-shot streaming
#   /usr/local/bin/grok-check-update  update probe (JSON one-liner, OTA contract)
#   earlyoom                        anti-freeze memory safety net
#
# OTA contract (shared by every Yumi-Lab/*-smartpi repo):
#   * re-running this script IS the update; it exits fast when already newest
#     (GROK_FORCE=1 to reinstall anyway);
#   * `grok-check-update` prints one JSON line {installed, latest,
#     update_available} — what the Yumi AI Gateway polls for its update badge;
#   * privileges: root (or sudo) for the FIRST install; a plain user that OWNS
#     /opt/grok for updates — the gateway service user updates WITHOUT sudo
#     (the /usr/local/bin wrappers are version-independent, only rewritten when
#     their content actually changes).
#
# See docs/METHODOLOGY.md for the reasoning behind every choice.
set -euo pipefail

RAW="https://raw.githubusercontent.com/Yumi-Lab/grok-cli-smartpi/main"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]:-.}")" 2>/dev/null && pwd || true)"
OPT=/opt/grok
BINDIR=/usr/local/bin

log()  { printf '\033[1;36m[grok-smartpi]\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m[grok-smartpi]\033[0m %s\n' "$*" >&2; }
fail() { printf '\033[1;31m[grok-smartpi]\033[0m %s\n' "$*" >&2; exit 1; }

[ "$(uname -m)" = "armv7l" ] || fail "This script targets armv7l (detected: $(uname -m)). On 64-bit, use https://x.ai/cli/install.sh"
command -v curl >/dev/null || fail "curl is required"
command -v python3 >/dev/null || fail "python3 is required"

# --- Privilege model. Root → no sudo. Non-root owning /opt/grok (the gateway
#     service user doing an OTA update) → plain writes, NO sudo at all.
#     Anything else → sudo (first install; may prompt for a password).
if [ "$(id -u)" -eq 0 ]; then SUDO=""
elif [ -d "$OPT" ] && [ -w "$OPT" ]; then SUDO=""
else SUDO="sudo"
fi
# Remember who owns an existing payload: a root re-run over a service-owned tree
# must give it back at the end, or the next unprivileged OTA update would break.
OPT_OWNER="$(stat -c %U "$OPT" 2>/dev/null || echo)"

# Install a file without sudo when the target allows it.
put() { # $1 src, $2 dest, $3 mode (default 755)
  local dir; dir="$(dirname "$2")"
  if [ -w "$dir" ] || { [ -e "$2" ] && [ -w "$2" ]; }; then
    install -m "${3:-755}" "$1" "$2"
  else
    $SUDO install -m "${3:-755}" "$1" "$2"
  fi
}

# Fetch one of our repo files to a temp path: local clone if present, else raw GitHub.
fetch_tmp() { # $1 repo-relative path → prints temp file path
  local tmpf; tmpf="$(mktemp)"
  if [ -n "$HERE" ] && [ -f "$HERE/$1" ]; then
    cat "$HERE/$1" > "$tmpf"
  else
    curl -fsSL "$RAW/$1" -o "$tmpf" || { rm -f "$tmpf"; return 1; }
  fi
  printf '%s' "$tmpf"
}

# Write $2 (a temp file) to $1 only when the content differs — routine updates
# never touch $BINDIR (root-owned), so the unprivileged OTA path stays clean.
put_if_changed() { # $1 dest, $2 src, $3 mode
  if [ -e "$1" ] && cmp -s "$1" "$2"; then rm -f "$2"; return 0; fi
  local rc=0
  put "$2" "$1" "${3:-755}" || rc=$?
  rm -f "$2"; return $rc
}

install_repo_bin() { # $1 repo-relative path (installed under $BINDIR, same name)
  local t; t="$(fetch_tmp "$1")" || { warn "cannot fetch $1 (non-fatal)"; return 0; }
  put_if_changed "$BINDIR/$(basename "$1")" "$t" 755 \
    || warn "cannot write $BINDIR/$(basename "$1") (no privileges) — existing copy kept."
}

$SUDO mkdir -p "$OPT"
[ -w "$OPT" ] || [ -n "$SUDO" ] || fail "$OPT is not writable and sudo is unavailable."

# 1. QEMU user mode 7.2 (bookworm) — the last generation able to run a 64-bit
#    guest on a 32-bit host (removed in QEMU 10 / Debian trixie).
#    Vendored in the repo: NO dependency on Debian mirrors.
QEMU_SHA256="a26fb51967c49bd100d8d9f4865f643c1a7084cc60de583cde55ac33c62f30a6"
if [ ! -x "$OPT/qemu-aarch64-static" ]; then
  log "Installing qemu-aarch64-static 7.2 (64-on-32)…"
  t="$(fetch_tmp vendor/qemu-aarch64-static)" || fail "cannot fetch vendor/qemu-aarch64-static"
  put "$t" "$OPT/qemu-aarch64-static" 755; rm -f "$t"
fi
if command -v sha256sum >/dev/null; then
  echo "$QEMU_SHA256  $OPT/qemu-aarch64-static" | sha256sum -c --quiet \
    || fail "qemu-aarch64-static checksum mismatch — corrupted download?"
fi

# 1bis. Yumi qemu fork 9.2.4 (Yumi-Lab/qemu-64on32-smartpi) — DEFAULT engine.
#    16 patches over v9.2.4: single-copy-atomic 64-bit accesses (the 7.2 engine
#    does torn reads — fast, but the reason long multithreaded runs crash),
#    termios2/TCGETS2 backport, configurable/persistent translation cache.
#    Net effect: the NATIVE grok TUI is stable (30+ min validated on the H3)
#    and long agent sessions stop being a gamble. GROK_QEMU=7.2 switches back.
#    Non-fatal on failure: everything still works on the vendored 7.2.
QEMU_FORK_TAG="v9.2.4-yumi.1"
QEMU_FORK_SHA256="cfdcb2f95299ada9ef5a0d3fb384df0a3a412b06a1c7271fc3e55c7d46680218"
QEMU_FORK_URL="https://github.com/Yumi-Lab/qemu-64on32-smartpi/releases/download/${QEMU_FORK_TAG}/qemu-aarch64"
cur_fork="$(head -1 "$OPT/QEMU_FORK_VERSION" 2>/dev/null | tr -d '[:space:]' || true)"
if [ "$cur_fork" != "$QEMU_FORK_TAG" ] || [ ! -x "$OPT/qemu-aarch64-fork" ] || [ -n "${GROK_FORCE:-}" ]; then
  log "Downloading qemu fork ${QEMU_FORK_TAG} (native-TUI grade 64-on-32, ~33 MB)…"
  tmpq="$(mktemp -p /var/tmp grok-qemu-fork.XXXXXX)"
  if curl -fSL --progress-bar -o "$tmpq" "$QEMU_FORK_URL"; then
    if command -v sha256sum >/dev/null \
       && ! echo "$QEMU_FORK_SHA256  $tmpq" | sha256sum -c --quiet 2>/dev/null; then
      rm -f "$tmpq"; warn "qemu fork checksum mismatch — keeping the 7.2-only setup."
    else
      put "$tmpq" "$OPT/qemu-aarch64-fork" 755; rm -f "$tmpq"
      tv="$(mktemp)"; printf '%s\n' "$QEMU_FORK_TAG" > "$tv"
      put "$tv" "$OPT/QEMU_FORK_VERSION" 644; rm -f "$tv"
      log "qemu fork installed → default engine (GROK_QEMU=7.2 to fall back)."
    fi
  else
    rm -f "$tmpq"; warn "cannot download the qemu fork (offline?) — 7.2 stays the only engine."
  fi
fi

# 2. Official grok binary (static Rust, aarch64).
#    Sources in order: xAI servers → xAI GCS mirror → this repo's Release
#    (backup mirror in case xAI changes its URLs). Pinned version as last resort.
PINNED_VER="0.2.102"
VER="${GROK_VERSION:-$(curl -fsSL --max-time 15 https://x.ai/cli/stable 2>/dev/null | head -1 | tr -d '[:space:]' || true)}"
[ -n "$VER" ] || { VER="$PINNED_VER"; log "x.ai unreachable — using pinned version $VER"; }

CURRENT="$(head -1 "$OPT/VERSION" 2>/dev/null | tr -d '[:space:]' || true)"
if [ "$CURRENT" = "$VER" ] && [ -x "$OPT/grok-aarch64" ] && [ -z "${GROK_FORCE:-}" ]; then
  log "grok $VER is already installed — refreshing helpers only (GROK_FORCE=1 to reinstall)."
else
  log "Downloading grok $VER (linux-aarch64, ~120 MB)…"
  # /var/tmp, NOT /tmp: /tmp is often a tmpfs (RAM) on Armbian — a 120 MB
  # download in RAM is asking for an OOM freeze on a 1 GB board.
  tmpb="$(mktemp -p /var/tmp grok-smartpi.XXXXXX)"
  curl -fSL --progress-bar -o "$tmpb" "https://x.ai/cli/grok-${VER}-linux-aarch64" \
    || curl -fSL --progress-bar -o "$tmpb" "https://storage.googleapis.com/grok-build-public-artifacts/cli/grok-${VER}-linux-aarch64" \
    || curl -fSL --progress-bar -o "$tmpb" "https://github.com/Yumi-Lab/grok-cli-smartpi/releases/download/v${VER}/grok-${VER}-linux-aarch64" \
    || { rm -f "$tmpb"; fail "Could not download grok (x.ai, GCS and Release mirror all failed)"; }
  put "$tmpb" "$OPT/grok-aarch64" 755
  rm -f "$tmpb"
  tv="$(mktemp)"; printf '%s\n' "$VER" > "$tv"
  put "$tv" "$OPT/VERSION" 644; rm -f "$tv"
fi

# 3. grok-bin: the real CLI, all 4 cores at low priority, fork engine first.
#    Watch thermals on sustained agentic loads: a 4-core run once drove the H3
#    to ~102 °C → machine freeze. Throttle without reinstalling: GROK_CPUS=0,1 grok …
#    GROK_QEMU=7.2 forces the vendored 7.2 engine (also the automatic fallback
#    when the fork is absent). Version-independent → put_if_changed leaves it
#    alone on routine updates.
w="$(mktemp)"
cat > "$w" <<'EOF'
#!/bin/sh
Q=/opt/grok/qemu-aarch64-fork
case "${GROK_QEMU:-fork}" in 7.2|72|static|system) Q=/opt/grok/qemu-aarch64-static ;; esac
[ -x "$Q" ] || Q=/opt/grok/qemu-aarch64-static
exec taskset -c "${GROK_CPUS:-0,1,2,3}" nice -n 5 \
  "$Q" /opt/grok/grok-aarch64 "$@"
EOF
put_if_changed "$BINDIR/grok-bin" "$w" 755 \
  || { [ -x "$BINDIR/grok-bin" ] && warn "cannot rewrite $BINDIR/grok-bin — existing wrapper kept." \
       || fail "cannot install $BINDIR/grok-bin (run once as root/sudo first)."; }

#    `grok` dispatcher:
#    * no arguments in a terminal → the NATIVE TUI (stable under the fork
#      engine); falls back to the legacy Python grok-tui when the fork is
#      absent or GROK_QEMU=7.2 / GROK_TUI=python asks for it. The warm daemon
#      is stopped first: one qemu at a time on a 1 GB board.
#    * `grok -p "question"` (exactly that shape) → warm daemon (~3-4 s once
#      warm instead of ~41 s cold). GROK_DAEMON=0 disables the fast path;
#      exit code 75 from the daemon (unavailable) falls back to a direct run.
#    * anything else → real CLI unchanged.
w="$(mktemp)"
cat > "$w" <<'EOF'
#!/bin/sh
if [ $# -eq 0 ] && [ -t 0 ] && [ -t 1 ]; then
  if [ -x /opt/grok/qemu-aarch64-fork ] && [ "${GROK_QEMU:-fork}" = "fork" ] \
     && [ "${GROK_TUI:-native}" != "python" ]; then
    command -v grok-daemon >/dev/null 2>&1 && grok-daemon stop >/dev/null 2>&1
    exec /usr/local/bin/grok-bin
  fi
  exec /usr/local/bin/grok-tui
fi
if [ $# -eq 2 ] && [ "$1" = "-p" ] && [ "${GROK_DAEMON:-1}" != "0" ] \
   && command -v grok-daemon >/dev/null 2>&1; then
  grok-daemon ask "$2"
  rc=$?
  [ "$rc" -ne 75 ] && exit "$rc"
fi
exec /usr/local/bin/grok-bin "$@"
EOF
put_if_changed "$BINDIR/grok" "$w" 755 \
  || { [ -x "$BINDIR/grok" ] && warn "cannot rewrite $BINDIR/grok — existing dispatcher kept." \
       || fail "cannot install $BINDIR/grok (run once as root/sudo first)."; }

# 4. Interfaces + update probe + warm daemon. grok-tui stays installed as the
#    legacy fallback for 7.2-only setups (the native TUI crashes under 7.2).
log "Installing grok-daemon / grok-tui / grok-chat / grok-live / grok-check-update…"
install_repo_bin bin/grok-daemon
install_repo_bin bin/grok-tui
install_repo_bin bin/grok-chat
install_repo_bin bin/grok-live
install_repo_bin bin/grok-check-update

# 5. Anti-freeze safety net: kills the largest process before memory exhaustion
#    (1 GB of RAM + SD-card swap = full machine freeze otherwise). Optional:
#    root/passwordless-sudo only — an unprivileged OTA update silently skips it.
if command -v apt-get >/dev/null; then
  if [ "$(id -u)" -eq 0 ]; then
    apt-get install -y -qq earlyoom >/dev/null 2>&1 \
      && systemctl enable --now earlyoom >/dev/null 2>&1 && log "earlyoom active" || true
  elif sudo -n true 2>/dev/null; then
    sudo apt-get install -y -qq earlyoom >/dev/null 2>&1 \
      && sudo systemctl enable --now earlyoom >/dev/null 2>&1 && log "earlyoom active" || true
  fi
fi

# A root re-run over a service-owned payload gives ownership back (the gateway
# service user must keep updating without sudo).
if [ "$(id -u)" -eq 0 ] && [ -n "$OPT_OWNER" ] && [ "$OPT_OWNER" != "root" ] \
   && id "$OPT_OWNER" >/dev/null 2>&1; then
  chown -R "$OPT_OWNER" "$OPT" && log "ownership of $OPT returned to $OPT_OWNER"
fi

# `timeout` so the installer never hangs on the check (grok --version is normally
# ~1.3 s on the H3, but a heavily-contended/throttled board can stall it).
log "Check: $(timeout 20 grok --version 2>/dev/null || echo 'grok --version did not answer in 20 s — try again on an idle board')"

cat <<'MSG'

✔ Install complete.

Sign in (grok.com / SuperGrok account, no API key):
    grok login --device-auth
  → open the displayed URL in a browser (any machine), approve the code:
    the CLI detects the authorization by itself.
  (If you get "429 slow_down" on the first try: wait 1 minute and retry.)

Usage:
    grok                      NATIVE interactive TUI (stable on the fork engine)
    grok -p "question"        one-shot answer through the warm daemon
                              (first call boots it, ~3-4 s once warm;
                               GROK_DAEMON=0 for the old direct behaviour)
    grok-daemon status|stop   inspect / stop the warm daemon (idle stop: 10 min)
    grok-live -p "task"       one-shot with readable streaming
    grok models               check the signed-in account

Engine:
    fork 9.2.4-yumi (default) — correct atomics, native TUI, long runs survive
    GROK_QEMU=7.2 grok …      — vendored qemu 7.2 (fallback engine)

Update:
    grok-check-update         →  {"installed":…,"latest":…,"update_available":…}
    re-run install.sh         installs the newest version (that IS the updater)

DO NOT:
    grok update               (it would install a binary outside the wrapper —
                               re-run install.sh to update instead)
MSG
