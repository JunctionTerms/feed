#!/bin/bash

# Authenticate
HUB_TOKEN=$(curl -s -H "Content-Type: application/json" -X POST \
  -d "{\"username\": \"$HUB_USERNAME\", \"password\": \"$HUB_PASSWORD\"}" \
  https://hub.docker.com/v2/users/login/ | jq -r .token)

[ -z "$HUB_TOKEN" ] && { echo "❌ Auth failed"; exit 1; }

# Get manifests with tags
RESPONSE=$(curl -s -H "Authorization: JWT $HUB_TOKEN" \
  "https://hub.docker.com/v2/repositories/$IMAGE_NAME/tags/?page_size=$MAX_DELETIONS&ordering=last_updated")

# Process deletions
DELETED=0
echo "$RESPONSE" | jq -c '.results[]' | while read -r ITEM; do
  TAG=$(echo "$ITEM" | jq -r '.name')
  DIGEST=$(echo "$ITEM" | jq -r '.images[0].digest')
  
  echo "Processing ${DIGEST:7:12} (tag: ${TAG:-none})..."
  
  # Delete tag if exists
  if [ "$TAG" != "null" ]; then
    echo "  Deleting tag..."
    curl -s -o /dev/null -X DELETE \
      -H "Authorization: JWT $HUB_TOKEN" \
      "https://hub.docker.com/v2/namespaces/${IMAGE_NAME%/*}/repositories/${IMAGE_NAME#*/}/tags/$TAG"
  fi
  
  # Delete manifest
  echo "  Deleting manifest..."
  STATUS=$(curl -s -o /dev/null -w "%{http_code}" -X DELETE \
    -H "Authorization: JWT $HUB_TOKEN" \
    -H "Accept: application/vnd.docker.distribution.manifest.v2+json" \
    "https://hub.docker.com/v2/repositories/$IMAGE_NAME/manifests/$DIGEST")
  
  if [ "$STATUS" -eq 202 ]; then
    ((DELETED++))
    echo "  ✅ Deleted"
  else
    echo "  ❌ Failed (HTTP $STATUS)"
  fi
  
  sleep 2
  [ $DELETED -ge $MAX_DELETIONS ] && break
done

echo "Total deleted: $DELETED/$MAX_DELETIONS"
