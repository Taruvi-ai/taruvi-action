# Taruvi Frontend Worker Deploy Action

Deploy frontend builds to Taruvi Frontend Workers.

## Usage

```yaml
- name: Deploy Frontend
  uses: Taruvi-ai/taruvi-action/frontend-worker@main
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
2. If one exists: uploads the build to that worker as its active build, in one request
3. If not: creates a worker for the app with subdomain `{app-slug}-{branch-name}`, uploads the build to it, and sets it as the app's default frontend worker, so the next run takes step 2. A worker already at that subdomain is reused if it belongs to this app or to no app.

A build is live as soon as its upload succeeds.

The branch name is lowercased and non-alphanumeric characters become hyphens, so `feature/Login-v2` yields the subdomain `{app-slug}-feature-login-v2`. With no `branch-name`, the subdomain is just `{app-slug}`.

## Failure behaviour

The action fails the step rather than deploying something misleading. Three cases are worth knowing about, because each of them used to pass silently.

**The settings lookup must succeed before anything else happens.** It decides between updating and creating, so a response that cannot be read is never treated as "this app has no worker yet" — that would create a duplicate worker on a transient error while the real one kept serving the old build. A non-2xx status, an unreachable host, or a body that is not JSON all stop the deploy.

Two statuses get a specific hint, because the cause is rarely what the status suggests:

| Status | Most likely cause |
|---|---|
| 401 / 403 | `site-url` and `api-key` came from **different Taruvi sites**. A key exists only in the schema of the site that issued it, so a valid key from site A simply does not exist on site B. Regenerating the key does not help. |
| 404 | `app-slug` is wrong, or the app belongs to a different site than `site-url` points at. |

**A new worker is not done until it is the app's default.** Without that, the next run would find no default and try to create the same worker again. If setting the default fails, the build is already live on the new worker but the step still fails; re-running the workflow reuses the worker and retries. A worker at `{app-slug}-{branch-name}` that belongs to a different app stops the deploy rather than being taken over.

**Outputs are only written on success.** No downstream step receives a `frontend-url` from a deploy that did not finish.

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
      - uses: actions/checkout@v7

      - uses: actions/setup-node@v7
        with:
          node-version: '22'

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
        uses: Taruvi-ai/taruvi-action/frontend-worker@main
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
