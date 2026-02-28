#!/usr/bin/env bash
# Usage: ./tools/scan-image.sh <image-ref> <output-json>
# Example: ./tools/scan-image.sh ghcr.io/owner/repo@sha trivy-report.json
set -euo pipefail
IMAGE="$1"
OUT="$2"

echo "Scanning image: $IMAGE"
# Pull image (ensures local availability for trivy)
docker pull "$IMAGE"

# Run Trivy scanner via container (no installation required on runner)
# This runs trivy inside a container and mounts the docker socket to access local images.
docker run --rm -v /var/run/docker.sock:/var/run/docker.sock \
  -v "$(pwd)":/workspace aquasec/trivy:latest \
  image --format json --output /workspace/"$OUT" "$IMAGE"

echo "Trivy report saved to $OUT"
