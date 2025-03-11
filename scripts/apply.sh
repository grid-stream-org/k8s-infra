#!/bin/bash
# Simplified script to detect version changes and redeploy services

set -euo pipefail

# Check if both SHA arguments are provided
if [ $# -ne 2 ]; then
  echo "Usage: $0 BEFORE_SHA CURRENT_SHA"
  exit 1
fi

BEFORE_SHA=$1
CURRENT_SHA=$2
NAMESPACE="gridstream-operations"

echo "Comparing versions.yaml between $BEFORE_SHA and $CURRENT_SHA"

# Extract version.yaml content from both commits
BEFORE_YAML=$(git show "$BEFORE_SHA:versions.yaml" 2>/dev/null || echo "")
CURRENT_YAML=$(git show "$CURRENT_SHA:versions.yaml" 2>/dev/null || echo "")

# Check if versions.yaml exists in both commits
if [ -z "$BEFORE_YAML" ]; then
  echo "Warning: versions.yaml not found in $BEFORE_SHA, treating as new file"
  # If it's a new file, we'll consider all services as changed
fi

if [ -z "$CURRENT_YAML" ]; then
  echo "Error: versions.yaml not found in $CURRENT_SHA"
  exit 1
fi

# Define services and their mapping
# Format: "directory image yaml_path"
declare -A services=(
  ["batcher.stream"]="k8s/batcher/stream us-docker.pkg.dev/grid-stream/gridstream/batcher services.batcher.stream" 
  ["batcher.event"]="k8s/batcher/event us-docker.pkg.dev/grid-stream/gridstream/batcher services.batcher.event"
  ["theo"]="k8s/theo us-docker.pkg.dev/grid-stream/gridstream/theo services.theo"
  #["validator"]="k8s/validator us-docker.pkg.dev/grid-stream/gridstream/validator services.validator"
)

# Extract versions from both commits for each service and compare
for service_key in "${!services[@]}"; do
  read -r dir image yaml_path <<< "${services[$service_key]}"
  
  echo "Checking $service_key (path: $yaml_path)..."
  
  # Get the old and new versions
  OLD_VERSION=$(echo "$BEFORE_YAML" | yq ".$yaml_path" 2>/dev/null || echo "")
  NEW_VERSION=$(echo "$CURRENT_YAML" | yq ".$yaml_path" 2>/dev/null || echo "")
  
  # If versions differ or old version was missing, update the service
  if [ "$OLD_VERSION" != "$NEW_VERSION" ]; then
    echo "Change detected for $service_key: $OLD_VERSION -> $NEW_VERSION"
    
    # Check if directory exists
    if [ ! -d "$dir" ]; then
      echo "Directory $dir does not exist, skipping deployment"
      continue
    fi
    
    echo "Deploying $service_key version $NEW_VERSION"
    pushd "$dir" > /dev/null
    
    # Edit kustomization and apply changes
    echo "   - Updating image to ${image}:${NEW_VERSION}"
    kustomize edit set image "${image}:${NEW_VERSION}"
    
    echo "   - Applying to Kubernetes namespace ${NAMESPACE}"
    kustomize build --load-restrictor=LoadRestrictionsNone . | kubectl apply -n "${NAMESPACE}" -f -
    
    echo "   - Deployment complete"
    popd > /dev/null
  else
    echo "Skipping $service_key: no change detected ($NEW_VERSION)"
  fi
done

echo "Deployment process completed"