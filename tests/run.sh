#!/usr/bin/env bash
# Runs the test suite in an Ubuntu 26.04 arm64 container.
# Usage: tests/run.sh [--quick]   (--quick skips the real tuner build)
set -euo pipefail

root=$(cd "$(dirname "$0")/.." && pwd)

docker build --quiet --tag radio-os-test --file "$root/tests/Dockerfile" "$root" > /dev/null
docker run --rm --volume "$root:/radio-os:ro" --workdir /radio-os radio-os-test tests/in-container.sh "$@"
