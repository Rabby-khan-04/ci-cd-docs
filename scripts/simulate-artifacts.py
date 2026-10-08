#!/usr/bin/env python3
"""Produce a runnable copy of a workflow with artifact steps replaced by local
equivalents.

Why: `act` has no artifact service. `actions/upload-artifact` needs
ACTIONS_RUNTIME_TOKEN, which only GitHub's runtime provides, so the step fails
with "Unable to get the ACTIONS_RUNTIME_TOKEN env variable". That is a limitation
of local execution, not a bug in the workflow.

Rather than skip those chapters' verification entirely, this rewrites the
workflow so that:

  - upload-artifact  -> tar the same paths into .artifacts/<name>.tar
  - download-artifact -> untar .artifacts/<name>.tar into the requested path

Everything else in the file is untouched, so steps, ordering, needs:, conditionals
and outputs are still exercised for real. What is NOT verified is GitHub's own
artifact storage, retention, or the v4+ immutable-artifact rules.

Usage:
  scripts/simulate-artifacts.py <in.yml> <out.yml> [artifact-root-dir] [--only-job ID]

With --only-job, the output contains just that job. Used by
scripts/verify-artifact-chain.sh so the consumer phase does not also re-run the
producer, which would overwrite the pre-staged artifact.
"""
import os
import sys
import pathlib
import yaml

IN_ = pathlib.Path(sys.argv[1])
OUT = pathlib.Path(sys.argv[2])
# The artifact store must live INSIDE the bind-mounted workspace, otherwise the
# tar written by one job's container is invisible to the next job's container.
# `act` does not share the host filesystem outside the workspace.
only_job = None
if "--only-job" in sys.argv:
    only_job = sys.argv[sys.argv.index("--only-job") + 1]

ROOT = pathlib.Path(sys.argv[3])
if ROOT.is_absolute():
    sys.exit("artifact root must be a path relative to the repo root, e.g. .tmp/artifacts")

doc = yaml.safe_load(IN_.read_text())

# Preserve key order as much as PyYAML allows.
class Dumper(yaml.SafeDumper):
    pass

def _dict_representer(dumper, data):
    return dumper.represent_mapping(yaml.resolver.BaseResolver.DEFAULT_MAPPING_TAG, data.items())

Dumper.add_representer(dict, _dict_representer)

conversions = []

def convert(job_id, job):
    steps = job.get("steps") if isinstance(job, dict) else None
    if not isinstance(steps, list):
        return
    for i, step in enumerate(steps):
        if not isinstance(step, dict):
            continue
        uses = str(step.get("uses", ""))
        with_ = step.get("with") or {}
        name = with_.get("name") or f"artifact-{i}"

        if "upload-artifact" in uses:
            path = with_.get("path", ".")
            missing = with_.get("if-no-files-found", "warn")
            # Mirror if-no-files-found, which `tar` does not implement. This
            # matters: with the real action, `ignore` and `warn` let a missing
            # path pass, and only `error` fails the step.
            # upload-artifact stores paths relative to the least common ancestor
            # of everything in `path`, so an artifact of `cicd-learn/dist` lands
            # as `app.js`, not `cicd-learn/dist/app.js`. tar needs -C <dir> to
            # reproduce that, otherwise the download step produces a nested path.
            pdir = os.path.dirname(path) or "."
            pbase = os.path.basename(path.rstrip("/"))
            guard = {
                "error": f'test -e {path} || {{ echo "::error::no files at {path}"; exit 1; }}',
                "warn": f'test -e {path} || echo "::warning::no files at {path}"',
                "ignore": "true",
            }[missing]
            # `path:` in upload-artifact is relative to the WORKSPACE ROOT, not
            # to defaults.run.working-directory. So the simulated step resets
            # working-directory to the root, otherwise a `cicd-learn/dist` path
            # is looked up inside cicd-learn/ and not found.
            steps[i] = {
                "name": f"[simulated upload-artifact: {name}]",
                "shell": "bash",
                "working-directory": ".",
                "run": (
                    f'mkdir -p {ROOT}\n'
                    f'{guard}\n'
                    f'if [ -e {path} ]; then\n'
                    f'  tar czf {ROOT}/{name}.tar -C {pdir} {pbase}\n'
                    f'  ls -l "{ROOT}/{name}.tar"\n'
                    f'  echo "SIMULATED upload of {path} as {name}"\n'
                    f'else\n'
                    f'  echo "SIMULATED upload of {path} as {name}: nothing to upload"\n'
                    f'fi'
                ),
            }
            conversions.append(f"{job_id}: upload-artifact {name} -> local tar (if-no-files-found: {missing})")

        elif "download-artifact" in uses:
            path = with_.get("path", ".")
            steps[i] = {
                "name": f"[simulated download-artifact: {name}]",
                "shell": "bash",
                "working-directory": ".",
                "run": (
                    f'mkdir -p "{path}"\n'
                    f'test -f {ROOT}/{name}.tar || {{ echo "::error::artifact {name} not found"; exit 1; }}\n'
                    f'tar xzf "{ROOT}/{name}.tar" -C "{path}"\n'
                    f'echo "SIMULATED download of {name} into {path}"'
                ),
            }
            conversions.append(f"{job_id}: download-artifact {name} -> local untar")

for jid, j in (doc.get("jobs") or {}).items():
    convert(jid, j)

if only_job:
    if only_job not in (doc.get("jobs") or {}):
        sys.exit(f"no such job in the workflow: {only_job}")
    job = dict(doc["jobs"][only_job])
    # A `needs:` pointing at a job we just deleted makes the workflow
    # unresolvable ("unable to build dependency graph"). The dependency has
    # already been satisfied by the fact that we staged its artifact, so drop it.
    job.pop("needs", None)
    doc["jobs"] = {only_job: job}
    print(f"  kept only job: {only_job} (needs: dropped, already satisfied)")

OUT.write_text(yaml.dump(doc, Dumper=Dumper, sort_keys=False, default_flow_style=False))

print(f"wrote {OUT}")
for c in conversions:
    print(f"  {c}")
if not conversions:
    print("  (no artifact steps found; file copied unchanged)")