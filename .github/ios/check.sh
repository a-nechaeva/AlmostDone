#!/usr/bin/env bash
set -euo pipefail

suite="${1:?Expected build, unit, ui, screenshots or lint}"
output="$PWD/.local/ios-ci"
reports="$output/reports"
derived="$output/DerivedData"
project="ios/AlmostReady/AlmostReady.xcodeproj"

xcode_version=$(xcodebuild -version)
printf 'Runner image: %s (%s)\n%s\n' "${ImageOS:-unknown}" "${ImageVersion:-unknown}" "$xcode_version"
if [[ "$xcode_version" != $'Xcode 26.2\nBuild version 17C52' ]]; then
  echo "Expected Xcode 26.2 (17C52)"
  exit 1
fi

mkdir -p "$reports"
if [[ "$suite" == lint ]]; then
  xcrun swift-format --version
  xcrun swift-format lint --strict --recursive --configuration .github/ios/swift-format.json ios
  exit
fi

xcode_args=(
  -project "$project"
  -scheme AlmostReady
  -configuration Debug
  -sdk iphonesimulator
  -derivedDataPath "$derived"
  -resultBundlePath "$reports/$suite.xcresult"
  CODE_SIGNING_ALLOWED=NO
)

if [[ "$suite" == build ]]; then
  xcodebuild "${xcode_args[@]}" -destination 'generic/platform=iOS Simulator' build
  # Preserve the executable bit and framework symlinks in the downloadable app.
  tar -czf "$output/AlmostReady-simulator.tar.gz" -C "$derived/Build/Products/Debug-iphonesimulator" AlmostReady.app
  exit
fi

case "$suite" in
  unit) test_filters=(-only-testing:AlmostReadyTests) ;;
  ui) test_filters=(-only-testing:AlmostReadyUITests/NavigationTests) ;;
  screenshots) test_filters=(-only-testing:AlmostReadyUITests/ProductsScreenshotTests) ;;
  *) echo "Unknown suite: $suite"; exit 1 ;;
esac

runtime='com.apple.CoreSimulator.SimRuntime.iOS-26-2'
device_type='com.apple.CoreSimulator.SimDeviceType.iPhone-17-Pro'
xcrun simctl list runtimes -j | jq -e --arg id "$runtime" \
  '.runtimes[] | select(.identifier == $id and .isAvailable and .version == "26.2") |
   {name, version, buildversion, identifier}'
echo "Creating $device_type"
device=$(xcrun simctl create AlmostReady-CI "$device_type" "$runtime")
cleanup() {
  xcrun simctl shutdown "$device" || true
  xcrun simctl delete "$device" || true
}
trap cleanup EXIT
xcrun simctl boot "$device"
xcrun simctl bootstatus "$device" -b

if [[ "$suite" == screenshots ]]; then
  xcrun simctl ui "$device" appearance light
  xcrun simctl ui "$device" content_size large
  xcrun simctl status_bar "$device" override --time '9:41' --dataNetwork wifi \
    --wifiMode active --wifiBars 3 --cellularMode active --cellularBars 4 \
    --batteryState discharging --batteryLevel 100
fi

# Parallel UI workers can clone the simulator and lose the display overrides.
xcodebuild "${xcode_args[@]}" -destination "platform=iOS Simulator,id=$device" \
  -parallel-testing-enabled NO "${test_filters[@]}" test

xcrun xcresulttool get test-results summary --path "$reports/$suite.xcresult" |
  jq -e '{passedTests, failedTests, skippedTests} | debug |
    .passedTests > 0 and .failedTests == 0 and .skippedTests == 0'
