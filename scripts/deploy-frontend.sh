#!/bin/bash
set -e

# Taruvi Frontend Deploy Script
# Deploys frontend build to Taruvi Frontend Workers

SITE_URL="${INPUT_SITE_URL}"
API_KEY="${INPUT_API_KEY}"
APP_SLUG="${INPUT_APP_SLUG}"
FRONTEND_ZIP="${INPUT_FRONTEND_ZIP}"
BRANCH_NAME="${INPUT_BRANCH_NAME}"
SKIP_FRONTEND="${INPUT_SKIP_FRONTEND}"

# Check if frontend deployment should be skipped
if [[ "$SKIP_FRONTEND" == "true" ]]; then
  echo "::notice::Frontend deployment skipped (skip-frontend=true)"
  echo "deploy_type=skipped" >> "$GITHUB_OUTPUT"
  echo "worker_slug=" >> "$GITHUB_OUTPUT"
  echo "frontend_url=" >> "$GITHUB_OUTPUT"
  exit 0
fi

# Check if frontend zip path is provided
if [[ -z "$FRONTEND_ZIP" ]]; then
  echo "::notice::No frontend-zip-path provided. Skipping frontend deployment."
  echo "deploy_type=skipped" >> "$GITHUB_OUTPUT"
  echo "worker_slug=" >> "$GITHUB_OUTPUT"
  echo "frontend_url=" >> "$GITHUB_OUTPUT"
  exit 0
fi

# Validate frontend zip exists
if [[ ! -f "$FRONTEND_ZIP" ]]; then
  echo "::error::Frontend zip file not found: $FRONTEND_ZIP"
  exit 1
fi

echo "Deploying frontend to: $SITE_URL"
echo "App slug: $APP_SLUG"

# Get default frontend worker slug from app settings
echo "Checking for default frontend worker..."
SETTINGS_RESPONSE=$(curl -s \
  "${SITE_URL}/api/apps/${APP_SLUG}/settings/" \
  -H "Authorization: Api-Key ${API_KEY}" \
  --connect-timeout 30) || true

WORKER_SLUG=$(echo "$SETTINGS_RESPONSE" | jq -r '.data.default_frontend_worker_slug // empty')

if [[ -n "$WORKER_SLUG" && "$WORKER_SLUG" != "null" ]]; then
  # Worker exists - Update it
  echo "Found default worker: $WORKER_SLUG"
  echo "Uploading new build..."
  
  RESPONSE=$(curl -s -w "\n%{http_code}" \
    -X PATCH "${SITE_URL}/api/cloud/frontend_workers/${WORKER_SLUG}/" \
    -H "Authorization: Api-Key ${API_KEY}" \
    -F "file=@${FRONTEND_ZIP};type=application/zip" \
    --connect-timeout 30 \
    --max-time 300)
  
  HTTP_CODE=$(echo "$RESPONSE" | tail -n1)
  BODY=$(echo "$RESPONSE" | sed '$d')
  
  if [[ "$HTTP_CODE" -ge 200 && "$HTTP_CODE" -lt 300 ]]; then
    # Get the new build UUID and set it as active
    BUILD_UUID=$(echo "$BODY" | jq -r '.data.latest_build.uuid // empty')
    FRONTEND_URL=$(echo "$BODY" | jq -r '.data.web_url // empty')
    
    if [[ -n "$BUILD_UUID" && "$BUILD_UUID" != "null" ]]; then
      echo "Setting build $BUILD_UUID as active..."
      curl -s -X PATCH "${SITE_URL}/api/cloud/frontend_workers/${WORKER_SLUG}/set-active-build/" \
        -H "Authorization: Api-Key ${API_KEY}" \
        -H "Content-Type: application/json" \
        -d "{\"build_uuid\": \"${BUILD_UUID}\"}" \
        --connect-timeout 30 || true
    fi
    
    echo "::notice::Frontend deployment successful! (updated existing worker: $WORKER_SLUG)"
    echo "worker_slug=$WORKER_SLUG" >> "$GITHUB_OUTPUT"
    echo "deploy_type=update" >> "$GITHUB_OUTPUT"
    echo "frontend_url=$FRONTEND_URL" >> "$GITHUB_OUTPUT"
  else
    echo "::error::Failed to update frontend worker (HTTP $HTTP_CODE)"
    echo "$BODY"
    exit 1
  fi
else
  # No default worker - Create new one with branch suffix
  echo "No default frontend worker. Creating new worker..."
  
  # Build subdomain with optional branch suffix
  if [[ -n "$BRANCH_NAME" ]]; then
    BRANCH_SUFFIX=$(echo "$BRANCH_NAME" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9]/-/g' | sed 's/--*/-/g' | sed 's/^-//' | sed 's/-$//')
    SUBDOMAIN="${APP_SLUG}-${BRANCH_SUFFIX}"
  else
    SUBDOMAIN="${APP_SLUG}"
  fi
  
  echo "Subdomain: $SUBDOMAIN"
  
  RESPONSE=$(curl -s -w "\n%{http_code}" \
    -X POST "${SITE_URL}/api/cloud/frontend_workers/" \
    -H "Authorization: Api-Key ${API_KEY}" \
    -F "file=@${FRONTEND_ZIP};type=application/zip" \
    -F "name=${APP_SLUG}" \
    -F "subdomain_input=${SUBDOMAIN}" \
    -F "is_internal=true" \
    --connect-timeout 30 \
    --max-time 300)
  
  HTTP_CODE=$(echo "$RESPONSE" | tail -n1)
  BODY=$(echo "$RESPONSE" | sed '$d')
  
  if [[ "$HTTP_CODE" -ge 200 && "$HTTP_CODE" -lt 300 ]]; then
    NEW_WORKER_SLUG=$(echo "$BODY" | jq -r '.data.slug // empty')
    FRONTEND_URL=$(echo "$BODY" | jq -r '.data.web_url // empty')
    
    echo "::notice::Frontend deployment successful! (created new worker: $NEW_WORKER_SLUG)"
    echo "worker_slug=$NEW_WORKER_SLUG" >> "$GITHUB_OUTPUT"
    echo "deploy_type=create" >> "$GITHUB_OUTPUT"
    echo "frontend_url=$FRONTEND_URL" >> "$GITHUB_OUTPUT"
  else
    echo "::error::Failed to create frontend worker (HTTP $HTTP_CODE)"
    echo "$BODY"
    exit 1
  fi
fi
