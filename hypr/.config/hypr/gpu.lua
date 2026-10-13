-- Rendering GPU follows the cabling. Aquamarine composites on whichever GPU the
-- monitors are plugged into, so with the monitors on the motherboard ports the
-- desktop runs on the AMD iGPU and the RTX card is left free for compute.
--
-- Omarchy's default/hypr/nvidia.lua exports NVIDIA-only env (VA-API, GLX vendor,
-- NVD_BACKEND) whenever an NVIDIA card is present, which would pull video decode
-- and XWayland GL back onto the RTX card. Point them at Mesa instead -- but only
-- while the AMD card actually drives an output, so the old cabling (monitors on
-- the RTX card) keeps Omarchy's defaults untouched.
local igpu_drives_a_display = [[
for s in /sys/class/drm/card*-*/status; do
  card=${s#/sys/class/drm/}; card=/sys/class/drm/${card%%-*}
  [ "$(cat "$card/device/vendor" 2>/dev/null)" = 0x1002 ] && [ "$(cat "$s")" = connected ] && exit 0
done
exit 1
]]

if o.shell_succeeds(igpu_drives_a_display) then
  hl.env("LIBVA_DRIVER_NAME", "radeonsi")
  hl.env("__GLX_VENDOR_LIBRARY_NAME", "mesa")
  hl.env("NVD_BACKEND", "")
end
