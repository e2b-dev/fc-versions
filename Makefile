ENV := $(shell cat ../../.last_used_env || echo "not-set")
-include ../../.env.${ENV}

.PHONY: build
build:
	@if ! git diff-index --quiet HEAD --; then \
		echo "Error: Uncommitted changes detected. Please commit or stash changes before building." >&2; \
		exit 1; \
	fi
	@hash=$$(git rev-parse HEAD); \
	tag=$$(git describe --tags --abbrev=0 HEAD 2>/dev/null || echo ""); \
	if [ -z "$$tag" ]; then \
		echo "Error: No tag found for current commit" >&2; \
		exit 1; \
	fi; \
	short_hash=$$(git rev-parse --short HEAD); \
	version_name="$${tag}_$${short_hash}"; \
	./build.sh "$$tag" "$$hash" "$$version_name"

.PHONY: upload
upload:
	./upload.sh $(GCP_PROJECT_ID)

.PHONY: build-and-upload
make build-and-upload: build upload