#!/bin/bash

set -euo pipefail

FIRECRACKER_REPO_URL="https://github.com/e2b-dev/firecracker.git"

if [[ $# -lt 3 ]]; then
  echo "Usage: $0 <version> <hash> <version_name> [arch]" >&2
  echo "  arch: amd64 (default) or arm64" >&2
  exit 1
fi

version="$1"
fullhash="$2"
version_name="$3"
arch="${4:-amd64}"

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

if [[ "$version" =~ ^([^_]+)_([0-9a-fA-F]+)$ ]]; then
  tag="${BASH_REMATCH[1]}"
  git checkout "$tag"
  if ! git merge-base --is-ancestor "$tag" "$fullhash"; then
    echo "Error: shorthash is not a descendant of tag $tag" >&2
    exit 1
  fi
  git checkout "$fullhash"
else
  git checkout "$fullhash"
fi

echo "Building Firecracker $version_name for $arch ($rust_target)..."
tools/devtool -y build --release -- --bin firecracker

# Output goes into {version_name}/{arch}/firecracker
mkdir -p "../builds/${version_name}/${arch}"
cp "build/cargo_target/${rust_target}/release/firecracker" "../builds/${version_name}/${arch}/firecracker"

# For amd64, also copy to the legacy flat path ({version_name}/firecracker)
# so existing production nodes that expect the old layout keep working.
if [[ "$arch" == "amd64" ]]; then
  cp "build/cargo_target/${rust_target}/release/firecracker" "../builds/${version_name}/firecracker"
fi

cd ..
rm -rf firecracker
