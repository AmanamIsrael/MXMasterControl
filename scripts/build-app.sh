#!/bin/sh
# Build "dist/MX Master Control.app": the release executable, Info.plist, and the
# icon. `--install` also puts it in /Applications.
#
# macOS keys Input Monitoring and Accessibility to the app's signature. The script
# signs with MXMASTER_SIGNING_IDENTITY, else a valid "Apple Development" or
# "Developer ID" certificate, else "MX Master Control Local Signing"
# (scripts/signing-cert.sh). With any of them, access carries over between builds.
set -eu
cd "$(dirname "$0")/.."
# Absolute: actool resolves relative paths against $PWD, which a caller can leave stale.
APP="$(pwd -P)/dist/MX Master Control.app"
INSTALL="/Applications/MX Master Control.app"
BUNDLE_ID=com.amanamisrael.MXMasterControl
for arg; do
  case "$arg" in
    --install) ;;
    *) echo "Usage: scripts/build-app.sh [--install]" >&2; exit 2 ;;
  esac
done

swift build -c release --product MXMasterControl
BIN=$(swift build -c release --show-bin-path)
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN/MXMasterControl" "$APP/Contents/MacOS/MXMasterControl"
cp Resources/Info.plist "$APP/Contents/Info.plist"
# The Liquid Glass icon (an Icon Composer document) compiles to Assets.car, plus
# AppIcon.icns for macOS 15. Info.plist names both.
xcrun actool "$(pwd -P)/Resources/AppIcon.icon" --compile "$APP/Contents/Resources" \
  --platform macosx --minimum-deployment-target 15.0 --app-icon AppIcon \
  --output-partial-info-plist "${TMPDIR:-/tmp}/mxmastercontrol-icon.plist" >/dev/null

IDENTITY=${MXMASTER_SIGNING_IDENTITY:-$(security find-identity -v -p codesigning | grep -Eo '"(Apple Development|Developer ID Application): [^"]+"' | head -n 1 | tr -d '"')}
# Self-signed, so not "valid" to find-identity -v, but codesign uses it.
if [ -z "$IDENTITY" ] && security find-identity -p codesigning | grep -q '"MX Master Control Local Signing"'; then
  IDENTITY="MX Master Control Local Signing"
fi
if [ -n "$IDENTITY" ]; then
  codesign --force --sign "$IDENTITY" --identifier "$BUNDLE_ID" "$APP"
else
  # Ad hoc pins access to the build's hash. Requiring only the identifier keeps
  # access across rebuilds, but any app with this identifier would match it.
  codesign --force --sign - --identifier "$BUNDLE_ID" \
    --requirements "=designated => identifier \"$BUNDLE_ID\"" "$APP"
  echo "Ad hoc: run scripts/signing-cert.sh once so privacy access is tied to a certificate." >&2
fi
echo "$APP (signed: ${IDENTITY:-ad hoc})"

case " $* " in *" --install "*)
  if pgrep -qf "$INSTALL/Contents/MacOS/MXMasterControl"; then
    echo "Quit MX Master Control first: it is running from $INSTALL." >&2
    exit 1
  fi
  rm -rf "$INSTALL"
  ditto "$APP" "$INSTALL"
  echo "$INSTALL"
  ;;
esac
