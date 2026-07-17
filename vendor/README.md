# vendor/qemu-aarch64-static

Émulateur user-mode QEMU pour exécuter le binaire grok (aarch64) sur hôte armv7l.

- **Version** : 7.2+dfsg-7+deb12u18+b3 (Debian 12 « bookworm », armhf)
- **Origine** : extrait sans modification du paquet officiel
  [`qemu-user-static`](https://packages.debian.org/bookworm/qemu-user-static)
  (`dpkg-deb -x qemu-user-static_7.2+dfsg-7+deb12u18+b3_armhf.deb`)
- **Licence** : GPL-2.0 — sources complètes disponibles chez Debian :
  <https://packages.debian.org/source/bookworm/qemu>
- **Pourquoi cette version** : c'est la dernière génération de QEMU dont le mode
  linux-user accepte un guest 64-bit sur un hôte 32-bit (support supprimé dans
  QEMU 10 / Debian trixie). Les versions 8.2 et 9.2 (Ubuntu ports) ont été testées
  et se comportent moins bien sur ce cas d'usage (voir docs/METHODOLOGIE.md).

Le fichier est vendorisé parce que les URLs du pool Debian changent à chaque
point-release (le `.deb` exact finit par disparaître du miroir principal).
