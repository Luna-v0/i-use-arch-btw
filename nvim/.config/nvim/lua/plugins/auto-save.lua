-- Save buffers automatically when leaving insert mode or after normal-mode edits.
-- Writes go through BufWritePre, so LazyVim's format-on-save still runs (toggle it with <leader>uf).
return {
  "okuuva/auto-save.nvim",
  event = { "InsertLeave", "TextChanged" },
  cmd = "ASToggle",
  keys = {
    { "<leader>uv", "<cmd>ASToggle<cr>", desc = "Toggle Auto-save" },
  },
  opts = {
    enabled = true, -- on at startup; <leader>uv toggles for the session
    debounce_delay = 1000,
    condition = function(buf)
      -- skip special buffers (neo-tree, lazy, help, terminals, ...) and unnamed ones
      return vim.bo[buf].buftype == "" and vim.api.nvim_buf_get_name(buf) ~= ""
    end,
  },
}
