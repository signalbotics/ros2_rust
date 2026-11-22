#!/bin/bash
# Build + test all distros locally, same steps as CI. Output: packaging/out/<distro>/
#   packaging/build-local.sh            # all distros in versions.env
#   packaging/build-local.sh jazzy      # one distro
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"; ROOT="$(dirname "$HERE")"
source "$HERE/versions.env"
for d in ${@:-$DISTROS}; do
  rm -rf "$HERE/out/$d"; mkdir -p "$HERE/out/$d"
  docker run --rm -e ROS_DISTRO="$d" -e REV="${REV:-1}" -v "$ROOT:/src/ros2_rust:ro" -v "$HERE/out/$d:/out" \
    "ros:$d-ros-base" /src/ros2_rust/packaging/build-debs.sh
  docker run --rm -e ROS_DISTRO="$d" -v "$ROOT:/src/ros2_rust:ro" -v "$HERE/out/$d:/debs:ro" \
    "ros:$d-ros-base" /src/ros2_rust/packaging/test/test-debs.sh
done
