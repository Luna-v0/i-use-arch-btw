-- Typst: tinymist LSP + live browser preview (typst-preview.nvim), on top of
-- LazyVim's lang.typst extra (enabled in lazyvim.json).
--
-- The `typst-live` launcher (~/.dotfiles/bin/.local/bin/typst-live) exports the
-- project layout before starting nvim:
--   TYPST_ROOT        project root (for absolute imports like "/lib/x.typ")
--   TYPST_FONT_PATHS  project font dir(s), ":"-separated
--   TYPST_MAIN        the document to preview, whichever file you are editing
-- Both the LSP and the preview must see the same root and fonts; otherwise
-- they quietly fall back to system fonts and the layout drifts from `typst
-- compile`. Without the launcher everything falls back to per-file defaults.
--
-- Over SSH the preview runs on a fixed port, does not try to open a browser
-- here, and listens on the address you SSH'd into (e.g. the mesh-VPN IP), so
-- http://<that-ip>:23635 works from the client. The preview has no auth, so
-- it binds only that address, never 0.0.0.0.
--
-- Open that URL by IP, NOT by a DNS name (Tailscale MagicDNS included). The
-- page itself loads either way, but the viewer derives its websocket URL from
-- the page origin, and tinymist drops a websocket upgrade whose Origin header
-- is a hostname -- it allows only localhost/127.0.0.1 and the bound IP. A name
-- gives you a blank viewer and 1006 close events in the console. There is no
-- flag to widen that allowlist, so the IP is the whole fix.
local root = os.getenv("TYPST_ROOT")
local main = os.getenv("TYPST_MAIN")
local fonts = os.getenv("TYPST_FONT_PATHS")
local font_paths = fonts and vim.split(fonts, ":", { trimempty = true }) or {}
-- "client_ip client_port server_ip server_port"
local ssh = os.getenv("SSH_CONNECTION")

-- A tmux pane inherits the environment of the tmux *server*, which usually
-- predates the SSH session you attached from, so a long-lived tmux has no
-- SSH_CONNECTION in its panes even when you are remote -- and the preview then
-- binds loopback on a random port, unreachable from the client. tmux does
-- refresh SSH_CONNECTION in the session environment on every attach (it is in
-- `update-environment` by default), so ask tmux when the variable did not come
-- through. TYPST_PREVIEW_HOST overrides both, for cases with no tmux either.
if not ssh and os.getenv("TMUX") then
  local out = vim.fn.system({ "tmux", "show-environment", "SSH_CONNECTION" })
  -- tmux prints "-NAME" for a variable it is tracking as unset.
  if vim.v.shell_error == 0 and not out:match("^%-") then
    ssh = out:match("^SSH_CONNECTION=(.-)%s*$")
  end
end

local forced_host = os.getenv("TYPST_PREVIEW_HOST")
local ssh_server_ip = forced_host or (ssh and vim.split(ssh, " ", { trimempty = true })[3]) or nil
local over_ssh = ssh_server_ip ~= nil

if over_ssh then
  vim.schedule(function()
    vim.notify(
      ("typst preview: http://%s:%d/  (use the IP, not a DNS name)"):format(ssh_server_ip, 23635),
      vim.log.levels.INFO
    )
  end)
end

return {
  {
    "neovim/nvim-lspconfig",
    opts = {
      servers = {
        tinymist = {
          settings = {
            rootPath = root,
            fontPaths = font_paths,
          },
          -- Compile the whole document, not just the open chapter, so errors
          -- and references resolve the way `typst compile main.typ` sees them.
          on_attach = main and function(client)
            client:exec_cmd({ title = "pin main", command = "tinymist.pinMain", arguments = { main } })
          end or nil,
        },
      },
    },
  },

  {
    "chomosuke/typst-preview.nvim",
    opts = {
      -- tinymist comes from Mason, which LazyVim puts on nvim's PATH.
      -- TYPST_ROOT and TYPST_FONT_PATHS are read from the environment by the
      -- plugin and by `tinymist preview` respectively.
      get_main_file = function(path)
        return main or path
      end,
      port = over_ssh and 23635 or 0,
      host = ssh_server_ip or "127.0.0.1",
      -- Nothing to open on this end when the browser is on the other machine;
      -- print the IP URL instead, since that is the one that actually works.
      open_cmd = over_ssh and "true %s" or nil,
    },
  },
}
