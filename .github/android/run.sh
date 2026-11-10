#!/usr/bin/env bash
set -euo pipefail
install_sdk() {
  local archive="$1" checksum="$2" folder="$3" destination="$4"
  if [[ ! -f "$ANDROID_HOME/$destination/source.properties" || ! -f "$ANDROID_HOME/$destination/.ci-$checksum" ]]; then
    curl --retry 3 --connect-timeout 30 -fsSL "https://dl.google.com/android/repository/$archive" -o "/tmp/$archive"
    echo "$checksum  /tmp/$archive" | sha1sum -c -
    unzip -q "/tmp/$archive" -d /tmp/android-package
    mkdir -p "$ANDROID_HOME/$destination"
    cp -a "/tmp/android-package/$folder/." "$ANDROID_HOME/$destination/"
    touch "$ANDROID_HOME/$destination/.ci-$checksum"
  fi
}
install_sdk platform-36_r02.zip 2c1a80dd4d9f7d0e6dd336ec603d9b5c55a6f576 android-36 platforms/android-36
install_sdk build-tools_r35_linux.zip 2cfaa0bbb2336e9ec18ed3ecea84fa2e2af607bc android-15 build-tools/35.0.0
install_sdk platform-tools_r37.0.1-linux.zip 477254aa5f903c15cf51001717bdf347fb6b53e0 platform-tools platform-tools
mkdir -p "$ANDROID_HOME/licenses"
echo 24333f8a63b6825ea9c5514f83c2829b004d1fee > "$ANDROID_HOME/licenses/android-sdk-license"
exec ./gradlew --no-daemon --no-watch-fs --console=plain --max-workers=2 --continue "$@"
