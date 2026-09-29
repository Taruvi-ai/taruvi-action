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

# api METHOD URL MAX_TIME [curl args...]
# Sends an authenticated request and sets HTTP_CODE and BODY. HTTP_CODE is 000
# when no HTTP response came back (DNS, TLS, timeout).
api() {
  local method="$1" url="$2" max_time="$3" response
  shift 3
  response=$(curl -s -w "\n%{http_code}" -X "$method" "$url" \
    -H "Authorization: Api-Key ${API_KEY}" \
    --connect-timeout 30 \
    --max-time "$max_time" \
    "$@") || true
  HTTP_CODE=$(echo "$response" | tail -n1)
  BODY=$(echo "$response" | sed '$d')
  [[ "$HTTP_CODE" =~ ^[0-9]{3}$ ]] || HTTP_CODE=000
}

is_2xx() {
  [[ "$HTTP_CODE" -ge 200 && "$HTTP_CODE" -lt 300 ]]
}

# json FILTER — reads a field from BODY; empty when missing, null, or not JSON.
json() {
  echo "$BODY" | jq -r "$1 // empty" 2>/dev/null || true
}

# fail MESSAGE — reports the last request's status and body, then stops.
fail() {
  if [[ "$HTTP_CODE" == "000" ]]; then
    echo "::error::$1 (no HTTP response from ${SITE_URL})."
  else
    echo "::error::$1 (HTTP ${HTTP_CODE})."
    echo "$BODY"
  fi
  exit 1
}

# upload_build METHOD URL [curl args...]
# Uploads the zip with set_active=true. The platform extracts an upload straight
# into the worker's live domain, so a 2xx means the build is already serving;
# set_active records it as the active build in the same request.
upload_build() {
  local method="$1" url="$2"
  shift 2
  api "$method" "$url" 300 \
    -F "file=@${FRONTEND_ZIP};type=application/zip" \
    -F "set_active=true" \
    "$@"
}

# Get default frontend worker slug from app settings.
#
# This lookup decides between updating the existing worker and creating a new
# one, so it must succeed before we act on it. A failed or unreadable response
# is NOT treated as "no default worker" — doing so would create a duplicate
# worker on a transient error and leave the real one serving the old build.
echo "Checking for default frontend worker..."
api GET "${SITE_URL}/api/apps/${APP_SLUG}/settings/" 60

if [[ "$HTTP_CODE" == "000" ]]; then
  echo "::error::Could not reach ${SITE_URL} to read app settings (no HTTP response)."
  echo "::error::Check that site-url is correct and reachable."
  exit 1
fi

if ! is_2xx; then
  echo "::error::Could not read settings for app '${APP_SLUG}' (HTTP ${HTTP_CODE})."
  case "$HTTP_CODE" in
    401|403) echo "::error::Credentials were rejected. An API key is only valid on the site that issued it — confirm site-url and api-key came from the same Taruvi site." ;;
    404)     echo "::error::App '${APP_SLUG}' not found on ${SITE_URL}. Check app-slug, and that the app belongs to this site." ;;
  esac
  echo "$BODY"
  exit 1
fi

if ! echo "$BODY" | jq -e . >/dev/null 2>&1; then
  echo "::error::App settings response was not valid JSON (HTTP ${HTTP_CODE})."
  echo "$BODY"
  exit 1
fi

WORKER_SLUG=$(json '.data.default_frontend_worker_slug')
SET_DEFAULT=false

if [[ -n "$WORKER_SLUG" ]]; then
  # Worker exists - Update it
  echo "Found default worker: $WORKER_SLUG"
  echo "Uploading new build..."
  upload_build PATCH "${SITE_URL}/api/cloud/frontend_workers/${WORKER_SLUG}/"
  is_2xx || fail "Failed to upload the build to worker $WORKER_SLUG"
  DEPLOY_TYPE=update
else
  # No default worker - deploy to a worker with branch suffix, then make it the
  # app's default so the next run takes the update path above.
  if [[ -n "$BRANCH_NAME" ]]; then
    BRANCH_SUFFIX=$(echo "$BRANCH_NAME" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9]/-/g' | sed 's/--*/-/g' | sed 's/^-//' | sed 's/-$//')
    WORKER_SLUG="${APP_SLUG}-${BRANCH_SUFFIX}"
  else
    WORKER_SLUG="${APP_SLUG}"
  fi
  SET_DEFAULT=true

  echo "No default frontend worker. Target worker: $WORKER_SLUG"

  # A worker can already exist at this slug without being the default: created
  # by a run that failed before setting it, or by an older version of this
  # action that never did. Reuse it instead of failing on the taken subdomain.
  api GET "${SITE_URL}/api/cloud/frontend_workers/${WORKER_SLUG}/" 60

  if [[ "$HTTP_CODE" == "404" ]]; then
    echo "Creating worker $WORKER_SLUG..."
    upload_build POST "${SITE_URL}/api/cloud/frontend_workers/" \
      -F "name=${APP_SLUG}" \
      -F "subdomain_input=${WORKER_SLUG}" \
      -F "is_internal=true" \
      -F "app=${APP_SLUG}"
    is_2xx || fail "Failed to create frontend worker $WORKER_SLUG"
    CREATED_SLUG=$(json '.data.slug')
    WORKER_SLUG="${CREATED_SLUG:-$WORKER_SLUG}"
    DEPLOY_TYPE=create
  elif is_2xx; then
    OWNER_APP=$(json '.data.app')
    if [[ -n "$OWNER_APP" && "$OWNER_APP" != "$APP_SLUG" ]]; then
      echo "::error::Worker $WORKER_SLUG already exists and belongs to app '${OWNER_APP}', not '${APP_SLUG}'."
      echo "::error::Use a different branch-name, or set this app's default frontend worker in its settings."
      exit 1
    fi
    echo "Found worker $WORKER_SLUG, not yet the app's default. Uploading new build..."
    upload_build PATCH "${SITE_URL}/api/cloud/frontend_workers/${WORKER_SLUG}/" \
      -F "app=${APP_SLUG}"
    is_2xx || fail "Failed to upload the build to worker $WORKER_SLUG"
    DEPLOY_TYPE=update
  else
    fail "Could not check for an existing worker $WORKER_SLUG"
  fi
fi

FRONTEND_URL=$(json '.data.web_url')

if [[ "$SET_DEFAULT" == "true" ]]; then
  # App settings take the worker's URL, not its slug, and accept only a worker
  # that belongs to the app — which the request above made sure of.
  if [[ -z "$FRONTEND_URL" ]]; then
    echo "::error::Worker $WORKER_SLUG is deployed, but the response had no web_url, so it could not be set as the default for app '${APP_SLUG}'."
    echo "::error::Re-run the workflow to retry; it reuses the worker."
    echo "$BODY"
    exit 1
  fi

  echo "Setting $WORKER_SLUG as the default frontend worker for app '${APP_SLUG}'..."
  api PATCH "${SITE_URL}/api/apps/${APP_SLUG}/settings/" 60 \
    -H "Content-Type: application/json" \
    -d "$(jq -n --arg url "$FRONTEND_URL" '{default_frontend_worker_url: $url}')"

  if ! is_2xx; then
    echo "::error::Worker $WORKER_SLUG is serving this build at $FRONTEND_URL, but could not be set as the default for app '${APP_SLUG}'."
    echo "::error::Re-run the workflow to retry; it reuses the worker."
    fail "Setting the default frontend worker failed"
  fi
fi

if [[ "$DEPLOY_TYPE" == "create" ]]; then
  echo "::notice::Frontend deployment successful! (created new worker: $WORKER_SLUG)"
else
  echo "::notice::Frontend deployment successful! (updated existing worker: $WORKER_SLUG)"
fi
echo "worker_slug=$WORKER_SLUG" >> "$GITHUB_OUTPUT"
echo "deploy_type=$DEPLOY_TYPE" >> "$GITHUB_OUTPUT"
echo "frontend_url=$FRONTEND_URL" >> "$GITHUB_OUTPUT"
