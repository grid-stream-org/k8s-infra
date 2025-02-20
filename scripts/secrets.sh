#!/bin/bash
set -euo pipefail

NAMESPACE="gridstream-operations"

# Format: "<gcloud_secret_id> <k8s_secret_name> <file_key>"
secrets=(
  "CREDS_PATH_SECRET bigquery-credentials credentials.json"
  "BATCHER_STREAM_CONFIG_SECRET batcher-stream-config config.json"
  # This is temporary because im still working on properly getting the event batcher config
  "BATCHER_STREAM_CONFIG_SECRET batcher-config config.json"
  "THEO_CONFIG_SECRET theo-config config.json"
)

for entry in "${secrets[@]}"; do
  read -r gcloudSecret k8sSecret fileKey <<< "$entry"
  echo "Creating secret ${k8sSecret} from ${gcloudSecret}..."
  gcloud secrets versions access latest --secret="${gcloudSecret}" \
    | kubectl create secret generic "${k8sSecret}" \
        -n "${NAMESPACE}" \
        --from-file="${fileKey}=/dev/stdin" \
        --dry-run=client -o yaml \
    | kubectl apply -n "${NAMESPACE}" -f -
done
