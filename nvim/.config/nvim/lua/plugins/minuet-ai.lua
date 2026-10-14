-- On-demand, Copilot-style inline completion via minuet-ai + a llama.cpp
-- FIM server on `lcc` (a different machine on the tailnet, NOT this one).
--
-- Uses fill-in-the-middle (FIM): the model sees code BOTH before and after
-- the cursor and fills the gap. The backend is a llama.cpp `llama-server`
-- running a Qwen2.5-Coder BASE model (base, not instruct -- FIM relies on the
-- model actually using <|fim_prefix|>/<|fim_suffix|>/<|fim_middle|> tokens,
-- which base checkpoints are trained on). See ~/.dotfiles/lcc/README.md for
-- how that server is built, deployed and started/stopped; it moved off
-- fantasy's Ollama + GPU specifically so fantasy's GPU stays fully free.
--
-- Default is ON-DEMAND, not auto-trigger: press the request key below to ask
-- for a suggestion; nothing fires as you type. Auto-trigger is one toggle
-- away (see the keymap table) if you change your mind.
--
-- This repo is PUBLIC: the server's actual Tailscale hostname/IP is never
-- written here. It's resolved at runtime below, from the (private, never
-- committed) `Host lcc` entry in ~/.ssh/config -- same as plain `ssh lcc`
-- already uses -- or overridden via the MINUET_LCC_FIM_ENDPOINT env var.
return {
  {
    "milanglacier/minuet-ai.nvim",
    event = "InsertEnter",
    dependencies = { "nvim-lua/plenary.nvim" },
    config = function()
      -- Resolve lcc's FIM endpoint at runtime. Priority: explicit env var,
      -- then `ssh -G lcc`'s resolved hostname (never hard-coded here), then a
      -- deliberately-unreachable loopback so a missing/broken resolution
      -- fails the HTTP request immediately instead of hanging.
      local function resolve_lcc_fim_endpoint()
        local env = vim.env.MINUET_LCC_FIM_ENDPOINT
        if env and env ~= "" then
          return env
        end

        local ok, result = pcall(vim.fn.system, { "ssh", "-G", "lcc" })
        local host = nil
        if ok and vim.v.shell_error == 0 and result then
          for line in result:gmatch("[^\r\n]+") do
            local h = line:match("^hostname%s+(.+)$")
            if h then
              host = h
              break
            end
          end
        end

        local port = vim.env.MINUET_LCC_FIM_PORT or "8012"
        if host then
          return string.format("http://%s:%s/v1/completions", host, port)
        end
        -- No 'Host lcc' in ~/.ssh/config and no env override: fail fast
        -- rather than DNS-timeout on every request.
        return "http://127.0.0.1:1/v1/completions"
      end

      require("minuet").setup({
        -- FIM completion against llama-server's /v1/completions
        -- (OpenAI-FIM-compatible shape; llama.cpp needs the FIM tokens
        -- stitched into the prompt manually -- see `template` below).
        provider = "openai_fim_compatible",
        n_completions = 1, -- one suggestion at a time -> lower latency

        -- Characters of surrounding context (~4 chars/token). 32000 ≈ 8000
        -- tokens. Deliberately generous since all three phase-1 candidate
        -- base models (1.5B/3B/7B) handle well beyond this; narrow it back
        -- down if the model phase 2 actually picks needs it.
        context_window = 32000,

        -- Short on purpose: this is now on-demand (see virtualtext below),
        -- so a request only happens when you ask for one, and a short
        -- timeout means minuet just stays quiet if lcc is unreachable
        -- instead of hanging the request.
        request_timeout = 2,

        provider_options = {
          openai_fim_compatible = {
            -- llama-server ignores this; non-empty is just required by minuet.
            api_key = "TERM",
            name = "lcc-llama-cpp",
            end_point = resolve_lcc_fim_endpoint(),
            model = "PLACEHOLDER", -- the server only ever has one model loaded
            optional = {
              max_tokens = 128,
              top_p = 0.9,
            },
            -- llama.cpp's /v1/completions doesn't support a separate
            -- `suffix` field for FIM; stitch the special tokens in manually
            -- instead. These are Qwen2.5-Coder's FIM tokens -- update them
            -- if phase 2 ever picks a model from a different family.
            template = {
              prompt = function(context_before_cursor, context_after_cursor, _)
                return "<|fim_prefix|>"
                  .. context_before_cursor
                  .. "<|fim_suffix|>"
                  .. context_after_cursor
                  .. "<|fim_middle|>"
              end,
              suffix = false,
            },
          },
        },

        -- Ghost-text (Copilot-like) inline suggestions, ON-DEMAND by
        -- default (user preference: auto-suggestions were "too dumb" /
        -- unhelpful). `auto_trigger_ft = {}` means nothing fires as you
        -- type, in any filetype.
        virtualtext = {
          auto_trigger_ft = {},
          keymap = {
            accept = "<A-A>", -- Alt+Shift+A: accept full suggestion
            accept_line = "<A-a>", -- Alt+a: accept one line
            accept_n_lines = "<A-z>", -- Alt+z: accept N lines (prompts for count)
            -- `next`/`prev` double as the ON-DEMAND REQUEST key: with no
            -- suggestion visible yet, pressing either one fires a new FIM
            -- request (minuet's own behavior); once a suggestion exists,
            -- they cycle between completion candidates instead.
            prev = "<A-[>", -- Alt+[: request a suggestion / cycle to previous
            next = "<A-]>", -- Alt+]: request a suggestion / cycle to next
            dismiss = "<A-e>", -- Alt+e: dismiss current suggestion
          },
        },
      })

      -- Simple on/off switch for auto-trigger, kept one keymap away without
      -- touching the on-demand default above. Checked against the rest of
      -- this config (grep for <A- / <M- across nvim/.config/nvim): no other
      -- Alt-based insert-mode mapping exists anywhere, so <A-m> is free.
      vim.keymap.set("i", "<A-m>", function()
        require("minuet.virtualtext").action.toggle_auto_trigger()
      end, { desc = "Minuet: toggle auto-trigger suggestions on/off" })
    end,
  },
}
