--===========================================================================
-- EzWoW - Utility Bar
-- UI/ToolbarFrame.lua : Main Utility Bar, Secure Buttons & Category Headers
--===========================================================================
local _, ns = ...
local ToolbarController = ns.ToolbarController or {}
ns.ToolbarController = ToolbarController
local type, pairs, ipairs, tonumber, tostring, select, pcall = type, pairs, ipairs, tonumber, tostring, select, pcall

local buttons = {}
local headers = {}
local draggingCategory = nil
local draggingTitle = false
local hoverUI = false
local hoverExitElapsed = 0
-- The bar's frame, outline and buttons come up only after the mouse has stayed on the title for
-- TITLE_HOVER_DELAY seconds (2026-11-22, user: passing over the title lit the bar up); dragging the
-- title brings them at once. Once up they stay while the mouse is on the bar.
local TITLE_HOVER_DELAY = 1
local titleHoverSince = nil
function ToolbarController.titleHoverDue(since, now, overTitle)
    if not overTitle or type(since) ~= "number" or type(now) ~= "number" then return false end
    return now - since >= TITLE_HOVER_DELAY
end

-- An icon's tooltip comes once the mouse rests on it for TOOLTIP_DELAY seconds (2026-11-24, user: the game
-- stuttered while the mouse moved over the bar). Every icon the mouse crossed built a whole item tooltip:
-- with the gear comparison and every addon's lines that is 20-80 ms (13 ms without them), so a mouse
-- sweeping the bar dropped frame after frame. The OnUpdate below shows the tooltip of the icon still
-- waiting; leaving the icon takes the wait back.
-- The wait is EzWoW - Tooltip's show delay for every tooltip (its option, 0.25 s by default) and
-- TOOLTIP_DELAY without it; never under MIN_TOOLTIP_DELAY, so crossing the bar builds nothing. The bar
-- waits itself and then asks EzWoW - Tooltip to show that tooltip at once (no second wait).
ToolbarController.TOOLTIP_DELAY = 0.25
ToolbarController.MIN_TOOLTIP_DELAY = 0.15
local pendingTip, pendingTipDue = nil, 0
function ToolbarController.tooltipDue(button, due, now)
    return button ~= nil and type(due) == "number" and type(now) == "number" and now >= due
end
function ToolbarController.tooltipDelay()
    local tipAddon = _G.EzWoW_Tooltip
    if type(tipAddon) == "table" and type(tipAddon.ShowDelay) == "function" then
        local ok, d = pcall(tipAddon.ShowDelay)
        if ok and type(d) == "number" then
            return math.max(ToolbarController.MIN_TOOLTIP_DELAY, d)
        end
    end
    return ToolbarController.TOOLTIP_DELAY
end

-----------------------------------------------------------------------------
-- Main Frame Creation
-----------------------------------------------------------------------------
local frame = CreateFrame("Frame", "EzWoWUtilityBarFrame", UIParent, "BackdropTemplate")
frame:SetSize(280, 62)
frame:SetClampedToScreen(true)
frame:SetPoint("CENTER", UIParent, "CENTER", 0, -180)
frame:SetMovable(true)
frame:EnableMouse(false)
ns.UIKit:ApplyBackdrop(frame, 1, 1)
frame:SetBackdropBorderColor(0.204, 0.298, 0.357, 0.90)
frame:SetBackdropColor(0.071, 0.094, 0.122, 0.93)

local title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
title:SetPoint("TOPLEFT", 12, -8)
title:SetTextColor(0.788, 0.643, 0.937)
title:SetText("EzWoW - Utility Bar")
title:SetDrawLayer("OVERLAY", 2)

ns.MainFrame = frame
ns.buttons = buttons
ns.headers = headers

-----------------------------------------------------------------------------
-- Cooldown, Usability & Active Stance Helpers
-----------------------------------------------------------------------------
function ToolbarController.GetEntryBorderColor(entry)
    local q = entry.type == "item" and tonumber(entry.quality)
    if q and q >= 2 then
        local c = ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[q]
        if c and c.r then
            return c.r * 0.85, c.g * 0.85, c.b * 0.85, 0.95
        end
        local fallback = {
            [2] = { 0.12, 0.85, 0.00 },
            [3] = { 0.00, 0.44, 0.87 },
            [4] = { 0.64, 0.21, 0.93 },
            [5] = { 1.00, 0.50, 0.00 },
        }
        local f = fallback[q]
        if f then return f[1], f[2], f[3], 0.95 end
    end
    return 0.17, 0.22, 0.26, 0.90
end

function ToolbarController.GetCooldownInfo(entry)
    local start, duration, enabled
    if entry.type == "item" then
        if C_Item and type(C_Item.GetItemCooldown) == "function" then
            local ok, a, b, c = pcall(C_Item.GetItemCooldown, entry.id)
            if ok then
                if type(a) == "table" then
                    start, duration, enabled = a.startTime, a.duration, a.isEnabled
                else
                    start, duration, enabled = a, b, c
                end
            end
        end
        if start == nil and type(GetItemCooldown) == "function" then
            local ok, a, b, c = pcall(GetItemCooldown, entry.id)
            if ok then start, duration, enabled = a, b, c end
        end
    else
        if C_Spell and type(C_Spell.GetSpellCooldown) == "function" then
            local ok, a, b, c = pcall(C_Spell.GetSpellCooldown, entry.id)
            if ok then
                if type(a) == "table" then
                    start, duration, enabled = a.startTime, a.duration, a.isEnabled
                else
                    start, duration, enabled = a, b, c
                end
            end
        end
        if start == nil and type(GetSpellCooldown) == "function" then
            local ok, a, b, c = pcall(GetSpellCooldown, entry.id)
            if ok then start, duration, enabled = a, b, c end
        end
    end

    if ns.IsSecret(start) or ns.IsSecret(duration) then
        return start, duration, enabled, true
    end
    return tonumber(start) or 0, tonumber(duration) or 0, enabled, false
end

-- In combat the game gives spell cooldowns as secret values that addon code can't read.
-- The game's DurationObject draws them without reading (C_Spell.GetSpellCooldownDuration +
-- Cooldown:SetCooldownFromDurationObject); otherwise the secret values go to SetCooldown.
-- Returns how it was drawn ("duration" / "secret") or nil when neither worked.
function ToolbarController.DrawSecretCooldown(b, start, duration)
    local entry, cd = b.entry, b.cooldown
    if not cd then return nil end
    -- (no finish flash here: drawn again on every cooldown change in combat, the flash
    -- kept going off on the icons; the normal path turns it back on)
    if cd.SetDrawBling then pcall(cd.SetDrawBling, cd, false) end
    if entry and entry.type == "spell" and C_Spell and type(C_Spell.GetSpellCooldownDuration) == "function"
        and type(cd.SetCooldownFromDurationObject) == "function" then
        local ok, durationObject = pcall(C_Spell.GetSpellCooldownDuration, entry.id)
        if ok and durationObject and pcall(cd.SetCooldownFromDurationObject, cd, durationObject) then
            return "duration"
        end
    end
    if cd.SetCooldown and pcall(cd.SetCooldown, cd, start, duration) then return "secret" end
    return nil
end

function ToolbarController.IsEntryUsable(entry)
    if entry.type == "spell" then
        if C_Spell and type(C_Spell.IsSpellUsable) == "function" then
            local ok, a, b = pcall(C_Spell.IsSpellUsable, entry.id)
            if ok then
                local u = ns.ToBooleanFlag(a)
                if u == nil then return true, false end
                return u, ns.ToBooleanFlag(b) == true
            end
        end
        if type(IsUsableSpell) == "function" then
            local ok, a, b = pcall(IsUsableSpell, entry.id)
            if ok then
                local u = ns.ToBooleanFlag(a)
                if u == nil then return true, false end
                return u, ns.ToBooleanFlag(b) == true
            end
        end
    else
        if C_Item and type(C_Item.IsUsableItem) == "function" then
            local ok, a, b = pcall(C_Item.IsUsableItem, entry.id)
            if ok then
                local u = ns.ToBooleanFlag(a)
                if u == nil then return true, false end
                return u, ns.ToBooleanFlag(b) == true
            end
        end
        if type(IsUsableItem) == "function" then
            local ok, a, b = pcall(IsUsableItem, entry.id)
            if ok then
                local u = ns.ToBooleanFlag(a)
                if u == nil then return true, false end
                return u, ns.ToBooleanFlag(b) == true
            end
        end
    end
    return true, false
end

-- While the player casts or channels (and 0.5 s after), the game now and then answers "not usable" for
-- every item (2026-11-26, flicker check: all icons went gray and back twice within a second while planting
-- a seed pouch; the game's own action bar does not change). Such an answer is not used then: the icon
-- keeps the look it had before the cast. A lack of mana still shows.
local usableSeen = {}          -- "type:id" -> usable as last answered outside a cast
local castSeenAt = -10
local function castingNow(fn)
    if type(fn) ~= "function" then return false end
    local ok, v = pcall(fn, "player")
    return (ok and (ns.IsSecret(v) or v ~= nil)) and true or false
end

function ToolbarController.PlayerCasting(now)
    if castingNow(UnitCastingInfo) or castingNow(UnitChannelInfo) then castSeenAt = now end
    return now - castSeenAt < 0.5
end

-- Outside a cast, too, the game answers "not usable" for every item for a moment while it is busy with
-- an action (2026-11-26, flicker check: gray twice within a second while the bags sold items at a vendor,
-- about 0.3 s each time). An icon that was usable turns gray only when that answer has lasted
-- UNUSABLE_SETTLE; an icon seen for the first time, or gray already, follows the answer at once.
local UNUSABLE_SETTLE = 0.6
local unusableSince = {}       -- "type:id" -> when the game began to answer "not usable"

-- An item whose data the game does not hold at the moment (other lookups pushed it out of the item
-- cache) answers anything: such an answer changes nothing either way (2026-11-26, flicker check: gray
-- icons turned bright and back twice within a second, with item data events at each change).
function ToolbarController.ItemDataReady(entry)
    if entry.type ~= "item" then return true end
    local fn = C_Item and C_Item.IsItemDataCachedByID
    if type(fn) ~= "function" then return true end
    local ok, cached = pcall(fn, entry.id)
    if not ok or ns.IsSecret(cached) then return true end
    return cached ~= false
end

-- Such an item also answers "no cooldown" (2026-11-26, flicker check on a flight path and while dead:
-- icons with a running cooldown went gray and back twice within a second, the cooldown gone each time
-- the item data was missing). The cooldown drawn last stays until it runs out.
function ToolbarController.KeptCooldown(b, start, duration, dataReady, now)
    if dataReady ~= false or (start > 0 and duration > 0) then return start, duration end
    local s, d = b.lastStart, b.lastDuration
    if type(s) == "number" and type(d) == "number" and s + d > (tonumber(now) or 0) then
        return s, d
    end
    return start, duration
end

-- the usable look of an icon (see above)
function ToolbarController.ShownUsable(entry, usable, noResource, casting, now, dataReady)
    local key = tostring(entry.type) .. ":" .. tostring(entry.id)
    if dataReady == false and usableSeen[key] ~= nil then
        unusableSince[key] = nil
        return usableSeen[key]
    end
    if usable or noResource then
        unusableSince[key] = nil
        usableSeen[key] = usable
        return usable
    end
    local before = usableSeen[key]
    if casting then
        unusableSince[key] = nil
        if before == nil then return true end
        return before
    end
    if before ~= true then
        usableSeen[key] = false
        return false
    end
    now = tonumber(now) or 0
    local since = unusableSince[key]
    if not since then
        unusableSince[key] = now
        return true
    end
    if now - since < UNUSABLE_SETTLE then return true end
    unusableSince[key] = nil
    usableSeen[key] = false
    return false
end

function ToolbarController.IsActiveFormSpell(entry)
    if entry.type ~= "spell" or entry.category ~= "forms" then return false end
    if type(GetShapeshiftForm) ~= "function" or type(GetShapeshiftFormInfo) ~= "function" then return false end
    local ok, idx = pcall(GetShapeshiftForm)
    if not ok or not idx or ns.IsSecret(idx) or idx <= 0 then return false end
    local success, texture, _, _, spellID = pcall(GetShapeshiftFormInfo, idx)
    if not success then return false end
    if spellID and not ns.IsSecret(spellID) and tonumber(spellID) == tonumber(entry.id) then
        return true
    end
    if texture and entry.icon and not ns.IsSecret(texture) and tostring(texture) == tostring(entry.icon) then
        return true
    end
    return false
end

-----------------------------------------------------------------------------
-- Secure Action Button Pool
-----------------------------------------------------------------------------
-- Follows the game's "cast on key down" option.
function ToolbarController.UseKeyDown()
    local fn = (C_CVar and C_CVar.GetCVarBool) or GetCVarBool
    if type(fn) ~= "function" then return false end
    local ok, value = pcall(fn, "ActionButtonUseKeyDown")
    return ok and value == true
end

-- SetAttribute on secure buttons only out of combat; otherwise after combat ends.
function ToolbarController.ApplyKeyDownSetting()
    if InCombatLockdown() then
        ns.pendingKeyDown = true
        return
    end
    ns.pendingKeyDown = false
    local keyDown = ToolbarController.UseKeyDown()
    for _, b in ipairs(buttons) do
        b:SetAttribute("useOnKeyDown", keyDown)
    end
end

function ToolbarController.AcquireActionButton(index)
    if buttons[index] then return buttons[index] end

    local b = CreateFrame("Button", "EzWoWUtilityBarAction" .. index, frame, "SecureActionButtonTemplate")
    b.icon = b:CreateTexture(nil, "ARTWORK")
    b.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)

    b.border = b:CreateTexture(nil, "BACKGROUND")
    b.border:SetAllPoints()
    b.border:SetTexture("Interface\\Buttons\\WHITE8X8")
    b.border:SetVertexColor(0.17, 0.22, 0.26, 0.90)
    b.border:SetDrawLayer("BACKGROUND", 0)

    b.icon:SetPoint("TOPLEFT", 2, -2)
    b.icon:SetPoint("BOTTOMRIGHT", -2, 2)

    b.cooldown = CreateFrame("Cooldown", nil, b, "CooldownFrameTemplate")
    b.cooldown:SetAllPoints(b.icon)
    b.cooldown:SetFrameLevel(b:GetFrameLevel() + 2)
    if b.cooldown.SetDrawEdge then b.cooldown:SetDrawEdge(false) end
    if b.cooldown.SetHideCountdownNumbers then b.cooldown:SetHideCountdownNumbers(false) end

    b.shade = b:CreateTexture(nil, "OVERLAY")
    b.shade:SetAllPoints(b.icon)
    b.shade:SetColorTexture(0, 0, 0, 0.52)
    b.shade:Hide()

    b.activeEdges = {}
    for edge = 1, 4 do
        local t = b:CreateTexture(nil, "OVERLAY")
        t:SetTexture("Interface\\Buttons\\WHITE8X8")
        t:SetVertexColor(0.95, 0.76, 0.33, 1)
        if edge == 1 then
            t:SetPoint("TOPLEFT", b, "TOPLEFT", 0, 0)
            t:SetPoint("TOPRIGHT", b, "TOPRIGHT", 0, 0)
            t:SetHeight(2)
        elseif edge == 2 then
            t:SetPoint("BOTTOMLEFT", b, "BOTTOMLEFT", 0, 0)
            t:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", 0, 0)
            t:SetHeight(2)
        elseif edge == 3 then
            t:SetPoint("TOPLEFT", b, "TOPLEFT", 0, 0)
            t:SetPoint("BOTTOMLEFT", b, "BOTTOMLEFT", 0, 0)
            t:SetWidth(2)
        else
            t:SetPoint("TOPRIGHT", b, "TOPRIGHT", 0, 0)
            t:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", 0, 0)
            t:SetWidth(2)
        end
        t:Hide()
        b.activeEdges[edge] = t
    end

    b.count = b:CreateFontString(nil, "OVERLAY", "NumberFontNormalSmall")
    b.count:SetPoint("BOTTOMRIGHT", -2, 2)
    b.count:SetDrawLayer("OVERLAY", 6)

    local glow = b:CreateTexture(nil, "HIGHLIGHT")
    glow:SetAllPoints(b.icon)
    glow:SetColorTexture(1, 0.86, 0.52, 0.16)

    local pushed = b:CreateTexture(nil, "OVERLAY")
    pushed:SetAllPoints(b.icon)
    pushed:SetColorTexture(0, 0, 0, 0.30)
    if b.SetPushedTexture then b:SetPushedTexture(pushed) else pushed:Hide() end

    local hideBtn = CreateFrame("Button", nil, b)
    hideBtn:SetSize(14, 14)
    hideBtn:SetPoint("TOPRIGHT", b, "TOPRIGHT", 2, 2)
    hideBtn:SetFrameLevel(b:GetFrameLevel() + 6)

    local hbg = hideBtn:CreateTexture(nil, "BACKGROUND")
    hbg:SetAllPoints()
    hbg:SetColorTexture(0.10, 0.06, 0.05, 0.92)

    local hedge = hideBtn:CreateTexture(nil, "BORDER")
    hedge:SetPoint("TOPLEFT", -1, 1)
    hedge:SetPoint("BOTTOMRIGHT", 1, -1)
    hedge:SetColorTexture(0.72, 0.30, 0.24, 0.95)
    hedge:SetDrawLayer("BACKGROUND", -1)

    local hx = hideBtn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    hx:SetPoint("CENTER", 0, 1)
    hx:SetText("x")
    hx:SetTextColor(1, 0.78, 0.70)

    hideBtn:SetScript("OnClick", function(self)
        local owner = self:GetParent()
        if not ns.db or not owner.entry then return end
        ns.db.hidden[ns.GetEntryKey(owner.entry)] = true
        self:Hide()
        GameTooltip:Hide()
        ns:RefreshToolbar()
        if ns.ConfigFrame and ns.ConfigFrame:IsShown() and ns.ConfigFrame.updateLabels then
            ns.ConfigFrame.updateLabels()
        end
    end)
    hideBtn:SetScript("OnEnter", function(self)
        hbg:SetColorTexture(0.42, 0.12, 0.09, 1)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:SetText(ns:L("hideIcon"), 1, 0.82, 0.60)
        GameTooltip:AddDoubleLine(" ", "EzWoW - Utility Bar", 0, 0, 0, 0.5, 0.5, 0.5)
        GameTooltip:Show()
        if _G.EzWoWTooltipTagSizer and _G.EzWoWTooltipTagSizer.Refit then pcall(_G.EzWoWTooltipTagSizer.Refit, GameTooltip) end
    end)
    hideBtn:SetScript("OnLeave", function(self)
        hbg:SetColorTexture(0.10, 0.06, 0.05, 0.92)
        GameTooltip:Hide()
        if not self:GetParent():IsMouseOver() then
            self:Hide()
        end
    end)
    hideBtn:Hide()
    b.hideBtn = hideBtn

    -- Both edges are registered; the attribute picks which one acts, so a click or key fires once.
    b:RegisterForClicks("AnyUp", "AnyDown")
    b:SetAttribute("useOnKeyDown", ToolbarController.UseKeyDown())
    b:SetScript("OnEnter", function(self)
        if not self.entry then return end
        if ns.hoverUIActive and ns.db and not ns.db.locked then
            self.hideBtn:Show()
        end
        pendingTip, pendingTipDue = self, GetTime() + ToolbarController.tooltipDelay()
    end)
    b:SetScript("OnLeave", function(self)
        if pendingTip == self then pendingTip = nil end
        if not GameTooltip.IsOwned or GameTooltip:IsOwned(self) then
            GameTooltip:Hide()
        end
        if not self.hideBtn:IsMouseOver() then
            self.hideBtn:Hide()
        end
    end)

    buttons[index] = b
    return b
end

function ToolbarController.ShowEntryTooltip(b)
    local entry = b.entry
    if not entry then return end
    local tipAddon = _G.EzWoW_Tooltip
    if type(tipAddon) == "table" and type(tipAddon.ShowNextWithoutDelay) == "function" then
        pcall(tipAddon.ShowNextWithoutDelay, b)
    end
    GameTooltip:SetOwner(b, "ANCHOR_RIGHT")
    if entry.type == "item" then
        if entry.inventorySlot and GameTooltip.SetInventoryItem then
            GameTooltip:SetInventoryItem("player", entry.inventorySlot)
        elseif GameTooltip.SetItemByID then
            GameTooltip:SetItemByID(entry.id)
        end
    elseif GameTooltip.SetSpellByID then
        GameTooltip:SetSpellByID(entry.id)
    end
    GameTooltip:Show()
end

-- The number on an item icon, as on the game's action bar: every use left (an item with 5 charges says 5),
-- shown even at 1 for things used up or stacking; reusable things (Hearthstone) only when there are several.
-- byReagents: the uses come from the reagents the item takes; none left says 0, as on the action bar.
function ToolbarController.CountText(entry, n, byReagents)
    if n == 0 and byReagents then return "0" end
    if type(n) ~= "number" or n <= 0 then return "" end
    if n > 1 or byReagents or entry.category == "reagent" or ns.IsCountedItem(entry.id) then
        return tostring(n)
    end
    return ""
end

-- Uses left of a bag item (nil: unknown), and true when they come from the reagents it takes.
function ToolbarController.ItemUses(entry)
    local n = ns.GetSafeItemCount(entry.id, true)
    if not n then return nil, false end
    if n > 0 then
        local casts = ns.ItemReagentCasts(entry.id)
        if casts then return casts, true end
    end
    return n, false
end

function ToolbarController.BindEntryToButton(b, entry, size)
    b.entry = entry
    b:ClearAllPoints()
    b:SetSize(size, size)
    b.icon:SetTexture(entry.icon)
    b.icon:SetVertexColor(1, 1, 1, 1)
    b:SetAlpha(1)

    local db = ns.db or _G.EzWoW_UtilityBarDB
    local n, byReagents = entry.count, false
    if entry.type == "item" and not entry.inventorySlot then
        local uses
        uses, byReagents = ToolbarController.ItemUses(entry)
        n = uses or entry.count
    end
    local isLow = db and db.lowStockWarn and entry.lowThreshold and n and n > 0 and n <= entry.lowThreshold
    if isLow then
        b.border:SetVertexColor(0.90, 0.26, 0.22, 0.98)
        b.count:SetTextColor(1, 0.32, 0.32)
        b.count:SetText(tostring(n))
    else
        b.border:SetVertexColor(ToolbarController.GetEntryBorderColor(entry))
        b.count:SetTextColor(1, 1, 1)
        b.count:SetText(entry.type == "item" and ToolbarController.CountText(entry, n, byReagents) or "")
    end

    b:SetAttribute("type", entry.type)
    if entry.type == "item" then
        b:SetAttribute("item", entry.inventorySlot and tostring(entry.inventorySlot) or ("item:" .. tostring(entry.id)))
        b:SetAttribute("spell", nil)
    else
        b:SetAttribute("item", nil)
        b:SetAttribute("spell", entry.id)
    end

    b.hideBtn:Hide()
    b.lastStart = nil
    b.lastDuration = nil
    b.secretDrawn = nil
    b.lastCount = nil
    b:Show()
end

-----------------------------------------------------------------------------
-- Category Header Bar & Drag Badge
-----------------------------------------------------------------------------
local dragBadge = CreateFrame("Frame", nil, UIParent, "BackdropTemplate")
dragBadge:SetSize(140, 22)
dragBadge:SetFrameStrata("TOOLTIP")
dragBadge:Hide()
ns.UIKit:ApplyBackdrop(dragBadge)
dragBadge:SetBackdropColor(0.14, 0.11, 0.20, 0.96)
dragBadge:SetBackdropBorderColor(0.788, 0.643, 0.937, 1)
dragBadge.text = dragBadge:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
dragBadge.text:SetPoint("CENTER", 0, 0)
dragBadge.text:SetTextColor(0.929, 0.957, 0.969)

function ToolbarController.AcquireCategoryHeader(groupKey)
    if headers[groupKey] then return headers[groupKey] end

    local h = CreateFrame("Button", nil, frame)
    h:SetHeight(20)
    h:EnableMouse(ns.hoverUIActive or (ns.db and not ns.db.locked))
    h:RegisterForDrag("LeftButton")

    h.bg = h:CreateTexture(nil, "BACKGROUND")
    h.bg:SetAllPoints()
    h.bg:SetColorTexture(0.114, 0.157, 0.192, 0.92)

    h.label = h:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    h.label:SetPoint("LEFT", 12, 0)
    h.label:SetJustifyH("LEFT")
    h.label:SetTextColor(0.929, 0.957, 0.969)

    h.grip = h:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    h.grip:SetPoint("RIGHT", -8, 0)
    h.grip:SetText("↕")
    h.grip:SetTextColor(0.788, 0.643, 0.937, 0.85)

    h.accent = h:CreateTexture(nil, "ARTWORK")
    h.accent:SetColorTexture(0.788, 0.643, 0.937, 0.95)
    h.accent:SetPoint("TOPLEFT", h, "TOPLEFT", 0, 0)
    h.accent:SetPoint("BOTTOMLEFT", h, "BOTTOMLEFT", 0, 0)
    h.accent:SetWidth(2)

    h:SetScript("OnClick", function(self)
        -- a click that arrives right as a drag ends belongs to the drag (the
        -- client may or may not send one): only later clicks fold the group
        if self.dragEndedAt and GetTime() - self.dragEndedAt < 0.3 then return end
        if not ns.hoverUIActive and (not ns.db or ns.db.locked) then return end
        ns.db.collapsed[groupKey] = not ns.db.collapsed[groupKey]
        ns:RefreshToolbar()
    end)

    h:SetScript("OnDragStart", function(self)
        if not ns.db or ns.db.locked or InCombatLockdown() then return end
        draggingCategory = groupKey
        self.bg:SetColorTexture(0.24, 0.19, 0.32, 0.98)
        dragBadge.text:SetText("↕  " .. ns:GetGroupLabel(groupKey))
        dragBadge:SetWidth(math.max(110, dragBadge.text:GetStringWidth() + 24))
        dragBadge:Show()
    end)

    h:SetScript("OnDragStop", function(self)
        self.dragEndedAt = GetTime()
        if draggingCategory ~= groupKey then return end
        draggingCategory = nil
        dragBadge:Hide()
        self.bg:SetColorTexture(0.114, 0.157, 0.192, 0.92)
        ns:RefreshToolbar()
        if ns.ConfigFrame and ns.ConfigFrame:IsShown() and ns.ConfigFrame.updateLabels then
            ns.ConfigFrame.updateLabels()
        end
    end)

    h:SetScript("OnEnter", function(self)
        local active = (draggingCategory == groupKey)
        self.bg:SetColorTexture(active and 0.24 or 0.16, active and 0.19 or 0.22, active and 0.32 or 0.27, 0.98)
    end)

    h:SetScript("OnLeave", function(self)
        local active = (draggingCategory == groupKey)
        self.bg:SetColorTexture(active and 0.24 or 0.114, active and 0.19 or 0.157, active and 0.32 or 0.192, active and 0.98 or 0.92)
    end)

    headers[groupKey] = h
    return h
end

-----------------------------------------------------------------------------
-- Developer check: icons that flicker (2026-11-26, user: "the bar sometimes flickers gray")
-- Only while the developer's data scanner (EzWoW-DataDumper) is loaded. An icon that turns into the
-- same look (gray or bright) twice within FLICKER_WINDOW is written down with what the game answered
-- at each of the three changes and what the player was doing, said in the chat and kept in
-- EzWoW_UtilityBarDB.devFlicker (last FLICKER_KEEP; /ezub flicker shows the last ones).
-----------------------------------------------------------------------------
local Flicker = { events = {} }
ns.Flicker = Flicker
local FLICKER_WINDOW = 1       -- two turns into the same look within this (seconds)
local FLICKER_QUIET = 3        -- the same icon is written down again only after this
local FLICKER_KEEP = 100
local FLICKER_EVENTS = 12

-- true on the developer's PC (asked once, after the addons have loaded)
function Flicker.On()
    if Flicker.on == nil then
        local fn = (C_AddOns and C_AddOns.IsAddOnLoaded) or _G.IsAddOnLoaded
        local ok, loaded = false, false
        if type(fn) == "function" then ok, loaded = pcall(fn, "EzWoW-DataDumper") end
        Flicker.on = (ok and loaded == true) and true or false
    end
    return Flicker.on
end

function Flicker.NoteEvent(event)
    if not Flicker.on then return end
    local list = Flicker.events
    list[#list + 1] = { GetTime(), event }
    if #list > FLICKER_EVENTS then table.remove(list, 1) end
end

local function plainValue(v)
    if v == nil or ns.IsSecret(v) then return nil end
    return v
end

local OPEN_WINDOWS = { "QuestFrame", "GossipFrame", "MerchantFrame", "LootFrame", "MailFrame", "TradeFrame",
    "BankFrame", "TaxiFrame", "SpellBookFrame", "ProfessionsFrame", "TradeSkillFrame", "CharacterFrame",
    "ContainerFrameCombinedBags", "StaticPopup1" }

-- what the player was doing: combat, casting, flying, open windows, the events just before
function Flicker.Context(now)
    local parts = {}
    local function add(s) parts[#parts + 1] = s end
    local function ask(fn, ...)
        if type(fn) ~= "function" then return nil end
        local ok, v = pcall(fn, ...)
        return ok and plainValue(v) or nil
    end
    if ask(InCombatLockdown) then add("전투") end
    local cast = ask(UnitCastingInfo, "player")
    if cast then add("시전 " .. tostring(cast)) end
    local channel = ask(UnitChannelInfo, "player")
    if channel then add("정신 집중 " .. tostring(channel)) end
    if ask(UnitOnTaxi, "player") then add("비행 경로") end
    if ask(IsMounted) then add("탈것") end
    if ask(UnitIsDeadOrGhost, "player") then add("죽음") end
    if ask(SpellIsTargeting) then add("대상 지정 중") end
    local form = tonumber(ask(GetShapeshiftForm))
    if form and form > 0 then add("변신 " .. form) end
    local open = {}
    for _, name in ipairs(OPEN_WINDOWS) do
        local f = _G[name]
        if type(f) == "table" and type(f.IsShown) == "function" then
            local ok, shown = pcall(f.IsShown, f)
            if ok and shown == true then open[#open + 1] = name end
        end
    end
    if #open > 0 then add("열린 창 " .. table.concat(open, ",")) end
    if (ns.lastFrameElapsed or 0) > 0.1 then add(string.format("직전 프레임 %.2f초", ns.lastFrameElapsed)) end
    if ns.refreshedAt and now - ns.refreshedAt < 1 then add(string.format("다시 배치 %.2f초 전", now - ns.refreshedAt)) end
    local events = {}
    for _, e in ipairs(Flicker.events) do
        if now - e[1] <= 0.6 then events[#events + 1] = e[2] end
    end
    if #events > 0 then add("이벤트 " .. table.concat(events, ",")) end
    return table.concat(parts, " · ")
end

-- the icon's look and the game's answers that made it
function Flicker.Why(blocked, usable, noResource, count, byReagents, onCD, active, gameUsable, dataReady)
    local parts = { blocked and "회색" or "밝음", "쓸 수 있음 " .. tostring(usable) }
    if gameUsable ~= nil and gameUsable ~= usable then parts[#parts + 1] = "게임 답 " .. tostring(gameUsable) .. "(잠깐인 답이라 안 씀)" end
    if noResource then parts[#parts + 1] = "자원 부족" end
    if count ~= nil then parts[#parts + 1] = "개수 " .. tostring(count) .. (byReagents and "(재료)" or "") end
    if onCD then parts[#parts + 1] = "재사용 대기" end
    if active then parts[#parts + 1] = "변신 중" end
    if dataReady == false then parts[#parts + 1] = "아이템 정보 없음" end
    return table.concat(parts, " · ")
end

-- One icon's look in this update. Returns a record when it turned into the same look twice within
-- FLICKER_WINDOW (three changes: A -> B -> A -> B).
function Flicker.Track(index, b, now, blocked, usable, noResource, count, byReagents, onCD, active, gameUsable, dataReady)
    local entry = b.entry
    local key = tostring(entry.type) .. ":" .. tostring(entry.id)
    local tr = b.flicker
    if not tr or tr.key ~= key then
        b.flicker = { key = key, blocked = blocked, marks = {} }
        return nil
    end
    if tr.blocked == blocked then return nil end
    tr.blocked = blocked
    local marks = tr.marks
    marks[#marks + 1] = { t = now, why = Flicker.Why(blocked, usable, noResource, count, byReagents, onCD, active, gameUsable, dataReady),
        ctx = Flicker.Context(now) }
    while #marks > 3 do table.remove(marks, 1) end
    if #marks < 3 or now - marks[1].t > FLICKER_WINDOW or now < (tr.quietUntil or 0) then return nil end
    tr.quietUntil = now + FLICKER_QUIET
    tr.marks = {}
    local rec = {
        at = date("%m-%d %H:%M:%S"),
        icon = index,
        name = tostring(entry.name or entry.id),
        id = entry.id,
        kind = entry.type,
        look = blocked and "회색" or "밝음",
        first = string.format("%.2f", marks[2].t - marks[1].t),   -- how long the first turn lasted
        gap = string.format("%.2f", marks[3].t - marks[2].t),     -- until the second turn
        m1 = marks[1].why .. " | " .. marks[1].ctx,
        m2 = marks[2].why .. " | " .. marks[2].ctx,
        m3 = marks[3].why .. " | " .. marks[3].ctx,
    }
    local db = ns.db
    if db then
        if type(db.devFlicker) ~= "table" then db.devFlicker = {} end
        table.insert(db.devFlicker, rec)
        while #db.devFlicker > FLICKER_KEEP do table.remove(db.devFlicker, 1) end
    end
    return rec
end

-- one chat line for the icons written down in one update
function Flicker.Say(list)
    if not list or #list == 0 then return end
    local r = list[1]
    local names = {}
    for i = 1, math.min(#list, 4) do names[#names + 1] = list[i].name end
    local more = (#list > 4) and string.format(" 외 %d칸", #list - 4) or ""
    ns.Print(string.format("|cffF1BD57[깜박임 점검]|r %s%s: 1초 안에 %s 2번 (처음 %s초, 사이 %s초) · %s",
        table.concat(names, ", "), more, r.look, r.first, r.gap, r.m1))
end

-- the last records in the chat (/ezub flicker)
function Flicker.Show(count)
    local list = ns.db and ns.db.devFlicker
    if type(list) ~= "table" or #list == 0 then
        ns.Print("깜박임 기록 없음" .. (Flicker.On() and "" or " (스캐너가 켜진 PC에서만 기록)"))
        return
    end
    for i = math.max(1, #list - (count or 5) + 1), #list do
        local r = list[i]
        ns.Print(string.format("%s #%s %s: %s 2번 (처음 %s초, 사이 %s초)", r.at, tostring(r.icon), r.name, r.look, r.first, r.gap))
        ns.Print("  1) " .. tostring(r.m1))
        ns.Print("  2) " .. tostring(r.m2))
        ns.Print("  3) " .. tostring(r.m3))
    end
end

-----------------------------------------------------------------------------
-- Visual State & Layout Refresh
-----------------------------------------------------------------------------
function ns:UpdateVisuals()
    local db = self.db or _G.EzWoW_UtilityBarDB
    if not db then return end
    local now = GetTime()
    local flickerOn = Flicker.On()
    local flickered = nil
    local casting = ToolbarController.PlayerCasting(now)

    for index, b in ipairs(buttons) do
        if b:IsShown() and b.entry then
            local empty = false
            local shownCount, shownByReagents = nil, false
            if b.entry.type == "item" and not b.entry.inventorySlot then
                local n, byReagents = ToolbarController.ItemUses(b.entry)
                shownCount, shownByReagents = n, byReagents
                if n then
                    local low = db.lowStockWarn and b.entry.lowThreshold and n > 0 and n <= b.entry.lowThreshold
                    if n ~= b.lastCount or low ~= b.lastLow or byReagents ~= b.lastByReagents then
                        b.lastCount = n
                        b.lastLow = low
                        b.lastByReagents = byReagents
                        if low then
                            b.border:SetVertexColor(0.90, 0.26, 0.22, 0.98)
                            b.count:SetTextColor(1, 0.32, 0.32)
                            b.count:SetText(tostring(n))
                        else
                            b.border:SetVertexColor(ToolbarController.GetEntryBorderColor(b.entry))
                            b.count:SetTextColor(1, 1, 1)
                            b.count:SetText(ToolbarController.CountText(b.entry, n, byReagents))
                        end
                    end
                    empty = (n == 0)
                end
            end

            local dataReady = ToolbarController.ItemDataReady(b.entry)
            local start, duration, _, secret = ToolbarController.GetCooldownInfo(b.entry)
            if not secret then
                start, duration = ToolbarController.KeptCooldown(b, start, duration, dataReady, now)
            end
            local onCD = false
            if secret then
                -- (secret values can't be compared: drawn again only when the game says a cooldown
                -- changed, not on every poll)
                if ns.cooldownChanged or not b.secretDrawn then
                    ToolbarController.DrawSecretCooldown(b, start, duration)
                    b.secretDrawn = true
                end
                b.cooldown:Show()
                b.lastStart, b.lastDuration = nil, nil
            else
                b.secretDrawn = nil
                onCD = start > 0 and duration > 0 and (start + duration) > (now + 0.05)
                if onCD then
                    if b.lastStart ~= start or b.lastDuration ~= duration then
                        if b.cooldown.SetDrawBling then b.cooldown:SetDrawBling(true) end
                        if CooldownFrame_Set then
                            CooldownFrame_Set(b.cooldown, start, duration, 1)
                        elseif b.cooldown.SetCooldown then
                            b.cooldown:SetCooldown(start, duration)
                        end
                        b.lastStart, b.lastDuration = start, duration
                    end
                    b.cooldown:Show()
                else
                    b.cooldown:Hide()
                    b.lastStart, b.lastDuration = nil, nil
                end
            end

            local gameUsable, noResource = ToolbarController.IsEntryUsable(b.entry)
            local usable = ToolbarController.ShownUsable(b.entry, gameUsable, noResource, casting, now, dataReady)
            local active = ToolbarController.IsActiveFormSpell(b.entry)
            local blocked = (not usable and not onCD and not active) or empty

            b.shade:SetAlpha(noResource and 0.75 or 0.52)
            b.shade:SetShown(blocked)
            b.icon:SetDesaturated(blocked)
            for _, edge in ipairs(b.activeEdges) do
                edge:SetShown(active)
            end
            b.icon:SetVertexColor(1, 1, 1, 1)
            if flickerOn then
                local rec = Flicker.Track(index, b, now, blocked, usable, noResource, shownCount, shownByReagents, onCD, active, gameUsable, dataReady)
                if rec then
                    flickered = flickered or {}
                    flickered[#flickered + 1] = rec
                end
            end
        end
    end
    ns.cooldownChanged = false
    if flickered then Flicker.Say(flickered) end
end

-----------------------------------------------------------------------------
-- Top-Right Toolbar Controls, Resize Grip & Hover Reveal
-----------------------------------------------------------------------------
function ToolbarController.SaveFramePosition()
    if not ns.db then return end
    local point, _, relativePoint, x, y = frame:GetPoint(1)
    ns.db.position = { point or "CENTER", relativePoint or "CENTER", x or 0, y or 0 }
end

function ToolbarController.CreateToolbarControl(name, iconName, xOffset, tipKey, onClick)
    local b = CreateFrame("Button", name, frame, "BackdropTemplate")
    b:SetSize(23, 23)
    b:SetPoint("TOPRIGHT", frame, "TOPRIGHT", xOffset, -3)
    ns.UIKit:ApplyBackdrop(b)
    b:SetBackdropColor(0.114, 0.157, 0.192, 0.92)
    b:SetBackdropBorderColor(0.204, 0.298, 0.357, 0.95)

    local icon = b:CreateTexture(nil, "ARTWORK")
    b.icon = icon
    icon:SetPoint("TOPLEFT", 3, -3)
    icon:SetPoint("BOTTOMRIGHT", -3, 3)
    icon:SetTexture(ns.MEDIA_PATH .. iconName .. ".tga")

    b:SetScript("OnEnter", function(self)
        self:SetBackdropColor(0.20, 0.16, 0.27, 0.98)
        self:SetBackdropBorderColor(0.788, 0.643, 0.937, 1)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:SetText("EzWoW - Utility Bar", 0.788, 0.643, 0.937)
        GameTooltip:AddLine(ns:L(tipKey), 0.929, 0.957, 0.969, true)
        GameTooltip:Show()
    end)
    b:SetScript("OnLeave", function(self)
        self:SetBackdropColor(0.114, 0.157, 0.192, 0.92)
        self:SetBackdropBorderColor(0.204, 0.298, 0.357, 0.95)
        GameTooltip:Hide()
    end)
    if onClick then b:SetScript("OnClick", onClick) end
    b:Hide()
    return b
end

local foldBtn = ToolbarController.CreateToolbarControl("EzWoWUtilityBarFoldButton", "fold", -57, "foldTip", function()
    if not ns.db then return end
    local allCollapsed = true
    for _, k in ipairs(ns.order) do
        if not ns.db.collapsed[k] then
            allCollapsed = false
            break
        end
    end
    for _, k in ipairs(ns.order) do
        ns.db.collapsed[k] = not allCollapsed
    end
    ns:RefreshToolbar()
end)

local gearBtn = ToolbarController.CreateToolbarControl("EzWoWUtilityBarSettingsButton", "gear", -6, "gearTip", function()
    ns:ToggleOptions()
end)

local lockBtn = ToolbarController.CreateToolbarControl("EzWoWUtilityBarLockButton", "unlock", -32, "lockTip", function()
    if not ns.db or InCombatLockdown() then return end
    ns.db.locked = not ns.db.locked
    ns:RefreshToolbar()
end)

local resizeHandle = CreateFrame("Button", "EzWoWUtilityBarResizeHandle", frame)
resizeHandle:SetSize(19, 19)
resizeHandle:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -1, 1)
resizeHandle:SetFrameLevel(frame:GetFrameLevel() + 10)
local resizeIcon = resizeHandle:CreateTexture(nil, "ARTWORK")
resizeIcon:SetAllPoints()
resizeIcon:SetTexture(ns.MEDIA_PATH .. "resize.tga")

frame:SetResizable(true)
if frame.SetResizeBounds then
    frame:SetResizeBounds(190, 55, 900, 900)
elseif frame.SetMinResize then
    frame:SetMinResize(190, 55)
    frame:SetMaxResize(900, 900)
end

local sizingFrame = false
resizeHandle:RegisterForDrag("LeftButton")
resizeHandle:SetScript("OnDragStart", function()
    if ns.db and not ns.db.locked and not InCombatLockdown() then
        sizingFrame = true
        frame:StartSizing("BOTTOMRIGHT")
    end
end)
resizeHandle:SetScript("OnDragStop", function()
    if not sizingFrame then return end
    sizingFrame = false
    if InCombatLockdown() then return end
    frame:StopMovingOrSizing()
    if not ns.db then return end
    ns.db.manualWidth = math.floor(frame:GetWidth() + 0.5)
    ns.db.manualHeight = math.floor(frame:GetHeight() + 0.5)
    ns.db.columns = math.max(1, math.floor((ns.db.manualWidth - 16) / ((ns.db.size or 36) + 4)))
    ToolbarController.SaveFramePosition()
    ns:RefreshToolbar()
end)

local titleHover = CreateFrame("Frame", nil, frame, "BackdropTemplate")
titleHover:SetPoint("TOPLEFT", frame, "TOPLEFT", 5, -3)
titleHover:SetSize(128, 23)
titleHover:SetBackdrop({ edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1 })
titleHover:SetBackdropBorderColor(0.788, 0.643, 0.937, 0)
titleHover:EnableMouse(true)
titleHover:RegisterForDrag("LeftButton")

titleHover:SetScript("OnDragStart", function()
    if not ns.db or InCombatLockdown() then return end
    if ns.db.locked and not IsControlKeyDown() then return end
    draggingTitle = true
    frame:StartMoving()
    if not hoverUI then ns:ShowHoverUI(true) end
end)
titleHover:SetScript("OnDragStop", function()
    if not draggingTitle then return end
    draggingTitle = false
    if InCombatLockdown() then return end
    frame:StopMovingOrSizing()
    ToolbarController.SaveFramePosition()
end)

-- PLAYER_REGEN_DISABLED comes just before the lockdown: a move or resize still
-- going on is finished there, while the bar may still be changed
local combatStop = CreateFrame("Frame")
pcall(combatStop.RegisterEvent, combatStop, "PLAYER_REGEN_DISABLED")
combatStop:SetScript("OnEvent", function()
    if not (draggingTitle or sizingFrame) then return end
    local wasSizing = sizingFrame
    draggingTitle, sizingFrame = false, false
    frame:StopMovingOrSizing()
    if wasSizing and ns.db then
        ns.db.manualWidth = math.floor(frame:GetWidth() + 0.5)
        ns.db.manualHeight = math.floor(frame:GetHeight() + 0.5)
        ns.db.columns = math.max(1, math.floor((ns.db.manualWidth - 16) / ((ns.db.size or 36) + 4)))
    end
    ToolbarController.SaveFramePosition()
end)

function ns:ShowHoverUI(show)
    hoverUI = show
    self.hoverUIActive = show
    local canClickHeader = show or (self.db and not self.db.locked)
    for _, h in pairs(headers) do
        h:EnableMouse(canClickHeader)
    end
    hoverExitElapsed = 0
    if not self.db then return end
    foldBtn:SetShown(show)
    gearBtn:SetShown(show)
    lockBtn:SetShown(show)
    resizeHandle:SetShown(show and not self.db.locked)
    titleHover:SetBackdropBorderColor(0.788, 0.643, 0.937, show and 0.9 or 0)
    frame:SetBackdropColor(0.071, 0.094, 0.122, show and 0.88 or (self.db.locked and 0 or 0.93))
    frame:SetBackdropBorderColor(0.788, 0.643, 0.937, show and 0.9 or (self.db.locked and 0 or 0.90))
    if not show then
        for _, b in ipairs(buttons) do
            if b.hideBtn then b.hideBtn:Hide() end
        end
    end
end

titleHover:SetScript("OnEnter", function(self)
    titleHoverSince = GetTime()
    GameTooltip:SetOwner(self, "ANCHOR_TOPLEFT")
    GameTooltip:SetText("EzWoW - Utility Bar", 0.788, 0.643, 0.937)
    GameTooltip:AddLine(ns:L("helpMove"), 0.929, 0.957, 0.969, true)
    GameTooltip:AddLine(ns:L("helpReorder"), 0.655, 0.725, 0.773, true)
    GameTooltip:AddLine(ns:L("hideHint"), 0.655, 0.725, 0.773, true)
    GameTooltip:Show()
end)
titleHover:SetScript("OnLeave", function()
    titleHoverSince = nil
    GameTooltip:Hide()
end)

function ns:RefreshToolbar()
    local db = self.db or _G.EzWoW_UtilityBarDB
    if not db then return end
    if InCombatLockdown() then
        self.pendingRefresh = true
        return
    end
    self.pendingRefresh = false
    self.refreshedAt = GetTime()

    local entries = self:CollectEntries()
    local size = db.size or 36
    local cols = math.max(1, db.columns or 8)

    local grouped = {}
    for _, entry in ipairs(entries) do
        grouped[entry.category] = grouped[entry.category] or {}
        table.insert(grouped[entry.category], entry)
    end

    local width = math.max(190, db.manualWidth or (16 + cols * (size + 4)))
    cols = math.max(1, math.floor((width - 16) / (size + 4)))

    local y = 32
    local index = 0

    if db.unified then
        for _, k in ipairs(self.order) do
            headers[k] = ToolbarController.AcquireCategoryHeader(k)
            headers[k]:Hide()
        end
        local shown = {}
        for _, entry in ipairs(entries) do
            if db.categories[entry.category] then
                shown[#shown + 1] = entry
            end
        end
        for n, entry in ipairs(shown) do
            index = index + 1
            local b = ToolbarController.AcquireActionButton(index)
            ToolbarController.BindEntryToButton(b, entry, size)
            b:SetPoint("TOPLEFT", frame, "TOPLEFT", 8 + ((n - 1) % cols) * (size + 4), -y - math.floor((n - 1) / cols) * (size + 4))
        end
        y = y + math.ceil(#shown / cols) * (size + 4) + 5
    else
        for _, k in ipairs(self.order) do
            local group = grouped[k]
            local h = ToolbarController.AcquireCategoryHeader(k)
            if db.categories[k] and group and #group > 0 then
                local collapsed = db.collapsed[k]
                h:ClearAllPoints()
                h:SetPoint("TOPLEFT", frame, "TOPLEFT", 8, -y)
                h:SetWidth(width - 16)
                h.label:SetText((collapsed and ">  " or "v  ") .. self:GetGroupLabel(k) .. "  |  " .. #group)
                ns.UIKit:FitFontString(h.label, width - 50, 1)  -- keep clear of the drag grip
                if h.grip then h.grip:SetShown(not db.locked) end
                if draggingCategory == k then
                    h.bg:SetColorTexture(0.24, 0.19, 0.32, 0.98)
                else
                    h.bg:SetColorTexture(0.114, 0.157, 0.192, 0.92)
                end
                h:Show()
                y = y + 25
                if not collapsed then
                    for n, entry in ipairs(group) do
                        index = index + 1
                        local b = ToolbarController.AcquireActionButton(index)
                        ToolbarController.BindEntryToButton(b, entry, size)
                        b:SetPoint("TOPLEFT", frame, "TOPLEFT", 8 + ((n - 1) % cols) * (size + 4), -y - math.floor((n - 1) / cols) * (size + 4))
                    end
                    y = y + math.ceil(#group / cols) * (size + 4) + 5
                end
            else
                h:Hide()
            end
        end
    end

    for i = index + 1, #buttons do
        local b = buttons[i]
        b:Hide()
        b:SetAttribute("type", nil)
        b.entry = nil
        b.cooldown:Hide()
        b.shade:Hide()
        b.hideBtn:Hide()
        for _, edge in ipairs(b.activeEdges) do edge:Hide() end
    end

    local left, top, bottom = frame:GetLeft(), frame:GetTop(), frame:GetBottom()
    if not draggingTitle and left and top and bottom then
        frame:ClearAllPoints()
        if db.growUp then
            frame:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", left, bottom)
            db.position = { "BOTTOMLEFT", "BOTTOMLEFT", left, bottom }
        else
            frame:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", left, top)
            db.position = { "TOPLEFT", "BOTTOMLEFT", left, top }
        end
    end

    frame:SetSize(width, math.max(48, y + 10, db.manualHeight or 0))
    frame:SetBackdropColor(0.071, 0.094, 0.122, db.locked and 0 or 0.93)
    frame:SetBackdropBorderColor(0.204, 0.298, 0.357, db.locked and 0 or 0.90)

    for _, h in pairs(headers) do
        if h.bg then h.bg:SetAlpha(db.locked and 0 or 1) end
        if h.accent then h.accent:SetAlpha(db.locked and 0 or 1) end
        if h.grip then h.grip:SetShown(not db.locked) end
    end

    if db.visible then frame:Show() else frame:Hide() end
    if lockBtn and lockBtn.icon then
        lockBtn.icon:SetTexture(ns.MEDIA_PATH .. (db.locked and "lock" or "unlock") .. ".tga")
    end
    self:ShowHoverUI(hoverUI)
    self:UpdateVisuals()
end

-----------------------------------------------------------------------------
-- OnUpdate Drivers & Events
-----------------------------------------------------------------------------
local visualTimer = 0
local VISUAL_MIN_GAP = 0.05
local sinceVisual = VISUAL_MIN_GAP

frame:SetScript("OnUpdate", function(_, elapsed)
    local db = ns.db or _G.EzWoW_UtilityBarDB
    if not db then return end
    ns.lastFrameElapsed = elapsed

    -- 0. The tooltip of the icon the mouse rests on (TOOLTIP_DELAY)
    if pendingTip and ToolbarController.tooltipDue(pendingTip, pendingTipDue, GetTime()) then
        local b = pendingTip
        pendingTip = nil
        if b:IsVisible() and b.entry then ToolbarController.ShowEntryTooltip(b) end
    end

    -- 1. Category Drag Reordering
    if draggingCategory then
        if InCombatLockdown() or not IsMouseButtonDown("LeftButton") then
            local prev = draggingCategory
            draggingCategory = nil
            dragBadge:Hide()
            if headers[prev] then
                headers[prev].bg:SetColorTexture(0.114, 0.157, 0.192, 0.92)
                headers[prev].dragEndedAt = GetTime()
            end
            ns:RefreshToolbar()
            if ns.ConfigFrame and ns.ConfigFrame:IsShown() and ns.ConfigFrame.updateLabels then
                ns.ConfigFrame.updateLabels()
            end
            return
        end
        local cx, cy = GetCursorPosition()
        local uScale = (dragBadge and dragBadge:GetEffectiveScale()) or UIParent:GetEffectiveScale() or 1
        dragBadge:ClearAllPoints()
        dragBadge:SetPoint("LEFT", UIParent, "BOTTOMLEFT", cx / uScale + 14, cy / uScale)
        local curY = cy / frame:GetEffectiveScale()

        local fromIdx
        for i, k in ipairs(ns.order) do
            if k == draggingCategory then fromIdx = i; break end
        end
        if fromIdx then
            for i, otherK in ipairs(ns.order) do
                local otherH = headers[otherK]
                if otherK ~= draggingCategory and otherH and otherH:IsShown() then
                    local _, otherCY = otherH:GetCenter()
                    if otherCY and ((i < fromIdx and curY > otherCY) or (i > fromIdx and curY < otherCY)) then
                        table.remove(ns.order, fromIdx)
                        table.insert(ns.order, i, draggingCategory)
                        db.order = ns.order
                        ns:RefreshToolbar()
                        if ns.ConfigFrame and ns.ConfigFrame:IsShown() and ns.ConfigFrame.updateLabels then
                            ns.ConfigFrame.updateLabels()
                        end
                        break
                    end
                end
            end
        end
    end

    -- 2. Hover Reveal: on after TITLE_HOVER_DELAY on the title, off when the mouse leaves the bar
    if not hoverUI and titleHoverSince then
        local overTitle = titleHover:IsMouseOver()
        if not overTitle then
            titleHoverSince = nil
        elseif ToolbarController.titleHoverDue(titleHoverSince, GetTime(), overTitle) then
            titleHoverSince = nil
            ns:ShowHoverUI(true)
        end
    end
    if hoverUI then
        if draggingTitle or draggingCategory or frame:IsMouseOver() or (resizeHandle.IsMouseOver and resizeHandle:IsMouseOver()) then
            hoverExitElapsed = 0
        else
            hoverExitElapsed = hoverExitElapsed + elapsed
            if hoverExitElapsed >= 0.15 then
                ns:ShowHoverUI(false)
            end
        end
    end

    -- 3. Smooth Opacity & Mouseover Fade
    local targetAlpha = db.opacity or 1
    if db.fade and not (hoverUI or draggingTitle or frame:IsMouseOver() or (ns.ConfigFrame and ns.ConfigFrame:IsShown())) then
        targetAlpha = 0
    end
    local curAlpha = frame:GetAlpha()
    if math.abs(curAlpha - targetAlpha) > 0.005 then
        local step = elapsed * 5
        if curAlpha < targetAlpha then
            curAlpha = math.min(targetAlpha, curAlpha + step)
        else
            curAlpha = math.max(targetAlpha, curAlpha - step)
        end
        frame:SetAlpha(curAlpha)
    end

    -- 4. Periodic Visual Cooldown/Count Poll, and the redraw asked for by events: at most once per
    -- VISUAL_MIN_GAP (2026-11-22: power, usable and cooldown events redrew every icon several times a frame,
    -- 2.3 ms per frame on average in the addon profiler)
    visualTimer = visualTimer + elapsed
    sinceVisual = sinceVisual + elapsed
    if visualTimer >= 0.25 or (ns.visualsDirty and sinceVisual >= VISUAL_MIN_GAP) then
        visualTimer, sinceVisual, ns.visualsDirty = 0, 0, false
        ns:UpdateVisuals()
    end
end)

local refreshQueued = false
function ns:RequestRefresh()
    if refreshQueued then return end
    if C_Timer and type(C_Timer.After) == "function" then
        refreshQueued = true
        C_Timer.After(0.2, function()
            refreshQueued = false
            ns:RefreshToolbar()
        end)
    else
        ns:RefreshToolbar()
    end
end

frame:RegisterEvent("PLAYER_LOGIN")
frame:RegisterEvent("PLAYER_REGEN_ENABLED")
frame:RegisterEvent("BAG_UPDATE_DELAYED")
frame:RegisterEvent("PLAYER_EQUIPMENT_CHANGED")
frame:RegisterEvent("SPELLS_CHANGED")
frame:RegisterEvent("SPELL_UPDATE_COOLDOWN")
frame:RegisterEvent("SPELL_UPDATE_USABLE")
frame:RegisterEvent("ACTIONBAR_UPDATE_COOLDOWN")
-- Only the player's power matters; other units would refresh the bar for nothing.
if not (frame.RegisterUnitEvent and pcall(frame.RegisterUnitEvent, frame, "UNIT_POWER_UPDATE", "player")) then
    frame:RegisterEvent("UNIT_POWER_UPDATE")
end
frame:RegisterEvent("PLAYER_TARGET_CHANGED")
frame:RegisterEvent("UPDATE_SHAPESHIFT_FORM")
frame:RegisterEvent("BAG_UPDATE_COOLDOWN")
frame:RegisterEvent("GET_ITEM_INFO_RECEIVED")
-- (C_Item.RequestLoadItemDataByID answers only with ITEM_DATA_LOAD_RESULT on this client, 2026-11-22)
pcall(frame.RegisterEvent, frame, "ITEM_DATA_LOAD_RESULT")
pcall(frame.RegisterEvent, frame, "CVAR_UPDATE")

frame:SetScript("OnEvent", function(_, event, arg1)
    if Flicker.on then Flicker.NoteEvent(event) end
    if event == "PLAYER_LOGIN" then
        ns:InitDB()
        if ns.db.position then
            frame:ClearAllPoints()
            frame:SetPoint(ns.db.position[1], UIParent, ns.db.position[2], ns.db.position[3], ns.db.position[4])
        end
        if ns.RegisterBlizzardOptions then
            ns:RegisterBlizzardOptions()
        end
        ns:RefreshToolbar()
    elseif event == "PLAYER_REGEN_ENABLED" then
        if ns.pendingKeyDown then
            ToolbarController.ApplyKeyDownSetting()
        end
        if ns.pendingRefresh then
            ns:RefreshToolbar()
        end
    elseif event == "CVAR_UPDATE" then
        if arg1 == "ActionButtonUseKeyDown" or arg1 == "ACTION_BUTTON_USE_KEY_DOWN" then
            ToolbarController.ApplyKeyDownSetting()
        end
    elseif event == "GET_ITEM_INFO_RECEIVED" or event == "ITEM_DATA_LOAD_RESULT" then
        if arg1 and ns.waitingItems[arg1] then
            ns.waitingItems[arg1] = nil
            if ns.db then ns:RequestRefresh() end
        end
    elseif event == "SPELL_UPDATE_COOLDOWN"
        or event == "SPELL_UPDATE_USABLE"
        or event == "ACTIONBAR_UPDATE_COOLDOWN"
        or event == "UNIT_POWER_UPDATE"
        or event == "PLAYER_TARGET_CHANGED"
        or event == "UPDATE_SHAPESHIFT_FORM"
        or event == "BAG_UPDATE_COOLDOWN" then
        -- (the cooldowns drawn from secret values in combat are drawn again only on these)
        if event == "SPELL_UPDATE_COOLDOWN" or event == "ACTIONBAR_UPDATE_COOLDOWN"
            or event == "BAG_UPDATE_COOLDOWN" or event == "UPDATE_SHAPESHIFT_FORM" then
            ns.cooldownChanged = true
        end
        -- drawn on the next frame (OnUpdate above), once for all the events of that moment
        ns.visualsDirty = true
    elseif ns.db then
        ns:RequestRefresh()
    end
end)
