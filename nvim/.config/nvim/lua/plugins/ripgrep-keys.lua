-- Ripgrep search keybinds (uses LazyVim's built-in snacks picker, which shells out to rg)
-- Prefix: <leader>r = "ripgrep"
return {
  {
    "folke/snacks.nvim",
    keys = {
      -- Live ripgrep across the project root
      { "<leader>rg", function() Snacks.picker.grep() end, desc = "Ripgrep (project)" },
      -- Ripgrep the word under cursor / visual selection
      { "<leader>rw", function() Snacks.picker.grep_word() end, mode = { "n", "x" }, desc = "Ripgrep word/selection" },
      -- Ripgrep across currently open buffers
      { "<leader>rB", function() Snacks.picker.grep_buffers() end, desc = "Ripgrep open buffers" },
      -- Live ripgrep in the current working directory (not root)
      { "<leader>rc", function() Snacks.picker.grep({ cwd = vim.fn.getcwd() }) end, desc = "Ripgrep (cwd)" },
    },
  },

  -- Register the which-key group label so the prefix is discoverable
  {
    "folke/which-key.nvim",
    opts = {
      spec = {
        { "<leader>r", group = "ripgrep", icon = "" },
      },
    },
  },
}
