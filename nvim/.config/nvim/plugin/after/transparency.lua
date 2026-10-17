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

-- Markdown quotes ("> ...") use the theme's comment grey, which nearly
-- vanishes against the background. Lift them partway toward the normal text
-- colour, keeping the theme's other attributes (italic).
local QUOTE_LIFT = 0.65 -- 0 = the theme background, 1 = its foreground

local function blend(a, b, t)
	local out = 0
	for shift = 16, 0, -8 do
		local ca, cb = bit.band(bit.rshift(a, shift), 0xff), bit.band(bit.rshift(b, shift), 0xff)
		out = out + bit.lshift(math.floor(ca + (cb - ca) * t + 0.5), shift)
	end
	return out
end

if vim.g.theme_normal_bg and vim.g.theme_normal_fg then
	local hl = vim.api.nvim_get_hl(0, { name = "@markup.quote", link = false })
	hl.fg = blend(vim.g.theme_normal_bg, vim.g.theme_normal_fg, QUOTE_LIFT)
	vim.api.nvim_set_hl(0, "@markup.quote", hl)
end
