# Taruvi Deploy Action

Deploy frontend and backend to Taruvi BaaS platform.

## Usage

```yaml
- name: Deploy to Taruvi
  uses: Taruvi-ai/taruvi-action@v1
  with:
    site-url: ${{ secrets.TARUVI_SITE_URL }}
    api-key: ${{ secrets.TARUVI_API_KEY }}
    app-slug: my-app
    frontend-zip-path: dist.zip
    backend-dir: .taruvi-backend
    branch-name: ${{ github.ref_name }}
```

## Inputs

| Input | Required | Default | Description |
|-------|----------|---------|-------------|
| `site-url` | Yes | - | Taruvi site URL (e.g., `https://api.taruvi.cloud/sites/my-site`) |
| `api-key` | Yes | - | Taruvi API key |
| `app-slug` | Yes | - | App slug for deployment |
| `frontend-zip-path` | No | `''` | Path to frontend build zip file. Skip frontend deploy if not provided. |
| `backend-dir` | No | `.taruvi-backend` | Path to backend config directory |
| `skip-frontend` | No | `false` | Skip frontend deployment |
| `skip-backend` | No | `false` | Skip backend import |
| `branch-name` | No | `''` | Branch name for subdomain suffix (used when creating new workers) |

## Outputs

| Output | Description |
|--------|-------------|
| `worker-slug` | Deployed frontend worker slug |
| `deploy-type` | Deploy type (`update`, `create`, or `skipped`) |
| `frontend-url` | Frontend worker URL |
| `backend-imported` | Whether backend was imported (`true`, `false`, or `skipped`) |

## Examples

### Full Deployment (Frontend + Backend)

```yaml
name: Deploy to Taruvi

on:
  push:
    branches: [main]

jobs:
  deploy:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - uses: actions/setup-node@v4
        with:
          node-version: '20'

      - name: Install and Build
        run: |
          npm install
          npm run build

      - name: Create ZIP
        run: cd dist && zip -r ../dist.zip . && cd ..

      - name: Deploy to Taruvi
        uses: Taruvi-ai/taruvi-action@v1
        with:
          site-url: ${{ secrets.TARUVI_SITE_URL }}
          api-key: ${{ secrets.TARUVI_API_KEY }}
          app-slug: my-app
          frontend-zip-path: dist.zip
          branch-name: ${{ github.ref_name }}
```

### Frontend Only

```yaml
- name: Deploy Frontend
  uses: Taruvi-ai/taruvi-action@v1
  with:
    site-url: ${{ secrets.TARUVI_SITE_URL }}
    api-key: ${{ secrets.TARUVI_API_KEY }}
    app-slug: my-app
    frontend-zip-path: dist.zip
    skip-backend: true
```

### Backend Only

```yaml
- name: Import Backend
  uses: Taruvi-ai/taruvi-action@v1
  with:
    site-url: ${{ secrets.TARUVI_SITE_URL }}
    api-key: ${{ secrets.TARUVI_API_KEY }}
    app-slug: my-app
    skip-frontend: true
    backend-dir: .taruvi-backend
```

### Using Outputs

```yaml
- name: Deploy to Taruvi
  id: deploy
  uses: Taruvi-ai/taruvi-action@v1
  with:
    site-url: ${{ secrets.TARUVI_SITE_URL }}
    api-key: ${{ secrets.TARUVI_API_KEY }}
    app-slug: my-app
    frontend-zip-path: dist.zip

- name: Print Results
  run: |
    echo "Worker: ${{ steps.deploy.outputs.worker-slug }}"
    echo "URL: ${{ steps.deploy.outputs.frontend-url }}"
    echo "Type: ${{ steps.deploy.outputs.deploy-type }}"
    echo "Backend: ${{ steps.deploy.outputs.backend-imported }}"
```

## How It Works

### Frontend Deployment

1. Checks if a default frontend worker is configured in app settings
2. If exists: Updates the worker with a new build and activates it
3. If not: Creates a new worker with subdomain `{app-slug}-{branch-name}`

### Backend Import

1. Checks if `.taruvi-backend` directory exists
2. If found: Zips the contents and imports via `/api/apps/imports/`
3. If not found: Skips with a notice (not an error)

## License

MIT
