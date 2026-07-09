-- Fully-local, Copilot-style inline completion via minuet-ai + Ollama.
-- Suggestions appear as ghost text (virtual text) as you type.
--
-- Uses fill-in-the-middle (FIM): the model sees code BOTH before and after the
-- cursor and fills the gap. Backed by the `qwen2.5-coder-minuet` model
-- (see ~/.dotfiles/ollama/qwen2.5-coder-minuet.Modelfile) -- a non-reasoning,
-- FIM-native code model. NOTE: your gemma4/qwen3.5 finetunes are reasoning models
-- and are deliberately NOT used here; they always emit chain-of-thought and can't
-- do sub-second inline completion (they remain great for chat/refactor though).
--
-- Requires Ollama running (systemctl status ollama). Rebuild the model with:
--   ollama create qwen2.5-coder-minuet -f ~/.dotfiles/ollama/qwen2.5-coder-minuet.Modelfile
return {
  {
    "milanglacier/minuet-ai.nvim",
    event = "InsertEnter",
    dependencies = { "nvim-lua/plenary.nvim" },
    config = function()
      require("minuet").setup({
        -- FIM completion against Ollama's /v1/completions (prefix + suffix)
        provider = "openai_fim_compatible",
        n_completions = 1, -- one suggestion at a time -> lower latency
        -- Characters of surrounding context (~4 chars/token). 12000 ≈ 3000 tokens,
        -- well within the model's num_ctx 8192.
        context_window = 12000,

        provider_options = {
          openai_fim_compatible = {
            -- Ollama ignores the key but minuet requires a non-empty env var name
            api_key = "TERM",
            name = "Ollama",
            end_point = "http://localhost:11434/v1/completions",
            model = "qwen2.5-coder-minuet",
            optional = {
              max_tokens = 128,
              top_p = 0.9,
            },
          },
        },

        -- Ghost-text (Copilot-like) inline suggestions
        virtualtext = {
          auto_trigger_ft = { "*" }, -- auto-suggest in every filetype
          keymap = {
            accept = "<A-A>", -- Alt+Shift+A: accept full suggestion
            accept_line = "<A-a>", -- Alt+a: accept one line
            accept_n_lines = "<A-z>", -- Alt+z: accept N lines (prompts for count)
            prev = "<A-[>", -- cycle to previous suggestion
            next = "<A-]>", -- cycle to next suggestion
            dismiss = "<A-e>", -- dismiss current suggestion
          },
        },
      })
    end,
  },
}
