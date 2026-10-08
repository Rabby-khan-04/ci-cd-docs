#!/usr/bin/env python3
"""Validate every workflow in .github/workflows: YAML syntax, structure, and
action pinning. Used so no chapter ships a workflow that is syntactically broken
or uses an unpinned action.

Checks per file:
  - parses as YAML
  - has `on` and `jobs` at the top level
  - every job has `runs-on` and `steps`
  - every `uses:` is pinned to a version or SHA (never a bare repo name or `main`)
  - every `run:` is a string or a list of strings
"""
import sys
import pathlib
import re
import yaml

REPO = pathlib.Path(__file__).resolve().parents[1]
WF_DIR = REPO / ".github" / "workflows"

# `on:` is parsed by YAML 1.1 as the boolean True. GitHub's parser is YAML 1.2
# and treats it as the string "on". We accept both and note it here.
ON_KEYS = {"on", True}

PIN_RE = re.compile(r"^[^@\s]+@(\S+)$")
SHA_RE = re.compile(r"^[0-9a-f]{40}$")

errors = []
warnings = []
checked = 0

def walk_runs(node, path, out):
    if isinstance(node, dict):
        for k, v in node.items():
            if k == "run" and isinstance(v, (str, list)):
                out.append((path, v))
            walk_runs(v, f"{path}.{k}", out)
    elif isinstance(node, list):
        for i, v in enumerate(node):
            walk_runs(v, f"{path}[{i}]", out)


def walk_uses(node, path, out):
    if isinstance(node, dict):
        for k, v in node.items():
            if k == "uses":
                out.append((path, v))
            walk_uses(v, f"{path}.{k}", out)
    elif isinstance(node, list):
        for i, v in enumerate(node):
            walk_uses(v, f"{path}[{i}]", out)


for wf in sorted(WF_DIR.glob("*.y*ml")):
    rel = wf.relative_to(REPO)
    try:
        doc = yaml.safe_load(wf.read_text())
    except yaml.YAMLError as e:
        errors.append(f"{rel}: YAML does not parse: {e}")
        continue

    if not isinstance(doc, dict):
        errors.append(f"{rel}: top level is not a mapping")
        continue

    if not (set(doc) & ON_KEYS):
        errors.append(f"{rel}: missing top-level `on:`")
    if "jobs" not in doc or not isinstance(doc["jobs"], dict) or not doc["jobs"]:
        errors.append(f"{rel}: missing or empty top-level `jobs:`")
        continue

    if "permissions" not in doc:
        warnings.append(f"{rel}: no top-level `permissions:` block (least privilege not set)")

    for job_id, job in doc["jobs"].items():
        if not isinstance(job, dict):
            errors.append(f"{rel}: jobs.{job_id} is not a mapping")
            continue
        if "runs-on" not in job and "uses" not in job:
            errors.append(f"{rel}: jobs.{job_id} has neither `runs-on:` nor `uses:`")
        if "steps" in job:
            for i, step in enumerate(job["steps"]):
                if not isinstance(step, dict):
                    errors.append(f"{rel}: jobs.{job_id}.steps[{i}] is not a mapping")
                elif "run" not in step and "uses" not in step:
                    errors.append(f"{rel}: jobs.{job_id}.steps[{i}] has neither `run:` nor `uses:`")
                elif "run" in step and "uses" in step:
                    errors.append(f"{rel}: jobs.{job_id}.steps[{i}] has both `run:` and `uses:`")

    runs = []
    uses = []
    walk_runs(doc, rel.name, runs)
    walk_uses(doc, rel.name, uses)

    for path, v in runs:
        if isinstance(v, list) and not all(isinstance(x, str) for x in v):
            errors.append(f"{path}: `run:` list must contain only strings")

    for path, v in uses:
        if not isinstance(v, str):
            errors.append(f"{path}: `uses:` must be a string, got {type(v).__name__}")
            continue
        if v.startswith("./") or v.startswith("docker://"):
            continue  # local or container reference, not a registry version
        m = PIN_RE.match(v)
        if not m:
            errors.append(f"{path}: `uses: {v}` is not pinned (needs @version or @sha)")
            continue
        ref = m.group(1)
        if ref in ("main", "master", "latest") or ref.startswith("refs/"):
            errors.append(f"{path}: `uses: {v}` pins to a moving ref")
        elif not (SHA_RE.match(ref) or re.match(r"^v\d+(\.\d+)*$", ref)):
            warnings.append(f"{path}: `uses: {v}` uses a non-SHA, non-semver ref")

    checked += 1
    print(f"ok  {rel}  ({len(doc['jobs'])} job(s))")

print()
for w in warnings:
    print(f"WARN {w}")
for e in errors:
    print(f"FAIL {e}")
print(f"\n{checked} workflow file(s) checked, {len(errors)} error(s), {len(warnings)} warning(s)")
sys.exit(1 if errors else 0)