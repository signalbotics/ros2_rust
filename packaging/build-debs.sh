#!/bin/bash
# Build unofficial .deb packages for ros2_rust inside a ros:<distro>-ros-base container.
#
#   docker run --rm -e ROS_DISTRO=jazzy -e REV=1 \
#     -v <repo-root>:/src/ros2_rust:ro -v $PWD/out/jazzy:/out \
#     ros:jazzy-ros-base /src/ros2_rust/packaging/build-debs.sh
#
# (or just: packaging/build-local.sh)
#
# Produces in /out:
#   ros-<distro>-rclrs_<ver>_all.deb            rclrs crate source, registered in the ament index
#   python3-colcon-ros-cargo_<ver>_all.deb      colcon plugin (pip-only upstream)
#   cargo-ament-build_<ver>_<arch>.deb          cargo subcommand binary
set -euo pipefail
: "${ROS_DISTRO:?set ROS_DISTRO}"
# '~' makes our revision sort BELOW any official buildfarm package of the same upstream version.
# shellcheck source=versions.env
source "$(dirname "$0")/versions.env"
REV="${REV:-1}"
REV_SUFFIX="0~signalbotics$REV"

export DEBIAN_FRONTEND=noninteractive PIP_ROOT_USER_ACTION=ignore
source /etc/os-release
CODENAME="$VERSION_CODENAME"
ARCH="$(dpkg --print-architecture)"
ROS_PREFIX="/opt/ros/$ROS_DISTRO"
D="ros-$ROS_DISTRO"   # debian name prefix

apt-get update -qq
apt-get install -y -qq curl libclang-dev python3-pip "$D-rosidl-generator-rs" >/dev/null
curl -sSf https://sh.rustup.rs | sh -s -- -y -q --profile minimal >/dev/null 2>&1
source "$HOME/.cargo/env"

WORK=/tmp/debwork; rm -rf "$WORK"; mkdir -p "$WORK" /out

# ---- cargo-ament-build (binary) --------------------------------------------------------------
cargo install -q --locked cargo-ament-build --version "$CARGO_AMENT_BUILD_VERSION" --root "$WORK/cab-root"
CAB_VER="$CARGO_AMENT_BUILD_VERSION"
P="$WORK/cargo-ament-build"
mkdir -p "$P/DEBIAN" "$P/usr/bin"
cp "$WORK/cab-root/bin/cargo-ament-build" "$P/usr/bin/"
strip "$P/usr/bin/cargo-ament-build" || true
cat > "$P/DEBIAN/control" <<EOF
Package: cargo-ament-build
Version: $CAB_VER-$REV_SUFFIX$CODENAME
Architecture: $ARCH
Maintainer: $MAINTAINER
Depends: libc6
Section: devel
Priority: optional
Homepage: https://github.com/ros2-rust/cargo-ament-build
Description: Cargo plugin for building ROS 2 ament packages (unofficial build)
EOF
dpkg-deb --root-owner-group -Zxz --build "$P" "/out/cargo-ament-build_${CAB_VER}-${REV_SUFFIX}${CODENAME}_${ARCH}.deb"

# ---- python3-colcon-ros-cargo ----------------------------------------------------------------
P="$WORK/colcon-ros-cargo"
mkdir -p "$P/DEBIAN" "$P/usr/lib/python3/dist-packages"
pip install -q --no-deps --no-compile --target "$P/usr/lib/python3/dist-packages" \
  "colcon-ros-cargo==$COLCON_ROS_CARGO_VERSION"
rm -rf "$P/usr/lib/python3/dist-packages/bin"
cat > "$P/DEBIAN/control" <<EOF
Package: python3-colcon-ros-cargo
Version: $COLCON_ROS_CARGO_VERSION-$REV_SUFFIX$CODENAME
Architecture: all
Maintainer: $MAINTAINER
Depends: python3, python3-colcon-core, python3-colcon-cargo, python3-colcon-ros, python3-toml, cargo-ament-build
Section: python
Priority: optional
Homepage: https://github.com/colcon/colcon-ros-cargo
Description: colcon extension for building ament_cargo (Rust ROS 2) packages (unofficial build)
EOF
dpkg-deb --root-owner-group -Zxz --build "$P" \
  "/out/python3-colcon-ros-cargo_${COLCON_ROS_CARGO_VERSION}-${REV_SUFFIX}${CODENAME}_all.deb"

# ---- ros-<distro>-rclrs ----------------------------------------------------------------------
# Version comes from Cargo.toml (package.xml is stale upstream).
RCLRS_VER="$(sed -n 's/^version = "\(.*\)"/\1/p' /src/ros2_rust/rclrs/Cargo.toml | head -1)"
P="$WORK/rclrs"
SHARE="$P$ROS_PREFIX/share"
mkdir -p "$P/DEBIAN" "$SHARE/rclrs/rust" \
  "$SHARE/ament_index/resource_index/packages" \
  "$SHARE/ament_index/resource_index/rust_packages"
# Same layout cargo-ament-build produces: crate source under share/<pkg>/rust.
( cd /src/ros2_rust/rclrs && tar --exclude=target --exclude=.git -cf - . ) | tar -xf - -C "$SHARE/rclrs/rust"
rm -f "$SHARE/rclrs/rust/package.xml"
sed "s|<version>.*</version>|<version>$RCLRS_VER</version>|" /src/ros2_rust/rclrs/package.xml > "$SHARE/rclrs/package.xml"
: > "$SHARE/ament_index/resource_index/packages/rclrs"
: > "$SHARE/ament_index/resource_index/rust_packages/rclrs"
# Sanity: the packaged source must compile against this distro before we ship it.
( set +u; source "$ROS_PREFIX/setup.bash"; set -u; cd "$SHARE/rclrs/rust" && cargo check -q --target-dir "$WORK/rclrs-target" )
rm -f "$SHARE/rclrs/rust/Cargo.lock"
cat > "$P/DEBIAN/control" <<EOF
Package: $D-rclrs
Version: $RCLRS_VER-$REV_SUFFIX$CODENAME
Architecture: all
Maintainer: $MAINTAINER
Depends: $D-rcl, $D-builtin-interfaces, $D-rcl-interfaces, $D-rosgraph-msgs, $D-rosidl-generator-rs, $D-ros-workspace, libclang-dev, python3-colcon-ros-cargo, cargo-ament-build
Suggests: rustup
Section: devel
Priority: optional
Homepage: https://github.com/ros2-rust/ros2_rust
Description: ROS 2 client library for Rust (rclrs) - unofficial build
 Installs the rclrs crate source into $ROS_PREFIX/share/rclrs/rust and registers it
 in the ament index so colcon-ros-cargo patches 'rclrs' to this copy.
 Requires a Rust toolchain >= 1.85 (e.g. via rustup).
EOF
dpkg-deb --root-owner-group -Zxz --build "$P" "/out/${D}-rclrs_${RCLRS_VER}-${REV_SUFFIX}${CODENAME}_all.deb"

ls -la /out
