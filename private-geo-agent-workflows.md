# Geo-Agent App Deployment Workflows

Reference for deploying and updating **private** geo-agent apps on NRP Kubernetes. 
IMPORTANT NOTE: this only applies to **Private** workflows,  apps on **Public GitHub Repos** simply clone from github instead.

---

## Source files vs generated ConfigMap

**The golden rule:** `k8s/content-configmap.yaml` is **generated** — never edit it by hand.

| Edit this | Never edit this |
|---|---|
| `index.html` | `k8s/content-configmap.yaml` |
| `layers-input.json` | |
| `system-prompt.md` | |
| `stac/*/collection.json` (private apps) | |

The ConfigMap is regenerated from sources by:

```bash
bash scripts/generate-configmap.sh
```

---

## Deployment workflow

Every content update follows the same three steps:

```bash
# 1. Regenerate the ConfigMap from source files
bash scripts/generate-configmap.sh

# 2. Apply it to the cluster
kubectl apply -f k8s/content-configmap.yaml

# 3. Restart the deployment to pick up the new ConfigMap
kubectl -n biodiversity rollout restart deployment/<app-name>
```

**Common mistake:** running only `rollout restart` after editing source files. The cluster doesn't read from git — it reads from the ConfigMap already in the cluster. Without `kubectl apply`, the pod restarts with the old content.

---

## Public app pattern (bosl-high-seas)

- STAC catalog is a public S3 URL referenced in `layers-input.json` — no local STAC files
- No authentication layer — ingress routes directly to nginx
- No private data — no rclone sidecar
- ConfigMap bundles: `index.html`, `layers-input.json`, `system-prompt.md`

```
Browser → HAProxy ingress → nginx pod
                              ↑
                         ConfigMap (content)
                         ConfigMap (LLM config template)
                         Secret (proxy key, MCP token)
```

---

## Private app pattern (wyoming)

Private apps add three layers on top of the public pattern:

### 1. OAuth2 authentication

An `oauth2-proxy` deployment sits in front of nginx. All requests are authenticated against a Google OAuth allowlist before reaching the app.

```
Browser → HAProxy ingress → oauth2-proxy → nginx pod
```

The oauth2-proxy allowlist lives in `k8s/auth-configmap.yaml` (plain email list). Secrets (`wyoming-oauth-secrets`) hold the Google client ID/secret and cookie secret — never committed.

The `/stac/` path is exempted from auth so the MCP server can access STAC metadata without credentials.

### 2. Private S3 tile serving (rclone sidecar)

A `rclone` sidecar container runs alongside nginx, proxying requests from `s3://private-wyoming/` to nginx's `/tiles/` location. This serves private PMTiles without exposing S3 credentials to the browser.

```yaml
# nginx configmap routes /tiles/ to rclone
location /tiles/ {
    proxy_pass http://localhost:8080/;
}
```

The rclone sidecar uses credentials from a secret (`mcp-private-wyoming-secrets`).

### 3. Local STAC + credential injection

Private STAC collection JSONs live in `stac/` and are bundled into the ConfigMap by `generate-configmap.sh`. This keeps private S3 paths out of the public internet.

The system-prompt.md undergoes `envsubst` at pod startup so S3 credentials can be injected for the MCP server:

```yaml
command:
  - sh
  - -c
  - |
    envsubst < /config/system-prompt.md > /usr/share/nginx/html/system-prompt.md
    envsubst < /config/config.template.json > /usr/share/nginx/html/config.json
    nginx -g 'daemon off;'
```

Private app ConfigMap bundles: `index.html`, `layers-input.json`, `system-prompt.md`, all `stac/*/collection.json` files.

---

## Troubleshooting rollouts

**Stuck rollout (>2 min):** likely a bad node. Check:

```bash
kubectl -n biodiversity get pods -l app=<name> -o wide
kubectl -n biodiversity describe pod <new-pod> | grep -A5 "Warning\|Failed"
```

If it's a node issue (not your image), delete the stuck pod — it reschedules, and the old pod stays live throughout (`maxUnavailable: 0`):

```bash
kubectl -n biodiversity delete pod <stuck-pod>
```
