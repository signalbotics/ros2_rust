#!/bin/bash
# Assemble a signed apt repository from CI artifacts.
#   apt-repo.sh <artifacts-dir> <output-dir>
# <artifacts-dir>/<distro>-<arch>/*.deb  (layout produced by the build workflow)
# Requires: reprepro, gpg with the signing key imported; APT_KEY_ID set to its fingerprint.
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"; source "$HERE/versions.env"
IN="$(realpath "$1")"; OUT="$(realpath -m "$2")"
: "${APT_KEY_ID:?set APT_KEY_ID}"
rm -rf "$OUT"; mkdir -p "$OUT/conf"
for d in $DISTROS; do
  c="CODENAME_$d"; cat >> "$OUT/conf/distributions" <<EOT
Origin: signalbotics
Label: signalbotics-ros2-rust
Codename: ${!c}
Architectures: amd64 arm64
Components: main
Description: Unofficial ROS 2 Rust (rclrs) packages for ROS 2 $d
SignWith: $APT_KEY_ID

EOT
done
for d in $DISTROS; do
  c="CODENAME_$d"
  for dir in "$IN/$d"-*; do
    for deb in "$dir"/*.deb; do
      # Arch 'all' packages are identical across build arches; add them once (from amd64).
      if [[ "$deb" == *_all.deb && "$dir" != *-amd64 ]]; then continue; fi
      reprepro -b "$OUT" includedeb "${!c}" "$deb"
    done
  done
done
rm -rf "$OUT/conf" "$OUT/db"
gpg --export "$APT_KEY_ID" > "$OUT/signalbotics-ros2-rust.gpg"
gpg --armor --export "$APT_KEY_ID" > "$OUT/signalbotics-ros2-rust.asc"
cp "$HERE/README.md" "$OUT/README.md"
cat > "$OUT/index.html" <<EOT
<!doctype html><meta charset="utf-8"><title>signalbotics ROS 2 Rust apt repo</title>
<h1>Unofficial ROS 2 Rust apt repository</h1>
<p>Packages: ros-&lt;distro&gt;-rclrs, python3-colcon-ros-cargo, cargo-ament-build for $DISTROS.</p>
<p>Setup instructions: <a href="https://github.com/signalbotics/ros2_rust/blob/apt-release/packaging/README.md">packaging/README.md</a></p>
EOT
touch "$OUT/.nojekyll"
find "$OUT" -maxdepth 3 | sort
