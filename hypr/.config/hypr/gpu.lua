-- Rendering GPU follows the cabling. Aquamarine composites on whichever GPU the
-- monitors are plugged into, so with the monitors on the motherboard ports the
-- desktop runs on the AMD iGPU and the RTX card is left free for compute.
--
-- Omarchy's default/hypr/nvidia.lua exports NVIDIA-only env (VA-API, GLX vendor,
-- NVD_BACKEND) whenever an NVIDIA card is present, which would pull video decode
-- and XWayland GL back onto the RTX card. Point them at Mesa instead -- but only
-- while the AMD card actually drives an output, so the old cabling (monitors on
-- the RTX card) keeps Omarchy's defaults untouched.
--
-- Same detection also feeds AQ_DRM_DEVICES below, pinning Aquamarine to the
-- single GPU that's actually driving a display. Without it, Aquamarine opens
-- the idle NVIDIA card as a second DRM backend too, and Hyprland's "auto"
-- hardware-cursor setting falls back to software cursors whenever it sees
-- more than one GPU -- a confirmed bug on this exact AMD-iGPU/NVIDIA-dGPU
-- shape (omacom/omarchy#12791, ~3% FPS loss, +16W). A detector for this is
-- in progress upstream (omacom/omarchy PR #14624, not yet in 4.0.4) but for
-- the opposite topology (NVIDIA drives the display, AMD iGPU idle); this
-- mirrors its shape for ours.
local amd_connected_card_path = [[
for s in /sys/class/drm/card*-*/status; do
  card=${s#/sys/class/drm/}; card=/sys/class/drm/${card%%-*}
  dev="/dev/dri/$(basename "$card")"
  [ "$(cat "$card/device/vendor" 2>/dev/null)" = 0x1002 ] \
    && [ "$(cat "$s" 2>/dev/null)" = connected ] \
    && [ -e "$dev" ] \
    && { echo "$dev"; exit 0; }
done
exit 1
]]

-- Hyprland reaps its own children, so (like helpers.lua's o.shell_succeeds)
-- os.execute() can't hand back a command's stdout either -- read it off a
-- pipe instead. This Omarchy release (4.0.4-1) doesn't ship o.shell_output
-- yet (that lands with PR #14624 above); defined locally here, scoped to
-- this file, so it can't collide with the real one once it does land.
local function shell_output(command)
  local pipe = io.popen("( " .. command .. " ) 2>/dev/null")
  if not pipe then
    return nil
  end

  local output = (pipe:read("*a") or ""):gsub("%s+$", "")
  pipe:close()

  if output == "" then
    return nil
  end

  return output
end

local amd_card = shell_output(amd_connected_card_path)

if amd_card then
  hl.env("LIBVA_DRIVER_NAME", "radeonsi")
  hl.env("__GLX_VENDOR_LIBRARY_NAME", "mesa")
  hl.env("NVD_BACKEND", "")

  -- Deliberately /dev/dri/cardN here, NOT /dev/dri/by-path/pci-...-card.
  -- AQ_DRM_DEVICES is colon-separated and PCI by-path names contain colons
  -- themselves (e.g. "pci-0000:0f:00.0-card"); Aquamarine splits naively on
  -- ':', which is a confirmed upstream footgun (omacom/omarchy#8776: it
  -- shreds the by-path string into bogus tokens, finds no GPU, the
  -- compositor exits, and SDDM autologin silently login-loops). The fix for
  -- that bug (omacom/omarchy#8786) resolves by-path back down to
  -- /dev/dri/cardN with `readlink -e` before export -- exactly the path
  -- shape the detector above already returns directly, since it re-reads
  -- sysfs fresh on every Hyprland start anyway. No by-path round-trip
  -- needed, and the colon bug never comes into play.
  --
  -- Safety: amd_card is nil (so this whole block is skipped and
  -- AQ_DRM_DEVICES is left unset, today's behaviour) unless the loop above
  -- found a connected AMD connector AND the resulting /dev/dri/cardN node
  -- exists. A wrong/missing value here only takes effect at the next
  -- Hyprland start.
  hl.env("AQ_DRM_DEVICES", amd_card)
end
