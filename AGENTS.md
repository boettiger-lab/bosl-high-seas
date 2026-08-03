# AI Agent Guide — bosl-high-seas

## Deployment model: public repo, git-clone initContainer

This repo is **public**. The pod's `git-clone` initContainer (`k8s/deployment.yaml`) runs `git clone --depth 1 https://github.com/boettiger-lab/bosl-high-seas.git` on each pod start and copies `index.html`, `layers-input.json`, and `system-prompt.md` into the nginx html dir. Pod content tracks `main`. The `k8s/configmap.yaml` ConfigMap holds only the LLM model list and the nginx reverse-proxy template — **not** website content.

## Two deployments

| | NRP Nautilus (prod) | cirrus (local k3s) |
|---|---|---|
| Manifests | `k8s/{configmap,deployment,service,ingress}.yaml` | `k8s/cirrus-*.yaml` |
| Namespace | `biodiversity` | `high-seas` |
| URL | https://high-seas.nrp-nautilus.io | https://high-seas.carlboettiger.info |
| Layer config | `layers-input.json` (s3-west.nrp-nautilus.io) | `layers-input.cirrus.json` (minio.carlboettiger.info) |
| MCP server | `duckdb-mcp.nrp-nautilus.io` | `duckdb-mcp.carlboettiger.info` (`mcp` ns) |
| LLM | open-llm-proxy → OpenRouter + NRP models | in-cluster vLLM `qwen3-6` only (`vllm` ns) |
| Ingress | HAProxy annotations | Traefik CRDs + cert-manager + external-dns |

**`layers-input.cirrus.json` is a committed copy of `layers-input.json`** with the S3
and MCP hosts rewritten — `config.json` can override `mcp_server_url` but *not* the
STAC catalog/collection URLs, so the layer file itself has to differ. **Any edit to
`layers-input.json` must be mirrored there:**

```bash
sed -e 's|https://s3-west\.nrp-nautilus\.io|https://minio.carlboettiger.info|g' \
    -e 's|https://duckdb-mcp\.nrp-nautilus\.io/mcp|https://duckdb-mcp.carlboettiger.info/mcp|g' \
    layers-input.json > layers-input.cirrus.json
```

The cirrus initContainer copies it over `layers-input.json` in the nginx html dir.
`titiler_url` still points at NRP — cirrus has no titiler.

### Deploying to cirrus

One-time setup (namespace + a copy of the vLLM API key, which nginx injects into
the `/api/llm/` Authorization header; secrets can't be read across namespaces):

```bash
kubectl create namespace high-seas
kubectl create secret generic vllm-api-key -n high-seas \
  --from-literal=api-key="$(kubectl get secret vllm-api-key -n vllm -o jsonpath='{.data.api-key}' | base64 -d)"
kubectl apply -f k8s/cirrus-configmap.yaml -f k8s/cirrus-service.yaml \
              -f k8s/cirrus-deployment.yaml -f k8s/cirrus-ingress.yaml
```

Routine content edits — same two-step as NRP (push, then restart so the pod re-clones):

```bash
git add <source-files> && git commit -m "<message>" && git push
kubectl rollout restart deployment/bosl-high-seas -n high-seas
kubectl rollout status deployment/bosl-high-seas -n high-seas
```

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
