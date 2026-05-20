# Taruvi Actions

GitHub Actions for deploying to Taruvi BaaS platform.

## Available Actions

| Action | Description |
|--------|-------------|
| [`frontend-worker`](#frontend-worker-action) | Deploy frontend to Taruvi Frontend Workers |
| [`backend`](#backend-action) | Import backend configuration |

---

## Frontend Worker Action

Deploy frontend builds to Taruvi Frontend Workers.

```yaml
- name: Deploy Frontend
  uses: Taruvi-ai/taruvi-action/frontend-worker@v1
  with:
    site-url: ${{ secrets.TARUVI_SITE_URL }}
    api-key: ${{ secrets.TARUVI_API_KEY }}
    app-slug: my-app
    zip-path: dist.zip
    branch-name: ${{ github.ref_name }}
```

### Inputs

| Input | Required | Default | Description |
|-------|----------|---------|-------------|
| `site-url` | Yes | - | Taruvi site URL |
| `api-key` | Yes | - | Taruvi API key |
| `app-slug` | Yes | - | App slug for deployment |
| `zip-path` | Yes | - | Path to frontend build zip file |
| `branch-name` | No | `''` | Branch name for subdomain suffix |

### Outputs

| Output | Description |
|--------|-------------|
| `worker-slug` | Deployed frontend worker slug |
| `deploy-type` | Deploy type (`update` or `create`) |
| `frontend-url` | Frontend worker URL |

### How It Works

1. Checks if a default frontend worker is configured in app settings
2. If exists: Updates the worker with a new build and activates it
3. If not: Creates a new worker with subdomain `{app-slug}-{branch-name}`

---

## Backend Action

Import backend configuration to Taruvi.

```yaml
- name: Import Backend
  uses: Taruvi-ai/taruvi-action/backend@v1
  with:
    site-url: ${{ secrets.TARUVI_SITE_URL }}
    api-key: ${{ secrets.TARUVI_API_KEY }}
    config-dir: .taruvi-backend
```

### Inputs

| Input | Required | Default | Description |
|-------|----------|---------|-------------|
| `site-url` | Yes | - | Taruvi site URL |
| `api-key` | Yes | - | Taruvi API key |
| `config-dir` | No | `.taruvi-backend` | Path to backend config directory |

### Outputs

| Output | Description |
|--------|-------------|
| `status` | Import status (`success` or `skipped`) |
| `message` | Status message |

### How It Works

1. Checks if the config directory exists and is not empty
2. If found: Zips the contents and imports via `/api/apps/imports/`
3. If not found: Skips with a notice (not an error)

---

## Examples

### Frontend Only

```yaml
name: Deploy Frontend

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

      - name: Deploy Frontend
        id: frontend
        uses: Taruvi-ai/taruvi-action/frontend-worker@v1
        with:
          site-url: ${{ secrets.TARUVI_SITE_URL }}
          api-key: ${{ secrets.TARUVI_API_KEY }}
          app-slug: my-app
          zip-path: dist.zip
          branch-name: main

      - name: Print URL
        run: echo "Deployed to ${{ steps.frontend.outputs.frontend-url }}"
```

### Backend Only

```yaml
name: Import Backend Config

on:
  push:
    branches: [main]
    paths:
      - '.taruvi-backend/**'

jobs:
  import:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - name: Import Backend
        id: backend
        uses: Taruvi-ai/taruvi-action/backend@v1
        with:
          site-url: ${{ secrets.TARUVI_SITE_URL }}
          api-key: ${{ secrets.TARUVI_API_KEY }}

      - name: Print Status
        run: echo "Import status: ${{ steps.backend.outputs.status }}"
```

### Full Deployment

```yaml
- name: Deploy Frontend
  id: frontend
  uses: Taruvi-ai/taruvi-action/frontend-worker@v1
  with:
    site-url: ${{ secrets.TARUVI_SITE_URL }}
    api-key: ${{ secrets.TARUVI_API_KEY }}
    app-slug: my-app
    zip-path: dist.zip
    branch-name: main

- name: Import Backend
  id: backend
  uses: Taruvi-ai/taruvi-action/backend@v1
  with:
    site-url: ${{ secrets.TARUVI_SITE_URL }}
    api-key: ${{ secrets.TARUVI_API_KEY }}

- name: Summary
  run: |
    echo "Frontend: ${{ steps.frontend.outputs.frontend-url }}"
    echo "Backend: ${{ steps.backend.outputs.status }}"
```

---

## License

MIT
