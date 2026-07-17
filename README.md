# Grok CLI pour Yumi Smart Pi One (ARM 32-bit)

Le **CLI Grok officiel de xAI** fonctionnel sur **Allwinner H3 / armv7l** (Smart Pi One,
SmartPad Yumi) — une plateforme que l'installeur officiel refuse (`Unsupported architecture`).

Connexion avec un **compte grok.com / SuperGrok** (pas de clé API nécessaire),
streaming temps réel, interface interactive complète, sessions reprenables.

```
╭──────────────────────────────────────────────────────────────╮
│  ⠀⠀⣼⡿⠁…   Grok Build Beta  0.2.102 · armv7 (qemu)          │
│  ⠀⠀⣿⡇⠀…   Grok 4.5 is here!                                │
│  ⠀⢠⠞⠁…    › New session                            enter    │
│  ⠐⠁⠀⠀…      Resume session                         ctrl+s   │
╰──────────────────────────────────────────────────────────────╯
```

## Installation

```bash
curl -fsSL https://raw.githubusercontent.com/Yumi-Lab/grok-cli-smartpi/main/install.sh | bash
```

Puis connexion avec ton compte grok.com (headless, sans navigateur local) :

```bash
grok login --device-auth
```

Une URL `accounts.x.ai` + un code court s'affichent : ouvre l'URL sur n'importe quelle
machine, approuve — le CLI détecte l'autorisation tout seul.

## Utilisation

| Commande | Usage |
|---|---|
| `grok` | **Interface interactive complète** (comme l'officiel) — menus aux flèches, streaming en direct, reprise de session (`ctrl+s`), scroll (`PgUp/PgDn`), interruption (`Esc`) |
| `grok -p "question"` | Réponse unique (mode agent complet : lit/écrit des fichiers, exécute des commandes) |
| `grok-live -p "tâche"` | One-shot avec streaming lisible (raisonnement grisé) |
| `grok-chat` | REPL minimal multi-tours |
| `grok models` | Vérifier le compte et le modèle |

`grok` sans argument ouvre l'interface interactive (`grok-tui`, bâtie sur le streaming
headless) ; avec des arguments il exécute le CLI réel (`grok-bin`) — la TUI native, elle,
crasherait sous émulation. ⚠️ **À ne pas faire** : `grok update` (installerait un binaire
hors wrapper — relancer `install.sh` à la place).

## Comment ça marche

1. Le binaire grok officiel est du **Rust statique** (static-PIE musl) : il s'émule
   remarquablement bien en user-mode — `grok --version` répond en ~1,3 s sur le H3.
2. QEMU a supprimé l'émulation « guest 64-bit sur hôte 32-bit » dans la version 10.
   On embarque le **qemu-aarch64-static 7.2 de Debian bookworm**, dernière génération
   qui la supporte (vendorisé dans [`vendor/`](vendor/)).
3. Un wrapper bride l'émulation à **3 cœurs + priorité basse** : à 4 cœurs, une tâche
   agentique fait monter le H3 à 102 °C (gel machine). `earlyoom` complète le filet.
4. La TUI native crashe sous émulation (atomics multithread non garantis en 64-on-32) ;
   [`grok-tui`](bin/grok-tui) reconstruit l'interface complète au-dessus du mode
   **headless streaming** (`--output-format streaming-json`), qui est 100 % fiable.

Le détail complet (versions testées, mesures thermiques, pièges) :
[docs/METHODOLOGIE.md](docs/METHODOLOGIE.md)

## Intégration yumi-ai-gateway

Le CLI s'intègre à la [gateway Yumi](https://github.com/Yumi-Lab/yumi-ai-gateway) comme
provider : la gateway pilote `grok agent stdio/serve` et l'expose en API compatible
OpenAI (`/v1/chat/completions`). Ajouter `grok-cli` au `MODEL_ROUTING` du `.env` puis
redémarrer le service. L'installeur détecte la gateway et affiche la marche à suivre.

## Matériel visé

Testé sur SmartPad Yumi (Allwinner H3, 4× Cortex-A7 1,2 GHz, 1 Go RAM, Debian 13 trixie
armhf). Tout SBC armv7l avec ≥1 Go de RAM devrait convenir. Performances mesurées :
démarrage 1,3 s · `grok models` 12 s · génération one-shot ~40 s · pic thermique 78 °C
(3 cœurs, repos 68 °C).

## Licences

- Scripts et interfaces de ce repo : MIT (Yumi Lab)
- `vendor/qemu-aarch64-static` : GPL-2.0, extrait tel quel du paquet Debian bookworm
  (provenance et sources : [vendor/README.md](vendor/README.md))
- Le binaire grok est téléchargé à l'installation depuis les serveurs officiels xAI
  (il n'est pas redistribué ici)
