#!/bin/bash
set -e

# Taruvi Backend Import Script
# Imports backend configuration to Taruvi

SITE_URL="${INPUT_SITE_URL}"
API_KEY="${INPUT_API_KEY}"
BACKEND_DIR="${INPUT_BACKEND_DIR}"
SKIP_BACKEND="${INPUT_SKIP_BACKEND}"

# Check if backend import should be skipped
if [[ "$SKIP_BACKEND" == "true" ]]; then
  echo "::notice::Backend import skipped (skip-backend=true)"
  echo "status=skipped" >> "$GITHUB_OUTPUT"
  exit 0
fi

# Check if backend directory exists
if [[ ! -d "$BACKEND_DIR" ]]; then
  echo "::notice::No backend configuration found at '$BACKEND_DIR'. Skipping backend import."
  echo "status=skipped" >> "$GITHUB_OUTPUT"
  exit 0
fi

# Check if directory is empty
if [[ -z "$(ls -A $BACKEND_DIR)" ]]; then
  echo "::notice::Backend directory '$BACKEND_DIR' is empty. Skipping backend import."
  echo "status=skipped" >> "$GITHUB_OUTPUT"
  exit 0
fi

echo "Found backend configuration at '$BACKEND_DIR'"

# Create ZIP archive of backend config
BACKEND_ZIP="backend-config.zip"
cd "$BACKEND_DIR"
zip -r "../$BACKEND_ZIP" .
cd ..

if [[ ! -f "$BACKEND_ZIP" ]]; then
  echo "::error::Failed to create backend ZIP archive"
  exit 1
fi

ZIP_SIZE=$(du -sh "$BACKEND_ZIP" | cut -f1)
echo "Backend ZIP size: $ZIP_SIZE"

# Import backend configuration
echo "Importing backend configuration..."
RESPONSE=$(curl -s -w "\n%{http_code}" \
  -X POST "${SITE_URL}/api/apps/imports/" \
  -H "Authorization: Api-Key ${API_KEY}" \
  -F "file=@${BACKEND_ZIP};type=application/zip" \
  --connect-timeout 30 \
  --max-time 300)

HTTP_CODE=$(echo "$RESPONSE" | tail -n1)
BODY=$(echo "$RESPONSE" | sed '$d')

# Cleanup
rm -f "$BACKEND_ZIP"

if [[ "$HTTP_CODE" -ge 200 && "$HTTP_CODE" -lt 300 ]]; then
  echo "::notice::Backend import successful!"
  echo "$BODY"
  echo "status=success" >> "$GITHUB_OUTPUT"
else
  echo "::error::Failed to import backend configuration (HTTP $HTTP_CODE)"
  echo "$BODY"
  exit 1
fi
