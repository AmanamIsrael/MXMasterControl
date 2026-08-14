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
codesign \
  --force \
  --sign - \
  --identifier com.amanamisrael.MXMasterControl \
  --requirements '=designated => identifier "com.amanamisrael.MXMasterControl"' \
  "$application_directory"

printf '%s\n' "$application_directory"
