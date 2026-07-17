# vendor/qemu-aarch64-static

QEMU user-mode emulator used to run the (aarch64) grok binary on an armv7l host.

- **Version**: 7.2+dfsg-7+deb12u18+b3 (Debian 12 "bookworm", armhf)
- **Origin**: extracted unmodified from the official
  [`qemu-user-static`](https://packages.debian.org/bookworm/qemu-user-static)
  package (`dpkg-deb -x qemu-user-static_7.2+dfsg-7+deb12u18+b3_armhf.deb`)
- **License**: GPL-2.0 — full sources available from Debian:
  <https://packages.debian.org/source/bookworm/qemu>
- **Why this version**: it is the last QEMU generation whose linux-user mode
  accepts a 64-bit guest on a 32-bit host (support removed in QEMU 10 /
  Debian trixie). Versions 8.2 and 9.2 (Ubuntu ports) were tested and behave
  worse for this use case (see docs/METHODOLOGY.md).

The file is vendored because Debian pool URLs change with every point release
(the exact `.deb` eventually disappears from the main mirror).
