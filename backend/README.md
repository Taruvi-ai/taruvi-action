# Taruvi Backend Import Action

Import backend configuration to Taruvi.

## Usage

```yaml
- name: Import Backend
  uses: Taruvi-ai/taruvi-action/backend@v1
  with:
    site-url: ${{ secrets.TARUVI_SITE_URL }}
    api-key: ${{ secrets.TARUVI_API_KEY }}
    config-dir: .taruvi-backend
```

## Inputs

| Input | Required | Default | Description |
|-------|----------|---------|-------------|
| `site-url` | Yes | - | Taruvi site URL (e.g., `https://api.taruvi.cloud/sites/my-site`) |
| `api-key` | Yes | - | Taruvi API key |
| `config-dir` | No | `.taruvi-backend` | Path to backend config directory |

## Outputs

| Output | Description |
|--------|-------------|
| `status` | Import status (`success` or `skipped`) |
| `message` | Status message |

## How It Works

1. Checks if the config directory exists and is not empty
2. If found: Zips the contents and imports via `/api/apps/imports/`
3. If not found: Skips with a notice (not an error)

## Backend Config Directory Structure

The `.taruvi-backend` directory should contain exported Taruvi app configuration:

```
.taruvi-backend/
├── datatables/
│   └── *.json
├── functions/
│   └── *.json
├── policies/
│   └── *.json
├── storage/
│   └── *.json
└── app.json
```

Use `taruvi export` CLI or the Taruvi Console export feature to generate this directory.

## Example

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
        id: import
        uses: Taruvi-ai/taruvi-action/backend@v1
        with:
          site-url: ${{ secrets.TARUVI_SITE_URL }}
          api-key: ${{ secrets.TARUVI_API_KEY }}

      - name: Print Status
        run: echo "Import status: ${{ steps.import.outputs.status }}"
```

## License

MIT
