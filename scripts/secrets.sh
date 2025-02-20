#!/bin/bash
set -euo pipefail

NAMESPACE="gridstream-operations"

# Format: "<gcloud_secret_id> <k8s_secret_name> <file_key>"
secrets=(
  "CREDS_PATH_SECRET bigquery-credentials credentials.json"
  "BATCHER_STREAM_CONFIG_SECRET batcher-stream-config config.json"
  "BATCHER_CONFIG_SECRET batcher-config config.json"
  "THEO_CONFIG_SECRET theo-config config.json"
)

for entry in "${secrets[@]}"; do
  read -r gcloudSecret k8sSecret fileKey <<< "$entry"
  echo "Processing secret ${k8sSecret} from ${gcloudSecret}..."
  
  # Retrieve new secret data and compute its hash
  new_data=$(gcloud secrets versions access latest --secret="${gcloudSecret}")
  new_hash=$(echo "$new_data" | sha256sum | awk '{print $1}')
  
  # Get the existing secret's hash annotation (if it exists)
  current_hash=$(kubectl get secret "${k8sSecret}" -n "${NAMESPACE}" -o jsonpath="{.metadata.annotations.secret-hash}" 2>/dev/null || echo "")
  
  if [ "$new_hash" != "$current_hash" ]; then
    echo "Updating secret ${k8sSecret}..."
    echo "$new_data" | kubectl create secret generic "${k8sSecret}" \
      -n "${NAMESPACE}" \
      --from-file="${fileKey}=/dev/stdin" \
      --dry-run=client -o yaml \
    | kubectl apply -n "${NAMESPACE}" -f -
    
    # Annotate the secret with the new hash for future comparisons
    kubectl annotate secret "${k8sSecret}" -n "${NAMESPACE}" secret-hash="$new_hash" --overwrite
  else
    echo "Secret ${k8sSecret} unchanged, skipping update."
  fi
done
