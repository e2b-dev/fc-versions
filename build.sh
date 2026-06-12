#!/bin/bash

set -euo pipefail

FIRECRACKER_REPO_HOST="github.com/e2b-dev/firecracker.git"

: "${FIRECRACKER_REPO_TOKEN:?must be set to clone the firecracker repo}"

if [[ $# -lt 2 ]]; then
  echo "Usage: $0 <commit_hash> <version_name> [arch]" >&2
  echo "  commit_hash:  Full git commit hash to build" >&2
  echo "  version_name: Output directory name (e.g., v1.14.1_abc1234)" >&2
  echo "  arch:         amd64 (default) or arm64" >&2
  exit 1
fi

commit_hash="$1"
version_name="$2"
arch="${3:-amd64}"

# Map Go/Docker arch names to Rust target triples
case "$arch" in
  amd64)  rust_target="x86_64-unknown-linux-musl" ;;
  arm64)  rust_target="aarch64-unknown-linux-musl" ;;
  *)
    echo "Error: unsupported architecture: $arch (expected amd64 or arm64)" >&2
    exit 1
    ;;
esac

git clone "https://x-access-token:${FIRECRACKER_REPO_TOKEN}@${FIRECRACKER_REPO_HOST}" firecracker
cd firecracker
git checkout "$commit_hash"

out_dir="../builds/${version_name}/${arch}"
mkdir -p "$out_dir"
release_bin="build/cargo_target/${rust_target}/release/firecracker"

echo "Building Firecracker $version_name for $arch ($rust_target)..."
tools/devtool -y build --release -- --bin firecracker

# Output goes into {version_name}/{arch}/firecracker
cp "$release_bin" "$out_dir/firecracker"

# Also build a debug variant: same release (optimized) build with the gdb
# feature enabled and debug symbols kept. Used ONLY for debugging guest kernels
# on dev nodes; it is never deployed to prod client nodes, which resolve the FC
# binary at exactly "<version>/<arch>/firecracker" (a different name).
#
# devtool's release build strips and splits debug info into <bin>.debug, so we
# publish the binary plus its companion. The debuglink is repointed to the
# renamed companion so gdb auto-loads it when the two are colocated.
echo "Building debug Firecracker $version_name for $arch ($rust_target)..."
tools/devtool -y build --release -- --bin firecracker --features gdb
cp "$release_bin" "$out_dir/firecracker-debug"
if [[ -f "${release_bin}.debug" ]]; then
  cp "${release_bin}.debug" "$out_dir/firecracker-debug.debug"
  objcopy --remove-section .gnu_debuglink "$out_dir/firecracker-debug" 2>/dev/null || true
  ( cd "$out_dir" && objcopy --add-gnu-debuglink=firecracker-debug.debug firecracker-debug )
else
  echo "Warning: ${release_bin}.debug not found; firecracker-debug ships without split DWARF" >&2
  # Drop any stale debuglink (the build points it at "firecracker.debug", which we
  # do not ship next to firecracker-debug) so gdb doesn't chase a missing file.
  objcopy --remove-section .gnu_debuglink "$out_dir/firecracker-debug" 2>/dev/null || true
fi

cd ..
rm -rf firecracker
