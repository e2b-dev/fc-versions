# fc-versions

## Overview

This project automates the building of custom Firecracker versions. It supports building specific firecracker versions and uploading the resulting binaries to a Google Cloud Storage (GCS) bucket.

## Prerequisites

- Linux environment (for building firecracker)

## Releasing Firecrackers

1. Run the `release.yml` GitHub Actions workflow (Actions → Manual Build & Release → Run workflow) to build and upload Firecracker binaries.
2. Create a new variation for the `firecracker-versions` feature flag to point a subset of users to the new firecracker version.
3. After testing, promote the new variation to all users.
4. Once the new variation is confirmed to be stable, update the DefaultFirecrackerV___Version constant in github.com/e2b-dev/infra, packages/shared/pkg/featureflags/flags.go.

### Workflow Inputs

- **tag** (required): Firecracker version tag (e.g., `v1.14.1`)
- **commit_hash** (optional): Full commit hash to build. Defaults to the tag's commit.
- **build_amd64** (optional): Build for amd64 architecture. Default: true
- **build_arm64** (optional): Build for arm64 architecture. Default: true

### What it does

1. Validates inputs and resolves the commit hash
2. Checks GCS and GitHub releases for existing artifacts
3. Builds missing architectures in parallel
4. Uploads binaries to GCS and creates a GitHub release

## Scripts

- `build.sh <tag> <commit_hash> <version_name> [arch]` - Builds a single Firecracker binary

## License

This project is licensed under the Apache License 2.0. See [LICENSE](LICENSE) for details.
