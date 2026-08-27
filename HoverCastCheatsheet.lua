local ADDON_NAME = ...

local addon = CreateFrame("Frame")
local rows = {}
local activeBindings = {}
local refreshPending = false
local RenderBindings
local UpdateCooldowns
local ApplyVisualSettings
local ToggleSettings
local ApplyLock
local settingsFrame
local ellesmereThemeRegistered = false
local ellesmereButtonsStyled = false

local DEFAULTS = {
    shown = true,
    locked = false,
    point = "CENTER",
    relativePoint = "CENTER",
    x = 320,
    y = 0,
    order = {},
    backgroundAlpha = 0.94,
    panelScale = 1,
    panelWidth = 220,
    iconSize = 26,
    rowHeight = 30,
    borderSize = 1,
    borderBrightness = 0.25,
    showBorder = false,
    showTitle = true,
    showCooldownText = true,
    hideTooltipsInCombat = true,
    keyColorMode = "ellesmere",
    keyColor = { r = 1, g = 0.82, b = 0.2 },
}

local function Print(message)
    DEFAULT_CHAT_FRAME:AddMessage("|cff7dd3fcHoverCast Cheatsheet:|r " .. message)
end

local function CopyDefaults()
    HoverCastCheatsheetDB = type(HoverCastCheatsheetDB) == "table" and HoverCastCheatsheetDB or {}
    for key, value in pairs(DEFAULTS) do
        if HoverCastCheatsheetDB[key] == nil then
            if type(value) == "table" then
                HoverCastCheatsheetDB[key] = {}
                for childKey, childValue in pairs(value) do
                    HoverCastCheatsheetDB[key][childKey] = childValue
                end
            else
                HoverCastCheatsheetDB[key] = value
            end
        end
    end
    if type(HoverCastCheatsheetDB.order) ~= "table" then
        HoverCastCheatsheetDB.order = {}
    end
end

local function TooltipsAllowed()
    return not (HoverCastCheatsheetDB and HoverCastCheatsheetDB.hideTooltipsInCombat
        and InCombatLockdown())
end

local frame = CreateFrame("Frame", "HoverCastCheatsheetFrame", UIParent, "BackdropTemplate")
frame:SetFrameStrata("MEDIUM")
frame:SetClampedToScreen(true)
frame:SetMovable(true)
frame:EnableMouse(true)
frame:RegisterForDrag("LeftButton")
frame:SetBackdrop({
    bgFile = "Interface\\Buttons\\WHITE8X8",
    edgeFile = "Interface\\Buttons\\WHITE8X8",
    edgeSize = 1,
})
frame:SetBackdropColor(0.035, 0.04, 0.055, 0.94)
frame:SetBackdropBorderColor(0.22, 0.25, 0.32, 1)

local title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
title:SetPoint("TOPLEFT", 8, -7)
title:SetText("HOVERCAST")
title:SetTextColor(0.49, 0.83, 0.98)

local lockMark = frame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
lockMark:Hide()

local lockButton = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
lockButton:SetSize(70, 18)
lockButton:SetPoint("TOPRIGHT", -31, -3)
lockButton:SetScript("OnClick", function()
    HoverCastCheatsheetDB.locked = not HoverCastCheatsheetDB.locked
    ApplyLock()
    Print(HoverCastCheatsheetDB.locked and "locked." or "unlocked; drag the panel or rows to move them.")
end)
lockButton:SetScript("OnEnter", function(self)
    if not TooltipsAllowed() then return end
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:SetText(HoverCastCheatsheetDB.locked and "Unlock panel" or "Lock panel")
    GameTooltip:AddLine(HoverCastCheatsheetDB.locked
        and "Allows panel movement and row reordering."
        or "Prevents panel movement and row reordering.", 0.75, 0.78, 0.85)
    GameTooltip:Show()
end)
lockButton:SetScript("OnLeave", GameTooltip_Hide)

local settingsButton = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
settingsButton:SetSize(25, 18)
settingsButton:SetPoint("TOPRIGHT", -4, -3)
settingsButton:SetText("...")
settingsButton:SetScript("OnClick", function() ToggleSettings() end)
settingsButton:SetScript("OnEnter", function(self)
    if not TooltipsAllowed() then return end
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:SetText("Visual settings")
    GameTooltip:Show()
end)
settingsButton:SetScript("OnLeave", GameTooltip_Hide)

local empty = frame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
empty:SetPoint("TOPLEFT", 8, -29)
empty:SetPoint("RIGHT", -8, 0)
empty:SetJustifyH("LEFT")
empty:SetText("No active HoverCast bindings found.\n/hccs refresh")

frame:SetScript("OnDragStart", function(self)
    if not HoverCastCheatsheetDB.locked then
        self:StartMoving()
    end
end)

frame:SetScript("OnDragStop", function(self)
    self:StopMovingOrSizing()
    local point, _, relativePoint, x, y = self:GetPoint(1)
    HoverCastCheatsheetDB.point = point
    HoverCastCheatsheetDB.relativePoint = relativePoint
    HoverCastCheatsheetDB.x = x
    HoverCastCheatsheetDB.y = y
end)

local function SafeSpellInfo(spell)
    if C_Spell and C_Spell.GetSpellInfo then
        local ok, info = pcall(C_Spell.GetSpellInfo, spell)
        if ok and info then
            return info.name, info.iconID, info.spellID or (type(spell) == "number" and spell or nil)
        end
    end
    if GetSpellInfo then
        local ok, name, _, icon, _, _, spellID = pcall(GetSpellInfo, spell)
        if ok and name then
            return name, icon, spellID or (type(spell) == "number" and spell or nil)
        end
    end
end

local function BindingToken(binding)
    return tostring(binding.spellID or binding.name) .. "\031" .. binding.key
end

local KEY_NAMES = {
    BUTTON1 = "M1", BUTTON2 = "M2", BUTTON3 = "M3",
    BUTTON4 = "M4", BUTTON5 = "M5",
    MOUSEWHEELUP = "Wheel Up", MOUSEWHEELDOWN = "Wheel Down",
}

local function FormatHoverCastKey(key)
    if type(key) ~= "string" then return "?" end
    local parts, base = {}, key:upper()
    while true do
        local prefix, label
        if base:sub(1, 4) == "ALT-" then prefix, label = "ALT-", "Alt"
        elseif base:sub(1, 5) == "CTRL-" then prefix, label = "CTRL-", "Ctrl"
        elseif base:sub(1, 6) == "SHIFT-" then prefix, label = "SHIFT-", "Shift"
        elseif base:sub(1, 5) == "META-" then prefix, label = "META-", "Meta"
        end
        if not prefix then break end
        parts[#parts + 1] = label
        base = base:sub(#prefix + 1)
    end
    -- Some legacy HoverCast saves contain an extra fragment before a mouse
    -- token. The final BUTTON/WHEEL token is the actual input.
    local mouseToken = base:match("(BUTTON%d+)$")
        or base:match("(MOUSEWHEELUP)$") or base:match("(MOUSEWHEELDOWN)$")
    if mouseToken then
        base = mouseToken
    end
    parts[#parts + 1] = KEY_NAMES[base] or base
    return table.concat(parts, "+")
end

local function CurrentGroupContext()
    local _, instanceType = IsInInstance()
    if instanceType == "pvp" or instanceType == "arena" then return "pvp" end
    if IsInRaid() then return "raid" end
    if IsInGroup() then return "party" end
    return "solo"
end

local function FindHoverCastNamespace()
    local eui = _G.EllesmereUI
    local moduleNS = type(eui) == "table" and eui._ModuleNS
    local ns = type(moduleNS) == "table" and (moduleNS.EllesmereUIRaidFrames
        or moduleNS["EllesmereUI Raid Frames"])
    ns = ns or _G.EllesmereUIRaidFrames
    return type(ns) == "table" and ns or nil
end

local function FindHoverCastDB(ns)
    ns = ns or FindHoverCastNamespace()
    if type(ns) == "table" and type(ns.CC_GetClickCastDB) == "function" then
        local ok, cc = pcall(ns.CC_GetClickCastDB)
        if ok and type(cc) == "table" then return cc end
    end
    local db = type(ns) == "table" and ns.db
    local saved = type(db) == "table" and (db.sv or db.profile or db)
    return type(saved) == "table" and saved.clickCast or nil
end

local function BindingIsActive(binding, context)
    if type(binding) ~= "table" or binding.enabled == false or not binding.key then return false end
    if binding.groupCtx and binding.groupCtx ~= "all" and binding.groupCtx ~= context then return false end
    return true
end

local function RelationshipLabel(binding)
    local friendly = binding.hoverFriendly ~= false
    local enemy = binding.hoverEnemy == true
    if friendly and enemy then return "Friendly + enemy" end
    if enemy then return "Enemy" end
    if friendly then return "Friendly" end
    return nil
end

local ACTION_NAMES = {
    target = "Target Unit", menu = "Open Unit Menu", macro = "Macro",
    item = "Item", dispel = "Class Dispel", dynamicrez = "Dynamic Resurrection",
    external = "External Defensive", trinket1 = "Upper Trinket", trinket2 = "Lower Trinket",
}

local ACTION_ICONS = {
    target = 132212, menu = 5341597, macro = 134400, item = 134400,
    dispel = 135894, dynamicrez = 136080, external = 135966,
}

local function AddHoverCastSpell(output, seen, binding, spell, relationship, scope)
    if spell == nil then return end
    if type(spell) == "string" then spell = tonumber(spell) or spell end
    local name, icon, spellID = SafeSpellInfo(spell)
    if not name then return end
    local key = FormatHoverCastKey(binding.key)
    local token = tostring(spellID or name) .. "\031" .. key
    if seen[token] then return end
    seen[token] = true
    output[#output + 1] = {
        name = name, icon = icon, spellID = spellID, key = key,
        relationship = relationship,
        castMode = binding.hovercast and "Actual units" or "Unit frames",
        scope = scope,
    }
end

local function AddHoverCastAction(output, seen, ns, binding, scope)
    if binding.type == "spell" or binding.spell or binding.spellID then
        AddHoverCastSpell(output, seen, binding, binding.spellID or binding.spell,
            RelationshipLabel(binding), scope)
        return
    end

    local kind = binding.type or "action"
    local name
    if type(ns) == "table" and type(ns.CC_GetBindingName) == "function" then
        local ok, value = pcall(ns.CC_GetBindingName, binding)
        if ok then name = value end
    end
    name = name or binding.macroName or binding.itemName or ACTION_NAMES[kind] or kind

    local icon = binding.icon
    if type(ns) == "table" and type(ns.CC_GetBindingIcon) == "function" then
        local ok, value = pcall(ns.CC_GetBindingIcon, binding)
        if ok and value then icon = value end
    end
    if kind == "trinket1" then
        icon = GetInventoryItemTexture("player", 13) or icon
    elseif kind == "trinket2" then
        icon = GetInventoryItemTexture("player", 14) or icon
    end
    icon = icon or ACTION_ICONS[kind] or 134400

    local key = FormatHoverCastKey(binding.key)
    local token = tostring(kind) .. "\031" .. tostring(name) .. "\031" .. key
    if seen[token] then return end
    seen[token] = true
    output[#output + 1] = {
        name = name, icon = icon, key = key,
        relationship = RelationshipLabel(binding),
        castMode = binding.hovercast and "Actual units" or "Unit frames",
        scope = scope,
    }
end

local function CollectHoverCastBindings(output, seen)
    local ns = FindHoverCastNamespace()
    local cc = FindHoverCastDB(ns)
    if type(cc) ~= "table" or cc.enabled == false then return end

    local context = CurrentGroupContext()
    if type(ns) == "table" and type(ns.CC_GetActiveBindings) == "function" then
        local ok, bindings = pcall(ns.CC_GetActiveBindings)
        if ok and type(bindings) == "table" then
            local globalSet = {}
            if type(ns.CC_GetGlobalBindings) == "function" then
                local globalsOK, globals = pcall(ns.CC_GetGlobalBindings)
                if globalsOK and type(globals) == "table" then
                    for _, binding in ipairs(globals) do globalSet[binding] = true end
                end
            end
            for _, binding in ipairs(bindings) do
                if BindingIsActive(binding, context) then
                    AddHoverCastAction(output, seen, ns, binding,
                        globalSet[binding] and "Global" or "Specialization")
                end
            end
            return
        end
    end

    local specIndex = GetSpecialization and GetSpecialization()
    local specID = specIndex and select(1, GetSpecializationInfo(specIndex))
    local claimedKeys = {}

    local function collectList(list, isSpec)
        if type(list) ~= "table" then return end
        for _, binding in pairs(list) do
            if BindingIsActive(binding, context) and (isSpec or not claimedKeys[binding.key]) then
                if isSpec then claimedKeys[binding.key] = true end
                if binding.type == "spell" or binding.spell or binding.spellID then
                    AddHoverCastSpell(output, seen, binding, binding.spellID or binding.spell,
                        RelationshipLabel(binding), isSpec and "Specialization" or "Global")
                    AddHoverCastSpell(output, seen, binding,
                        binding.harmfulSpellID or binding.harmfulSpell, "Enemy",
                        isSpec and "Specialization" or "Global")
                else
                    AddHoverCastAction(output, seen, ns, binding,
                        isSpec and "Specialization" or "Global")
                end
            end
        end
    end

    collectList(type(cc.specs) == "table" and cc.specs[specID], true)
    collectList(cc.globals, false)
end

local dragInsertIndex
local insertionLine = frame:CreateTexture(nil, "OVERLAY", nil, 7)
insertionLine:SetHeight(2)
insertionLine:SetColorTexture(0.22, 0.82, 0.84, 1)
insertionLine:Hide()

local function UpdateInsertionLine()
    local count = #activeBindings
    if count == 0 then insertionLine:Hide(); return end
    local scale = UIParent:GetEffectiveScale()
    local _, cursorY = GetCursorPosition()
    cursorY = cursorY / scale

    local slot = count + 1
    for candidateIndex = 1, count do
        local candidate = rows[candidateIndex]
        local _, centerY = candidate and candidate:GetCenter()
        if centerY and cursorY > centerY then
            slot = candidateIndex
            break
        end
    end
    dragInsertIndex = slot
    insertionLine:ClearAllPoints()
    if slot <= count then
        insertionLine:SetPoint("LEFT", rows[slot], "TOPLEFT", 7, 0)
        insertionLine:SetPoint("RIGHT", rows[slot], "TOPRIGHT", -7, 0)
    else
        insertionLine:SetPoint("LEFT", rows[count], "BOTTOMLEFT", 7, 0)
        insertionLine:SetPoint("RIGHT", rows[count], "BOTTOMRIGHT", -7, 0)
    end
    insertionLine:Show()
end

local function CreateRow(index)
    local row = CreateFrame("Frame", nil, frame)
    row:SetHeight(HoverCastCheatsheetDB.rowHeight)
    row:EnableMouse(true)
    row:RegisterForDrag("LeftButton")

    row.icon = row:CreateTexture(nil, "ARTWORK")
    row.icon:SetSize(HoverCastCheatsheetDB.iconSize, HoverCastCheatsheetDB.iconSize)
    row.icon:SetPoint("LEFT", 7, 0)
    row.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

    row.cooldown = CreateFrame("Cooldown", nil, row, "CooldownFrameTemplate")
    row.cooldown:SetAllPoints(row.icon)
    row.cooldown:SetDrawEdge(false)
    row.cooldown:SetHideCountdownNumbers(not HoverCastCheatsheetDB.showCooldownText)

    row.key = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    row.key:SetPoint("LEFT", row.icon, "RIGHT", 7, 0)
    row.key:SetWidth(64)
    row.key:SetJustifyH("LEFT")
    row.key:SetTextColor(1, 0.82, 0.2)

    row.name = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.name:SetPoint("LEFT", row.key, "RIGHT", 1, 0)
    row.name:SetPoint("RIGHT", -7, 0)
    row.name:SetJustifyH("LEFT")
    row.name:SetWordWrap(false)

    row:SetScript("OnEnter", function(self)
        if not self.binding or not TooltipsAllowed() then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        if self.binding.spellID then
            GameTooltip:SetSpellByID(self.binding.spellID)
        else
            GameTooltip:SetText(self.binding.name)
        end
        GameTooltip:AddLine("HoverCast: " .. self.binding.key, 1, 0.82, 0.2)
        if self.binding.relationship then
            GameTooltip:AddLine(self.binding.relationship .. " target", 0.65, 0.82, 0.9)
        end
        if self.binding.castMode then
            GameTooltip:AddLine(self.binding.castMode, 0.55, 0.6, 0.68)
        end
        if self.binding.scope then
            GameTooltip:AddLine(self.binding.scope .. " binding", 0.55, 0.6, 0.68)
        end
        if not HoverCastCheatsheetDB.locked then
            GameTooltip:AddLine("Drag to reorder", 0.65, 0.7, 0.8)
        end
        GameTooltip:Show()
    end)
    row:SetScript("OnLeave", GameTooltip_Hide)
    row:SetScript("OnDragStart", function(self)
        if HoverCastCheatsheetDB.locked then return end
        self.dragging = true
        self:SetAlpha(0.45)
        GameTooltip:Hide()
        dragInsertIndex = index
        UpdateInsertionLine()
    end)
    row:SetScript("OnUpdate", function(self)
        if self.dragging then UpdateInsertionLine() end
    end)
    row:SetScript("OnDragStop", function(self)
        if not self.dragging then return end
        self.dragging = nil
        self:SetAlpha(1)
        insertionLine:Hide()

        local targetIndex = dragInsertIndex or index
        local moved = table.remove(activeBindings, index)
        if targetIndex > index then targetIndex = targetIndex - 1 end
        targetIndex = math.max(1, math.min(targetIndex, #activeBindings + 1))
        table.insert(activeBindings, targetIndex, moved)
        dragInsertIndex = nil
        wipe(HoverCastCheatsheetDB.order)
        for orderIndex, binding in ipairs(activeBindings) do
            HoverCastCheatsheetDB.order[orderIndex] = BindingToken(binding)
        end
        RenderBindings()
    end)
    rows[index] = row
    return row
end

RenderBindings = function()
    local rowHeight = math.max(HoverCastCheatsheetDB.rowHeight, HoverCastCheatsheetDB.iconSize + 4)
    local keyWidth = 64
    for index, binding in ipairs(activeBindings) do
        local row = rows[index] or CreateRow(index)
        row.binding = binding
        row.icon:SetTexture(binding.icon or 134400)
        row.key:SetText(binding.key)
        local measuredWidth
        if row.key.GetUnboundedStringWidth then
            local ok, width = pcall(row.key.GetUnboundedStringWidth, row.key)
            if ok then measuredWidth = width end
        end
        measuredWidth = measuredWidth or (#binding.key * 8)
        keyWidth = math.max(keyWidth, math.ceil(measuredWidth) + 8)
        row.name:SetText(binding.name)
        row:ClearAllPoints()
        row:SetHeight(rowHeight)
        row:SetPoint("TOPLEFT", 0, -25 - ((index - 1) * rowHeight))
        row:SetPoint("RIGHT", 0, 0)
        row:Show()
    end
    for index = #activeBindings + 1, #rows do rows[index]:Hide() end

    -- Keybinds are the primary information: give every row a column wide enough
    -- for the longest one, and sacrifice spell-name space before clipping a key.
    for index = 1, #activeBindings do
        rows[index].key:SetWidth(keyWidth)
    end

    empty:SetShown(#activeBindings == 0)
    local minimumWidth = 7 + HoverCastCheatsheetDB.iconSize + 7 + keyWidth + 1 + 55 + 7
    frame:SetSize(math.max(HoverCastCheatsheetDB.panelWidth, minimumWidth),
        34 + math.max(1, #activeBindings) * rowHeight)
    UpdateCooldowns()
end

local function CooldownValues(spellID)
    if not spellID or not C_Spell then return end
    if C_Spell.GetSpellCharges then
        local ok, charges = pcall(C_Spell.GetSpellCharges, spellID)
        if ok and charges and charges.currentCharges and charges.maxCharges
            and charges.currentCharges < charges.maxCharges and charges.cooldownStartTime then
            return charges.cooldownStartTime, charges.cooldownDuration, charges.chargeModRate or 1
        end
    end
    if C_Spell.GetSpellCooldown then
        local ok, info = pcall(C_Spell.GetSpellCooldown, spellID)
        if ok and info and info.isEnabled ~= false then
            return info.startTime, info.duration, info.modRate or 1
        end
    end
end

UpdateCooldowns = function()
    for index, binding in ipairs(activeBindings) do
        local row = rows[index]
        if row and binding.spellID then
            -- Midnight may mark cooldown values as secret in some combat contexts.
            -- Keep the cheatsheet alive if inspecting or applying one is restricted.
            local ok, start, duration, modRate = pcall(CooldownValues, binding.spellID)
            if ok and start and duration then
                pcall(row.cooldown.SetCooldown, row.cooldown, start, duration, modRate)
            else
                row.cooldown:Clear()
            end
        elseif row then
            row.cooldown:Clear()
        end
    end
end

ApplyVisualSettings = function()
    local eui = _G.EllesmereUI
    local accent = type(eui) == "table" and eui.ELLESMERE_GREEN
    local dark = type(eui) == "table" and eui.DARK_BG
    local borderColor = type(eui) == "table" and eui.BORDER_COLOR
    local accentR = type(accent) == "table" and (accent.r or accent[1]) or 0.22
    local accentG = type(accent) == "table" and (accent.g or accent[2]) or 0.82
    local accentB = type(accent) == "table" and (accent.b or accent[3]) or 0.84
    local bgR = type(dark) == "table" and (dark.r or dark[1]) or 0.035
    local bgG = type(dark) == "table" and (dark.g or dark[2]) or 0.04
    local bgB = type(dark) == "table" and (dark.b or dark[3]) or 0.055
    local border = HoverCastCheatsheetDB.borderBrightness
    local borderR = type(borderColor) == "table" and (borderColor.r or borderColor[1])
        or (type(eui) == "table" and eui.BORDER_R) or border
    local borderG = type(borderColor) == "table" and (borderColor.g or borderColor[2])
        or (type(eui) == "table" and eui.BORDER_G) or border
    local borderB = type(borderColor) == "table" and (borderColor.b or borderColor[3])
        or (type(eui) == "table" and eui.BORDER_B) or math.min(1, border + 0.07)
    local keyR, keyG, keyB = accentR, accentG, accentB
    if HoverCastCheatsheetDB.keyColorMode == "class" then
        local _, class = UnitClass("player")
        local color = class and RAID_CLASS_COLORS and RAID_CLASS_COLORS[class]
        if color then keyR, keyG, keyB = color.r, color.g, color.b end
    elseif HoverCastCheatsheetDB.keyColorMode == "custom" then
        local color = HoverCastCheatsheetDB.keyColor or DEFAULTS.keyColor
        keyR, keyG, keyB = color.r or 1, color.g or 0.82, color.b or 0.2
    end
    frame:SetScale(HoverCastCheatsheetDB.panelScale)
    frame:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        edgeSize = 1,
    })
    frame:SetBackdropColor(bgR, bgG, bgB, HoverCastCheatsheetDB.backgroundAlpha)
    frame:SetBackdropBorderColor(borderR, borderG, borderB,
        HoverCastCheatsheetDB.showBorder and 1 or 0)
    title:SetTextColor(accentR, accentG, accentB)
    insertionLine:SetColorTexture(accentR, accentG, accentB, 1)
    title:SetShown(HoverCastCheatsheetDB.showTitle)

    local fontPath
    if type(eui) == "table" and type(eui.GetFontPath) == "function" then
        local ok, value = pcall(eui.GetFontPath, "raidFrames")
        if ok then fontPath = value end
    end
    fontPath = fontPath or (type(eui) == "table" and eui.EXPRESSWAY)
    local outline
    if type(eui) == "table" and type(eui.GetFontOutlineFlag) == "function" then
        local ok, value = pcall(eui.GetFontOutlineFlag, "raidFrames")
        if ok then outline = value end
    end
    local function ApplyFontString(fontString)
        if not fontPath or not fontString or not fontString.GetFont then return end
        local _, size, flags = fontString:GetFont()
        if size then pcall(fontString.SetFont, fontString, fontPath, size, outline or flags or "") end
    end
    ApplyFontString(title)
    ApplyFontString(empty)
    ApplyFontString(lockButton:GetFontString())
    ApplyFontString(settingsButton:GetFontString())
    ApplyFontString(lockButton._hccsLabel)
    ApplyFontString(settingsButton._hccsLabel)

    for _, row in ipairs(rows) do
        row.icon:SetSize(HoverCastCheatsheetDB.iconSize, HoverCastCheatsheetDB.iconSize)
        row.cooldown:SetHideCountdownNumbers(not HoverCastCheatsheetDB.showCooldownText)
        row.key:SetTextColor(keyR, keyG, keyB)
        ApplyFontString(row.key)
        ApplyFontString(row.name)
    end
    if settingsFrame then
        settingsFrame:SetBackdropColor(bgR, bgG, bgB, 0.98)
        settingsFrame:SetBackdropBorderColor(borderR, borderG, borderB, 1)
        for _, region in ipairs({ settingsFrame:GetRegions() }) do
            if region and region.GetObjectType and region:GetObjectType() == "FontString" then
                ApplyFontString(region)
            end
        end
    end
    if RenderBindings and HoverCastCheatsheetDB then RenderBindings() end
end

local function StylePanelButtonsWithEllesmereUI()
    if ellesmereButtonsStyled then return end
    local eui = _G.EllesmereUI
    if type(eui) ~= "table" or type(eui.MakeStyledButton) ~= "function"
        or type(eui.WB_COLOURS) ~= "table" then return end

    local function ClearBlizzardTextures(button)
        for _, region in ipairs({ button.Left, button.Middle, button.Right,
            button:GetNormalTexture(), button:GetPushedTexture(),
            button:GetHighlightTexture(), button:GetDisabledTexture() }) do
            if region then region:SetAlpha(0) end
        end
        local fontString = button:GetFontString()
        if fontString then fontString:SetText("") end
    end
    ClearBlizzardTextures(lockButton)
    ClearBlizzardTextures(settingsButton)

    local okLock, _, _, lockLabel = pcall(eui.MakeStyledButton, lockButton,
        HoverCastCheatsheetDB.locked and "UNLOCK" or "LOCK", 10, eui.WB_COLOURS, function()
            HoverCastCheatsheetDB.locked = not HoverCastCheatsheetDB.locked
            ApplyLock()
            Print(HoverCastCheatsheetDB.locked and "locked."
                or "unlocked; drag the panel or rows to move them.")
        end)
    if not okLock then return end
    lockButton._hccsLabel = lockLabel
    lockButton:HookScript("OnEnter", function(self)
        if not TooltipsAllowed() then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(HoverCastCheatsheetDB.locked and "Unlock panel" or "Lock panel")
        GameTooltip:AddLine(HoverCastCheatsheetDB.locked
            and "Allows panel movement and row reordering."
            or "Prevents panel movement and row reordering.", 0.75, 0.78, 0.85)
        GameTooltip:Show()
    end)
    lockButton:HookScript("OnLeave", GameTooltip_Hide)

    local okSettings, _, _, settingsLabel = pcall(eui.MakeStyledButton, settingsButton,
        "...", 10, eui.WB_COLOURS, ToggleSettings)
    if okSettings then
        settingsButton._hccsLabel = settingsLabel
        settingsButton:HookScript("OnEnter", function(self)
            if not TooltipsAllowed() then return end
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetText("Visual settings")
            GameTooltip:Show()
        end)
        settingsButton:HookScript("OnLeave", GameTooltip_Hide)
    end
    ellesmereButtonsStyled = okLock and okSettings
    ApplyLock()
end

local function RegisterEllesmereTheme()
    if ellesmereThemeRegistered then return end
    local eui = _G.EllesmereUI
    if type(eui) ~= "table" then return end
    local registered = false
    if type(eui.RegAccent) == "function" then
        registered = pcall(eui.RegAccent, { type = "callback", fn = ApplyVisualSettings }) or registered
    end
    if type(eui.RegisterWidgetRefresh) == "function" then
        registered = pcall(eui.RegisterWidgetRefresh, ApplyVisualSettings) or registered
    end
    ellesmereThemeRegistered = registered
    StylePanelButtonsWithEllesmereUI()
    ApplyVisualSettings()
end

local function BuildSettingsFrame()
    if settingsFrame then return end

    local euiAccent = _G.EllesmereUI and _G.EllesmereUI.ELLESMERE_GREEN
    local accentR = type(euiAccent) == "table" and (euiAccent.r or euiAccent[1]) or 0.22
    local accentG = type(euiAccent) == "table" and (euiAccent.g or euiAccent[2]) or 0.82
    local accentB = type(euiAccent) == "table" and (euiAccent.b or euiAccent[3]) or 0.84
    settingsFrame = CreateFrame("Frame", "HoverCastCheatsheetSettings", UIParent, "BackdropTemplate")
    settingsFrame:SetSize(390, 500)
    settingsFrame:SetPoint("CENTER")
    settingsFrame:SetFrameStrata("DIALOG")
    settingsFrame:SetClampedToScreen(true)
    settingsFrame:SetMovable(true)
    settingsFrame:EnableMouse(true)
    settingsFrame:RegisterForDrag("LeftButton")
    settingsFrame:SetScript("OnDragStart", settingsFrame.StartMoving)
    settingsFrame:SetScript("OnDragStop", settingsFrame.StopMovingOrSizing)
    settingsFrame:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        edgeSize = 1,
    })
    settingsFrame:SetBackdropColor(0.018, 0.025, 0.032, 0.98)
    settingsFrame:SetBackdropBorderColor(0.13, 0.32, 0.34, 1)
    settingsFrame.controls = {}

    local titleBar = settingsFrame:CreateTexture(nil, "BACKGROUND")
    titleBar:SetPoint("TOPLEFT", 1, -1)
    titleBar:SetPoint("TOPRIGHT", -1, -1)
    titleBar:SetHeight(29)
    titleBar:SetColorTexture(0.03, 0.08, 0.09, 1)

    local windowTitle = settingsFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    windowTitle:SetPoint("LEFT", titleBar, "LEFT", 12, 0)
    windowTitle:SetText("HOVERCAST CHEATSHEET  /  VISUALS")
    windowTitle:SetTextColor(accentR, accentG, accentB)

    local close = CreateFrame("Button", nil, settingsFrame, "BackdropTemplate")
    close:SetSize(25, 21)
    close:SetPoint("TOPRIGHT", -5, -4)
    close:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8" })
    close:SetBackdropColor(0.07, 0.11, 0.12, 1)
    close.label = close:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    close.label:SetPoint("CENTER", 0, 0)
    close.label:SetText("X")
    close.label:SetTextColor(0.72, 0.77, 0.78)
    close:SetScript("OnClick", function() settingsFrame:Hide() end)
    close:SetScript("OnEnter", function(self)
        self:SetBackdropColor(0.45, 0.12, 0.12, 1)
        self.label:SetTextColor(1, 1, 1)
    end)
    close:SetScript("OnLeave", function(self)
        self:SetBackdropColor(0.07, 0.11, 0.12, 1)
        self.label:SetTextColor(0.72, 0.77, 0.78)
    end)

    local intro = settingsFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    intro:SetPoint("TOPLEFT", 22, -42)
    intro:SetPoint("RIGHT", -22, 0)
    intro:SetJustifyH("LEFT")
    intro:SetText("LIVE PREVIEW  -  SETTINGS SAVE AUTOMATICALLY")
    intro:SetTextColor(0.48, 0.55, 0.57)

    local nextY = -78
    local function AddSlider(label, key, minimum, maximum, step, format, displayMultiplier)
        local slider = CreateFrame("Slider", nil, settingsFrame)
        slider:SetPoint("TOPLEFT", 25, nextY)
        slider:SetSize(335, 17)
        slider:SetOrientation("HORIZONTAL")
        slider:SetMinMaxValues(minimum, maximum)
        slider:SetValueStep(step)
        slider:SetObeyStepOnDrag(true)

        local track = slider:CreateTexture(nil, "BACKGROUND")
        track:SetPoint("LEFT", 0, 0)
        track:SetPoint("RIGHT", 0, 0)
        track:SetHeight(4)
        track:SetColorTexture(0.075, 0.105, 0.115, 1)
        slider:SetThumbTexture("Interface\\Buttons\\WHITE8X8")
        local thumb = slider:GetThumbTexture()
        thumb:SetSize(10, 17)
        thumb:SetVertexColor(accentR, accentG, accentB, 1)

        local caption = settingsFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        caption:SetPoint("BOTTOMLEFT", slider, "TOPLEFT", 0, 6)
        caption:SetText(label:upper())
        caption:SetTextColor(0.67, 0.72, 0.73)
        local valueText = settingsFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        valueText:SetPoint("BOTTOMRIGHT", slider, "TOPRIGHT", 0, 6)
        valueText:SetTextColor(accentR, accentG, accentB)

        slider:SetScript("OnEnter", function() thumb:SetVertexColor(0.42, 0.96, 0.98, 1) end)
        slider:SetScript("OnLeave", function() thumb:SetVertexColor(accentR, accentG, accentB, 1) end)

        slider:SetScript("OnValueChanged", function(_, value)
            value = math.floor((value / step) + 0.5) * step
            HoverCastCheatsheetDB[key] = value
            valueText:SetFormattedText(format, value * (displayMultiplier or 1))
            ApplyVisualSettings()
        end)
        settingsFrame.controls[key] = slider
        slider:SetValue(HoverCastCheatsheetDB[key])
        nextY = nextY - 55
    end

    AddSlider("Background opacity", "backgroundAlpha", 0.05, 1, 0.05, "%d%%", 100)
    AddSlider("Panel scale", "panelScale", 0.6, 1.5, 0.05, "%.2fx")
    AddSlider("Panel width", "panelWidth", 170, 420, 10, "%d px")
    AddSlider("Icon size", "iconSize", 16, 48, 1, "%d px")
    AddSlider("Row height", "rowHeight", 20, 56, 1, "%d px")

    local colorTitle = settingsFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    colorTitle:SetPoint("BOTTOMLEFT", 20, 158)
    colorTitle:SetText("KEYBIND COLOR")
    colorTitle:SetTextColor(0.67, 0.72, 0.73)

    settingsFrame.colorModeButtons = {}
    local function RefreshColorModeButtons()
        for mode, button in pairs(settingsFrame.colorModeButtons) do
            local selected = HoverCastCheatsheetDB.keyColorMode == mode
            button:SetBackdropColor(selected and accentR or 0.035,
                selected and accentG or 0.06, selected and accentB or 0.065, selected and 0.22 or 1)
            button:SetBackdropBorderColor(selected and accentR or 0.16,
                selected and accentG or 0.3, selected and accentB or 0.32, selected and 1 or 0.7)
            button.label:SetTextColor(selected and 1 or 0.68, selected and 1 or 0.72,
                selected and 1 or 0.73)
        end
    end

    local function OpenCustomColorPicker()
        local previousMode = HoverCastCheatsheetDB.keyColorMode
        local previous = HoverCastCheatsheetDB.keyColor or DEFAULTS.keyColor
        previous = { r = previous.r, g = previous.g, b = previous.b }
        HoverCastCheatsheetDB.keyColorMode = "custom"
        RefreshColorModeButtons()

        local function ApplyPickerColor()
            local r, g, b = ColorPickerFrame:GetColorRGB()
            HoverCastCheatsheetDB.keyColor = { r = r, g = g, b = b }
            ApplyVisualSettings()
        end
        local function CancelPickerColor()
            HoverCastCheatsheetDB.keyColorMode = previousMode
            HoverCastCheatsheetDB.keyColor = previous
            RefreshColorModeButtons()
            ApplyVisualSettings()
        end
        if ColorPickerFrame.SetupColorPickerAndShow then
            ColorPickerFrame:SetupColorPickerAndShow({
                r = previous.r, g = previous.g, b = previous.b,
                hasOpacity = false,
                swatchFunc = ApplyPickerColor,
                cancelFunc = CancelPickerColor,
            })
        else
            ColorPickerFrame.hasOpacity = false
            ColorPickerFrame.func = ApplyPickerColor
            ColorPickerFrame.cancelFunc = CancelPickerColor
            ColorPickerFrame:SetColorRGB(previous.r, previous.g, previous.b)
            ColorPickerFrame:Show()
        end
    end

    local function AddColorModeButton(mode, text, x)
        local button = CreateFrame("Button", nil, settingsFrame, "BackdropTemplate")
        button:SetSize(106, 24)
        button:SetPoint("BOTTOMLEFT", x, 125)
        button:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8",
            edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1 })
        button.label = button:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        button.label:SetPoint("CENTER")
        button.label:SetText(text)
        button:SetScript("OnClick", function()
            if mode == "custom" then
                OpenCustomColorPicker()
            else
                HoverCastCheatsheetDB.keyColorMode = mode
                RefreshColorModeButtons()
                ApplyVisualSettings()
            end
        end)
        button:SetScript("OnEnter", function(self) self.label:SetTextColor(1, 1, 1) end)
        button:SetScript("OnLeave", function() RefreshColorModeButtons() end)
        settingsFrame.colorModeButtons[mode] = button
    end
    AddColorModeButton("ellesmere", "ELLESMEREUI", 20)
    AddColorModeButton("class", "CLASS", 142)
    AddColorModeButton("custom", "CUSTOM...", 264)
    RefreshColorModeButtons()

    local function AddCheckbox(label, key, x, bottomY)
        local check = CreateFrame("CheckButton", nil, settingsFrame, "BackdropTemplate")
        check:SetSize(17, 17)
        check:SetPoint("BOTTOMLEFT", x, bottomY or 47)
        check:SetBackdrop({
            bgFile = "Interface\\Buttons\\WHITE8X8",
            edgeFile = "Interface\\Buttons\\WHITE8X8",
            edgeSize = 1,
        })
        check:SetBackdropColor(0.035, 0.05, 0.06, 1)
        check:SetBackdropBorderColor(0.15, 0.27, 0.28, 1)
        check.mark = check:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        check.mark:SetPoint("CENTER", 0, 0)
        check.mark:SetText("X")
        check.mark:SetTextColor(accentR, accentG, accentB)
        check:SetChecked(HoverCastCheatsheetDB[key])
        check.Refresh = function(self)
            self.mark:SetShown(self:GetChecked())
            if self:GetChecked() then
                self:SetBackdropBorderColor(accentR, accentG, accentB, 1)
            else
                self:SetBackdropBorderColor(0.15, 0.27, 0.28, 1)
            end
        end
        check:Refresh()
        local checkLabel = settingsFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        checkLabel:SetPoint("LEFT", check, "RIGHT", 7, 0)
        checkLabel:SetText(label:upper())
        checkLabel:SetTextColor(0.67, 0.72, 0.73)
        check:SetScript("OnClick", function(self)
            HoverCastCheatsheetDB[key] = self:GetChecked() and true or false
            self:Refresh()
            ApplyVisualSettings()
        end)
        settingsFrame.controls[key] = check
    end
    AddCheckbox("Show title", "showTitle", 20, 82)
    AddCheckbox("Cooldown numbers", "showCooldownText", 200, 82)
    AddCheckbox("Hide tooltips in combat", "hideTooltipsInCombat", 20, 53)
    AddCheckbox("Show border", "showBorder", 20, 24)

    local reset = CreateFrame("Button", nil, settingsFrame, "BackdropTemplate")
    reset:SetSize(112, 23)
    reset:SetPoint("BOTTOMRIGHT", -18, 14)
    reset:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        edgeSize = 1,
    })
    reset:SetBackdropColor(0.035, 0.06, 0.065, 1)
    reset:SetBackdropBorderColor(0.16, 0.48, 0.5, 1)
    reset.label = reset:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    reset.label:SetPoint("CENTER", 0, 0)
    reset.label:SetText("RESET VISUALS")
    reset.label:SetTextColor(0.68, 0.82, 0.83)
    reset:SetScript("OnEnter", function(self)
        self:SetBackdropColor(0.06, 0.16, 0.17, 1)
        self:SetBackdropBorderColor(accentR, accentG, accentB, 1)
    end)
    reset:SetScript("OnLeave", function(self)
        self:SetBackdropColor(0.035, 0.06, 0.065, 1)
        self:SetBackdropBorderColor(0.16, 0.48, 0.5, 1)
    end)
    reset:SetScript("OnClick", function()
        for _, key in ipairs({ "backgroundAlpha", "panelScale", "panelWidth", "iconSize", "rowHeight",
            "showTitle", "showCooldownText", "hideTooltipsInCombat",
            "showBorder" }) do
            HoverCastCheatsheetDB[key] = DEFAULTS[key]
            local control = settingsFrame.controls[key]
            if control then
                if type(DEFAULTS[key]) == "boolean" then
                    control:SetChecked(DEFAULTS[key])
                    control:Refresh()
                else
                    control:SetValue(DEFAULTS[key])
                end
            end
        end
        HoverCastCheatsheetDB.keyColorMode = DEFAULTS.keyColorMode
        HoverCastCheatsheetDB.keyColor = {
            r = DEFAULTS.keyColor.r, g = DEFAULTS.keyColor.g, b = DEFAULTS.keyColor.b,
        }
        RefreshColorModeButtons()
        ApplyVisualSettings()
    end)
    settingsFrame:Hide()
    ApplyVisualSettings()
end

ToggleSettings = function()
    BuildSettingsFrame()
    settingsFrame:SetShown(not settingsFrame:IsShown())
end

local function Refresh()
    refreshPending = false
    local found, seenRecords = {}, {}
    CollectHoverCastBindings(found, seenRecords)
    local orderRank = {}
    for rank, token in ipairs(HoverCastCheatsheetDB.order) do
        orderRank[token] = rank
    end
    table.sort(found, function(a, b)
        local aRank, bRank = orderRank[BindingToken(a)], orderRank[BindingToken(b)]
        if aRank or bRank then
            if aRank and bRank then return aRank < bRank end
            return aRank ~= nil
        end
        if a.key == b.key then return a.name < b.name end
        return a.key < b.key
    end)
    activeBindings = found
    RenderBindings()
end

local function QueueRefresh(delay)
    if refreshPending then return end
    refreshPending = true
    C_Timer.After(delay or 0.2, Refresh)
end

ApplyLock = function()
    local label = HoverCastCheatsheetDB.locked and "UNLOCK" or "LOCK"
    if lockButton._hccsLabel then
        lockButton._hccsLabel:SetText(label)
    else
        lockButton:SetText(label)
    end
    frame:EnableMouse(true)
end

local function SetShown(shown)
    HoverCastCheatsheetDB.shown = shown
    frame:SetShown(shown)
end

addon:SetScript("OnEvent", function(_, event, arg1)
    if event == "ADDON_LOADED" and arg1 == ADDON_NAME then
        CopyDefaults()
        frame:ClearAllPoints()
        frame:SetPoint(HoverCastCheatsheetDB.point, UIParent, HoverCastCheatsheetDB.relativePoint,
            HoverCastCheatsheetDB.x, HoverCastCheatsheetDB.y)
        ApplyVisualSettings()
        RegisterEllesmereTheme()
        ApplyLock()
        SetShown(HoverCastCheatsheetDB.shown)
    elseif event == "PLAYER_LOGIN" then
        RegisterEllesmereTheme()
        C_Timer.After(1.5, function()
            RegisterEllesmereTheme()
            ApplyVisualSettings()
        end)
        QueueRefresh(1)
    elseif event == "SPELL_UPDATE_COOLDOWN" or event == "SPELL_UPDATE_CHARGES" then
        UpdateCooldowns()
    elseif event == "PLAYER_REGEN_DISABLED" then
        if HoverCastCheatsheetDB.hideTooltipsInCombat then GameTooltip:Hide() end
    else
        QueueRefresh(0.35)
    end
end)

addon:RegisterEvent("ADDON_LOADED")
addon:RegisterEvent("PLAYER_LOGIN")
addon:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED")
addon:RegisterEvent("TRAIT_CONFIG_UPDATED")
addon:RegisterEvent("SPELLS_CHANGED")
addon:RegisterEvent("SPELL_UPDATE_COOLDOWN")
addon:RegisterEvent("SPELL_UPDATE_CHARGES")
addon:RegisterEvent("GROUP_ROSTER_UPDATE")
addon:RegisterEvent("PLAYER_ENTERING_WORLD")
addon:RegisterEvent("ZONE_CHANGED_NEW_AREA")
addon:RegisterEvent("PLAYER_REGEN_DISABLED")

SLASH_HOVERCASTCHEATSHEET1 = "/hovercastcs"
SLASH_HOVERCASTCHEATSHEET2 = "/hccs"
SlashCmdList.HOVERCASTCHEATSHEET = function(message)
    local command = (message or ""):match("^%s*(%S*)"):lower()
    if command == "show" then
        SetShown(true)
    elseif command == "hide" then
        SetShown(false)
    elseif command == "refresh" then
        Refresh()
        Print("refreshed (" .. #activeBindings .. " bindings).")
    elseif command == "lock" then
        HoverCastCheatsheetDB.locked = not HoverCastCheatsheetDB.locked
        ApplyLock()
        Print(HoverCastCheatsheetDB.locked and "locked." or "unlocked; drag the panel to move it.")
    elseif command == "resetorder" then
        wipe(HoverCastCheatsheetDB.order)
        Refresh()
        Print("binding order reset.")
    elseif command == "config" or command == "settings" or command == "options" then
        ToggleSettings()
    elseif command == "debug" then
        local ns = FindHoverCastNamespace()
        local cc = FindHoverCastDB(ns)
        local apiCount = "n/a"
        if ns and type(ns.CC_GetActiveBindings) == "function" then
            local ok, bindings = pcall(ns.CC_GetActiveBindings)
            apiCount = ok and type(bindings) == "table" and tostring(#bindings) or "error"
        end
        Print("module=" .. (ns and "found" or "missing")
            .. ", database=" .. (cc and "found" or "missing")
            .. ", enabled=" .. tostring(cc and cc.enabled)
            .. ", active bindings=" .. apiCount
            .. ", displayed spells=" .. #activeBindings .. ".")
    else
        Print("/hccs show | hide | refresh | lock | resetorder | config | debug")
    end
end
