#!/usr/bin/env bash
# Repackage the upstream PixelFlasher Linux build into a Debian package.
#
#   build-deb.sh <version> <upstream-file> <outdir> <deb-arch> [icon.png]
#
# Upstream ships two Linux flavours and neither is a .deb:
#   * PixelFlasher_Ubuntu_24_04 / _22_04  -> PyInstaller standalone binary
#   * PixelFlasher-x86_64.AppImage        -> AppImage (squashfs)
# Both are handled: a squashfs is unpacked directly (works for foreign
# architectures on an amd64 runner), otherwise the file is treated as a
# standalone executable. Either way the payload is installed read-only under
# /opt/pixelflasher with a launcher on PATH.
set -euo pipefail

VERSION=${1:?usage: build-deb.sh <version> <upstream-file> <outdir> <deb-arch> [icon]}
SRC=${2:?usage: build-deb.sh <version> <upstream-file> <outdir> <deb-arch> [icon]}
OUTDIR=${3:?usage: build-deb.sh <version> <upstream-file> <outdir> <deb-arch> [icon]}
DEB_ARCH=${4:-amd64}
ICON=${5:-}

PKGNAME=pixelflasher
PREFIX="/opt/${PKGNAME}"

WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
PKG="$WORK/pkg"

mkdir -p "$PKG$PREFIX" "$PKG/usr/bin" "$PKG/usr/share/applications" \
         "$PKG/usr/share/pixmaps" "$PKG/DEBIAN"

# 1. Install the payload.
extract_appimage() { # extract_appimage <image> <dest>
  local img=$1 dest=$2 off
  # shellcheck disable=SC2013 # squashfs offsets are plain numbers, one per line
  for off in $(LC_ALL=C grep -abo 'hsqs' "$img" | cut -d: -f1); do
    if unsquashfs -q -o "$off" -d "$dest" "$img" >/dev/null 2>&1; then
      return 0
    fi
    rm -rf "$dest"
  done
  return 1
}

APPDIR="$WORK/squashfs-root"
if LC_ALL=C grep -aq 'hsqs' "$SRC" && extract_appimage "$SRC" "$APPDIR"; then
  echo "-- packaging as AppImage"
  cp -a "$APPDIR/." "$PKG$PREFIX/"
  test -x "$PKG$PREFIX/AppRun" || chmod 755 "$PKG$PREFIX/AppRun"
  ln -s "$PREFIX/AppRun" "$PKG/usr/bin/$PKGNAME"
else
  echo "-- packaging as standalone binary"
  install -m 755 "$SRC" "$PKG$PREFIX/$PKGNAME"
  cat > "$PKG/usr/bin/$PKGNAME" <<EOF
#!/bin/sh
# Thin wrapper around the read-only install in $PREFIX.
# PixelFlasher needs raw USB access, so flashing requires root
# (run "sudo pixelflasher").
exec "$PREFIX/$PKGNAME" "\$@"
EOF
  chmod 755 "$PKG/usr/bin/$PKGNAME"
fi

# 2. Desktop entry.
cat > "$PKG/usr/share/applications/pixelflasher.desktop" <<'EOF'
[Desktop Entry]
Type=Application
Name=PixelFlasher
GenericName=Android Firmware Flasher
Comment=Flash factory images, patched boot images and OTA packages
Exec=pixelflasher
TryExec=pixelflasher
Icon=pixelflasher
Terminal=false
Categories=Development;Utility;
EOF

# 3. Icon.
if [ -n "$ICON" ] && [ -f "$ICON" ]; then
  cp -a "$ICON" "$PKG/usr/share/pixmaps/pixelflasher.png"
else
  echo "-- no icon supplied, desktop entry will fall back to a generic icon"
fi

# 4. Control file.
SIZE=$(du -sk "$PKG" | awk '{print $1}')
cat > "$PKG/DEBIAN/control" <<EOF
Package: $PKGNAME
Version: $VERSION
Architecture: $DEB_ARCH
Maintainer: Tommy Miland <tmiland@tmiland.com>
Installed-Size: $SIZE
Section: utils
Priority: optional
Homepage: https://github.com/badabing2005/PixelFlasher
Depends: libc6 (>= 2.35), libgcc-s1, libstdc++6, zlib1g, libglib2.0-0,
 libgtk-3-0, libgdk-pixbuf-2.0-0, libpango-1.0-0, libcairo2, libfontconfig1,
 libfreetype6, libdbus-1-3, libsecret-1-0, libnotify4, libx11-6, libx11-xcb1,
 libxcb1, libxcb-cursor0, libxcb-icccm4, libxcb-image0, libxcb-keysyms1,
 libxcb-randr0, libxcb-render0, libxcb-render-util0, libxcb-shape0,
 libxcb-xinerama0, libxcb-xkb1, libxkbcommon0, libxkbcommon-x11-0, libgl1,
 libegl1, libsm6, libice6, libxi6, libxtst6, libdrm2, libgbm1,
 libwayland-client0, libexpat1, libuuid1, libbz2-1.0, liblzma5
Recommends: android-sdk-platform-tools
Description: Android firmware flashing GUI for Pixel devices
 PixelFlasher is a GUI application to flash factory images, patched boot
 images and OTA packages on Pixel devices (and other Android devices).
 It manages Magisk patching, device backups and firmware downloads.
 .
 This package repackages the upstream Linux standalone build.
 .
 PixelFlasher needs raw USB access to the device; run it as root
 (for example "sudo pixelflasher") when flashing.
EOF

cat > "$PKG/DEBIAN/postinst" <<'EOF'
#!/bin/sh
set -e
if [ -x "$(command -v update-desktop-database)" ]; then
  update-desktop-database -q /usr/share/applications || true
fi
if [ -x "$(command -v gtk-update-icon-cache)" ]; then
  gtk-update-icon-cache -q -t -f /usr/share/icons/hicolor || true
fi
exit 0
EOF

cat > "$PKG/DEBIAN/postrm" <<'EOF'
#!/bin/sh
set -e
if [ -x "$(command -v update-desktop-database)" ]; then
  update-desktop-database -q /usr/share/applications || true
fi
if [ -x "$(command -v gtk-update-icon-cache)" ]; then
  gtk-update-icon-cache -q -t -f /usr/share/icons/hicolor || true
fi
exit 0
EOF

chmod 755 "$PKG/DEBIAN/postinst" "$PKG/DEBIAN/postrm"
find "$PKG" -type d -exec chmod 755 {} +
find "$PKG$PREFIX" -type f -exec chmod 644 {} + 2>/dev/null || true
chmod 755 "$PKG$PREFIX/AppRun" 2>/dev/null || true
chmod 755 "$PKG$PREFIX/$PKGNAME" 2>/dev/null || true
find "$PKG$PREFIX" -type f -name '*.so*' -exec chmod 755 {} + 2>/dev/null || true

# 5. Build.
mkdir -p "$OUTDIR"
DEB="$OUTDIR/${PKGNAME}-${VERSION}-linux-${DEB_ARCH}.deb"
dpkg-deb --root-owner-group -Zzstd -b "$PKG" "$DEB"
echo "built: $DEB"
