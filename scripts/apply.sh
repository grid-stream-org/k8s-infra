#!/bin/bash
set -euo pipefail
BEFORE_SHA=$1
CURRENT_SHA=$2
NAMESPACE="gridstream-operations"

# Get list of keys changed in versions.yaml between commits
changed_keys=$(git diff "${BEFORE_SHA}" "${CURRENT_SHA}" -- versions.yaml | grep -oP '(?<=\s)[^:\s]+(?=:)' | sort | uniq)

# Format: "<directory> <full-image-name> <yq query for version>"
services=(
"k8s/batcher/stream us-docker.pkg.dev/grid-stream/gridstream/batcher .services.batcher.stream"
"k8s/batcher/event us-docker.pkg.dev/grid-stream/gridstream/batcher .services.batcher.event"
"k8s/theo us-docker.pkg.dev/grid-stream/gridstream/theo .services.theo"
# "k8s/validator us-docker.pkg.dev/grid-stream/gridstream/validator .services.validator"
)

for entry in "${services[@]}"; do
    read -r dir image versionQuery key <<< "$entry"
    
    # Only process if the service key appears in the diff
    if echo "$changed_keys" | grep -q "$key"; then
        version=$(yq "$versionQuery" versions.yaml)
        pushd "$dir" > /dev/null
        kustomize edit set image "${image}:${version}"
        kustomize build --load-restrictor=LoadRestrictionsNone . | kubectl apply -n "${NAMESPACE}" -f -
        
        # Determine deployment name based on directory (special case for batcher)
        deployment_name=$(if [[ "$dir" == *"/stream" ]]; then
            echo "batcher-stream"
        elif [[ "$dir" == *"/event" ]]; then
            echo "batcher"
        else
            basename "$dir"
        fi)
        
        # Restart the deployment
        kubectl rollout restart deployment/"$deployment_name" -n "${NAMESPACE}"
        
        popd > /dev/null
    else
        echo "Skipping $key: no change detected"
    fi
done