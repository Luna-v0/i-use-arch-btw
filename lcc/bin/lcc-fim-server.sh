#!/usr/bin/env bash
# llama.cpp FIM completion server for nvim's minuet-ai, run ON lcc.
#
# Serves one GGUF model fully on lcc's GPU via the official llama.cpp CUDA
# Docker image. Bound ONLY to lcc's own Tailscale IPv4, resolved HERE AT RUN
# TIME via `tailscale ip -4` -- never hard-coded, since this file lives in a
# public repo. The container's internal --host 0.0.0.0 is just the
# container-local bind; Docker's `-p <tailscale-ip>:<port>:<port>` is what
# actually restricts external reachability to the tailnet.
#
# Does NOT start anything by itself when merely sourced/inspected -- running
# it does start a container, so don't run this while lcc's GPU is busy with
# something else (check `nvidia-smi` first).
#
# Env overrides (all optional; defaults picked for phase-1 prep, not yet the
# phase-2 winner):
#   LCC_FIM_MODEL       filename under LCC_FIM_MODELS_DIR (default: Qwen2.5-Coder-7B.Q4_K_M.gguf)
#   LCC_FIM_MODELS_DIR  models directory (default: $HOME/llm-bench/models)
#   LCC_FIM_PORT        port to bind (default: 8012)
#   LCC_FIM_CTX         context size in tokens (default: 32768)
#   LCC_FIM_IMAGE       llama.cpp docker image (default: ghcr.io/ggml-org/llama.cpp:server-cuda)
#   LCC_FIM_NAME        docker container name (default: lcc-fim)
#
# Usage:
#   ./lcc-fim-server.sh                       # foreground, Ctrl-C to stop
#   LCC_FIM_MODEL=Qwen2.5-Coder-1.5B.Q8_0.gguf ./lcc-fim-server.sh
set -euo pipefail

MODEL="${LCC_FIM_MODEL:-Qwen2.5-Coder-7B.Q4_K_M.gguf}"
MODELS_DIR="${LCC_FIM_MODELS_DIR:-$HOME/llm-bench/models}"
PORT="${LCC_FIM_PORT:-8012}"
CTX="${LCC_FIM_CTX:-32768}"
IMAGE="${LCC_FIM_IMAGE:-ghcr.io/ggml-org/llama.cpp:server-cuda}"
NAME="${LCC_FIM_NAME:-lcc-fim}"

if [[ ! -f "$MODELS_DIR/$MODEL" ]]; then
  echo "lcc-fim-server: model not found: $MODELS_DIR/$MODEL" >&2
  exit 1
fi

if ! command -v tailscale >/dev/null 2>&1; then
  echo "lcc-fim-server: tailscale CLI not found" >&2
  exit 1
fi

TS_IP="$(tailscale ip -4)"
if [[ -z "$TS_IP" ]]; then
  echo "lcc-fim-server: could not resolve this host's Tailscale IPv4 (is 'tailscale up' active?)" >&2
  exit 1
fi

# Replace a stale container left over from a previous run of THIS script
# under the same name -- not a foreign process. Never touches anything else.
if docker ps -a --format '{{.Names}}' | grep -qx "$NAME"; then
  docker rm -f "$NAME" >/dev/null
fi

echo "lcc-fim-server: binding ${TS_IP}:${PORT} -> model=${MODEL} ctx=${CTX}" >&2

# --cache-reuse keeps/re-matches cached prompt prefixes across requests
# (prompt caching) so repeated FIM calls on the same buffer region don't
# reprocess the whole prefix every keystroke. -np 1 (single slot) maximizes
# the cache hit rate for a single nvim user; raise it only if you need
# concurrent completions from more than one client.
exec docker run --rm --gpus all --name "$NAME" \
  -v "$MODELS_DIR":/models \
  -p "${TS_IP}:${PORT}:${PORT}" \
  --entrypoint /app/llama-server \
  "$IMAGE" \
  -m "/models/$MODEL" \
  -ngl 999 -np 1 \
  --cache-reuse 256 \
  --host 0.0.0.0 --port "$PORT" \
  --ctx-size "$CTX"
