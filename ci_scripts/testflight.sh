#!/bin/bash
# Builds a signed App Store version and, with UPLOAD=1, uploads it to App Store
# Connect (TestFlight). Called by .github/workflows/testflight.yml, runs on a
# Mac as well:
#
#   ci_scripts/testflight.sh            archive, export, check the signature
#   UPLOAD=1 ci_scripts/testflight.sh   ... and upload
#
# Why not Xcode Cloud: it signs with a cloud-managed distribution certificate,
# and that path writes the umlaut of the account holder's name decomposed into
# the designated requirement. The app then fails its own signature check and
# App Store Connect rejects it with ITMS-90035. A local "Apple Distribution"
# certificate (from the keychain, in CI from a secret) signs correctly.
#
# Optional environment:
#   VERSION        overrides MARKETING_VERSION, e.g. 1.2.3
#   BUILD_NUMBER   default: UTC time as yyMMddHHmm, so it always increases
#   TEAM_ID        Apple team ID for the export
#   ASC_KEY_PATH, ASC_KEY_ID, ASC_ISSUER_ID
#                  App Store Connect API key (role Admin). Without it, Xcode
#                  uses the account signed in to Xcode, which only exists on a Mac.
set -euo pipefail

cd "$(dirname "$0")/.."
XCODE_ARGS=(-project Recipe2Mealie.xcodeproj -scheme Recipe2Mealie)

VERSION="${VERSION:-}"
BUILD_NUMBER="${BUILD_NUMBER:-$(date -u +%y%m%d%H%M)}"
UPLOAD="${UPLOAD:-0}"
TEAM_ID="${TEAM_ID:-}"
WORK="${RUNNER_TEMP:-${TMPDIR:-/tmp}}/testflight"

if [[ -n "$VERSION" && ! "$VERSION" =~ ^[0-9]+(\.[0-9]+){0,2}$ ]]; then
  echo "error: VERSION must look like 1.2.3, not '$VERSION'" >&2
  exit 1
fi
if [[ ! "$BUILD_NUMBER" =~ ^[0-9]+$ ]]; then
  echo "error: BUILD_NUMBER must be a number, not '$BUILD_NUMBER'" >&2
  exit 1
fi

AUTH=(-allowProvisioningUpdates)
if [[ -n "${ASC_KEY_PATH:-}" ]]; then
  AUTH+=(-authenticationKeyPath "$ASC_KEY_PATH"
         -authenticationKeyID "$ASC_KEY_ID"
         -authenticationKeyIssuerID "$ASC_ISSUER_ID")
fi

OVERRIDES=(CURRENT_PROJECT_VERSION="$BUILD_NUMBER")
if [[ -n "$VERSION" ]]; then
  OVERRIDES+=(MARKETING_VERSION="$VERSION")
fi

rm -rf "$WORK"
mkdir -p "$WORK"

echo "==> Archive (build $BUILD_NUMBER${VERSION:+, version $VERSION})"
xcodebuild archive "${XCODE_ARGS[@]}" -configuration Release \
  -destination 'generic/platform=iOS' -archivePath "$WORK/App.xcarchive" \
  -skipPackagePluginValidation -skipMacroValidation \
  "${AUTH[@]}" "${OVERRIDES[@]}" -quiet

# $1: "export" writes the .ipa to $WORK/export, "upload" sends it to App Store Connect.
export_archive() {
  local team=""
  if [[ -n "$TEAM_ID" ]]; then
    team="<key>teamID</key><string>$TEAM_ID</string>"
  fi
  cat > "$WORK/$1.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>method</key><string>app-store-connect</string>
  <key>destination</key><string>$1</string>
  <key>signingStyle</key><string>automatic</string>
  <key>manageAppVersionAndBuildNumber</key><false/>
  <key>uploadSymbols</key><true/>
  $team
</dict>
</plist>
PLIST
  xcodebuild -exportArchive -archivePath "$WORK/App.xcarchive" \
    -exportOptionsPlist "$WORK/$1.plist" -exportPath "$WORK/$1" \
    "${AUTH[@]}" -quiet
}

echo "==> Export"
export_archive export

echo "==> Check signature"
mkdir "$WORK/check"
unzip -q "$WORK"/export/*.ipa -d "$WORK/check"
APP=$(echo "$WORK"/check/Payload/*.app)
codesign --verify --deep --strict "$APP"
# Every app and extension: signed for distribution and satisfying its own
# designated requirement (exactly what failed with ITMS-90035).
while IFS= read -r -d '' BUNDLE; do
  NAME=$(basename "$BUNDLE")
  INFO=$(codesign -dvv "$BUNDLE" 2>&1)
  if [[ "$INFO" != *$'\nAuthority=Apple Distribution'* ]]; then
    echo "error: $NAME is not signed with an Apple Distribution certificate" >&2
    exit 1
  fi
  DR=$(codesign -d -r- "$BUNDLE" 2>&1 | sed -n 's/^designated => //p')
  if ! codesign --verify -R="$DR" "$BUNDLE"; then
    echo "error: $NAME does not satisfy its own designated requirement" >&2
    exit 1
  fi
  echo "ok: $NAME"
done < <(find "$APP" \( -name '*.app' -o -name '*.appex' \) -print0)

SHORT=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Info.plist")
BUILT=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$APP/Info.plist")
if [[ "$BUILT" != "$BUILD_NUMBER" ]]; then
  echo "error: Info.plist has build $BUILT instead of $BUILD_NUMBER" >&2
  exit 1
fi
RESULT="Version $SHORT ($BUILT) built and signed"

if [[ "$UPLOAD" == 1 ]]; then
  echo "==> Upload"
  export_archive upload
  RESULT="Version $SHORT ($BUILT) uploaded to App Store Connect. It appears in TestFlight after processing (5–30 min)."
fi

echo "$RESULT"
if [[ -n "${GITHUB_STEP_SUMMARY:-}" ]]; then
  echo "$RESULT" >> "$GITHUB_STEP_SUMMARY"
fi
