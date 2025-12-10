# fc-kernels

## Overview

This project automates the building of custom Firecracker. It supports building specific firecracker versions and uploading the resulting binaries to a Google Cloud Storage (GCS) bucket.

## Prerequisites

- Linux environment (for building firecracker)

## Building Kernels

1. **Configure firecracker versions:**
    - Edit `firecracker_versions.txt` to specify which kernel versions to build (one per line, e.g., `<last_tag-prelease>-<first-8-letters-of-the-specific-commit>`).

2. **Build:**

   ```sh
   make build
   # or directly
   ./build.sh
   ```

   The built kernels will be placed in `builds/vmlinux-<version>/vmlinux.bin`.

## Development Workflow

- On every push, GitHub Actions will automatically build the kernels and save it as an artifact.

## License

This project is licensed under the Apache License 2.0. See [LICENSE](LICENSE) for details.
