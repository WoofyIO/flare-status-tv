#!/usr/bin/env bash
#
# Archive, sign and upload the tvOS app to TestFlight with an App Store
# Connect API key.
#
# Usage:
#   scripts/testflight.sh              archive, export and upload
#   scripts/testflight.sh --no-upload  archive and export the IPA only
#   scripts/testflight.sh --check      validate the setup, stop before archiving
#
# Configuration (environment variables; nothing is stored in this script):
#   ASC_KEY_ID       App Store Connect API key id                    (required)
#   ASC_ISSUER_ID    App Store Connect issuer id                     (required)
#   ASC_KEY_PATH     path to the AuthKey_<id>.p8 file                (required)
#   ASC_ENV_FILE     optional file of KEY=value lines that sets the three
#                    variables above; sourced if it exists
#   TEAM_ID          Apple Developer team id; defaults to DEVELOPMENT_TEAM
#                    in Config/Local.xcconfig
#   BUNDLE_ID        bundle identifier; defaults to PRODUCT_BUNDLE_IDENTIFIER
#                    in Config/Local.xcconfig
#   BUILD_NUMBER     CFBundleVersion for this upload; must be higher than the
#                    last uploaded build. Defaults to a UTC timestamp.
#   BUILD_DIR        where the archive and IPA go (default: build/release)
#   KEYCHAIN_PASSWORD  optional; unlocks the login keychain for headless runs
#
# Before the first upload, the bundle identifier must be registered and an
# app record must exist in App Store Connect. This script creates neither.
#
set -euo pipefail

cd "$(dirname "$0")/.."
ROOT="$PWD"

SCHEME="FlareStatus"
PROJECT="FlareStatus.xcodeproj"
LOCAL_CONFIG="Config/Local.xcconfig"
BUILD_DIR="${BUILD_DIR:-$ROOT/build/release}"
ARCHIVE="$BUILD_DIR/$SCHEME.xcarchive"
EXPORT_DIR="$BUILD_DIR/export"

UPLOAD=1
CHECK=0
for arg in "$@"; do
  case "$arg" in
    --no-upload) UPLOAD=0 ;;
    --check)     CHECK=1 ;;
    -h|--help)   sed -n '2,29p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "unknown argument: $arg" >&2; exit 2 ;;
  esac
done

die() { echo "error: $*" >&2; exit 1; }

# Reads one setting from an xcconfig file ("NAME = value").
xcconfig_value() {
  [ -f "$2" ] || return 0
  sed -n "s/^[[:space:]]*$1[[:space:]]*=[[:space:]]*\(.*[^[:space:]]\)[[:space:]]*$/\1/p" "$2" | tail -1
}

# --- credentials -------------------------------------------------------------
if [ -n "${ASC_ENV_FILE:-}" ]; then
  [ -f "$ASC_ENV_FILE" ] || die "ASC_ENV_FILE does not exist"
  set -a
  # shellcheck disable=SC1090
  . "$ASC_ENV_FILE"
  set +a
  # A key path in the file may be relative to the file.
  case "${ASC_KEY_PATH:-}" in
    ""|/*) ;;
    *) ASC_KEY_PATH="$(cd "$(dirname "$ASC_ENV_FILE")" && pwd)/$ASC_KEY_PATH" ;;
  esac
fi
[ -n "${ASC_KEY_ID:-}" ]    || die "ASC_KEY_ID is not set"
[ -n "${ASC_ISSUER_ID:-}" ] || die "ASC_ISSUER_ID is not set"
[ -n "${ASC_KEY_PATH:-}" ]  || die "ASC_KEY_PATH is not set"
[ -f "$ASC_KEY_PATH" ]      || die "the API key file named by ASC_KEY_PATH does not exist"

AUTH=(-authenticationKeyPath "$ASC_KEY_PATH"
      -authenticationKeyID "$ASC_KEY_ID"
      -authenticationKeyIssuerID "$ASC_ISSUER_ID")

# --- identity ----------------------------------------------------------------
TEAM_ID="${TEAM_ID:-$(xcconfig_value DEVELOPMENT_TEAM "$LOCAL_CONFIG")}"
BUNDLE_ID="${BUNDLE_ID:-$(xcconfig_value PRODUCT_BUNDLE_IDENTIFIER "$LOCAL_CONFIG")}"
[ -n "$TEAM_ID" ]   || die "no team id: set TEAM_ID or DEVELOPMENT_TEAM in $LOCAL_CONFIG"
[ -n "$BUNDLE_ID" ] || die "no bundle id: set BUNDLE_ID or PRODUCT_BUNDLE_IDENTIFIER in $LOCAL_CONFIG"
case "$BUNDLE_ID" in com.example.*) die "the bundle id is still the placeholder; set your own in $LOCAL_CONFIG" ;; esac

VERSION="$(xcconfig_value MARKETING_VERSION Config/Base.xcconfig)"
[ -n "$VERSION" ] || die "could not read MARKETING_VERSION from Config/Base.xcconfig"
BUILD_NUMBER="${BUILD_NUMBER:-$(date -u +%Y%m%d%H%M)}"
case "$BUILD_NUMBER" in *[!0-9.]*|"") die "BUILD_NUMBER must be digits (and dots)" ;; esac

echo "==> $SCHEME $VERSION ($BUILD_NUMBER)"

if [ "$CHECK" = 1 ]; then
  echo "==> check passed: credentials, team id and bundle id are present"
  exit 0
fi

# Runs a command with its output in a log file. xcodebuild prints the team id,
# bundle id and key path many times over; they stay in the (git-ignored) log
# and are masked in anything shown on screen.
run_logged() {
  local log="$1"; shift
  if "$@" >"$log" 2>&1; then
    return 0
  fi
  echo "error: step failed; last lines of $log (identifiers masked):" >&2
  tail -40 "$log" | mask >&2
  exit 1
}
mask() {
  sed -e "s|$ASC_KEY_PATH|<key-path>|g" -e "s|$ASC_ISSUER_ID|<issuer-id>|g" \
      -e "s|$ASC_KEY_ID|<key-id>|g" -e "s|$TEAM_ID|<team-id>|g" -e "s|$BUNDLE_ID|<bundle-id>|g"
}

# --- keychain (headless runs only) --------------------------------------------
if [ -n "${KEYCHAIN_PASSWORD:-}" ]; then
  KEYCHAIN="$HOME/Library/Keychains/login.keychain-db"
  security unlock-keychain -p "$KEYCHAIN_PASSWORD" "$KEYCHAIN"
  # Lets codesign use the signing key without the "allow access?" prompt.
  security set-key-partition-list -S apple-tool:,apple:,codesign: -s -k "$KEYCHAIN_PASSWORD" "$KEYCHAIN" >/dev/null
  echo "==> login keychain unlocked"
fi

# --- archive -----------------------------------------------------------------
rm -rf "$ARCHIVE" "$EXPORT_DIR"
mkdir -p "$BUILD_DIR"

echo "==> archiving (Release); log: $BUILD_DIR/archive.log"
run_logged "$BUILD_DIR/archive.log" xcodebuild -project "$PROJECT" -scheme "$SCHEME" \
  -configuration Release -destination 'generic/platform=tvOS' \
  -archivePath "$ARCHIVE" \
  -derivedDataPath "$BUILD_DIR/DerivedData" \
  CURRENT_PROJECT_VERSION="$BUILD_NUMBER" \
  DEVELOPMENT_TEAM="$TEAM_ID" \
  PRODUCT_BUNDLE_IDENTIFIER="$BUNDLE_ID" \
  -allowProvisioningUpdates "${AUTH[@]}" \
  archive

# --- export (and optionally upload) -------------------------------------------
DESTINATION=export
[ "$UPLOAD" = 1 ] && DESTINATION=upload
cat > "$BUILD_DIR/ExportOptions.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>method</key><string>app-store-connect</string>
  <key>destination</key><string>$DESTINATION</string>
  <key>teamID</key><string>$TEAM_ID</string>
  <key>signingStyle</key><string>automatic</string>
  <key>uploadSymbols</key><true/>
  <key>manageAppVersionAndBuildNumber</key><false/>
</dict>
</plist>
PLIST

echo "==> exporting (destination=$DESTINATION); log: $BUILD_DIR/export.log"
# xcodebuild copies the archive with the first rsync on PATH; a Homebrew rsync
# rejects the flags it passes. Pin Apple's tools for this step.
PATH="/usr/bin:/bin:/usr/sbin:/sbin:$PATH" run_logged "$BUILD_DIR/export.log" xcodebuild -exportArchive \
  -archivePath "$ARCHIVE" \
  -exportPath "$EXPORT_DIR" \
  -exportOptionsPlist "$BUILD_DIR/ExportOptions.plist" \
  -allowProvisioningUpdates "${AUTH[@]}"

if [ "$UPLOAD" = 1 ]; then
  echo "==> uploaded $VERSION ($BUILD_NUMBER) to App Store Connect"
  echo "    Processing takes a few minutes before the build appears in TestFlight."
else
  echo "==> exported $VERSION ($BUILD_NUMBER); IPA in $EXPORT_DIR"
  ls "$EXPORT_DIR"
fi
