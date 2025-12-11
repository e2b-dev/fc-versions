#!/bin/bash

set -euo pipefail

FIRECRACKER_REPO_URL="https://github.com/e2b-dev/firecracker.git"

function build_version {
  local version=$1

  # Detect if the version is of the form tag_shorthash (e.g., v1.12.1_abcdef12)
  if [[ "$version" =~ ^([^_]+)_([0-9a-fA-F]+)$ ]]; then
    local tag="${BASH_REMATCH[1]}"
    local shorthash="${BASH_REMATCH[2]}"
    echo "Starting build for Firecracker tag: $tag and shorthash: $shorthash"

    echo "Checking out repo at tag: $tag"
    git checkout "$tag"

    # Find full hash from shorthash
    fullhash=$(git rev-parse --verify "$shorthash^{commit}" 2>/dev/null || true)
    if [[ -z "$fullhash" ]]; then
      echo "Error: Could not resolve hash $shorthash"
      exit 1
    fi

    # Ensure that $fullhash is a descendant of $tag
    if git merge-base --is-ancestor "$tag" "$fullhash"; then
      echo "Shorthash $shorthash is AFTER tag $tag -- proceeding"
      git checkout "$fullhash"
    else
      echo "Error: shorthash $shorthash is not a descendant of tag $tag"
      exit 1
    fi
    version_name="${tag}_$shorthash"
  else
    echo "Starting build for Firecracker at commit: $version"
    echo "Checking out repo for Firecracker at commit: $version"
    git checkout "${version}"
    
    fullhash=$(git rev-parse HEAD)
    # The format will be: latest_tag_latest_commit_hash — v1.7.0-dev_g8bb88311
    version_name=$(git describe --tags --abbrev=0 "$fullhash")_$(git rev-parse --short HEAD)
  fi

  echo "Version name: $version_name"

  echo "Building Firecracker version: $version_name"
  # Build only the firecracker binary, skip jailer and snapshot-editor for faster builds
  tools/devtool -y build --release -- --bin firecracker

  echo "Copying finished build to builds directory"
  mkdir -p "../builds/${version_name}"
  cp build/cargo_target/x86_64-unknown-linux-musl/release/firecracker "../builds/${version_name}/firecracker"
  
  # Write version name and commit hash to file for CI to use
  echo "${version_name}:${fullhash}" >> ../built_versions.txt
}

# If a version is passed as argument, build only that version
# Otherwise, build all versions from firecracker_versions.txt
if [[ $# -ge 1 ]]; then
  versions=("$@")
else
  mapfile -t versions < <(grep -v '^ *#' firecracker_versions.txt | grep -v '^$')
fi

echo "Cloning the Firecracker repository"
git clone $FIRECRACKER_REPO_URL firecracker
cd firecracker

for version in "${versions[@]}"; do
  build_version "$version"
done

cd ..
rm -rf firecracker
