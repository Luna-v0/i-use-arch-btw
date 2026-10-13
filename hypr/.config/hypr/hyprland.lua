-- Learn how to configure Hyprland: https://wiki.hypr.land/Configuring/Start/

-- Omarchy's bootstrap keeps path setup out of this user config.
dofile((os.getenv("OMARCHY_PATH") or "/usr/share/omarchy") .. "/default/hypr/bootstrap.lua")

-- Disable all Omarchy default bindings. Add your own in hypr/bindings.lua.
-- omarchy_default_bindings = false
--
-- Or disable only bindings for Omarchy's preinstalled apps/web apps while
-- keeping core window-manager bindings:
-- omarchy_preinstalled_bindings = false

-- Load Omarchy defaults.
require("default.hypr.omarchy")

-- Put your personal overrides in these files. They're loaded after Omarchy's
-- defaults so package updates can improve the defaults without rewriting your
-- ~/.config/hypr files.
require("hypr.monitors")
require("hypr.input")
require("hypr.bindings")
require("hypr.looknfeel")
require("hypr.autostart")

-- After Omarchy's defaults: retarget NVIDIA env to Mesa when the iGPU drives the displays.
require("hypr.gpu")

-- Toggle config flags dynamically.
require("default.hypr.toggles")

-- Add any other personal Hyprland configuration below.
-- o.window("qemu", { workspace = "5" })

-- Don't let the lock/screensaver interrupt a long GPU-bound run that's being
-- watched (Isaac Lab training, a long Jupyter cell) just because the window
-- lost focus for a bit -- "always" (inhibit idle for as long as the window
-- exists) rather than "focus" (only while it's the active window), because
-- the whole point is surviving an alt-tab to check something else mid-run;
-- "focus" would reintroduce exactly that friction. Same pattern Omarchy
-- already ships for Steam/Moonlight/GeForceNow (default/hypr/apps/*.lua).

-- jlab (xonsh/.config/xonsh/jlab.xsh) just prints a localhost URL -- Jupyter
-- opens as a normal tab in whatever browser is default (BROWSER=zen), not
-- its own --app window, so there's no stable class to match. Match by title
-- instead; this fires for any window titled "...Jupyter[Lab]...", regardless
-- of which browser hosts it.
o.window({ title = ".*Jupyter.*" }, { idle_inhibit = "always" })

-- Isaac Sim isn't installed on this host, so its real WM_CLASS is unverified.
-- NVIDIA Omniverse Kit apps (which Isaac Sim is built on) are reported to use
-- "Isaac Sim", "isaac-sim" or the generic Kit class "Kit" depending on
-- version; this regex covers all three candidates. Confirm with
-- `hyprctl activewindow` once Isaac Sim actually runs, and narrow it if
-- "Kit" turns out to be too broad (it would also catch other Kit-based apps,
-- if any get installed).
o.window({ class = "[Ii]saac[ _-]?[Ss]im|^Kit$" }, { idle_inhibit = "always" })
