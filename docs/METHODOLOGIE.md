# Méthodologie complète — Grok CLI officiel sur ARM 32-bit

Comment faire tourner un CLI distribué uniquement en binaires 64-bit (x86_64/aarch64)
sur un SoC qui ne sait exécuter que du 32-bit (Allwinner H3, Cortex-A7, armv7l).
Document de référence : chaque choix ci-dessous a été testé sur un SmartPad Yumi
(H3 quad 1,2 GHz, 1 Go RAM, Debian 13 trixie armhf) le 17/07/2026.

## 1. Le problème

- Le Cortex-A7 est **32-bit only** (ARMv7-A) : aucune exécution native d'aarch64
  possible, contrairement aux SoC 64-bit (H5, A53…) qui peuvent booter un OS 32-bit.
- L'installeur officiel (`curl https://x.ai/cli/install.sh | bash`) fait un
  `case $(uname -m)` qui n'accepte que `x86_64|amd64` et `arm64|aarch64` → exit 1.
- Aucune distribution alternative : pas de paquet npm, pas de Docker officiel, pas
  de build 32-bit. Le code source est publié (github.com/xai-org/grok-build, Apache
  2.0, Rust) mais la compilation armv7 est irréaliste : dépendances non portées
  (aws-lc-sys, dav1d, jemalloc), toolchain épinglée x86_64/aarch64 uniquement.

## 2. La découverte clé : le binaire est du Rust statique

```
$ file grok-0.2.102-linux-aarch64
ELF 64-bit LSB executable, ARM aarch64, statically linked, stripped   (~119 Mo)
$ strings … | grep rustc   → /rustc/…/library/alloc/src/string.rs
```

Un binaire **Rust statique (static-PIE musl)** est le meilleur candidat possible pour
l'émulation user-mode : pas de bibliothèques dynamiques à fournir, pas de runtime JS
qui réserve des dizaines de Go d'espace d'adressage virtuel (contrairement aux CLIs
compilés Bun/Node, inémulables sur un espace 32-bit).

## 3. QEMU user-mode : quelle version fonctionne

Le mode linux-user de QEMU exécute un binaire d'une autre architecture en traduisant
instructions et syscalls, sans VM complète. Mais le support « guest 64-bit sur hôte
32-bit » a été **retiré de QEMU 10.0** (avril 2025) — le paquet `qemu-user-static`
de Debian trixie ne contient plus `qemu-aarch64-static` en armhf.

Versions testées sur le H3 (binaire grok 0.2.102) :

| QEMU | Origine (armhf) | `--version` | headless `-p` | TUI native |
|---|---|---|---|---|
| 5.2 | Debian bullseye | ✔ | ✔ | ✖ ENOSYS |
| **7.2** | **Debian bookworm** | ✔ | **✔ fiable** | ✖ ENOSYS |
| 8.2 | Ubuntu ports | ✔ | ✖ muet/instable | ✖ segfault |
| 9.2 | Ubuntu ports | ✔ | ✖ SIGSEGV interne | ✖ segfault |
| 10.0 | Debian trixie | — | — | plus de 64-on-32 |

→ **7.2 bookworm est le choix**, vendorisé dans `vendor/` (les URLs du pool Debian
meurent à chaque point-release). Extraction sans installation :
`dpkg-deb -x qemu-user-static_7.2+…_armhf.deb …` puis copie du seul binaire utile.

Pourquoi la TUI native échoue partout :
- ENOSYS (« os error 38 ») sur 7.2 : la TUI passe le terminal en mode brut via des
  ioctls (`TCGETS2`, utilisés par rustix) que qemu ≤ 7.2 ne traduit pas.
- Segfault sur 8.2/9.2 (qui ont ces ioctls) après 2-5 min de JIT : le 64-on-32 ne
  garantit pas les **atomics 64-bit multithread** — documenté par QEMU comme
  « best effort » — et le rendu TUI est le chemin le plus multithreadé du programme.
- Les modes headless (`-p`, `models`, `agent stdio/serve`), moins concurrents,
  sont stables sur 7.2 (aucun crash constaté en usage réel).

## 4. Architecture installée

```
/opt/grok/qemu-aarch64-static      QEMU 7.2 user-mode (vendor/)
/opt/grok/grok-aarch64             binaire officiel (téléchargé de x.ai à l'install)
/usr/local/bin/grok                #!/bin/sh
                                   exec taskset -c ${GROK_CPUS:-0,1,2} nice -n 5 \
                                     /opt/grok/qemu-aarch64-static /opt/grok/grok-aarch64 "$@"
/usr/local/bin/grok-tui            TUI de remplacement (Python, streaming headless)
/usr/local/bin/grok-chat|grok-live interfaces annexes
```

Le binaire officiel se télécharge directement (l'installeur x.ai refuse armv7l mais
les artefacts sont publics) : `https://x.ai/cli/grok-<version>-linux-aarch64`, version
stable via `https://x.ai/cli/stable`, miroir GCS `grok-build-public-artifacts`.

## 5. Authentification (compte grok.com, sans clé API)

`grok login --device-auth` : flow device-code officiel pour machines headless.
Affiche une URL `accounts.x.ai` + un code court ; on approuve depuis n'importe quel
navigateur, le CLI polle jusqu'à confirmation. Credentials dans `~/.grok/auth.json`
(30 jours, refresh automatique).

Pièges :
- Premier appel parfois rejeté `429 slow_down` → attendre ~1 min et relancer.
- En pilotage à distance via tmux : terminer la commande par `; sleep 99999`,
  sinon le pane meurt avec le process et la sortie est perdue.

## 6. Thermique et mémoire (vital sur H3/1 Go)

Incident mesuré : une tâche agentique (`--always-approve`) occupant les 4 cœurs sous
émulation a porté le SoC à **102 °C → gel complet** (le châssis SmartPad throttle dès
75 °C, trips passifs 75/80/85/90 °C). Par ailleurs deux instances qemu simultanées
saturent le Go de RAM et le swap sur SD fige la machine avant que l'OOM killer n'agisse.

Contre-mesures installées :
- Wrapper `taskset -c 0,1,2 nice -n 5` (3 cœurs) — pic mesuré 78 °C à 2 cœurs,
  repos 68 °C ; ajustable sans réinstaller : `GROK_CPUS=0,1 grok …`
- `earlyoom` : tue le plus gros process avant l'épuisement mémoire.
- Règle d'exploitation : une seule instance lourde à la fois (`pgrep qemu-aarch64`
  avant de lancer), et borner les traitements batch
  (`systemd-run --scope -p MemoryMax=600M`, `timeout`).

## 7. L'interface : grok-tui

Le mode `--output-format streaming-json` émet des événements JSONL token par token :
`{"type":"thought","data":…}` (raisonnement), `{"type":"text",…}` (réponse),
`{"type":"end","stopReason":…,"sessionId":…,"usage":{…}}`.

`grok-tui` (Python, stdlib uniquement) reconstruit l'expérience de la TUI officielle
au-dessus de ce flux — design relevé sur grok 0.2.102 (macOS) : palette truecolor
(fond `#141414`, gris hiérarchisés, doré `#e0af68`), logo braille, barre du haut
(chemin + compteur de contexte alimenté par `usage`), bande utilisateur horodatée,
`◆ Thought for Xs`, `Worked for Xs.`, saisie encadrée avec le modèle en bordure.

Pilotage clavier : flèches (menus, historique), Enter, Esc (interrompre le tour),
PgUp/PgDn (scroll du transcript), ctrl+s (Resume session — liste `grok sessions
list`, reprise par `-r <sessionId>`), ctrl+q (quitter).

Deux choix d'implémentation importants :
- **`--always-approve` par défaut** : en headless il n'existe pas d'écran
  d'approbation d'outils — sans ce flag, tout tour utilisant un outil se termine
  `cancelled`. Option `--safe` pour le désactiver.
- **Suivi de session par `sessionId`** (récupéré dans l'événement `end`) plutôt que
  `-c` : « continuer la dernière session du dossier » est détournable par tout autre
  process grok (la gateway en crée en permanence).

## 8. Intégration yumi-ai-gateway

La gateway pilote le CLI en mode `grok agent stdio` / `serve` (JSON-RPC/WebSocket,
sans terminal — donc insensible aux limites TUI) et l'expose en
`/v1/chat/completions`. Côté pad : ajouter `grok-cli` au `MODEL_ROUTING` du `.env`
et redémarrer `yumi-ai-gateway`.

## 9. Maintenance

- **Mise à jour de grok** : relancer `install.sh` (jamais `grok update`, qui
  installerait un binaire hors wrapper dans `~/.grok/bin`).
- **Ne jamais monter le qemu vendorisé au-delà de 7.2** (cf. tableau §3).
- Vérifier la santé thermique après usage intensif :
  `cat /sys/class/thermal/thermal_zone0/temp`.
