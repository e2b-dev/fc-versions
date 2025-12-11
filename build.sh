#!/bin/bash

set -euo pipefail

FIRECRACKER_REPO_URL="https://github.com/e2b-dev/firecracker.git"

if [[ $# -lt 3 ]]; then
  echo "Usage: $0 <version> <hash> <version_name>" >&2
  exit 1
fi

version="$1"
fullhash="$2"
version_name="$3"

git clone $FIRECRACKER_REPO_URL firecracker
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

tools/devtool -y build --release -- --bin firecracker

mkdir -p "../builds/${version_name}"
cp build/cargo_target/x86_64-unknown-linux-musl/release/firecracker "../builds/${version_name}/firecracker"

cd ..
rm -rf firecracker
