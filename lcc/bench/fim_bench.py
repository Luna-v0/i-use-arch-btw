#!/usr/bin/env python3
"""FIM latency + quality benchmark for a llama.cpp server, used to pick the
minuet-ai completion model on lcc (phase 2 of reports/2026-10-14-minuet-on-lcc.md).

Sends the SAME prefix/suffix/FIM-token template minuet-ai's llama.cpp provider
uses (see nvim/.config/nvim/lua/plugins/minuet-ai.lua) against a running
llama-server's OpenAI-compatible /v1/completions endpoint, over a handful of
real prefix/suffix/held-out-middle triples pulled from the user's own repos
(lcc/bench/prompts/fim_prompts.json). Measures:
  - TTFT: time to first streamed token
  - total: time to the end of the stream
  - a match score against the held-out line(s) (normalized, not exact-string)
  - a syntax-validity check: does prefix + completion + suffix still parse?

Run this FROM wherever minuet-ai actually runs (fantasy), hitting the
candidate server on lcc over Tailscale -- that measures the real round trip,
not an on-box number. No GPU/model-loading logic lives here; start the
server first with lcc/bin/lcc-fim-server.sh (see lcc/README.md).

Usage:
    python3 fim_bench.py --endpoint http://<lcc-tailscale-host>:8012 \\
        --label qwen2.5-coder-7b-base --runs 3

Writes a Markdown summary to stdout and a JSON of raw samples next to the
prompts file (fim_bench_results/<label>.json) for later comparison across
candidates.
"""

from __future__ import annotations

import argparse
import ast
import json
import pathlib
import shutil
import subprocess
import sys
import tempfile
import time
import urllib.request

HERE = pathlib.Path(__file__).resolve().parent
DEFAULT_PROMPTS = HERE / "prompts" / "fim_prompts.json"
RESULTS_DIR = HERE / "fim_bench_results"

# Qwen2.5-Coder's FIM tokens. All three phase-1 candidates (1.5B/3B/7B BASE)
# are this family; if a future candidate uses different FIM tokens, change
# this one constant rather than the per-prompt logic below.
FIM_PREFIX_TOKEN = "<|fim_prefix|>"
FIM_SUFFIX_TOKEN = "<|fim_suffix|>"
FIM_MIDDLE_TOKEN = "<|fim_middle|>"


def build_fim_prompt(prefix: str, suffix: str) -> str:
    return f"{FIM_PREFIX_TOKEN}{prefix}{FIM_SUFFIX_TOKEN}{suffix}{FIM_MIDDLE_TOKEN}"


def stream_completion(endpoint: str, prompt: str, max_tokens: int, timeout: float):
    """POST /v1/completions with stream=true; return (ttft_s, total_s, text)."""
    url = endpoint.rstrip("/") + "/v1/completions"
    payload = json.dumps(
        {
            "prompt": prompt,
            "model": "PLACEHOLDER",
            "max_tokens": max_tokens,
            "top_p": 0.9,
            "stream": True,
        }
    ).encode()

    req = urllib.request.Request(
        url, data=payload, headers={"Content-Type": "application/json"}
    )

    text_parts = []
    ttft = None
    t0 = time.monotonic()
    with urllib.request.urlopen(req, timeout=timeout) as resp:
        for raw_line in resp:
            line = raw_line.decode("utf-8", "replace").strip()
            if not line or not line.startswith("data:"):
                continue
            data = line[len("data:"):].strip()
            if data == "[DONE]":
                break
            try:
                chunk = json.loads(data)
            except json.JSONDecodeError:
                continue
            piece = chunk.get("choices", [{}])[0].get("text", "")
            if piece and ttft is None:
                ttft = time.monotonic() - t0
            text_parts.append(piece)
    total = time.monotonic() - t0
    if ttft is None:
        ttft = total
    return ttft, total, "".join(text_parts)


def normalize(s: str) -> str:
    return "\n".join(line.rstrip() for line in s.strip("\n").splitlines())


def match_score(completion: str, expected: str) -> float:
    """Crude line-overlap score in [0, 1]: fraction of expected lines that
    appear verbatim (post-normalization) somewhere in the completion. Good
    enough to rank candidates; not a real diff/edit-distance metric."""
    exp_lines = [l for l in normalize(expected).splitlines() if l.strip()]
    if not exp_lines:
        return 0.0
    comp_norm = normalize(completion)
    hits = sum(1 for l in exp_lines if l.strip() in comp_norm)
    return hits / len(exp_lines)


def check_syntax(language: str, prefix: str, completion: str, suffix: str) -> bool | None:
    """Return True/False if checkable, None if no checker is available here."""
    full = prefix + completion + suffix
    if language == "python":
        try:
            ast.parse(full)
            return True
        except SyntaxError:
            return False
    if language == "lua":
        luac = shutil.which("luac") or shutil.which("luac5.1")
        if not luac:
            return None
        with tempfile.NamedTemporaryFile(suffix=".lua", mode="w", delete=False) as tf:
            tf.write(full)
            path = tf.name
        try:
            r = subprocess.run([luac, "-p", path], capture_output=True, text=True)
            return r.returncode == 0
        finally:
            pathlib.Path(path).unlink(missing_ok=True)
    return None


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument(
        "--endpoint",
        required=True,
        help="e.g. http://<lcc-tailscale-host>:8012 (no path suffix; resolve the host "
        "yourself, e.g. `ssh -G lcc | awk '/^hostname /{print $2; exit}'` -- never "
        "hard-code it here, this script is committed to a public repo)",
    )
    ap.add_argument("--label", required=True, help="short name for this model/run, e.g. qwen2.5-coder-7b-base")
    ap.add_argument("--prompts", default=str(DEFAULT_PROMPTS))
    ap.add_argument("--max-tokens", type=int, default=128, help="matches minuet's optional.max_tokens")
    ap.add_argument("--runs", type=int, default=3, help="repeats per prompt, for latency stats")
    ap.add_argument("--timeout", type=float, default=30.0, help="HTTP timeout per request, seconds")
    args = ap.parse_args()

    prompts = json.loads(pathlib.Path(args.prompts).read_text())

    all_samples = []
    print(f"# FIM benchmark: {args.label}\n")
    print(f"endpoint={args.endpoint} max_tokens={args.max_tokens} runs/prompt={args.runs}\n")
    print("| prompt | run | TTFT (s) | total (s) | match | syntax ok |")
    print("|---|---|---|---|---|---|")

    for p in prompts:
        fim_prompt = build_fim_prompt(p["prefix"], p["suffix"])
        for run_idx in range(1, args.runs + 1):
            try:
                ttft, total, completion = stream_completion(
                    args.endpoint, fim_prompt, args.max_tokens, args.timeout
                )
            except Exception as e:  # noqa: BLE001 - report and keep going
                print(f"| {p['id']} | {run_idx} | ERROR | ERROR | - | - |  <!-- {e} -->")
                continue

            score = match_score(completion, p["expected_middle"])
            syntax_ok = check_syntax(p["language"], p["prefix"], completion, p["suffix"])
            syntax_str = "yes" if syntax_ok is True else ("no" if syntax_ok is False else "n/a")

            print(
                f"| {p['id']} | {run_idx} | {ttft:.3f} | {total:.3f} | {score:.2f} | {syntax_str} |"
            )

            all_samples.append(
                {
                    "prompt_id": p["id"],
                    "language": p["language"],
                    "run": run_idx,
                    "ttft_s": ttft,
                    "total_s": total,
                    "match_score": score,
                    "syntax_ok": syntax_ok,
                    "completion": completion,
                }
            )

    RESULTS_DIR.mkdir(parents=True, exist_ok=True)
    out_path = RESULTS_DIR / f"{args.label}.json"
    out_path.write_text(json.dumps({"label": args.label, "endpoint": args.endpoint, "samples": all_samples}, indent=2))
    print(f"\nRaw samples written to {out_path}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
