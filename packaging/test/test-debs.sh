#!/bin/bash
# Smoke test in a clean ros:<distro>-ros-base container: install the packages, then build and run
# a Rust node. No rclrs source is mounted, so rclrs must come from the package.
#
#   SOURCE=debs  (default) install /debs/*.deb
#   SOURCE=repo            install from the published apt repo ($APT_URL)
set -eo pipefail
source "$(dirname "$0")/../versions.env"
export DEBIAN_FRONTEND=noninteractive
SOURCE="${SOURCE:-debs}"
apt-get update -qq
apt-get install -y -qq curl >/dev/null
if [ "$SOURCE" = repo ]; then
  curl -fsSL "$APT_URL/signalbotics-ros2-rust.gpg" -o /usr/share/keyrings/signalbotics-ros2-rust.gpg
  echo "deb [signed-by=/usr/share/keyrings/signalbotics-ros2-rust.gpg] $APT_URL $(. /etc/os-release; echo $VERSION_CODENAME) main" \
    > /etc/apt/sources.list.d/signalbotics-ros2-rust.list
  apt-get update -qq
  apt-get install -y -qq "ros-$ROS_DISTRO-rclrs" >/dev/null
else
  apt-get install -y -qq /debs/*.deb >/dev/null
fi
echo "== installed:"; dpkg -l | awk '/rclrs|colcon-ros-cargo|cargo-ament-build/ {print $2, $3}'
curl -sSf https://sh.rustup.rs | sh -s -- -y -q --profile minimal >/dev/null 2>&1
source "$HOME/.cargo/env"
source "/opt/ros/$ROS_DISTRO/setup.bash"
rm -rf /ws && mkdir -p /ws/src && cp -r "$(dirname "$0")/talker" /ws/src/
cd /ws && colcon build 2>&1 | tail -4
grep -q "/opt/ros/$ROS_DISTRO/share/rclrs/rust" .cargo/config.toml \
  || { echo "FAIL: rclrs not patched to the packaged copy"; cat .cargo/config.toml; exit 1; }
source install/setup.bash
out="$(ros2 run talker_rs talker_rs)"; echo "$out"
[ "$(grep -c '^published:' <<<"$out")" -eq 3 ] || { echo "FAIL: talker did not publish"; exit 1; }
echo "PASS ($ROS_DISTRO, $(dpkg --print-architecture), source=$SOURCE)"
