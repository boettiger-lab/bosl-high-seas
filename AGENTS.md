# AI Agent Guide — bosl-high-seas

## ⚠ PRIVATE REPO — ConfigMap deployment

This repo is **private**. The k8s pod does **not** git-clone at startup — it reads content from a k8s ConfigMap. Do not apply public-repo deployment patterns here.

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

**Never edit `k8s/content-configmap.yaml` directly** — it is generated from source files.

```bash
# 1. Edit source files (index.html, layers-input.json, system-prompt.md)
# 2. Regenerate the ConfigMap
bash scripts/generate-configmap.sh
# 3. Apply and restart
kubectl apply -f k8s/content-configmap.yaml -n <namespace>
kubectl rollout restart deployment/bosl-high-seas -n <namespace>
kubectl rollout status deployment/bosl-high-seas -n <namespace>
# 4. Commit and push
git add <source-files> k8s/content-configmap.yaml && git commit -m "<message>" && git push
```

The git push does **not** update running pods — step 3 does.

### CDN versioning

`index.html` pins the geo-agent library version. Verify jsDelivr serves a new tag before deploying:

```bash
curl -sI https://cdn.jsdelivr.net/gh/boettiger-lab/geo-agent@vX.Y.Z/app/style.css | grep HTTP
# Must return HTTP/2 200 — a 404 means jsDelivr hasn't indexed the tag yet
```

For private data modules (rclone sidecar, oauth2-proxy, private parquet credentials): [docs/guide/private-deployment](https://boettiger-lab.github.io/geo-agent/docs/guide/private-deployment)

---

For full `layers-input.json` schema, troubleshooting, and configuration reference see the [geo-agent-template AGENTS.md](https://github.com/boettiger-lab/geo-agent-template/blob/main/AGENTS.md) or the [docs](https://boettiger-lab.github.io/geo-agent/docs/).
