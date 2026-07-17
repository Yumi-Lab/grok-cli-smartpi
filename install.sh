#!/usr/bin/env bash
# Grok CLI officiel (xAI) sur Yumi Smart Pi One / SmartPad — ARM 32-bit (armv7l)
#
# Install en une ligne :
#   curl -fsSL https://raw.githubusercontent.com/Yumi-Lab/grok-cli-smartpi/main/install.sh | bash
#
# Ce script installe :
#   /opt/grok/qemu-aarch64-static   émulateur user-mode 7.2 (dernière génération 64-on-32)
#   /opt/grok/grok-aarch64          binaire grok officiel (téléchargé depuis x.ai)
#   /usr/local/bin/grok             wrapper (3 cœurs + nice, anti-surchauffe H3)
#   /usr/local/bin/grok-tui         TUI interactive complète (menus, flèches, streaming)
#   /usr/local/bin/grok-chat        REPL minimal
#   /usr/local/bin/grok-live        streaming lisible en one-shot
#   earlyoom                        filet anti-gel mémoire
#
# Voir docs/METHODOLOGIE.md pour le pourquoi de chaque choix.
set -euo pipefail

RAW="https://raw.githubusercontent.com/Yumi-Lab/grok-cli-smartpi/main"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]:-.}")" 2>/dev/null && pwd || true)"

log()  { printf '\033[1;36m[grok-smartpi]\033[0m %s\n' "$*"; }
fail() { printf '\033[1;31m[grok-smartpi]\033[0m %s\n' "$*" >&2; exit 1; }

[ "$(uname -m)" = "armv7l" ] || fail "Ce script cible armv7l (détecté : $(uname -m)). Sur 64-bit, utiliser https://x.ai/cli/install.sh"
command -v curl >/dev/null || fail "curl est requis"
command -v python3 >/dev/null || fail "python3 est requis"

# Récupère un fichier : copie locale du clone si dispo, sinon raw GitHub.
fetch() { # $1 chemin relatif repo, $2 destination
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

# 1. QEMU user-mode 7.2 (bookworm) — la dernière génération capable d'exécuter
#    un guest 64-bit sur un hôte 32-bit (supprimé dans QEMU 10 / Debian trixie).
if [ ! -x /opt/grok/qemu-aarch64-static ]; then
  log "Installation de qemu-aarch64-static 7.2 (64-on-32)…"
  fetch vendor/qemu-aarch64-static /opt/grok/qemu-aarch64-static
fi

# 2. Binaire grok officiel (Rust statique aarch64) depuis les serveurs xAI.
VER="${GROK_VERSION:-$(curl -fsSL https://x.ai/cli/stable | head -1 | tr -d '[:space:]')}"
[ -n "$VER" ] || fail "Impossible de déterminer la version stable de grok"
log "Téléchargement de grok $VER (linux-aarch64, ~120 Mo)…"
tmpb=$(mktemp)
curl -fSL --progress-bar -o "$tmpb" "https://x.ai/cli/grok-${VER}-linux-aarch64" \
  || curl -fSL --progress-bar -o "$tmpb" "https://storage.googleapis.com/grok-build-public-artifacts/cli/grok-${VER}-linux-aarch64"
sudo install -m755 "$tmpb" /opt/grok/grok-aarch64
rm -f "$tmpb"

# 3. Wrapper : bride l'émulation à 3 cœurs sur 4 avec priorité basse.
#    Sans ça, une tâche agentique monte le H3 à ~102 °C → gel machine.
#    Ajustable : GROK_CPUS=0,1 grok …
sudo tee /usr/local/bin/grok >/dev/null <<'EOF'
#!/bin/sh
exec taskset -c "${GROK_CPUS:-0,1,2}" nice -n 5 \
  /opt/grok/qemu-aarch64-static /opt/grok/grok-aarch64 "$@"
EOF
sudo chmod +x /usr/local/bin/grok

# 4. Interfaces : la TUI native crashe sous émulation (voir méthodologie),
#    on fournit des interfaces bâties sur le mode headless streaming (fiable).
log "Installation de grok-tui / grok-chat / grok-live…"
fetch bin/grok-tui  /usr/local/bin/grok-tui
fetch bin/grok-chat /usr/local/bin/grok-chat
fetch bin/grok-live /usr/local/bin/grok-live

# 5. Filet anti-gel : tue le plus gros process avant l'épuisement mémoire
#    (1 Go de RAM + swap sur SD = gel complet sinon).
if command -v apt-get >/dev/null; then
  sudo apt-get install -y -qq earlyoom >/dev/null 2>&1 \
    && sudo systemctl enable --now earlyoom >/dev/null 2>&1 \
    && log "earlyoom actif" || true
fi

log "Vérification : $(grok --version)"

cat <<'MSG'

✔ Installation terminée.

Connexion (compte grok.com / SuperGrok, sans clé API) :
    grok login --device-auth
  → ouvre l'URL affichée dans un navigateur (n'importe quelle machine),
    approuve le code : le CLI détecte l'autorisation tout seul.
  (Si "429 slow_down" au premier essai : attendre 1 minute et relancer.)

Utilisation :
    grok-tui                  interface interactive complète (recommandé)
    grok -p "question"        réponse unique
    grok-live -p "tâche"      one-shot avec streaming lisible
    grok models               vérifier le compte connecté

À NE PAS FAIRE :
    grok                      (TUI native : crashe sous émulation)
    grok update               (installerait un binaire hors wrapper —
                               relancer install.sh pour mettre à jour)
MSG

# Intégration yumi-ai-gateway (optionnelle)
if systemctl is-active yumi-ai-gateway >/dev/null 2>&1; then
  cat <<'MSG'
Gateway Yumi détectée : grok est utilisable comme provider CLI
(mode `grok agent stdio/serve`). Ajouter grok-cli au MODEL_ROUTING
dans /opt/yumi-ai-gateway/.env puis redémarrer le service.
MSG
fi
