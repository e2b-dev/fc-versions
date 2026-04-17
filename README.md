# fc-versions

## Overview

This project automates the building of custom Firecracker versions. It supports building specific firecracker versions and uploading the resulting binaries to a Google Cloud Storage (GCS) bucket.

## Prerequisites

- Linux environment (for building firecracker)

## Building Firecrackers

Run the 'build.yml' GitHub Action workflow to build and upload Firecracker binaries to GCS.
1. Build each architecture in parallel
2. Upload successful builds to GCS and create GitHub releases

## Scripts

- `build.sh <version> <hash> <version_name>` - Builds a single Firecracker version

## License

This project is licensed under the Apache License 2.0. See [LICENSE](LICENSE) for details.
