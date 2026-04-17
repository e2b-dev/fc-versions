#!/bin/bash

set -euo pipefail

FIRECRACKER_REPO_URL="https://github.com/e2b-dev/firecracker.git"

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

git clone "$FIRECRACKER_REPO_URL" firecracker
cd firecracker
git checkout "$commit_hash"

echo "Building Firecracker $version_name for $arch ($rust_target)..."
tools/devtool -y build --release -- --bin firecracker

# Output goes into {version_name}/{arch}/firecracker
mkdir -p "../builds/${version_name}/${arch}"
cp "build/cargo_target/${rust_target}/release/firecracker" "../builds/${version_name}/${arch}/firecracker"

cd ..
rm -rf firecracker
