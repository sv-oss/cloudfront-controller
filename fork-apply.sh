#!/usr/bin/env bash
# fork-apply.sh — Post-generation overlay that renames the API group
# from "cloudfront.services.k8s.aws" to "cloudfront.fork.services.k8s.aws"
#
# Usage: Run this AFTER code generation (build-controller.sh / ack-generate).
#        Safe to run repeatedly (idempotent).
#
# What it does:
#   1. Replaces the group string in all Go source, YAML, and template files
#   2. Renames CRD files to match the new group prefix
#   3. Updates kustomization.yaml references
#
# To undo: git checkout -- .

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")" && pwd)"
cd "$REPO_ROOT"

OLD_GROUP="cloudfront.services.k8s.aws"
NEW_GROUP="cloudfront.fork.services.k8s.aws"

echo "==> Applying fork group rename: $OLD_GROUP → $NEW_GROUP"

# Step 1: Replace group string in all relevant source files
find . \( -name "*.go" -o -name "*.yaml" -o -name "*.yml" -o -name "*.tpl" \) \
  -not -path "./.git/*" \
  -not -path "./fork-apply.sh" \
  -print0 | xargs -0 sed -i '' "s|${OLD_GROUP}|${NEW_GROUP}|g"

echo "  [done] String replacement in source files"

# Step 2: Regenerate CRDs from Go types (picks up fork group + any new fields)
controller-gen crd:allowDangerousTypes=true paths="./apis/..." output:crd:artifacts:config=config/crd/bases

echo "  [done] CRDs regenerated from Go types"

# Step 3: Rename CRD files under helm/crds/ and config/crd/bases/
for dir in helm/crds config/crd/bases; do
  if [[ -d "$dir" ]]; then
    for f in "$dir"/${OLD_GROUP}_*.yaml; do
      [[ -f "$f" ]] || continue
      newname="${f/${OLD_GROUP}/${NEW_GROUP}}"
      if [[ "$f" != "$newname" ]]; then
        mv "$f" "$newname"
      fi
    done
  fi
done

echo "  [done] CRD file renames"

# Step 4: Sync CRDs from config/crd/bases to helm/crds
rm -f helm/crds/${NEW_GROUP}_*.yaml
cp config/crd/bases/${NEW_GROUP}_*.yaml helm/crds/

echo "  [done] Helm CRDs synced"

# Step 5: Update kustomization.yaml references to renamed CRD files
KUSTOMIZE_FILE="config/crd/kustomization.yaml"
if [[ -f "$KUSTOMIZE_FILE" ]]; then
  sed -i '' "s|${OLD_GROUP}|${NEW_GROUP}|g" "$KUSTOMIZE_FILE"
fi

echo "  [done] Kustomization references"

# Step 6: Patch Helm chart name to avoid collision with official chart
CHART_FILE="helm/Chart.yaml"
if [[ -f "$CHART_FILE" ]]; then
  sed -i '' 's/^name: cloudfront-chart$/name: cloudfront-fork-chart/' "$CHART_FILE"
  # Append -fork to appVersion if not already present
  if ! grep -q "appVersion:.*-fork" "$CHART_FILE"; then
    sed -i '' 's/^appVersion: \(.*\)$/appVersion: \1-fork/' "$CHART_FILE"
  fi
fi

echo "  [done] Helm chart name/version patched"
echo ""
echo "==> Fork overlay applied. Verify with:"
echo "      go build ./..."
echo "      go test ./..."
