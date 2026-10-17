-- The theme's own background, read before Normal goes transparent below. Kept in
-- a global so a second source (the theme hot-reload) still finds it.
local normal = vim.api.nvim_get_hl(0, { name = "Normal", link = false })
if normal.bg then
	vim.g.theme_normal_bg, vim.g.theme_normal_fg = normal.bg, normal.fg
end

-- Make highlight groups transparent while preserving their other attributes
local function make_transparent(name)
	local ok, hl = pcall(vim.api.nvim_get_hl, 0, { name = name, link = false })
	if ok then
		hl.bg = nil
		vim.api.nvim_set_hl(0, name, hl)
	end
end

local groups = {
	-- transparent background
	"Normal",
	"NormalFloat",
	"FloatBorder",
	"Pmenu",
	"Terminal",
	"EndOfBuffer",
	"FoldColumn",
	"Folded",
	"SignColumn",
	"LineNr",
	"CursorLineNr",
	"NormalNC",
	"WhichKeyFloat",
	"TelescopeBorder",
	"TelescopeNormal",
	"TelescopePromptBorder",
	"TelescopePromptTitle",
	-- neotree
	"NeoTreeNormal",
	"NeoTreeNormalNC",
	"NeoTreeVertSplit",
	"NeoTreeWinSeparator",
	"NeoTreeEndOfBuffer",
	-- nvim-tree
	"NvimTreeNormal",
	"NvimTreeVertSplit",
	"NvimTreeEndOfBuffer",
	-- notify
	"NotifyINFOBody",
	"NotifyERRORBody",
	"NotifyWARNBody",
	"NotifyTRACEBody",
	"NotifyDEBUGBody",
	"NotifyINFOTitle",
	"NotifyERRORTitle",
	"NotifyWARNTitle",
	"NotifyTRACETitle",
	"NotifyDEBUGTitle",
	"NotifyINFOBorder",
	"NotifyERRORBorder",
	"NotifyWARNBorder",
	"NotifyTRACEBorder",
	"NotifyDEBUGBorder",
}

for _, name in ipairs(groups) do
	make_transparent(name)
end

-- Popups with a solid body (completion menu and docs, the cmdline popup, snacks
-- windows, trouble, float titles) keep the theme's darkest background, which
-- reads as a near-black hole next to the transparent editor. Give them the
-- theme's own background lifted a little toward its foreground instead.
local LIFT = 0.08 -- 0 = the theme background, 1 = its foreground

local function blend(a, b, t)
	local out = 0
	for shift = 16, 0, -8 do
		local ca, cb = bit.band(bit.rshift(a, shift), 0xff), bit.band(bit.rshift(b, shift), 0xff)
		out = out + bit.lshift(math.floor(ca + (cb - ca) * t + 0.5), shift)
	end
	return out
end

local popups = {
	"BlinkCmpMenu",
	"BlinkCmpMenuBorder",
	"BlinkCmpDoc",
	"BlinkCmpDocBorder",
	"BlinkCmpSignatureHelp",
	"BlinkCmpSignatureHelpBorder",
	"NoiceCmdlinePopup",
	"NoiceCmdlinePopupBorder",
	"NoiceCmdlinePopupBorderSearch",
	"NoiceConfirm",
	"NoiceConfirmBorder",
	"SnacksNormal",
	"SnacksNormalNC",
	"TroubleNormal",
	"TelescopePromptNormal",
	"FloatTitle",
	"FloatFooter",
}

if vim.g.theme_normal_bg and vim.g.theme_normal_fg then
	local lifted = blend(vim.g.theme_normal_bg, vim.g.theme_normal_fg, LIFT)
	for _, name in ipairs(popups) do
		local ok, hl = pcall(vim.api.nvim_get_hl, 0, { name = name, link = false })
		if ok and hl.bg then
			hl.bg = lifted
			vim.api.nvim_set_hl(0, name, hl)
		end
	end
end
