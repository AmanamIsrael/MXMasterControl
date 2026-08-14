#!/bin/sh
set -eu

project_directory=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
cd "$project_directory"

swift build -c release --product MXMasterControl
binary_directory=$(swift build -c release --show-bin-path)
application_directory="$project_directory/dist/MX Master Control.app"
contents_directory="$application_directory/Contents"

mkdir -p "$contents_directory/MacOS" "$contents_directory/Resources"
cp "$binary_directory/MXMasterControl" "$contents_directory/MacOS/MXMasterControl"
cp "$project_directory/Resources/Info.plist" "$contents_directory/Info.plist"
signing_identity=${MXMASTER_SIGNING_IDENTITY:--}
if [ "$signing_identity" = "-" ]; then
  printf '%s\n' \
    'warning: no MXMASTER_SIGNING_IDENTITY configured; Input Monitoring may need reauthorization after rebuilds' >&2
fi

if [ "$signing_identity" = "-" ]; then
  codesign \
    --force \
    --sign - \
    --identifier com.amanamisrael.MXMasterControl \
    --requirements '=designated => identifier "com.amanamisrael.MXMasterControl"' \
    "$application_directory"
else
  codesign \
    --force \
    --sign "$signing_identity" \
    --identifier com.amanamisrael.MXMasterControl \
    "$application_directory"
fi

printf '%s\n' "$application_directory"
