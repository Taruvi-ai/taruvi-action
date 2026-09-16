# Taruvi Backend Import Action

Import backend configuration to Taruvi.

## Usage

```yaml
- name: Import Backend
  uses: Taruvi-ai/taruvi-action/backend@v1
  with:
    site-url: ${{ vars.TARUVI_SITE_URL }}
    api-key: ${{ secrets.TARUVI_API_KEY }}
    config-dir: .taruvi-backend
```

Only `api-key` is a secret. See [Handling credentials](../README.md#handling-credentials) in the root README for why `site-url` belongs in `vars`, and how to lay out one GitHub Environment per branch.

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

## How It Works

1. Checks if the config directory exists and is not empty
2. If found: Zips the contents and imports via `/api/apps/imports/`
3. If not found: Skips with a notice (not an error)

## Failure behaviour

A missing or empty `config-dir` is not a failure — the action reports `status=skipped` and the job continues.

Everything past that point is a hard failure: a zip that cannot be created, or a non-2xx response from the import endpoint, fails the step and prints the response body.

`status` is only ever `success` or `skipped`. There is no failure value, because a failed import fails the step instead of reporting itself downstream.

If credentials are rejected, check that `site-url` and `api-key` came from the same Taruvi site — a key is only valid on the site that issued it. See [Handling credentials](../README.md#handling-credentials).

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
    environment: ${{ github.ref_name }}
    steps:
      - uses: actions/checkout@v4

      - name: Import Backend
        id: import
        uses: Taruvi-ai/taruvi-action/backend@v1
        with:
          site-url: ${{ vars.TARUVI_SITE_URL }}
          api-key: ${{ secrets.TARUVI_API_KEY }}

      - name: Print Status
        run: echo "Import status: ${{ steps.import.outputs.status }}"
```

`environment:` requires a `push` trigger. For `pull_request` events `github.ref` is `refs/pull/<n>/merge`, which no deployment branch policy matches, so environment secrets are withheld from the job.

## License

MIT
