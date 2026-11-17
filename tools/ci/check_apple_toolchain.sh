#!/usr/bin/env bash
# Fail before export/signing if the selected Xcode cannot satisfy Apple's SDK rule.
set -euo pipefail

xcode_info="$(xcodebuild -version)"
xcode_version="$(printf '%s\n' "$xcode_info" | awk '/^Xcode / {print $2; exit}')"
sdk_version="$(xcrun --sdk iphoneos --show-sdk-version)"
printf '%s\n' "$xcode_info"
printf 'iPhoneOS SDK %s\n' "$sdk_version"

for item in "Xcode:$xcode_version" "iPhoneOS SDK:$sdk_version"; do
    name="${item%%:*}"
    version="${item#*:}"
    if [[ ! "$version" =~ ^[0-9]+(\.[0-9]+)*$ ]]; then
        echo "Unable to determine a numeric $name version: $version" >&2
        exit 1
    fi
    major="${version%%.*}"
    if (( 10#$major < 27 )); then
        echo "$name $version is too old; Xcode 27 and iOS 27 SDK or later are required." >&2
        exit 1
    fi
done
