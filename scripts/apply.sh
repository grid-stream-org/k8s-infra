#!/bin/bash
set -euo pipefail

# <directory> <full-image-name> <yq query for version>
services=(
  "k8s/batcher/stream us-docker.pkg.dev/grid-stream/gridstream/batcher .services.batcher.stream"
#   "k8s/batcher/event us-docker.pkg.dev/grid-stream/gridstream/batcher-event .services.batcher.event"
#   "k8s/validator us-docker.pkg.dev/grid-stream/gridstream/validator .services.validator"
)

for entry in "${services[@]}"; do
  read -r dir image versionQuery <<< "$entry"
  version=$(yq "$versionQuery" versions.yaml)
  echo "Applying manifests for ${dir} with image ${image}:${version}"
  pushd "$dir" > /dev/null
  kustomize edit set image "${image}:${version}"
  kustomize build --load-restrictor=LoadRestrictionsNone . | kubectl apply -n gridstream-operations -f -
  popd > /dev/null
done
