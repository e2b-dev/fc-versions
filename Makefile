ENV := $(shell cat ../../.last_used_env || echo "not-set")
-include ../../.env.${ENV}

.PHONY: build
build:
	@versions_json=$$(./scripts/parse-versions-with-hash.sh firecracker_versions.txt); \
	echo "$$versions_json" | jq -r '.[] | "\(.version)|\(.hash)|\(.version_name)"' | \
	while IFS='|' read -r version hash version_name; do \
		echo "Building $$version_name..."; \
		./build.sh "$$version" "$$hash" "$$version_name"; \
	done

.PHONY: upload
upload:
	./upload.sh $(GCP_PROJECT_ID)

.PHONY: build-and-upload
make build-and-upload: build upload