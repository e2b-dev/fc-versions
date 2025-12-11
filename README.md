# fc-versions

## Overview

This project automates the building of custom Firecracker versions. It supports building specific firecracker versions and uploading the resulting binaries to a Google Cloud Storage (GCS) bucket.

## Prerequisites

- Linux environment (for building firecracker)

## Building Firecrackers

The `firecracker_versions.txt` file specifies which versions to build:

- Edit `firecracker_versions.txt` to specify firecracker versions (one per line)
- Versions can be tags (e.g., `v1.10.1`) or tag with shorthash (e.g., `v1.12.1_abcdef12`)
- On every push, GitHub Actions will automatically:
  1. Parse versions from `firecracker_versions.txt` and resolve commit hashes
  2. Build each version in parallel
  3. Check CI status for each version
  4. Upload successful builds to GCS and create GitHub releases (on main branch)

## Scripts

- `build.sh <version> <hash> <version_name>` - Builds a single Firecracker version
- `scripts/parse-versions-with-hash.sh` - Parses versions and resolves commit hashes
- `scripts/check-fc-ci.sh <versions_json>` - Checks CI status for parsed versions

## License

This project is licensed under the Apache License 2.0. See [LICENSE](LICENSE) for details.
