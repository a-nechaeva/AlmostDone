#!/usr/bin/env bash
set -euo pipefail
root="$(cd "$(dirname "$0")/../.." && pwd)"
cache="$root/.local/android-ci"
mkdir -p "$cache/gradle" "$cache/project-gradle" "$cache/sdk" "$cache/build"
if (( $# == 0 )); then
  set -- :app:testDebugUnitTest :app:verifyRoborazziDebug :app:lintDebug :app:assembleDebug -Proborazzi.test.compare=true
fi
reference_access=rw
if [[ "${GITHUB_ACTIONS:-}" == true ]]; then
  reference_access=ro
  for argument in "$@"; do
    case "$argument" in
      *[Rr]ecord*) echo "Recording screenshot references is forbidden in CI" >&2; exit 1 ;;
    esac
  done
fi
docker run --rm --platform linux/amd64 --read-only --tmpfs /tmp:exec,size=2g \
  --entrypoint bash \
  --user "$(id -u):$(id -g)" \
  -e GRADLE_USER_HOME=/gradle-cache -e ANDROID_HOME=/opt/android-sdk \
  -e HOME=/tmp -e TZ=UTC -e LANG=C.UTF-8 -e LC_ALL=C.UTF-8 \
  -e GITHUB_ACTIONS="${GITHUB_ACTIONS:-}" \
  -v "$root/mobile:/workspace" \
  -v "$root/mobile/app/src/test/screenshots:/workspace/app/src/test/screenshots:$reference_access" \
  -v "$root/.github/android:/android-ci:ro" \
  -v "$cache/sdk:/opt/android-sdk" \
  -v "$cache/build:/workspace/app/build" \
  -v /dev/null:/workspace/local.properties:ro \
  -v "$cache/gradle:/gradle-cache" \
  -v "$cache/project-gradle:/workspace/.gradle" \
  -w /workspace \
  gradle:8.14.3-jdk21@sha256:29ce2a983b946396c31d98d0b7625065ae131d6aa7e76bb21b90358d029ea8d8 \
  /android-ci/run.sh "$@"
