-- Chat/media web-apps that must stay logged in, each in its OWN Chromium
-- profile (--user-data-dir). Sharing the default profile made them race for its
-- SingletonLock at cold boot (worsened by the login-time GPU-process crash on
-- the NVIDIA card): a second browser process ended up on the same profile,
-- threw "Profile error occurred / could not be opened" and never persisted its
-- session -- the "logged out every boot" symptom. Separate profiles can't race.
--
-- Used by BOTH autostart.lua and bindings.lua: a keybinding that opened the
-- default profile instead would show a logged-out copy of the app.
-- Window class stays chrome-<host>__-Default, so workspace rules still match.
local M = {}

local profiles = os.getenv("HOME") .. "/.local/share/omarchy-webapps/"

M.urls = {
  ytmusic = "https://music.youtube.com/",
  whatsapp = "https://web.whatsapp.com/",
  discord = "https://discord.com/channels/@me",
}

local function profile_flag(name)
  return " --user-data-dir=" .. profiles .. name
end

-- Always launch (a second launch hands off to the app's running instance).
function M.launch(name)
  return o.launch_webapp(M.urls[name]) .. profile_flag(name)
end

-- Focus an existing window matching `pattern`, else launch.
function M.launch_sole(name, pattern)
  return o.launch_webapp_sole(pattern, M.urls[name]) .. profile_flag(name)
end

return M
