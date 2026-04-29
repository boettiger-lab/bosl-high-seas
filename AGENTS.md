# AI Agent Guide — bosl-high-seas

## Deployment model: public repo, git-clone initContainer

This repo is **public**. The pod's `git-clone` initContainer (`k8s/deployment.yaml`) runs `git clone --depth 1 https://github.com/boettiger-lab/bosl-high-seas.git` on each pod start and copies `index.html`, `layers-input.json`, and `system-prompt.md` into the nginx html dir. Pod content tracks `main`. The `k8s/configmap.yaml` ConfigMap holds only the LLM model list and the nginx reverse-proxy template — **not** website content.

## Repo relationship

| Repo | Purpose |
|---|---|
| `geo-agent` | Core library (map, chat, agent, tools). Source of truth for all functionality. |
| `bosl-high-seas` | Application repo. Configure `layers-input.json`, `system-prompt.md`, and `k8s/` for this dataset. |

**Full docs:** [boettiger-lab.github.io/geo-agent/docs](https://boettiger-lab.github.io/geo-agent/docs/)

---

## What you configure (and what you don't)

**You configure:** `layers-input.json`, `system-prompt.md`, `index.html`, and `k8s/` manifests.

**You do not write JavaScript.** Core modules are loaded from the CDN.

---

## Deployment

> **If you lack credentials or permissions** to run `kubectl` or `git push`, do not attempt to discover or work around credentials. Instead, provide the user with the exact commands to run.

```bash
# 1. Edit source files (index.html, layers-input.json, system-prompt.md)
# 2. Commit and push to main — the initContainer clones from GitHub
git add <source-files> && git commit -m "<message>" && git push
# 3. Restart the deployment so a new pod re-clones the latest main
kubectl rollout restart deployment/bosl-high-seas -n biodiversity
kubectl rollout status deployment/bosl-high-seas -n biodiversity
```

The git push does **not** update running pods — step 3 does.

If you change `k8s/configmap.yaml` (LLM model list or nginx template), apply it before the rollout: `kubectl apply -f k8s/configmap.yaml -n biodiversity`. Routine content edits don't need this.

### CDN versioning

`index.html` pins the geo-agent library version. Verify jsDelivr serves a new tag before deploying:

```bash
curl -sI https://cdn.jsdelivr.net/gh/boettiger-lab/geo-agent@vX.Y.Z/app/style.css | grep HTTP
# Must return HTTP/2 200 — a 404 means jsDelivr hasn't indexed the tag yet
```

For private data modules (rclone sidecar, oauth2-proxy, private parquet credentials): [docs/guide/private-deployment](https://boettiger-lab.github.io/geo-agent/docs/guide/private-deployment)

---

For full `layers-input.json` schema, troubleshooting, and configuration reference see the [geo-agent-template AGENTS.md](https://github.com/boettiger-lab/geo-agent-template/blob/main/AGENTS.md) or the [docs](https://boettiger-lab.github.io/geo-agent/docs/).
