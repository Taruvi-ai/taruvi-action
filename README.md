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
    site-url: ${{ vars.TARUVI_SITE_URL }}
    api-key: ${{ secrets.TARUVI_API_KEY }}
    app-slug: ${{ vars.TARUVI_APP_SLUG }}
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

1. Reads the app's settings to find its default frontend worker
2. If one exists: uploads the build to that worker, then activates it
3. If not: creates a new worker with subdomain `{app-slug}-{branch-name}`

### Failure behaviour

The action fails the step rather than deploying something misleading. Three cases are worth knowing about, because each of them used to pass silently.

**The settings lookup must succeed before anything else happens.** It decides between updating and creating, so a response that cannot be read is never treated as "this app has no worker yet" — that would create a duplicate worker on a transient error while the real one kept serving the old build. A non-2xx status, an unreachable host, or a body that is not JSON all stop the deploy.

Two statuses get a specific hint, because the cause is rarely what the status suggests:

| Status | Most likely cause |
|---|---|
| 401 / 403 | `site-url` and `api-key` came from **different Taruvi sites**. A key exists only in the schema of the site that issued it, so a valid key from site A simply does not exist on site B. Regenerating the key does not help. |
| 404 | `app-slug` is wrong, or the app belongs to a different site than `site-url` points at. |

**Uploading a build is not the same as making it live.** After a successful upload the action activates the new build, and treats failure to do so as a deploy failure — a green run over a site still serving the previous build is the one outcome a deploy tool must never produce. If activation fails, the uploaded build is left in place but inactive; it is not rolled back, and re-running uploads another build.

**Outputs are only written on success.** No downstream step receives a `frontend-url` for a build that is not live.

---

## Backend Action

Import backend configuration to Taruvi.

```yaml
- name: Import Backend
  uses: Taruvi-ai/taruvi-action/backend@v1
  with:
    site-url: ${{ vars.TARUVI_SITE_URL }}
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

### How It Works

1. Checks if the config directory exists and is not empty
2. If found: Zips the contents and imports via `/api/apps/imports/`
3. If not found: Skips with a notice (not an error)

---

## Handling credentials

Both actions take `site-url` and `api-key` as inputs. Composite actions cannot read the `secrets` context themselves, so the calling workflow must pass them in. Three rules when you do:

**Only the API key is a secret.** Store `site-url` and `app-slug` as Actions **variables** (`vars.*`). Neither is a credential, and the site URL ends up in your app's browser bundle anyway. Keeping them unmasked matters when you are debugging a 404 — a redacted site URL tells you nothing.

The reverse mistake is the dangerous one. **Never store an API key as a variable.** Variables are plaintext: unmasked in logs, visible in the Settings UI, and returned by the REST API to anyone with read access to the repo. Secrets are write-only and masked. The two columns look interchangeable in the UI and are not.

**Reference secrets by literal name, at the step that uses them.** Do not load the whole secrets context:

```yaml
# Don't — exposes every repository secret to the runner
env:
  ALL_SECRETS: ${{ toJson(secrets) }}
```

The job needs two values; `toJson(secrets)` hands it all of them, including unrelated tokens and keys. Anything running in that job can read the lot, and `npm install` executes a lot of third-party code. Datadog documents the pattern as [overprovisioned secrets](https://docs.datadoghq.com/security/code_security/iac_security/iac_rules/cicd-github-overprovisioned-secrets/), noting that referencing the full secrets context exposes every repository secret to the runner instead of only the ones the job requires. *(Content rephrased for compliance with licensing restrictions.)*

**Never write a credential to `$GITHUB_OUTPUT`.** Step outputs are run metadata, not secret storage, and `::add-mask::` only redacts log text — it does not make an output a secret:

```yaml
# Don't — persists the key into workflow run state
run: echo "api_key=$API_KEY" >> "$GITHUB_OUTPUT"
```

Pass secrets straight into `with:` instead, as the examples below do.

The recommended shape is a **GitHub Environment per branch**, named after the branch, each holding the same three names — `TARUVI_API_KEY` as a secret, `TARUVI_SITE_URL` and `TARUVI_APP_SLUG` as variables — with values taken from that instance's Connect page in the Taruvi Console. `environment: ${{ github.ref_name }}` then picks the right set, and a job targeting one branch cannot reach another environment's secrets. Adding an instance needs no new secret names.

Take all three values from the same Connect page in one sitting. An API key is only valid on the site that issued it, so a key from one site paired with another site's URL fails as `Invalid token.` — which reads like an expired key and prompts people to regenerate, and regenerating cannot fix it.

Environments require a `push` trigger rather than `pull_request`. For `pull_request` events `github.ref` is `refs/pull/<n>/merge`, which no deployment branch policy matches, so environment secrets are withheld from the job. A merged PR pushes to its target branch, so triggering on `push` gives the same behaviour.

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
        id: frontend
        uses: Taruvi-ai/taruvi-action/frontend-worker@v1
        with:
          site-url: ${{ vars.TARUVI_SITE_URL }}
          api-key: ${{ secrets.TARUVI_API_KEY }}
          app-slug: ${{ vars.TARUVI_APP_SLUG }}
          zip-path: dist.zip
          branch-name: ${{ github.ref_name }}

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
    environment: ${{ github.ref_name }}
    steps:
      - uses: actions/checkout@v4

      - name: Import Backend
        id: backend
        uses: Taruvi-ai/taruvi-action/backend@v1
        with:
          site-url: ${{ vars.TARUVI_SITE_URL }}
          api-key: ${{ secrets.TARUVI_API_KEY }}

      - name: Print Status
        run: |
          echo "Import status: ${{ steps.backend.outputs.status }}"
```

### Full Deployment

```yaml
- name: Deploy Frontend
  id: frontend
  uses: Taruvi-ai/taruvi-action/frontend-worker@v1
  with:
    site-url: ${{ vars.TARUVI_SITE_URL }}
    api-key: ${{ secrets.TARUVI_API_KEY }}
    app-slug: ${{ vars.TARUVI_APP_SLUG }}
    zip-path: dist.zip
    branch-name: ${{ github.ref_name }}

- name: Import Backend
  id: backend
  uses: Taruvi-ai/taruvi-action/backend@v1
  with:
    site-url: ${{ vars.TARUVI_SITE_URL }}
    api-key: ${{ secrets.TARUVI_API_KEY }}

- name: Summary
  run: |
    echo "Frontend: ${{ steps.frontend.outputs.frontend-url }}"
    echo "Backend: ${{ steps.backend.outputs.status }}"
```

---

## License

MIT
