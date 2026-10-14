# lcc — FIM completion server for minuet-ai

Not a stow package (lcc is a different machine; nothing here is symlinked on
this machine). These files are meant to be deployed onto `lcc` itself and run
there. Background: `reports/2026-10-14-minuet-on-lcc.md` in the maintenance
repo (not this one) has the full brief and phase-1/phase-2 write-up.

Goal: move minuet-ai's FIM completion backend off fantasy's Ollama and onto
lcc's own GPU (an RTX 4070 Laptop, 8 GB), so fantasy's GPU stays fully free.
Nothing here is enabled or started yet — phase 1 only prepares it.

## Layout

- `bin/lcc-fim-server.sh` — launcher: runs a llama.cpp CUDA server for one
  GGUF model, bound only to lcc's own Tailscale IPv4 (resolved at run time via
  `tailscale ip -4`, never hard-coded). See the script's own header for every
  env override (model file, port, context size, image, container name).
- `systemd/lcc-fim-server.service` — a `systemd --user` unit wrapping the
  script above. Not enabled, not started.
- `bench/fim_bench.py` + `bench/prompts/fim_prompts.json` — a FIM latency +
  quality benchmark, meant to run from wherever minuet-ai actually runs
  (fantasy), hitting a candidate server on lcc over Tailscale, so the numbers
  reflect the real round trip rather than an on-box number.

## Deploying to lcc

Nothing here assumes lcc already has this repo. Simplest options:

```bash
# whole repo (matches the systemd unit's ExecStart path as written):
ssh lcc 'git clone https://github.com/Luna-v0/i-use-arch-btw.git ~/.dotfiles'

# just this folder, if you'd rather not clone the whole repo there:
rsync -av ~/.dotfiles/lcc/ lcc:~/.dotfiles/lcc/
```

If you use the rsync route and the path differs from `~/.dotfiles/lcc`,
update `ExecStart=`/`ExecStop=` in `lcc-fim-server.service` to match before
installing it (`systemctl --user link`, not `enable`, works directly in place
— see below).

## Running it (phase 2, once lcc's GPU is free and a model is picked)

Foreground, for testing:

```bash
ssh lcc
nvidia-smi   # confirm the GPU is actually idle first
LCC_FIM_MODEL=<winning-model>.gguf ~/.dotfiles/lcc/bin/lcc-fim-server.sh
```

As a user service, once you're happy with it:

```bash
ssh lcc
systemctl --user link ~/.dotfiles/lcc/systemd/lcc-fim-server.service
systemctl --user daemon-reload
systemctl --user enable --now lcc-fim-server.service   # on
systemctl --user disable --now lcc-fim-server.service  # off
systemctl --user status lcc-fim-server.service         # check
```

## Benchmarking candidates (phase 2)

```bash
# on lcc: start one candidate (foreground is fine for benchmarking)
ssh lcc 'LCC_FIM_MODEL=Qwen2.5-Coder-1.5B.Q8_0.gguf ~/.dotfiles/lcc/bin/lcc-fim-server.sh &'

# from wherever minuet-ai runs (fantasy), against the SAME Tailscale name
# minuet's config resolves (see nvim/.config/nvim/lua/plugins/minuet-ai.lua):
python3 ~/.dotfiles/lcc/bench/fim_bench.py \
  --endpoint "http://$(ssh -G lcc | awk '/^hostname /{print $2; exit}'):8012" \
  --label qwen2.5-coder-1.5b-base --runs 3

# repeat per candidate, then stop it before starting the next one
ssh lcc 'docker stop lcc-fim'
```

Results land in `bench/fim_bench_results/<label>.json` (gitignored — local
scratch, not committed) plus a Markdown table on stdout; compare TTFT/total
and the match/syntax columns across candidates to pick a winner.

## Why these specific defaults

- **Model**: BASE (not instruct) checkpoints — FIM relies on the model
  actually being trained with `<|fim_prefix|>`/`<|fim_suffix|>`/`<|fim_middle|>`
  tokens, which Qwen2.5-Coder's instruct tuning doesn't re-emphasize. See the
  research in `reports/2026-10-14-minuet-on-lcc.md` phase 1.
- **`-np 1`**: a single server slot maximizes `--cache-reuse` prompt-prefix
  cache hits for one interactive nvim user, at the cost of not serving a
  second concurrent client well. Raise `-np` if that ever matters.
- **Bind to the Tailscale IP, not `0.0.0.0`**: the server is reachable from
  any tailnet peer (fantasy included) but never from the LAN or internet.
