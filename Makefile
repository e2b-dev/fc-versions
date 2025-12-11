ENV := $(shell cat ../../.last_used_env || echo "not-set")
-include ../../.env.${ENV}

.PHONY: build
build:
	@if ! git diff-index --quiet HEAD --; then \
		echo "Error: Uncommitted changes detected. Please commit or stash changes before building." >&2; \
		exit 1; \
	fi
	@hash=$$(git rev-parse HEAD); \
	tag=$$(git tag --sort=-version:refname | head -1); \
	if [ -z "$$tag" ]; then \
		echo "Error: No tags found in repository" >&2; \
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