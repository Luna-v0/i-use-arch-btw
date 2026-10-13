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
    -- CapsLock is remapped to Hyper (Mod3), giving a dedicated modifier for
    -- the second workspace decade -- see bindings.lua. This also stops
    -- CapsLock locking at all (<CAPS> becomes ONE_LEVEL Hyper_L, and it drops
    -- out of the Lock modifier map), so there is no caps state to get stuck in.
    -- Compose moves off CapsLock to Right Ctrl to make room.
    kb_options = "caps:hyper,compose:rctrl",

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
