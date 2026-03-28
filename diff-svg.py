#!/usr/bin/env python3
"""Generate a dependency diff SVG between two NixOS system toplevels.

Reads tracking-explicit.json, tracking.json, and tracking-deps.json from
each toplevel store path to find user-changed options and their dependency
neighborhood.

Usage:
  diff-svg.py BASE_TOPLEVEL CHANGED_TOPLEVEL

Output:
  SVG to stdout, diagnostics to stderr.
"""

import json
import os
import subprocess
import sys
import tempfile


def flatten(obj, prefix=""):
    """Flatten a nested dict into dot-separated leaf paths."""
    if isinstance(obj, dict):
        for k, v in obj.items():
            yield from flatten(v, f"{prefix}.{k}" if prefix else k)
    else:
        yield prefix, obj


def read_tracking_file(toplevel, filename):
    path = os.path.join(toplevel, filename)
    if not os.path.exists(path):
        print(f"Error: {path} not found. Was this toplevel built with trackDependencies = true?", file=sys.stderr)
        sys.exit(1)
    with open(path) as f:
        return json.load(f)


def main():
    if len(sys.argv) != 3:
        print(f"Usage: {sys.argv[0]} BASE_TOPLEVEL CHANGED_TOPLEVEL", file=sys.stderr)
        sys.exit(1)

    base_toplevel = sys.argv[1]
    changed_toplevel = sys.argv[2]

    base_keys = set(dict(flatten(read_tracking_file(base_toplevel, "tracking-explicit.json"))).keys())
    changed_keys = set(dict(flatten(read_tracking_file(changed_toplevel, "tracking-explicit.json"))).keys())
    deps = read_tracking_file(changed_toplevel, "tracking-deps.json")

    # User-changed options = keys present in changed but not in base
    diff_keys = changed_keys - base_keys
    if not diff_keys:
        print("No new options found between base and changed.", file=sys.stderr)
        sys.exit(1)

    print(f"User-changed options: {sorted(diff_keys)}", file=sys.stderr)

    # Leaf options from the full config values (not just explicit ones)
    leaf_options = set(dict(flatten(read_tracking_file(changed_toplevel, "tracking.json"))).keys())

    # Build adjacency maps filtered to leaf options only
    forward = {}  # accessed -> set of accessors (who reads this)
    backward = {}  # accessor -> set of accessed (what this reads)
    for d in deps:
        accessor = ".".join(d["accessor"])
        accessed = ".".join(d["accessed"])
        if accessor not in leaf_options or accessed not in leaf_options:
            continue
        forward.setdefault(accessed, set()).add(accessor)
        backward.setdefault(accessor, set()).add(accessed)

    # Depth-1 neighborhood: diff keys + direct consumers + direct dependencies
    visited = set(diff_keys)
    for k in diff_keys:
        visited.update(forward.get(k, set()))
        visited.update(backward.get(k, set()))

    relevant_edges = {
        (a, b)
        for d in deps
        for a, b in [(".".join(d["accessor"]), ".".join(d["accessed"]))]
        if a in visited and b in visited
    }

    print(f"Nodes: {len(visited)}, Edges: {len(relevant_edges)}", file=sys.stderr)

    # Generate DOT
    lines = [
        "digraph diff_dependencies {",
        "  rankdir=LR;",
        "  node [shape=box, fontsize=10];",
        '  edge [fontsize=8, color="#666666"];',
        "",
    ]

    for node in sorted(visited):
        color = "#ff9999" if node in diff_keys else "#ffffaa"
        lines.append(f'  "{node}" [style=filled, fillcolor="{color}", fontcolor="black"];')

    lines.append("")
    for accessor, accessed in sorted(relevant_edges):
        lines.append(f'  "{accessor}" -> "{accessed}";')

    lines.append("}")

    with tempfile.NamedTemporaryFile(mode="w", suffix=".dot", delete=False) as f:
        f.write("\n".join(lines))
        dot_path = f.name

    result = subprocess.run(["dot", "-Tsvg", dot_path], capture_output=True)
    if result.returncode != 0:
        print(result.stderr.decode(), file=sys.stderr)
        sys.exit(1)
    sys.stdout.buffer.write(result.stdout)


if __name__ == "__main__":
    main()
