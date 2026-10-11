local addonName, namespace = ...

if type(namespace) ~= "table" then
    return
end

local MinimapButton = {}
namespace.Minimap = MinimapButton

local ICON_PATH = "Interface\\AddOns\\TacoTip_Extras\\icons\\GS-icon"
local BORDER_PATH = "Interface\\Minimap\\MiniMap-TrackingBorder"
local HIGHLIGHT_PATH = "Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight"
local BACKGROUND_PATH = "Interface\\Minimap\\UI-Minimap-Background"
local DEFAULT_ANGLE = 225
local MAX_RADIUS = 80

local settings
local button
local initialized = false
local dragging = false

local function isFinite(value)
    return type(value) == "number"
        and value == value
        and value ~= math.huge
        and value ~= -math.huge
end

local function normalizeAngle(value)
    if not isFinite(value) then
        return DEFAULT_ANGLE
    end
    value = value % 360
    if value < 0 then
        value = value + 360
    end
    return value
end

local function minimapSettings()
    if type(settings) == "table" and type(settings.minimap) == "table" then
        return settings.minimap
    end
    return nil
end

local function minimapRadius()
    local minimap = _G.Minimap
    local width = type(minimap.GetWidth) == "function" and minimap:GetWidth() or 140
    local height = type(minimap.GetHeight) == "function" and minimap:GetHeight() or 140
    if not isFinite(width) or width < 0 then
        width = 140
    end
    if not isFinite(height) or height < 0 then
        height = 140
    end
    return math.max(0, math.min(MAX_RADIUS, math.min(width, height) * 0.5 + 4))
end

local function quadrantAngle(y, x)
    if x > 0 then
        return math.atan(y / x)
    elseif x < 0 and y >= 0 then
        return math.atan(y / x) + math.pi
    elseif x < 0 and y < 0 then
        return math.atan(y / x) - math.pi
    elseif y > 0 then
        return math.pi * 0.5
    elseif y < 0 then
        return -math.pi * 0.5
    end
    return nil
end

local function updateAngleFromCursor()
    local config = minimapSettings()
    local minimap = _G.Minimap
    if not config
        or type(_G.GetCursorPosition) ~= "function"
        or type(minimap) ~= "table"
        or type(minimap.GetEffectiveScale) ~= "function"
        or type(minimap.GetCenter) ~= "function" then
        return false
    end

    local scale = minimap:GetEffectiveScale()
    local centerX, centerY = minimap:GetCenter()
    local cursorX, cursorY = _G.GetCursorPosition()
    if not isFinite(scale) or scale <= 0
        or not isFinite(centerX) or not isFinite(centerY)
        or not isFinite(cursorX) or not isFinite(cursorY) then
        return false
    end

    local x = cursorX / scale - centerX
    local y = cursorY / scale - centerY
    local radians = quadrantAngle(y, x)
    if not radians then
        return false
    end
    config.angle = normalizeAngle(radians * 180 / math.pi)
    MinimapButton.RefreshPosition()
    return true
end

local function onDragUpdate()
    if dragging then
        updateAngleFromCursor()
    end
end

local function onDragStart(self)
    dragging = true
    self:SetScript("OnUpdate", onDragUpdate)
    updateAngleFromCursor()
end

local function onDragStop(self)
    updateAngleFromCursor()
    dragging = false
    self:SetScript("OnUpdate", nil)
end

local function onClick(_, mouseButton)
    if mouseButton ~= nil and mouseButton ~= "LeftButton" then
        return false
    end
    local options = namespace.Options
    if type(options) == "table" and type(options.Toggle) == "function" then
        return options.Toggle()
    end
    return false
end

local function onEnter(self)
    local tooltip = _G.GameTooltip
    if type(tooltip) ~= "table"
        or type(tooltip.SetOwner) ~= "function"
        or type(tooltip.SetText) ~= "function"
        or type(tooltip.AddLine) ~= "function" then
        return
    end
    tooltip:SetOwner(self, "ANCHOR_LEFT")
    tooltip:SetText("TacoTip Extras")
    tooltip:AddLine("Left-click to toggle settings")
    tooltip:AddLine("Drag to move")
    if type(tooltip.Show) == "function" then
        tooltip:Show()
    end
end

local function onLeave()
    local tooltip = _G.GameTooltip
    if type(tooltip) == "table" and type(tooltip.Hide) == "function" then
        tooltip:Hide()
    end
end

local function createButton()
    if button then
        return button
    end

    local minimap = _G.Minimap
    if type(_G.CreateFrame) ~= "function" or type(minimap) ~= "table" then
        return nil
    end

    -- Named, so the button is reachable as a global for users who want to move
    -- or hide it themselves. Phase 1 rebranded the folder, the TOC and the
    -- saved variables, but this name is a bare global rather than a path, so no
    -- automatic rename reached it and it still advertised the old add-on.
    button = CreateFrame(
        "Button",
        addonName .. "MinimapButton",
        minimap
    )
    button:SetSize(32, 32)
    button:SetFrameStrata("MEDIUM")
    if type(button.SetFrameLevel) == "function"
        and type(minimap.GetFrameLevel) == "function" then
        button:SetFrameLevel(minimap:GetFrameLevel() + 5)
    end
    button:RegisterForClicks("LeftButtonUp")
    button:RegisterForDrag("LeftButton")

    local background = button:CreateTexture(nil, "BACKGROUND")
    background:SetTexture(BACKGROUND_PATH)
    background:SetSize(24, 24)
    background:SetPoint("CENTER", button, "CENTER", 0, 0)

    local icon = button:CreateTexture(nil, "ARTWORK")
    icon:SetTexture(ICON_PATH)
    icon:SetSize(20, 20)
    icon:SetPoint("CENTER", button, "CENTER", 0, 0)
    icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

    local border = button:CreateTexture(nil, "OVERLAY")
    border:SetTexture(BORDER_PATH)
    border:SetSize(54, 54)
    border:SetPoint("TOPLEFT", button, "TOPLEFT", 0, 0)

    button:SetHighlightTexture(HIGHLIGHT_PATH, "ADD")
    button:SetScript("OnClick", onClick)
    button:SetScript("OnDragStart", onDragStart)
    button:SetScript("OnDragStop", onDragStop)
    button:SetScript("OnEnter", onEnter)
    button:SetScript("OnLeave", onLeave)
    return button
end

function MinimapButton.Initialize(runtimeSettings)
    if type(runtimeSettings) ~= "table" then
        return false
    end
    settings = runtimeSettings
    if initialized then
        MinimapButton.ApplySettings()
        return true
    end
    if not createButton() then
        return false
    end
    initialized = true
    MinimapButton.ApplySettings()
    return true
end

function MinimapButton.ApplySettings()
    if not initialized or not button then
        return false
    end
    MinimapButton.RefreshPosition()
    local config = minimapSettings()
    local shown = type(settings) == "table"
        and settings.enabled == true
        and config ~= nil
        and config.show == true
    if shown then
        button:Show()
    else
        button:Hide()
    end
    return shown
end

function MinimapButton.RefreshPosition()
    local config = minimapSettings()
    if not button or not config or type(_G.Minimap) ~= "table" then
        return false
    end
    config.angle = normalizeAngle(config.angle)
    local radians = config.angle * math.pi / 180
    local radius = minimapRadius()
    button:ClearAllPoints()
    button:SetPoint(
        "CENTER",
        _G.Minimap,
        "CENTER",
        math.cos(radians) * radius,
        math.sin(radians) * radius
    )
    return true
end
