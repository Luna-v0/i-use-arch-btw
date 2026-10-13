-- Ported from input.conf (Omarchy 3). https://wiki.hypr.land/Configuring/Basics/Variables/#input
--
-- Quattro's default input.lua derives kb_layout from /etc/vconsole.conf, which
-- here has XKBLAYOUT=br but XKBMODEL=abnt2 and no XKBVARIANT -- so the abnt2
-- variant would be dropped. Pin it explicitly, along with the slower repeat
-- delay and the compose-only Caps behaviour this setup has always used.
hl.config({
  input = {
    kb_layout = "br",
    kb_variant = "abnt2",
    kb_options = "compose:caps",

    repeat_rate = 40,
    repeat_delay = 600,
    numlock_by_default = true,

    touchpad = {
      scroll_factor = 0.4,
    },
  },
})

-- Terminal scroll tuning is identical to Quattro's default input.lua, so it is
-- intentionally not repeated here.
