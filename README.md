# pixelflasher-deb

Repackages the upstream [PixelFlasher](https://github.com/badabing2005/PixelFlasher)
Linux build into a Debian/Ubuntu `.deb` for
[deb.tmiland.com](https://deb.tmiland.com), which can only ingest `.deb`
release assets (upstream ships a standalone binary / AppImage, plus exe/dmg).

- Builds from the `PixelFlasher_Ubuntu_22_04` standalone binary — the oldest
  glibc variant upstream publishes (`libc6 >= 2.35`), so the package installs on
  Debian 12/13 and current Ubuntu. The asset is verified against the published
  `.sha256` before packaging.
- Installs the binary read-only as `/opt/pixelflasher/pixelflasher`, a
  launcher on `PATH` (`/usr/bin/pixelflasher`), a desktop entry and the
  upstream icon. AppImages are also handled: an embedded squashfs is unpacked
  into `/opt/pixelflasher`.
- Publishes `pixelflasher-<version>-linux-amd64.deb` as a release asset. The
  asset basename deliberately differs from the apt repo's
  `pixelflasher_<version>_amd64.deb` stub name (see the deb.tmiland.com notes
  about the self-reinstall footgun).
- Runs daily at 04:17 UTC and on demand (`Actions → Build PixelFlasher .deb →
  Run workflow`, optionally with an explicit version).

PixelFlasher needs raw USB access to the device, so run it as root
(`sudo pixelflasher`) when flashing.
