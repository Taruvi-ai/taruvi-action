# Setup Guide

Set up automatic deploys to Taruvi on every merge to `dev` or `main`.

Three steps: collect your values, add them to GitHub, copy the workflow file.

---

## Step 1 — Collect your values

Open your app in the **Taruvi Console → Connect** page and copy:

| Value | Example |
|---|---|
| Site URL | `https://api.taruvi.cloud/sites/my-site` |
| API key | `14de44e0e32e...` |
| App slug | `my-app` |

Copy all three from the **same** Connect page. An API key only works on the site that issued it.

Repeat for each instance you deploy to (one for `dev`, one for `main`).

---

## Step 2 — Add them to GitHub

Go to **Settings → Environments** and create one environment per branch, named **exactly** after the branch:

- `main`
- `dev`

In each environment add the following. Names are identical in both environments — only the values differ.

**Secrets** (Settings → Environments → *your env* → Environment secrets)

| Name | Value |
|---|---|
| `TARUVI_API_KEY` | Your API key |

**Variables** (same page → Environment variables)

| Name | Value |
|---|---|
| `TARUVI_SITE_URL` | Your site URL |
| `TARUVI_APP_SLUG` | Your app slug |
| `TARUVI_APP_TITLE` | Display name, e.g. `My App` |

Put the API key in **Secrets**, never in Variables. Variables are plaintext and readable by anyone with repo read access.

---

## Step 3 — Create the workflow

Create the file `.github/workflows/deploy.yml` and paste this in as-is. No edits needed.

```yaml
name: Deploy to Taruvi

on:
  push:
    branches: [main, dev]
  workflow_dispatch:

concurrency:
  group: deploy-${{ github.ref_name }}
  cancel-in-progress: true

jobs:
  deploy:
    runs-on: ubuntu-latest
    environment: ${{ github.ref_name }}

    steps:
      - uses: actions/checkout@v4

      - uses: actions/setup-node@v4
        with:
          node-version: '20'
          cache: 'npm'

      - name: Install dependencies
        run: npm ci

      - name: Build frontend
        run: npm run build
        env:
          TARUVI_SITE_URL: ${{ vars.TARUVI_SITE_URL }}
          TARUVI_APP_SLUG: ${{ vars.TARUVI_APP_SLUG }}
          TARUVI_APP_TITLE: ${{ vars.TARUVI_APP_TITLE }}
          TARUVI_API_KEY: ${{ secrets.TARUVI_API_KEY }}

      - name: Create ZIP
        run: cd dist && zip -r ../dist.zip . && cd ..

      - name: Deploy frontend worker
        id: frontend
        uses: Taruvi-ai/taruvi-action/frontend-worker@v1
        with:
          site-url: ${{ vars.TARUVI_SITE_URL }}
          api-key: ${{ secrets.TARUVI_API_KEY }}
          app-slug: ${{ vars.TARUVI_APP_SLUG }}
          zip-path: dist.zip
          branch-name: ${{ github.ref_name }}

      - name: Import backend config
        id: backend
        uses: Taruvi-ai/taruvi-action/backend@v1
        with:
          site-url: ${{ vars.TARUVI_SITE_URL }}
          api-key: ${{ secrets.TARUVI_API_KEY }}
          config-dir: .taruvi-backend

      - name: Summary
        run: |
          echo "Frontend: ${{ steps.frontend.outputs.frontend-url }}"
          echo "Backend:  ${{ steps.backend.outputs.status }}"
```

Commit it to `main` and `dev`. Done.

---

## What happens on merge

1. Frontend is built and zipped.
2. The build is uploaded to your app's frontend worker and activated. If the app has no worker yet, one is created at `{app-slug}-{branch}`.
3. If a `.taruvi-backend/` directory exists, its contents are imported. If not, the step reports `skipped` and the run still passes.
4. The deployed URL is printed in the **Summary** step.

---

## Adjustments

**Different branches** — change both the trigger list and your environment names to match:

```yaml
on:
  push:
    branches: [main, staging]
```

**Frontend only** — delete the `Import backend config` step.

**Backend only** — delete the setup-node, install, build, ZIP, and frontend steps.

**Backend config in another folder** — change `config-dir`.

**Skip deploys for docs-only changes:**

```yaml
on:
  push:
    branches: [main, dev]
    paths-ignore:
      - '**.md'
```

---

## Troubleshooting

| Symptom | Fix |
|---|---|
| `Invalid token.` / 401 / 403 | `TARUVI_SITE_URL` and `TARUVI_API_KEY` are from different sites. Re-copy both from one Connect page. Regenerating the key will not help. |
| 404 on app settings | `TARUVI_APP_SLUG` is wrong, or the app is on a different site than `TARUVI_SITE_URL`. |
| Secrets come through empty | Environment name must match the branch name exactly (`main`, not `Main`). Also check the values are on the environment, not only at repo level. |
| `dist.zip: No such file` | Build produced no `dist/`. Check the `Build frontend` step log. |
| Backend step says `skipped` | No `.taruvi-backend/` directory in the repo. Expected if you have no backend config. |
| Nothing runs on merge | Workflow file must exist on the target branch, and the trigger is `push` — not `pull_request`. |

Environment secrets are only available to `push` events. Don't switch the trigger to `pull_request`; a merged PR pushes to its target branch, which gives the same result.
