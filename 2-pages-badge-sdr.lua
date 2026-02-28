--[[ KOReader patch: safe page number badges from .sdr metadata ]]--

local userpatch = require("userpatch")
local lfs = require("libs/libkoreader-lfs")
local Screen = require("device").screen
local Blitbuffer = require("ffi/blitbuffer")
local TextWidget = require("ui/widget/textwidget")
local FrameContainer = require("ui/widget/container/framecontainer")
local Font = require("ui/font")
local logger = require("logger")

--========================== [[User settings]] ================================
local page_font_size = 1.0                 -- badge font scaling
local page_text_color = Blitbuffer.COLOR_BLACK
local border_thickness = 2
local border_corner_radius = 6
local border_color = Blitbuffer.COLOR_DARK_GRAY
local background_color = Blitbuffer.COLOR_WHITE
local badge_position = "bottom-left"       -- badge corner
local move_from_border = 4                 -- padding from corner
local debug_mode = false
--=============================================================================

local count_cache = {}

-- Safe read of .sdr metadata
local function getPageCountFromSDR(filepath)
    if not filepath then return nil end
    local ok, pages = pcall(function()
        local sdr_path = filepath:gsub("%.([^%.]+)$", ".sdr")
        local metadata_file = sdr_path .. "/metadata.epub.lua"
        local attr = lfs.attributes(metadata_file)
        if not attr then return nil end
        local f = io.open(metadata_file, "r")
        if not f then return nil end
        local content = f:read("*all")
        f:close()
        local p = content:match('%["pagemap_doc_pages"%]%s*=%s*(%d+)') or
                  content:match('%["doc_pages"%]%s*=%s*(%d+)')
        return p and tonumber(p) or nil
    end)
    if ok then return pages end
    return nil
end

local function getBookStats(filepath)
    if count_cache[filepath] then return count_cache[filepath] end
    local stats = { pages = nil }
    local pages = getPageCountFromSDR(filepath)
    if pages and pages > 0 then stats.pages = pages end
    count_cache[filepath] = stats
    return stats
end

local function formatNumber(num)
    if num >= 1000 then return string.format("%.1fK", num/1000) end
    return tostring(num)
end

-- Patch the MosaicMenuItem paintTo to draw page badges safely
local function patchCoverBrowserSDRPageBadge(plugin)
    local MosaicMenu = require("mosaicmenu")
    local MosaicMenuItem = userpatch.getUpValue(MosaicMenu._updateItemsBuildUI, "MosaicMenuItem")
    if MosaicMenuItem.patched_sdr_pagebadge then return end
    MosaicMenuItem.patched_sdr_pagebadge = true

    local origPaintTo = MosaicMenuItem.paintTo

    function MosaicMenuItem:paintTo(bb, x, y)
        origPaintTo(self, bb, x, y)

        if not self.filepath or self.is_directory or self.file_deleted then return end

        local stats = getBookStats(self.filepath)
        if not stats.pages then return end

        local display_text = formatNumber(stats.pages) .. "p"

        local corner_mark_size = Screen:scaleBySize(10)
        local font_size = math.floor(corner_mark_size * page_font_size)

        local text_widget = TextWidget:new{
            text = display_text,
            face = Font:getFace("cfont", font_size),
            fgcolor = page_text_color,
            bold = true,
            padding = 1,
        }

        local badge = FrameContainer:new{
            bordersize = border_thickness,
            radius = Screen:scaleBySize(border_corner_radius),
            color = border_color,
            background = background_color,
            padding = Screen:scaleBySize(2),
            margin = 0,
            text_widget,
        }

        local target = self[1][1][1]
        if not target or not target.dimen then return end
        local cover_w, cover_h = target.dimen.w, target.dimen.h
        local cover_left = x + math.floor((self.width - cover_w)/2)
        local cover_top = y + math.floor((self.height - cover_h)/2)
        local cover_right = cover_left + cover_w
        local cover_bottom = cover_top + cover_h
        local pad = Screen:scaleBySize(move_from_border)

        local pos_x, pos_y
        if badge_position == "bottom-left" then
            pos_x = cover_left + pad
            pos_y = cover_bottom - pad - badge:getSize().h
        elseif badge_position == "bottom-right" then
            pos_x = cover_right - pad - badge:getSize().w
            pos_y = cover_bottom - pad - badge:getSize().h
        elseif badge_position == "top-left" then
            pos_x = cover_left + pad
            pos_y = cover_top + pad
        else -- top-right
            pos_x = cover_right - pad - badge:getSize().w
            pos_y = cover_top + pad
        end

        -- Paint the badge safely
        pcall(function()
            badge:paintTo(bb, pos_x, pos_y)
        end)
    end
end

userpatch.registerPatchPluginFunc("coverbrowser", patchCoverBrowserSDRPageBadge)