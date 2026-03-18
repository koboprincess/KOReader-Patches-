-- Bottom Navigation Bar patch for KOReader File Manager
-- Adds a tab bar at the bottom with Home, Continue, Collections
-- This version merges working ImageWidget cover logic with the original full navbar structure.

local Blitbuffer = require("ffi/blitbuffer")
local CenterContainer = require("ui/widget/container/centercontainer")
local Device = require("device")
local FileManager = require("apps/filemanager/filemanager")
local Font = require("ui/font")
local Geom = require("ui/geometry")
local GestureRange = require("ui/gesturerange")
local HorizontalGroup = require("ui/widget/horizontalgroup")
local IconWidget = require("ui/widget/iconwidget")
local ImageWidget = require("ui/widget/imagewidget") -- ADDED: For rendering cover files
local InputContainer = require("ui/widget/container/inputcontainer")
local LineWidget = require("ui/widget/linewidget")
local Size = require("ui/size")
local TextWidget = require("ui/widget/textwidget")
local UIManager = require("ui/uimanager")
local VerticalGroup = require("ui/widget/verticalgroup")
local VerticalSpan = require("ui/widget/verticalspan")
local Screen = Device.screen
local _ = require("gettext")
local lfs = require("libs/libkoreader-lfs")

-- === Layout constants ===

local navbar_icon_size = Screen:scaleBySize(40)
local navbar_font = Font:getFace("smallinfofont")
local navbar_font_bold = Font:getFace("smallinfofontbold")
local navbar_v_padding = Screen:scaleBySize(-2) -- active line move
local navbar_h_padding = Screen:scaleBySize(5) -- line edge space
local navbar_top_gap = Screen:scaleBySize(60) 
local underline_thickness = Screen:scaleBySize(4) -- active tab line

-- === Persistent config ===

local config_default = {
    show_tabs = {
        books = true,
        continue = true,
        collections = false,
        exit = false,
    },
    tab_order = { "books", "continue", "collections", "exit" },
    show_labels = true,
    show_top_border = true,
    books_label = "Books",
    colored = false,
    active_tab_color = {0x33, 0x99, 0xFF}, -- blue
    show_in_standalone = true,
    show_top_gap = false,
    active_tab_styling = true,
    active_tab_bold = true,
    active_tab_underline = true,
    underline_above = true,
}

local function loadConfig()
    local config = G_reader_settings:readSetting("bottom_navbar", config_default)
    for k, v in pairs(config_default) do
        if config[k] == nil then config[k] = v end
    end
    if type(config.show_tabs) == "table" then
        for k, v in pairs(config_default.show_tabs) do
            if config.show_tabs[k] == nil then config.show_tabs[k] = v end
        end
    else
        config.show_tabs = config_default.show_tabs
    end
    if type(config.tab_order) ~= "table" then
        config.tab_order = config_default.tab_order
    else
        local order_set = {}
        for _, v in ipairs(config.tab_order) do order_set[v] = true end
        for _, v in ipairs(config_default.tab_order) do
            if not order_set[v] then table.insert(config.tab_order, v) end
        end
    end
    local seen = {}
    local dedup = {}
    for _, id in ipairs(config.tab_order) do
        if not seen[id] then
            table.insert(dedup, id)
            seen[id] = true
        end
    end
    config.tab_order = dedup
    return config
end

local config = loadConfig()

-- === Tab definitions ===

local function getBooksLabel()
    return config.books_label ~= "" and config.books_label or "Books"
end

local tabs = {
    { id = "books", label = getBooksLabel() },
    { id = "continue", label = _(""), icon = "reading1" },
    { id = "collections", label = _("Collections") },
    { id = "exit", label = _("Exit") },
}

local tabs_without_icons = {
    books = true,
    continue = false,
    collections = true,
    exit = true,
}

local tabs_by_id = {}
for _, tab in ipairs(tabs) do tabs_by_id[tab.id] = tab end

local active_tab = "books"
local injectNavbar
local injectStandaloneNavbar

local function setActiveTab(id)
    active_tab = id
    local fm = FileManager.instance
    if fm then
        injectNavbar(fm)
        UIManager:setDirty(fm, "ui")
    end
end

-- === Tab callbacks ===

local function onTabBooks()
    local fm = FileManager.instance
    if not fm then return end
    local home_dir = G_reader_settings:readSetting("home_dir")
                     or require("apps/filemanager/filemanagerutil").getDefaultDir()
    fm.file_chooser.path_items[home_dir] = nil
    fm.file_chooser:changeToPath(home_dir)
end

local function onTabContinue()
    local last_file = G_reader_settings:readSetting("lastfile")
    if not last_file or lfs.attributes(last_file, "mode") ~= "file" then
        local InfoMessage = require("ui/widget/infomessage")
        UIManager:show(InfoMessage:new{ text = _("Cannot open last document") })
        return
    end
    require("apps/reader/readerui"):showReader(last_file)
end

local function onTabCollections()
    local fm = FileManager.instance
    if fm and fm.collections then fm.collections:onShowCollList() end
end

local function onTabExit()
    if FileManager.instance then FileManager.instance:onClose() end
end

local tab_callbacks = {
    books = onTabBooks,
    continue = onTabContinue,
    collections = onTabCollections,
    exit = onTabExit,
}

-- === Color text support ===
local RenderText = require("ui/rendertext")
local ColorTextWidget = TextWidget:extend{}
function ColorTextWidget:paintTo(bb, x, y)
    self:updateSize()
    if self._is_empty or not self.fgcolor or Blitbuffer.isColor8(self.fgcolor) or not Screen:isColorScreen() or not self.use_xtext then
        TextWidget.paintTo(self, bb, x, y)
        return
    end
    if not self._xshaping then
        self._xshaping = self._xtext:shapeLine(self._shape_start, self._shape_end, self._shape_idx_to_substitute_with_ellipsis)
    end
    local text_width = math.min(bb:getWidth() - x, self.max_width or (bb:getWidth() - x))
    local pen_x = 0
    local baseline = self.forced_baseline or self._baseline_h
    for _, xglyph in ipairs(self._xshaping) do
        if pen_x >= text_width then break end
        local face = self.face.getFallbackFont(xglyph.font_num)
        local glyph = RenderText:getGlyphByIndex(face, xglyph.glyph, self.bold)
        bb:colorblitFromRGB32(glyph.bb, x + pen_x + glyph.l + xglyph.x_offset, y + baseline - glyph.t - xglyph.y_offset, 0, 0, glyph.bb:getWidth(), glyph.bb:getHeight(), self.fgcolor)
        pen_x = pen_x + xglyph.x_advance
    end
end

-- === Colored icon widget ===
local ColorIconWidget = IconWidget:extend{ _tint_color = nil }
function ColorIconWidget:paintTo(bb, x, y)
    if not self._tint_color or not Screen:isColorScreen() or self.hide then
        IconWidget.paintTo(self, bb, x, y)
        return
    end
    local size = self:getSize()
    self.dimen = self.dimen or Geom:new{ x = x, y = y, w = size.w, h = size.h }
    self.dimen.x, self.dimen.y = x, y
    self._bb:invert()
    bb:colorblitFromRGB32(self._bb, x, y, self._offset_x, self._offset_y, size.w, size.h, self._tint_color)
    self._bb:invert()
end

-- === Build a single tab (visual only) ===
local function createTabWidget(tab, tab_w, is_active)
    local styled = is_active and config.active_tab_styling
    local use_color = styled and config.colored and Screen:isColorScreen()
    local active_color
    if use_color then
        local c = config.active_tab_color
        if c and type(c) == "table" then active_color = Blitbuffer.ColorRGB32(c[1], c[2], c[3], 0xFF) end
    end

    local use_bold = styled and config.active_tab_bold
    local icon
    local top_pad = 2

    if tab.icon and not tabs_without_icons[tab.id] then
        if tab.id == "continue" then
            local last_file = G_reader_settings:readSetting("lastfile")
            local cover_path = nil
            if last_file then
                -- 1. Identify the two possible SDR folder naming conventions
                local sdr_with_ext = last_file .. ".sdr/"
                local sdr_no_ext = last_file:gsub("%.%w+$", "") .. ".sdr/"

                -- 2. Define the priority list of filenames KOReader uses
                local possible_files = {
                    "metadata.epub.jpg", -- Standard KOReader EPUB cache
                    "cover.png",        -- Common for Kepubs/Custom
                    "cover.jpg",        -- Generic fallback
                    "metadata.jpg",     -- Generic fallback
                }

                -- 3. Loop through both folder types and all possible filenames
                for _, folder in ipairs({sdr_with_ext, sdr_no_ext}) do
                    for _, name in ipairs(possible_files) do
                        local full_path = folder .. name
                        if lfs.attributes(full_path, "mode") == "file" then
                            cover_path = full_path
                            break
                        end
                    end
                    if cover_path then break end
                end
            end

            local scale_factor = 2.5
            local icon_height = math.floor(navbar_icon_size * scale_factor)
            local icon_width = math.floor(icon_height * 3 / 4)
            top_pad = -Screen:scaleBySize(25) -- Move cover up

            if cover_path then
                local FrameContainer = require("ui/widget/container/framecontainer")
                local cover_img = ImageWidget:new{ file = cover_path, width = icon_width, height = icon_height }
                
                -- Two-layer stack: White Frame -> Black Outline -> Image
                icon = FrameContainer:new{
                    padding = Screen:scaleBySize(2), -- White Frame thickness
                    bordersize = 0, -- optional border around white frame
                    background = Blitbuffer.ColorRGB32(255, 255, 255, 255),
                    FrameContainer:new{
                        bordersize = 1, -- outline around the cover art
                        bordercolor = Blitbuffer.COLOR_LIGHT_GRAY,
                        padding = 0,
                        cover_img
                    }
                }
            else
                icon = IconWidget:new{ icon = tab.icon, width = icon_width, height = icon_height }
            end
            icon = VerticalGroup:new{ align = "center", VerticalSpan:new{ width = top_pad }, icon }
        else
            icon = active_color and ColorIconWidget:new{ icon = tab.icon, width = navbar_icon_size, height = navbar_icon_size, _tint_color = active_color }
                             or IconWidget:new{ icon = tab.icon, width = navbar_icon_size, height = navbar_icon_size }
            if top_pad > 0 then icon = VerticalGroup:new{ align = "center", VerticalSpan:new{ width = top_pad }, icon } end
        end
    end

    local label
    if config.show_labels then
        local face = use_bold and navbar_font_bold or navbar_font
        label = active_color and ColorTextWidget:new{ text = tab.label, face = face, fgcolor = active_color }
                            or TextWidget:new{ text = tab.label, face = face }
    end

    -- 1. YOUR CUSTOM GROUPING (with label adjustment)
    local icon_label_group
    if icon and label then
        if tab.id ~= "continue" then
            -- Moves Home/Collections icons and text down for better visual balance
            icon_label_group = VerticalGroup:new{ 
                align = "center", 
                VerticalSpan:new{ width = Screen:scaleBySize(10) }, 
                icon, 
                label 
            }
        else
            -- Keeps the Continue cover exactly as it was
            icon_label_group = VerticalGroup:new{ align = "center", icon, label }
        end
    else
        icon_label_group = (icon or label)
    end

    -- 2. FIXED STAMP UNDERLINE (No guesswork, identical for all tabs)
    local show_underline = styled and config.active_tab_underline
    local underline
    if show_underline then
        local u_color = (config.colored and Screen:isColorScreen() and active_color) or Blitbuffer.COLOR_BLACK
        local Widget = require("ui/widget/widget")
        
        -- This is your Master Width. Change 100 to your preferred size.
        local fixed_width = Screen:scaleBySize(295) 
        
        -- We define the widget and the paint logic using that SAME width
        underline = Widget:new{ dimen = Geom:new{ w = fixed_width, h = underline_thickness } }
        
        function underline:paintTo(bb, x, y)
            -- Draws the line starting at x for the full fixed_width
            bb:paintRectRGB32(x, y, fixed_width, self.dimen.h, u_color)
        end
    else
        underline = VerticalSpan:new{ width = underline_thickness }
    end

    -- 3. YOUR PRESERVED SPACING LOGIC
    local v_pad = config.show_labels and navbar_v_padding or navbar_v_padding * 2
    local children = config.underline_above and { 
        align = "center", 
        underline, 
        VerticalSpan:new{ width = v_pad + 10}, 
        icon_label_group, 
        VerticalSpan:new{ width = v_pad - 5} 
    } or { 
        align = "center", 
        VerticalSpan:new{ width = v_pad + 10}, 
        icon_label_group, 
        VerticalSpan:new{ width = v_pad - 5}, 
        underline 
    }

    return CenterContainer:new{ 
        dimen = Geom:new{ w = tab_w, h = Screen:scaleBySize(65) }, 
        VerticalGroup:new(children) 
    }
end

-- === Build the full navbar ===
local HorizontalSpan = require("ui/widget/horizontalspan")
local function getVisibleTabs()
    local visible = {}
    for _, id in ipairs(config.tab_order) do
        if (id == "books" or config.show_tabs[id]) and tabs_by_id[id] then table.insert(visible, tabs_by_id[id]) end
    end
    return visible
end

local function createNavBar()
    tabs_by_id["books"].label = getBooksLabel()
    local visible_tabs = getVisibleTabs()
    if #visible_tabs == 0 then return nil end

    local screen_w = Screen:getWidth()
    local inner_w = screen_w - navbar_h_padding * 2
    
    -- === WIDTH ADJUSTMENT ===
    -- Increase this to add more space around the cover, decrease to make it tighter.
    local continue_tab_extra = Screen:scaleBySize(10) 
    local continue_w = math.floor(navbar_icon_size * 2.5 * 3 / 4) + continue_tab_extra
    
    -- Calculate remaining space for other tabs
    local other_tabs_count = 0
    local has_continue = false
    for _, tab in ipairs(visible_tabs) do
        if tab.id == "continue" then has_continue = true else other_tabs_count = other_tabs_count + 1 end
    end
    
    local other_tab_w = math.floor((inner_w - (has_continue and continue_w or 0)) / other_tabs_count)

    local row = HorizontalGroup:new{}
    local boundaries = {}
    local current_x = navbar_h_padding
    
    for _, tab in ipairs(visible_tabs) do 
        local current_w = (tab.id == "continue") and continue_w or other_tab_w
        table.insert(row, createTabWidget(tab, current_w, tab.id == active_tab)) 
        
        -- Store tap zones
        table.insert(boundaries, { id = tab.id, x_min = current_x, x_max = current_x + current_w })
        current_x = current_x + current_w
    end

    local OverlapGroup = require("ui/widget/overlapgroup")
    local row_with_padding = VerticalGroup:new{ align = "center", VerticalSpan:new{ width = Screen:scaleBySize(-15) }, HorizontalGroup:new{ HorizontalSpan:new{ width = navbar_h_padding }, row, HorizontalSpan:new{ width = navbar_h_padding } } }
    local row_h = row_with_padding:getSize().h

    local visual_children = {}
    if config.show_top_border then
        local separator = LineWidget:new{ dimen = Geom:new{ w = inner_w, h = Size.line.medium }, background = Blitbuffer.COLOR_LIGHT_GRAY }
        local separator_and_row = OverlapGroup:new{ dimen = Geom:new{ w = screen_w, h = row_h }, allow_mirroring = false, CenterContainer:new{ dimen = Geom:new{ w = screen_w, h = Size.line.medium }, separator }, row_with_padding }
        if config.show_top_gap then table.insert(visual_children, VerticalSpan:new{ width = navbar_top_gap }) end
        table.insert(visual_children, separator_and_row)
    else
        if config.show_top_gap then table.insert(visual_children, VerticalSpan:new{ width = navbar_top_gap }) end
        table.insert(visual_children, row_with_padding)
    end

    local navbar = InputContainer:new{
        dimen = Geom:new{ w = screen_w, h = VerticalGroup:new(visual_children):getSize().h },
        ges_events = { TapNavBar = { GestureRange:new{ ges = "tap", range = Geom:new{ x = 0, y = 0, w = screen_w, h = Screen:getHeight() } } } },
    }

    navbar.onTapNavBar = function(self, _, ges)
        if not self.dimen or not self.dimen:contains(ges.pos) then return false end
        for _, b in ipairs(boundaries) do
            if ges.pos.x >= b.x_min and ges.pos.x <= b.x_max then
                local cb = tab_callbacks[b.id]
                if cb then cb() end
                return true
            end
        end
        return true
    end

    navbar[1] = VerticalGroup:new(visual_children)
    return navbar
end

-- === Hook Menu:init() ===
local Menu = require("ui/widget/menu")
local function getNavbarHeight() local nb = createNavBar(); return nb and nb:getSize().h or 0 end
local standalone_view_names = { history = true, collections = true }
local function isStandaloneNavbarView(menu)
    return standalone_view_names[menu.name] or (not menu.name and menu.covers_fullscreen and menu.is_borderless and menu.title_bar_fm_style)
end
local _skip_standalone_navbar = false
local orig_menu_init = Menu.init
function Menu:init()
    if self.name == "filemanager" and not self.height then
        self.height = Screen:getHeight() - getNavbarHeight()
    elseif config.show_in_standalone and not _skip_standalone_navbar and isStandaloneNavbarView(self) then
        self.height = Screen:getHeight() - getNavbarHeight()
        if not self.is_borderless then self.is_borderless = true end
    end
    orig_menu_init(self)
end

-- === Injections ===
injectNavbar = function(fm)
    local fm_ui = fm[1]
    if not fm_ui then return end
    local file_chooser = fm._navbar_injected and (fm_ui[1] and fm_ui[1][1]) or fm_ui[1]
    if not file_chooser then return end
    fm._navbar_injected = true
    local navbar = createNavBar()
    if not navbar then fm_ui[1] = file_chooser; return end
    local navbar_h = navbar:getSize().h
    local new_height = Screen:getHeight() - navbar_h
    if file_chooser.height ~= new_height then
        local chrome = file_chooser.dimen.h - file_chooser.inner_dimen.h
        file_chooser.height, file_chooser.dimen.h, file_chooser.inner_dimen.h = new_height, new_height, new_height - chrome
        file_chooser:updateItems()
    end
    fm_ui[1] = VerticalGroup:new{ align = "left", file_chooser, navbar }
end

injectStandaloneNavbar = function(menu, view_tab_id)
    if not menu or not menu[1] then return end
    local saved_active = active_tab
    active_tab = view_tab_id
    local navbar = createNavBar()
    active_tab = saved_active
    if not navbar then return end

    navbar.onTapNavBar = function(self_nb, _, ges)
        if not self_nb.dimen or not self_nb.dimen:contains(ges.pos) then return false end
        
        -- Recalculate widths to match the visual layout
        local vis_tabs = getVisibleTabs()
        local cont_extra = Screen:scaleBySize(20)
        local cont_w = math.floor(navbar_icon_size * 2.5 * 3 / 4) + cont_extra
        
        local o_count = 0
        local has_cont = false
        for _, t in ipairs(vis_tabs) do 
            if t.id == "continue" then has_cont = true else o_count = o_count + 1 end 
        end
        
        local screen_w = Screen:getWidth()
        local o_w = math.floor((screen_w - navbar_h_padding * 2 - (has_cont and cont_w or 0)) / o_count)

        -- Iterate through the calculated boundaries to find the hit
        local check_x = navbar_h_padding
        for _, tab in ipairs(vis_tabs) do
            local cur_w = (tab.id == "continue") and cont_w or o_w
            if ges.pos.x >= check_x and ges.pos.x <= (check_x + cur_w) then
                -- Logic for switching views
                if tab.id == view_tab_id then return true end
                if menu.close_callback then menu.close_callback() elseif menu.onClose then menu:onClose() else UIManager:close(menu) end
                setActiveTab(tab.id)
                local cb = tab_callbacks[tab.id]
                if cb then cb() end
                return true
            end
            check_x = check_x + cur_w
        end
        return true
    end

    menu.dimen.h = Screen:getHeight()
    menu[1] = require("ui/widget/container/framecontainer"):new{ 
        background = Blitbuffer.COLOR_WHITE, 
        bordersize = 0, 
        padding = 0, 
        margin = 0, 
        VerticalGroup:new{ align = "left", menu[1], navbar } 
    }
end

local orig_setupLayout = FileManager.setupLayout
function FileManager:setupLayout()
    orig_setupLayout(self)
    self._navbar_injected = false
    local fm = self
    UIManager:nextTick(function() injectNavbar(fm); UIManager:setDirty(fm, "ui") end)
end

local FileManagerHistory = require("apps/filemanager/filemanagerhistory")
local orig_onShowHist = FileManagerHistory.onShowHist
function FileManagerHistory:onShowHist(search_info)
    local res = orig_onShowHist(self, search_info)
    if config.show_in_standalone and self.booklist_menu then injectStandaloneNavbar(self.booklist_menu, "history") end
    return res
end

local FileManagerCollection = require("apps/filemanager/filemanagercollection")
local orig_onShowColl = FileManagerCollection.onShowColl
function FileManagerCollection:onShowColl(collection_name)
    local from_coll_list = self.coll_list ~= nil
    local res = orig_onShowColl(self, collection_name)
    if config.show_in_standalone and self.booklist_menu then injectStandaloneNavbar(self.booklist_menu, from_coll_list and "collections" or "favorites") end
    return res
end

local orig_onShowCollList = FileManagerCollection.onShowCollList
function FileManagerCollection:onShowCollList(f_or_s, cb, nd)
    if f_or_s ~= nil then _skip_standalone_navbar = true end
    local res = orig_onShowCollList(self, f_or_s, cb, nd)
    _skip_standalone_navbar = false
    if config.show_in_standalone and self.coll_list and f_or_s == nil then injectStandaloneNavbar(self.coll_list, "collections") end
    return res
end
