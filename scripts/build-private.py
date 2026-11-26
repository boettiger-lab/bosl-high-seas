#!/usr/bin/env python3
"""Generate the private deployment (#85) from the public app files.

Outputs (all generated, do not edit by hand):
  layers-input.private.json   layers-input.json + private/layers.json
  system-prompt.private.md    system-prompt.md + private/system-prompt-addendum.md

The private k8s files (k8s/private-*.yaml) are hand-written. Their nginx config
is a server block over the shared snippets in glen-template nginx/ (glen-ops#340),
so there is little left to generate, and the private ConfigMap's model list and
the private Deployment's keys differ from the public ones on purpose.
"""
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent


def replace_once(text, old, new):
    assert text.count(old) == 1, f"expected exactly one match for {old!r}"
    return text.replace(old, new)


def build_layers():
    public = json.loads((ROOT / "layers-input.json").read_text())
    extra = json.loads((ROOT / "private/layers.json").read_text())
    for entry in extra["collections"]:
        ids = [c["collection_id"] for c in public["collections"]]
        public["collections"].insert(ids.index(entry["insert_after"]) + 1, entry["collection"])
    if "mcp_servers" in extra:
        # glen core: the MCP servers are the options of the mcp plugin.
        mcp = [p for p in public["plugins"]
               if isinstance(p, dict) and p["url"].endswith("/core/plugins/mcp.js")]
        assert len(mcp) == 1, "expected exactly one mcp plugin in layers-input.json"
        mcp[0]["options"] = {"servers": extra["mcp_servers"]}
    public["welcome"]["examples"] += extra.get("welcome_examples", [])
    public["sidebar"]["title"] = public["sidebar"]["title"] + " (private)"
    (ROOT / "layers-input.private.json").write_text(json.dumps(public, indent=4, ensure_ascii=False) + "\n")


def build_prompt():
    text = (ROOT / "system-prompt.md").read_text().rstrip("\n") + "\n"
    text += (ROOT / "private/system-prompt-addendum.md").read_text()
    (ROOT / "system-prompt.private.md").write_text(text)


if __name__ == "__main__":
    build_layers()
    build_prompt()
    print("wrote layers-input.private.json, system-prompt.private.md")
