# Taruvi Frontend Worker Deploy Action

Deploy frontend builds to Taruvi Frontend Workers.

## Usage

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

## Inputs

| Input | Required | Default | Description |
|-------|----------|---------|-------------|
| `site-url` | Yes | - | Taruvi site URL (e.g., `https://api.taruvi.cloud/sites/my-site`) |
| `api-key` | Yes | - | Taruvi API key |
| `app-slug` | Yes | - | App slug for deployment |
| `zip-path` | Yes | - | Path to frontend build zip file |
| `branch-name` | No | `''` | Branch name for subdomain suffix (used when creating new workers) |

## Outputs

| Output | Description |
|--------|-------------|
| `worker-slug` | Deployed frontend worker slug |
| `deploy-type` | Deploy type (`update` or `create`) |
| `frontend-url` | Frontend worker URL |

## How It Works

1. Checks if a default frontend worker is configured in app settings
2. If exists: Updates the worker with a new build and activates it
3. If not: Creates a new worker with subdomain `{app-slug}-{branch-name}`

## Example

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
        id: deploy
        uses: Taruvi-ai/taruvi-action/frontend-worker@v1
        with:
          site-url: ${{ secrets.TARUVI_SITE_URL }}
          api-key: ${{ secrets.TARUVI_API_KEY }}
          app-slug: my-app
          zip-path: dist.zip
          branch-name: ${{ github.ref_name }}

      - name: Print URL
        run: echo "Deployed to ${{ steps.deploy.outputs.frontend-url }}"
```

## License

MIT
