#!/bin/bash
# Produces a Developer ID export, then notarizes/staples it in a separate explicit step.
set -euo pipefail
cd "$(dirname "$0")/.."
usage() {
  cat <<'HELP'
Usage:
  Scripts/release-beta.sh prepare VERSION BUILD SUPPORT_EMAIL
  Scripts/release-beta.sh notarize OUTPUT_DIRECTORY KEYCHAIN_PROFILE

prepare requires a local Developer ID Application certificate, Apple Developer
sign-in in Xcode, and distribution provisioning for the app's iCloud container.
notarize uploads the prepared ZIP to Apple using an existing notarytool profile.
Final download and SHA-256 checksum are written only after verification passes.
HELP
}
fail() { echo "$*" >&2; exit 1; }
case "${1:-}" in
  prepare)
    [[ $# == 4 ]] || { usage; exit 1; }
    version=$2
    build=$3
    support_email=$4
    [[ $version =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || fail 'Use a numeric version such as 0.1.0.'
    [[ $build =~ ^[1-9][0-9]*$ ]] || fail 'Build must be a positive integer.'
    [[ $support_email =~ ^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$ ]] || fail 'Provide a valid support email address.'
    security find-identity -v -p codesigning | /usr/bin/grep -q '"Developer ID Application:' \
      || fail 'No Developer ID Application signing identity is installed. Create/download it in Xcode first.'
    output="$PWD/build/beta/$version-$build"
    [[ ! -e $output ]] || fail 'This release directory already exists. Use a new build number.'
    Scripts/check-diagnostics.sh
    mkdir -p "$output"
    xcodebuild -project SwiftWhisper/SwiftWhisper.xcodeproj -scheme SwiftWhisper \
      -configuration Release -destination 'generic/platform=macOS' \
      -archivePath "$output/SwiftWhisper.xcarchive" \
      -disableAutomaticPackageResolution -onlyUsePackageVersionsFromResolvedFile \
      MARKETING_VERSION="$version" CURRENT_PROJECT_VERSION="$build" \
      SWIFTWHISPER_SUPPORT_EMAIL="$support_email" ARCHS=arm64 ONLY_ACTIVE_ARCH=NO archive
    cat > "$output/ExportOptions.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>method</key><string>developer-id</string>
<key>signingStyle</key><string>automatic</string>
<key>teamID</key><string>TYS32Z4DEC</string>
<key>destination</key><string>export</string>
<key>stripSwiftSymbols</key><true/>
</dict></plist>
PLIST
    xcodebuild -exportArchive -archivePath "$output/SwiftWhisper.xcarchive" \
      -exportPath "$output/export" -exportOptionsPlist "$output/ExportOptions.plist" \
      -allowProvisioningUpdates
    app="$output/export/SwiftWhisper.app"
    [[ -d $app ]] || fail 'Xcode did not export SwiftWhisper.app.'
    codesign --verify --deep --strict --verbose=2 "$app"
    codesign -dv --verbose=4 "$app" 2> "$output/signature.txt"
    /usr/bin/grep -q 'Authority=Developer ID Application:' "$output/signature.txt" || fail 'Export is not Developer ID signed.'
    /usr/bin/grep -q 'runtime' "$output/signature.txt" || fail 'Hardened runtime is not enabled.'
    actual_email=$(plutil -extract SwiftWhisperSupportEmail raw "$app/Contents/Info.plist")
    [[ $actual_email == "$support_email" ]] || fail 'Support email is missing from the exported app.'
    codesign -d --entitlements :- "$app" > "$output/entitlements.plist" 2>/dev/null
    if [[ $(plutil -extract com.apple.security.get-task-allow raw "$output/entitlements.plist" 2>/dev/null || true) == true ]]; then
      fail 'Export has debug entitlements; do not distribute it.'
    fi
    ditto -c -k --keepParent "$app" "$output/notarization-upload.zip"
    cp SwiftWhisper/SwiftWhisper.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved "$output/Package.resolved"
    echo "Prepared $output. Not yet ready to publish: complete notarization and clean-Mac testing."
    ;;
  notarize)
    [[ $# == 3 ]] || { usage; exit 1; }
    output=$(cd "$2" && pwd)
    profile=$3
    app="$output/export/SwiftWhisper.app"
    [[ -d $app && -f $output/notarization-upload.zip ]] || fail 'Run prepare first.'
    [[ ! -e $output/SwiftWhisper-Beta.zip ]] || fail 'A final download already exists; use a new build for changes.'
    xcrun notarytool submit "$output/notarization-upload.zip" --keychain-profile "$profile" \
      --wait --output-format plist > "$output/notarization-result.plist"
    status=$(plutil -extract status raw "$output/notarization-result.plist")
    [[ $status == Accepted ]] || fail "Notarization status: $status. Inspect the submission log before proceeding."
    xcrun stapler staple "$app"
    xcrun stapler validate "$app"
    codesign --verify --deep --strict --verbose=2 "$app"
    spctl --assess --type execute --verbose=2 "$app"
    ditto -c -k --keepParent "$app" "$output/SwiftWhisper-Beta.zip"
    (cd "$output" && shasum -a 256 SwiftWhisper-Beta.zip > SwiftWhisper-Beta.zip.sha256)
    echo "Verified download: $output/SwiftWhisper-Beta.zip"
    echo 'Keep the archive and dSYMs private; publish only the final ZIP and checksum after manual testing.'
    ;;
  -h|--help) usage ;;
  *) usage; exit 1 ;;
esac
