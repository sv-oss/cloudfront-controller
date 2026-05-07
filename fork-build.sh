#!/usr/bin/env bash
# fork-build.sh — Build and push forked controller image + Helm chart OCI to GHCR
#
# Prerequisites:
#   - docker (or podman aliased to docker)
#   - helm v3.8+
#   - Logged into GHCR: echo $GITHUB_TOKEN | docker login ghcr.io -u <user> --password-stdin
#                        echo $GITHUB_TOKEN | helm registry login ghcr.io -u <user> --password-stdin
#
# Usage:
#   GHCR_REPO=ghcr.io/<owner>/cloudfront-fork-controller ./fork-build.sh
#
# Environment variables:
#   GHCR_REPO   — required, e.g. ghcr.io/msessa/cloudfront-fork-controller
#   TAG         — optional, defaults to "latest"
#   PLATFORM    — optional, defaults to "linux/arm64" (set to "linux/amd64,linux/arm64" for multi-arch)

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")" && pwd)"
cd "$REPO_ROOT"

: "${GHCR_REPO:?Set GHCR_REPO to your GHCR image path, e.g. ghcr.io/youruser/cloudfront-fork-controller}"
TAG="${TAG:-latest}"
PLATFORM="${PLATFORM:-linux/arm64}"

IMAGE="${GHCR_REPO}:${TAG}"
CHART_DIR="helm"

echo "==> Building controller image: ${IMAGE}"
echo "    Platform: ${PLATFORM}"

docker buildx build \
  --platform "${PLATFORM}" \
  --build-arg VERSION="${TAG}" \
  -t "${IMAGE}" \
  --push \
  .

echo "  [done] Image pushed: ${IMAGE}"
echo ""

# Build and push Helm chart as OCI artifact
CHART_VERSION=$(grep '^version:' "${CHART_DIR}/Chart.yaml" | awk '{print $2}')
CHART_NAME=$(grep '^name:' "${CHART_DIR}/Chart.yaml" | awk '{print $2}')

# Derive OCI registry path from GHCR_REPO (strip the image name, use charts subpath)
# e.g. ghcr.io/msessa/cloudfront-fork-controller → ghcr.io/msessa/charts
GHCR_CHARTS="${GHCR_REPO%/*}/charts"

echo "==> Packaging Helm chart: ${CHART_NAME} v${CHART_VERSION}"

# Update image reference in values.yaml to point to the fork image
sed -i '' "s|image:.*|image:|" "${CHART_DIR}/values.yaml" 2>/dev/null || true
# Set the image repository and tag in values for the fork
cat > /tmp/fork-values-patch.yaml <<EOF
image:
  repository: ${GHCR_REPO}
  tag: ${TAG}
EOF

helm package "${CHART_DIR}" --version "${CHART_VERSION}" --app-version "${TAG}" -d /tmp/fork-chart/

echo "==> Pushing Helm chart OCI: oci://${GHCR_CHARTS}/${CHART_NAME}:${CHART_VERSION}"

helm push "/tmp/fork-chart/${CHART_NAME}-${CHART_VERSION}.tgz" "oci://${GHCR_CHARTS}"

echo "  [done] Chart pushed: oci://${GHCR_CHARTS}/${CHART_NAME}:${CHART_VERSION}"
echo ""
echo "==> Install with:"
echo "    helm install cloudfront-fork oci://${GHCR_CHARTS}/${CHART_NAME} --version ${CHART_VERSION} \\"
echo "      --set image.repository=${GHCR_REPO} --set image.tag=${TAG}"

rm -rf /tmp/fork-chart /tmp/fork-values-patch.yaml
