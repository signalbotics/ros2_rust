# Unofficial apt packages for ROS 2 Rust (rclrs)

Signalbotics-maintained `.deb` packages for **ROS 2 Jazzy** (Ubuntu 24.04 noble) and **Lyrical**
(Ubuntu 26.04 resolute), on **amd64** and **arm64**. They're a stopgap until the official ROS buildfarm
can release Rust packages (tracked in [ros_buildfarm#1157](https://github.com/ros-infrastructure/ros_buildfarm/issues/1157)
and [ros2_rust#310](https://github.com/ros2-rust/ros2_rust/issues/310)).
This is **not** an official ros2-rust or OSRF release.

| Package | Contents |
|---|---|
| `ros-<distro>-rclrs` | rclrs crate source in `/opt/ros/<distro>/share/rclrs/rust`, registered in the ament index (`rust_packages/rclrs`), so colcon-ros-cargo builds against it |
| `python3-colcon-ros-cargo` | colcon plugin (pip-only upstream) |
| `cargo-ament-build` | cargo subcommand binary |

Everything else (`rosidl-generator-rs`, `python3-colcon-cargo`, `rcl`, message packages with Rust
bindings) comes from the official ROS apt repo and is pulled in as dependencies.

## Install

Prerequisite: ROS 2 Jazzy or Lyrical installed from packages.ros.org.

```bash
sudo curl -fsSL https://signalbotics.github.io/ros2_rust/signalbotics-ros2-rust.gpg \
  -o /usr/share/keyrings/signalbotics-ros2-rust.gpg
echo "deb [signed-by=/usr/share/keyrings/signalbotics-ros2-rust.gpg] https://signalbotics.github.io/ros2_rust $(. /etc/os-release; echo $VERSION_CODENAME) main" \
  | sudo tee /etc/apt/sources.list.d/signalbotics-ros2-rust.list
gpg --show-keys /usr/share/keyrings/signalbotics-ros2-rust.gpg   # expect fingerprint 3ECE A431 6291 2C5B FEC4  3FB6 1772 7F1B 7DC9 4DF7
sudo apt update
sudo apt install ros-$ROS_DISTRO-rclrs      # pulls colcon-ros-cargo + cargo-ament-build

# Rust >= 1.85 is required; Ubuntu's packaged cargo is too old.
curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh
```

The `.deb`s and `SHA256SUMS` are also attached to each
[GitHub Release](https://github.com/signalbotics/ros2_rust/releases) (tags `apt/v*`).

## Use

`Cargo.toml` of your `ament_cargo` package:

```toml
[dependencies]
rclrs = "0.8"
ros-env = "0.3"   # gives access to every installed message package
```

```rust
use rclrs::*;
use ros_env::std_msgs;
```

```bash
source /opt/ros/$ROS_DISTRO/setup.bash
colcon build
```

Use messages through `ros_env::<pkg>`. Writing `std_msgs = "*"` directly in Cargo.toml doesn't work
with the apt message packages: they aren't registered in the `rust_packages` index, so cargo tries
crates.io instead. rclrs's own crates.io dependencies (tokio, futures, …) are still downloaded by
cargo at build time; they aren't bundled.

## Uninstall / switch to official packages

```bash
sudo apt remove ros-$ROS_DISTRO-rclrs python3-colcon-ros-cargo cargo-ament-build
sudo rm /etc/apt/sources.list.d/signalbotics-ros2-rust.list /usr/share/keyrings/signalbotics-ros2-rust.gpg
```

Our versions are `<upstream>-0~signalbotics<rev><codename>`. The `~` sorts below any official
buildfarm release of the same upstream version, so an official package wins on `apt upgrade`.

---

## Maintainers: layout, CI and releases

### Branches

| Branch | Purpose |
|---|---|
| `main` | Exact mirror of `ros2-rust/ros2_rust:main`. Never commit here; it's the base for upstream MRs. |
| `apt-release` | Default branch. `main` + `packaging/` + `.github/workflows/apt-*.yml`. No upstream files modified. |

Sync with upstream:

```bash
gh repo sync signalbotics/ros2_rust -b main          # fast-forward main
git checkout apt-release && git fetch signalbotics && git merge signalbotics/main && git push signalbotics apt-release
```

### Files

| File | Role |
|---|---|
| `packaging/versions.env` | Single source of truth: distros, codenames, pinned tool versions, maintainer, apt URL |
| `packaging/build-debs.sh` | Builds the 3 debs inside `ros:<distro>-ros-base`; `cargo check`s rclrs against the distro first |
| `packaging/test/test-debs.sh` | Clean-container smoke test: install (`SOURCE=debs` or `SOURCE=repo`), build + run `test/talker` |
| `packaging/apt-repo.sh` | Assembles and signs the apt repo (reprepro) from CI artifacts |
| `packaging/build-local.sh` | Runs build + test locally, same as CI |
| `.github/workflows/apt-build.yml` | Reusable build+test matrix (distro × amd64/arm64), shared by CI and release |
| `.github/workflows/apt-ci.yml` | Runs on every push/PR to `apt-release` |
| `.github/workflows/apt-release.yml` | Runs on `apt/v*` tags: validate → build → publish (Release + Pages) → verify from live repo |

The upstream workflows (`rust-*`, `generate-bindings`, `release-plz`) are disabled in this fork's
Actions settings; they target upstream's infrastructure and secrets.

### Local build

```bash
packaging/build-local.sh            # all distros; output in packaging/out/<distro>/
packaging/build-local.sh jazzy
```

### Cutting a release

1. Bump anything needed in `packaging/versions.env` (or merge a new upstream rclrs) and get `apt CI` green.
2. Tag `apt/v<rclrs version>-<rev>`. The version must equal `rclrs/Cargo.toml`, or the release fails.
   `rev` starts at 1 and increases for packaging-only changes to the same rclrs version.
   ```bash
   git tag apt/v0.8.0-1 && git push signalbotics apt/v0.8.0-1
   ```
3. `apt release` publishes the GitHub Release and the apt repo, then installs from the live repo on
   all distro/arch combinations to check it.

The apt repo always contains the latest release only. Older `.deb`s stay on their GitHub Releases.

### Signing key

- The private key is in the repo secret `APT_SIGNING_KEY` (armored, no passphrase). A maintainer holds an offline
  backup of the private key and its revocation certificate.
- Previous key `B7B8 4DFB BE6E 1520 3B96  2426 3CAB 06EC A0B1 86BD` (2026-11-22) was replaced on 2026-11-23 because it
  had no backup or revocation certificate. Users who installed before then must re-download the keyring.
- Fingerprint: `3ECE A431 6291 2C5B FEC4  3FB6 1772 7F1B 7DC9 4DF7` (ed25519, created 2026-11-23, expires 2029-11-22).
- The public key is published at `https://signalbotics.github.io/ros2_rust/signalbotics-ros2-rust.{gpg,asc}`.
- To rotate: generate a new key, update the secret, cut a new `rev`, and tell users to re-download the keyring.
