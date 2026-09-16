# Taruvi Frontend Worker Deploy Action

Deploy frontend builds to Taruvi Frontend Workers.

## Usage

```yaml
- name: Deploy Frontend
  uses: Taruvi-ai/taruvi-action/frontend-worker@v1
  with:
    site-url: ${{ vars.TARUVI_SITE_URL }}
    api-key: ${{ secrets.TARUVI_API_KEY }}
    app-slug: ${{ vars.TARUVI_APP_SLUG }}
    zip-path: dist.zip
    branch-name: ${{ github.ref_name }}
```

Only `api-key` is a secret. See [Handling credentials](../README.md#handling-credentials) in the root README for why `site-url` and `app-slug` belong in `vars`, and how to lay out one GitHub Environment per branch.

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

1. Reads the app's settings to find its default frontend worker
2. If one exists: uploads the build to that worker, then activates it
3. If not: creates a new worker with subdomain `{app-slug}-{branch-name}`

The branch name is lowercased and non-alphanumeric characters become hyphens, so `feature/Login-v2` yields the subdomain `{app-slug}-feature-login-v2`. With no `branch-name`, the subdomain is just `{app-slug}`.

## Failure behaviour

The action fails the step rather than deploying something misleading. Three cases are worth knowing about, because each of them used to pass silently.

**The settings lookup must succeed before anything else happens.** It decides between updating and creating, so a response that cannot be read is never treated as "this app has no worker yet" — that would create a duplicate worker on a transient error while the real one kept serving the old build. A non-2xx status, an unreachable host, or a body that is not JSON all stop the deploy.

Two statuses get a specific hint, because the cause is rarely what the status suggests:

| Status | Most likely cause |
|---|---|
| 401 / 403 | `site-url` and `api-key` came from **different Taruvi sites**. A key exists only in the schema of the site that issued it, so a valid key from site A simply does not exist on site B. Regenerating the key does not help. |
| 404 | `app-slug` is wrong, or the app belongs to a different site than `site-url` points at. |

**Uploading a build is not the same as making it live.** After a successful upload the action activates the new build, and treats failure to do so as a deploy failure — a green run over a site still serving the previous build is the one outcome a deploy tool must never produce. If activation fails, the uploaded build is left in place but inactive; it is not rolled back, and re-running uploads another build.

**Outputs are only written on success.** No downstream step receives a `frontend-url` for a build that is not live.

## Example

```yaml
name: Deploy Frontend

on:
  push:
    branches: [main]

jobs:
  deploy:
    runs-on: ubuntu-latest
    environment: ${{ github.ref_name }}
    steps:
      - uses: actions/checkout@v4

      - uses: actions/setup-node@v4
        with:
          node-version: '20'

      # Kept as separate steps so the build can take env vars without
      # accidentally handing them to the install.
      - name: Install
        run: npm ci

      - name: Build
        run: npm run build

      - name: Create ZIP
        run: cd dist && zip -r ../dist.zip . && cd ..

      - name: Deploy Frontend
        id: deploy
        uses: Taruvi-ai/taruvi-action/frontend-worker@v1
        with:
          site-url: ${{ vars.TARUVI_SITE_URL }}
          api-key: ${{ secrets.TARUVI_API_KEY }}
          app-slug: ${{ vars.TARUVI_APP_SLUG }}
          zip-path: dist.zip
          branch-name: ${{ github.ref_name }}

      - name: Print URL
        run: echo "Deployed to ${{ steps.deploy.outputs.frontend-url }}"
```

`environment:` requires a `push` trigger. For `pull_request` events `github.ref` is `refs/pull/<n>/merge`, which no deployment branch policy matches, so environment secrets are withheld from the job.

## License

MIT
