--   U[[
 rban Ghost v1 - Roblox Luau mod menu (target game: Urban Reload)
    Layout: left sidebar tabs (AIM / VISUALS / SETTINGS), switches, sliders, red + black theme.
    Features: Aimbot, Aimlock, Chams, English / French.
    Menu: floating red "UG" button (tap) or RightShift on PC. Language: EN/FR button in the header.

    STATUS: written without running it. Not tested in Roblox, Delta or any PC executor.

    UNKNOWN GAME DATA (not verified for Urban Reload) lives in GameConfig below.
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local LocalPlayer = Players.LocalPlayer

------------------------------------------------------------------------
-- Game-specific values. nil = UNKNOWN (not taken from any dump).
------------------------------------------------------------------------
local GameConfig = {
    -- Run  print(game.GameId, game.PlaceId)  inside Urban Reload, then put the GameId here.
    -- While nil the script loads in any game.
    gameId = nil,
    -- Name of a Player attribute that holds the team/crew, if the game uses one instead of Player.Team.
    -- nil = only Roblox's Player.Team is used.
    teamAttribute = nil,
}

if GameConfig.gameId ~= nil and game.GameId ~= GameConfig.gameId then
    warn("[UrbanGhost] Wrong game (GameId " .. tostring(game.GameId) .. "). Not loading.")
    return
end

------------------------------------------------------------------------
-- Single instance
------------------------------------------------------------------------
local env = (type(getgenv) == "function" and getgenv()) or _G
if env.UrbanGhost and type(env.UrbanGhost.Unload) == "function" then
    pcall(env.UrbanGhost.Unload)
end

------------------------------------------------------------------------
-- State and text
------------------------------------------------------------------------
local S = {
    lang = "EN",
    aimbot = false,
    aimlock = false,
    trigger = "Hold", -- "Hold" (AIM button / right mouse) or "Always"
    part = 1,         -- index into PART_NAMES
    fov = 150,        -- pixel radius around screen center (uncalibrated default)
    speed = 14,       -- smoothing speed for Aimbot (uncalibrated default)
    maxDist = 500,    -- studs
    teamCheck = true,
    wallCheck = true,
    showFov = true,
    chams = false,
    chamsTeamCheck = true,
}

local PART_NAMES = { { "Head" }, { "UpperTorso", "Torso" }, { "HumanoidRootPart" } }
local PART_KEYS = { "head", "torso", "body" }

local STRINGS = {
    EN = {
        tab_aim = "AIM", tab_visuals = "VISUALS", tab_settings = "SETTINGS",
        sec_main = "AIM ASSIST", sec_filters = "FILTERS", sec_esp = "CHAMS", sec_overlay = "OVERLAY",
        sec_interface = "INTERFACE",
        aimbot = "Aimbot", aimlock = "Aimlock (sticky)", aimkey = "Activation",
        hold = "Hold", always = "Always",
        target = "Target", head = "Head", torso = "Torso", body = "Body",
        fov = "FOV radius", speed = "Aim speed", dist = "Max distance",
        teamcheck = "Team check", wallcheck = "Wall check", showfov = "Show FOV circle",
        chams = "Chams", chamsteam = "Chams team check",
        language = "Language", moveaim = "Move AIM button", unload = "Unload script",
    },
    FR = {
        tab_aim = "VISÉE", tab_visuals = "VISUELS", tab_settings = "RÉGLAGES",
        sec_main = "AIDE À LA VISÉE", sec_filters = "FILTRES", sec_esp = "CHAMS", sec_overlay = "AFFICHAGE",
        sec_interface = "INTERFACE",
        aimbot = "Aimbot", aimlock = "Aimlock (verrou)", aimkey = "Activation",
        hold = "Maintenir", always = "Toujours",
        target = "Cible", head = "Tête", torso = "Torse", body = "Corps",
        fov = "Rayon FOV", speed = "Vitesse visée", dist = "Distance max",
        teamcheck = "Vérif. équipe", wallcheck = "Vérif. mur", showfov = "Cercle FOV",
        chams = "Chams", chamsteam = "Chams vérif. équipe",
        language = "Langue", moveaim = "Déplacer bouton AIM", unload = "Décharger le script",
    },
}

local function T(key)
    local t = STRINGS[S.lang] or STRINGS.EN
    return t[key] or STRINGS.EN[key] or key
end

------------------------------------------------------------------------
-- Cleanup bookkeeping
------------------------------------------------------------------------
local alive = true
local conns = {}
local function track(conn)
    table.insert(conns, conn)
    return conn
end

local aimHeld, rmbHeld, aimUnlocked = false, false, false

------------------------------------------------------------------------
-- Targeting (pure game-side logic, no UI)
------------------------------------------------------------------------
local function isEnemy(plr)
    if GameConfig.teamAttribute ~= nil then
        local a = plr:GetAttribute(GameConfig.teamAttribute)
        local b = LocalPlayer:GetAttribute(GameConfig.teamAttribute)
        if a ~= nil and b ~= nil then
            return a ~= b
        end
    end
    local t1, t2 = plr.Team, LocalPlayer.Team
    if t1 == nil or t2 == nil then
        return true
    end
    return t1 ~= t2
end

local function getAimPart(char)
    for _, name in ipairs(PART_NAMES[S.part]) do
        local p = char:FindFirstChild(name)
        if p and p:IsA("BasePart") then
            return p
        end
    end
    local root = char:FindFirstChild("HumanoidRootPart")
    if root and root:IsA("BasePart") then
        return root
    end
    return nil
end

-- Returns character, aim part if the player is a valid target right now.
local function getTargetParts(plr)
    if plr == LocalPlayer then
        return nil
    end
    local char = plr.Character
    if not char or not char.Parent then
        return nil
    end
    local hum = char:FindFirstChildOfClass("Humanoid")
    if not hum or hum.Health <= 0 then
        return nil
    end
    if char:FindFirstChildOfClass("ForceField") then
        return nil
    end
    if S.teamCheck and not isEnemy(plr) then
        return nil
    end
    local part = getAimPart(char)
    if not part then
        return nil
    end
    return char, part
end

local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Exclude
rayParams.RespectCanCollide = true

local function isVisible(origin, part, targetChar)
    local ignore = {}
    if LocalPlayer.Character then
        table.insert(ignore, LocalPlayer.Character)
    end
    table.insert(ignore, targetChar)
    rayParams.FilterDescendantsInstances = ignore
    return Workspace:Raycast(origin, part.Position - origin, rayParams) == nil
end

-- Closest valid target to the screen center, inside the FOV circle.
local function findTarget(cam)
    local vp = cam.ViewportSize
    local center = Vector2.new(vp.X / 2, vp.Y / 2)
    local camPos = cam.CFrame.Position
    local best, bestDist = nil, S.fov
    for _, plr in ipairs(Players:GetPlayers()) do
        local char, part = getTargetParts(plr)
        if char then
            if (part.Position - camPos).Magnitude <= S.maxDist then
                local sp, onScreen = cam:WorldToViewportPoint(part.Position)
                if onScreen and sp.Z > 0 then
                    local d = (Vector2.new(sp.X, sp.Y) - center).Magnitude
                    if d < bestDist and (not S.wallCheck or isVisible(camPos, part, char)) then
                        best, bestDist = plr, d
                    end
                end
            end
        end
    end
    return best
end

local lockedPlayer = nil

local function aimStepInner(dt)
    local cam = Workspace.CurrentCamera
    if not cam then
        return
    end
    local active = S.trigger == "Always" or aimHeld or rmbHeld
    if not (S.aimbot or S.aimlock) or not active then
        lockedPlayer = nil
        return
    end

    local camPos = cam.CFrame.Position
    local part = nil

    if S.aimlock then
        if lockedPlayer then
            local c, p = getTargetParts(lockedPlayer)
            if c and (p.Position - camPos).Magnitude <= S.maxDist then
                part = p
            else
                lockedPlayer = nil
            end
        end
        if not part then
            lockedPlayer = findTarget(cam)
            if lockedPlayer then
                local _, p = getTargetParts(lockedPlayer)
                part = p
            end
        end
    else
        lockedPlayer = nil
        local plr = findTarget(cam)
        if plr then
            local _, p = getTargetParts(plr)
            part = p
        end
    end

    if not part then
        return
    end

    local goal = CFrame.lookAt(camPos, part.Position)
    local alpha = S.aimlock and 1 or (1 - math.exp(-S.speed * dt))
    cam.CFrame = cam.CFrame:Lerp(goal, alpha)
end

local aimErrorShown = false
local function aimStep(dt)
    local ok, err = pcall(aimStepInner, dt)
    if not ok and not aimErrorShown then
        aimErrorShown = true
        warn("[UrbanGhost] aim error: " .. tostring(err))
    end
end

------------------------------------------------------------------------
-- UI helpers
------------------------------------------------------------------------
local COLORS = {
    bg = Color3.fromRGB(14, 14, 16),
    panel = Color3.fromRGB(20, 20, 24),
    row = Color3.fromRGB(30, 30, 35),
    red = Color3.fromRGB(210, 32, 44),
    off = Color3.fromRGB(62, 62, 70),
    text = Color3.fromRGB(235, 235, 238),
    amber = Color3.fromRGB(230, 170, 30),
}

local function mk(class, props, parent)
    local inst = Instance.new(class)
    for k, v in pairs(props) do
        inst[k] = v
    end
    inst.Parent = parent
    return inst
end

local function corner(inst, radius)
    return mk("UICorner", { CornerRadius = UDim.new(0, radius) }, inst)
end

local function circle(inst)
    return mk("UICorner", { CornerRadius = UDim.new(1, 0) }, inst)
end

local function stroke(inst, color, thickness)
    return mk("UIStroke", { Color = color, Thickness = thickness, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, inst)
end

local function isPointerBegin(input)
    return input.UserInputType == Enum.UserInputType.MouseButton1
        or input.UserInputType == Enum.UserInputType.Touch
end

local function getGuiParent()
    if type(gethui) == "function" then
        local ok, ui = pcall(gethui)
        if ok and typeof(ui) == "Instance" then
            return ui
        end
    end
    local probe = Instance.new("Folder")
    local ok = pcall(function()
        probe.Parent = game:GetService("CoreGui")
    end)
    local parented = ok and probe.Parent ~= nil
    probe:Destroy()
    if parented then
        return game:GetService("CoreGui")
    end
    return LocalPlayer:WaitForChild("PlayerGui")
end

local guiParent = getGuiParent()

local gui = mk("ScreenGui", {
    Name = "UrbanGhost",
    ResetOnSpawn = false,
    IgnoreGuiInset = true,
    ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
    DisplayOrder = 100,
}, guiParent)

local chamsFolder = mk("Folder", { Name = "UrbanGhostChams" }, guiParent)

local function makeDraggable(handle, target, onTap, canDrag)
    local dragging, dragInput, dragStart, startPos, moved = false, nil, nil, nil, false
    handle.InputBegan:Connect(function(input)
        if not isPointerBegin(input) then
            return
        end
        if canDrag and not canDrag() then
            return
        end
        dragging, dragInput, moved = true, input, false
        dragStart, startPos = input.Position, target.Position
        local c
        c = input.Changed:Connect(function()
            if input.UserInputState == Enum.UserInputState.End then
                dragging = false
                c:Disconnect()
                if onTap and not moved then
                    onTap()
                end
            end
        end)
    end)
    track(UserInputService.InputChanged:Connect(function(input)
        if not dragging then
            return
        end
        if input.UserInputType == Enum.UserInputType.MouseMovement or input == dragInput then
            local delta = input.Position - dragStart
            if delta.Magnitude > 6 then
                moved = true
            end
            if moved then
                target.Position = UDim2.new(
                    startPos.X.Scale, startPos.X.Offset + delta.X,
                    startPos.Y.Scale, startPos.Y.Offset + delta.Y
                )
            end
        end
    end))
end

------------------------------------------------------------------------
-- FOV circle and AIM button
------------------------------------------------------------------------
local fovCircle = mk("Frame", {
    Name = "FovCircle",
    AnchorPoint = Vector2.new(0.5, 0.5),
    Position = UDim2.new(0.5, 0, 0.5, 0),
    Size = UDim2.fromOffset(S.fov * 2, S.fov * 2),
    BackgroundTransparency = 1,
    Active = false,
    Visible = false,
}, gui)
circle(fovCircle)
stroke(fovCircle, COLORS.red, 1.5)

local aimBtn = mk("TextButton", {
    Name = "AimButton",
    Size = UDim2.fromOffset(72, 72),
    Position = UDim2.new(1, -110, 1, -190),
    BackgroundColor3 = COLORS.red,
    BackgroundTransparency = 0.15,
    Text = "AIM",
    Font = Enum.Font.GothamBold,
    TextSize = 18,
    TextColor3 = COLORS.text,
    AutoButtonColor = false,
    Visible = false,
}, gui)
circle(aimBtn)
stroke(aimBtn, COLORS.text, 1.5)

aimBtn.InputBegan:Connect(function(input)
    if isPointerBegin(input) and not aimUnlocked then
        aimHeld = true
        local c
        c = input.Changed:Connect(function()
            if input.UserInputState == Enum.UserInputState.End then
                aimHeld = false
                c:Disconnect()
            end
        end)
    end
end)
makeDraggable(aimBtn, aimBtn, nil, function()
    return aimUnlocked
end)

------------------------------------------------------------------------
-- Localisation refresh registry
------------------------------------------------------------------------
local refreshers = {}
local function register(fn)
    table.insert(refreshers, fn)
    fn()
end
local function refreshAll()
    for _, fn in ipairs(refreshers) do
        fn()
    end
end

------------------------------------------------------------------------
-- Main window: header, sidebar, pages
------------------------------------------------------------------------
local main = mk("Frame", {
    Name = "Main",
    Size = UDim2.fromOffset(460, 290),
    Position = UDim2.new(0.5, -230, 0.5, -145),
    BackgroundColor3 = COLORS.bg,
    BorderSizePixel = 0,
    Active = true,
}, gui)
corner(main, 8)
stroke(main, COLORS.red, 1.5)

local header = mk("Frame", {
    Size = UDim2.new(1, 0, 0, 38),
    BackgroundColor3 = COLORS.panel,
    BorderSizePixel = 0,
}, main)
corner(header, 8)
mk("Frame", {
    Size = UDim2.new(1, 0, 0, 2),
    Position = UDim2.new(0, 0, 0, 38),
    BackgroundColor3 = COLORS.red,
    BorderSizePixel = 0,
}, main)

mk("TextLabel", {
    BackgroundTransparency = 1,
    Position = UDim2.new(0, 14, 0, 0),
    Size = UDim2.new(1, -120, 1, 0),
    Font = Enum.Font.GothamBold,
    TextSize = 16,
    TextColor3 = COLORS.text,
    TextXAlignment = Enum.TextXAlignment.Left,
    RichText = true,
    Text = 'URBAN GHOST <font color="#D2202C">v1</font>',
}, header)

local langBtn = mk("TextButton", {
    Size = UDim2.fromOffset(40, 24),
    Position = UDim2.new(1, -92, 0.5, -12),
    BackgroundColor3 = COLORS.row,
    AutoButtonColor = false,
    Font = Enum.Font.GothamBold,
    TextSize = 12,
    TextColor3 = COLORS.text,
}, header)
corner(langBtn, 6)
stroke(langBtn, COLORS.red, 1)
langBtn.Activated:Connect(function()
    S.lang = (S.lang == "EN") and "FR" or "EN"
    refreshAll()
end)
register(function()
    langBtn.Text = S.lang
end)

local hideBtn = mk("TextButton", {
    Size = UDim2.fromOffset(34, 24),
    Position = UDim2.new(1, -46, 0.5, -12),
    BackgroundColor3 = COLORS.red,
    AutoButtonColor = false,
    Font = Enum.Font.GothamBold,
    TextSize = 14,
    TextColor3 = COLORS.text,
    Text = "–",
}, header)
corner(hideBtn, 6)

makeDraggable(header, main)

local layoutCounter = 0
local function nextOrder()
    layoutCounter += 1
    return layoutCounter
end

local sidebar = mk("Frame", {
    Position = UDim2.new(0, 8, 0, 48),
    Size = UDim2.new(0, 104, 1, -56),
    BackgroundTransparency = 1,
}, main)
mk("UIListLayout", { Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder }, sidebar)

local pageHolder = mk("Frame", {
    Position = UDim2.new(0, 120, 0, 48),
    Size = UDim2.new(1, -128, 1, -56),
    BackgroundColor3 = COLORS.panel,
    BorderSizePixel = 0,
}, main)
corner(pageHolder, 8)

local pages, tabButtons = {}, {}
local buildPage = nil
local applyState -- assigned below, after all UI exists

local function selectTab(name)
    for n, page in pairs(pages) do
        page.Visible = (n == name)
    end
    for n, btn in pairs(tabButtons) do
        btn.BackgroundColor3 = (n == name) and COLORS.red or COLORS.row
    end
end

local function addTab(name, labelKey)
    local page = mk("ScrollingFrame", {
        Position = UDim2.new(0, 4, 0, 4),
        Size = UDim2.new(1, -8, 1, -8),
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        ScrollBarThickness = 3,
        ScrollBarImageColor3 = COLORS.red,
        CanvasSize = UDim2.new(0, 0, 0, 0),
        AutomaticCanvasSize = Enum.AutomaticSize.Y,
        Visible = false,
    }, pageHolder)
    mk("UIListLayout", { Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder }, page)
    mk("UIPadding", { PaddingRight = UDim.new(0, 6) }, page)
    pages[name] = page

    local btn = mk("TextButton", {
        Size = UDim2.new(1, 0, 0, 36),
        BackgroundColor3 = COLORS.row,
        AutoButtonColor = false,
        Font = Enum.Font.GothamBold,
        TextSize = 12,
        TextColor3 = COLORS.text,
        LayoutOrder = nextOrder(),
    }, sidebar)
    corner(btn, 6)
    btn.Activated:Connect(function()
        selectTab(name)
    end)
    tabButtons[name] = btn
    register(function()
        btn.Text = T(labelKey)
    end)

    buildPage = page
end

local function newRow(height)
    local row = mk("Frame", {
        Size = UDim2.new(1, 0, 0, height),
        BackgroundColor3 = COLORS.row,
        BorderSizePixel = 0,
        LayoutOrder = nextOrder(),
    }, buildPage)
    corner(row, 6)
    return row
end

local function rowLabel(row, size)
    return mk("TextLabel", {
        BackgroundTransparency = 1,
        Position = UDim2.new(0, 10, 0, 0),
        Size = size,
        Font = Enum.Font.GothamMedium,
        TextSize = 13,
        TextColor3 = COLORS.text,
        TextXAlignment = Enum.TextXAlignment.Left,
        TextTruncate = Enum.TextTruncate.AtEnd,
    }, row)
end

local function addSection(key)
    local lbl = mk("TextLabel", {
        Size = UDim2.new(1, 0, 0, 18),
        BackgroundTransparency = 1,
        Font = Enum.Font.GothamBold,
        TextSize = 11,
        TextColor3 = COLORS.red,
        TextXAlignment = Enum.TextXAlignment.Left,
        LayoutOrder = nextOrder(),
    }, buildPage)
    register(function()
        lbl.Text = T(key)
    end)
end

-- Switch with a sliding knob
local function addToggle(key, get, set)
    local row = newRow(36)
    local lbl = rowLabel(row, UDim2.new(1, -70, 1, 0))
    local pill = mk("TextButton", {
        Size = UDim2.fromOffset(44, 22),
        Position = UDim2.new(1, -54, 0.5, -11),
        BackgroundColor3 = COLORS.off,
        AutoButtonColor = false,
        Text = "",
    }, row)
    circle(pill)
    local knob = mk("Frame", {
        Size = UDim2.fromOffset(16, 16),
        Position = UDim2.new(0, 3, 0.5, -8),
        BackgroundColor3 = COLORS.text,
        BorderSizePixel = 0,
    }, pill)
    circle(knob)
    local function refresh(animate)
        lbl.Text = T(key)
        local on = get()
        local pos = on and UDim2.new(0, 25, 0.5, -8) or UDim2.new(0, 3, 0.5, -8)
        local col = on and COLORS.red or COLORS.off
        if animate == true then
            TweenService:Create(knob, TweenInfo.new(0.12), { Position = pos }):Play()
            TweenService:Create(pill, TweenInfo.new(0.12), { BackgroundColor3 = col }):Play()
        else
            knob.Position = pos
            pill.BackgroundColor3 = col
        end
    end
    pill.Activated:Connect(function()
        set(not get())
        applyState()
        refresh(true)
    end)
    register(refresh)
end

-- Draggable slider with value on the right
local function addSlider(key, min, max, step, get, set)
    local pg = buildPage
    local row = newRow(54)
    local lbl = rowLabel(row, UDim2.new(1, -84, 0, 26))
    lbl.Position = UDim2.new(0, 10, 0, 2)
    local valLbl = mk("TextLabel", {
        BackgroundTransparency = 1,
        Position = UDim2.new(1, -74, 0, 2),
        Size = UDim2.fromOffset(64, 26),
        Font = Enum.Font.GothamBold,
        TextSize = 13,
        TextColor3 = COLORS.red,
        TextXAlignment = Enum.TextXAlignment.Right,
    }, row)
    local hit = mk("TextButton", {
        Position = UDim2.new(0, 10, 0, 28),
        Size = UDim2.new(1, -20, 0, 22),
        BackgroundTransparency = 1,
        AutoButtonColor = false,
        Text = "",
    }, row)
    local rail = mk("Frame", {
        Position = UDim2.new(0, 0, 0.5, -3),
        Size = UDim2.new(1, 0, 0, 6),
        BackgroundColor3 = COLORS.off,
        BorderSizePixel = 0,
    }, hit)
    circle(rail)
    local fill = mk("Frame", {
        Size = UDim2.new(0, 0, 1, 0),
        BackgroundColor3 = COLORS.red,
        BorderSizePixel = 0,
    }, rail)
    circle(fill)
    local knob = mk("Frame", {
        Size = UDim2.fromOffset(14, 14),
        Position = UDim2.new(0, -7, 0.5, -7),
        BackgroundColor3 = COLORS.text,
        BorderSizePixel = 0,
        ZIndex = 2,
    }, rail)
    circle(knob)

    local function refresh()
        lbl.Text = T(key)
        local v = get()
        valLbl.Text = tostring(v)
        local r = math.clamp((v - min) / (max - min), 0, 1)
        fill.Size = UDim2.new(r, 0, 1, 0)
        knob.Position = UDim2.new(r, -7, 0.5, -7)
    end

    local function setFromX(x)
        local width = hit.AbsoluteSize.X
        if width <= 0 then
            return
        end
        local r = math.clamp((x - hit.AbsolutePosition.X) / width, 0, 1)
        local v = min + math.floor(((max - min) * r) / step + 0.5) * step
        set(math.clamp(v, min, max))
        applyState()
        refresh()
    end

    local dragging, dragInput = false, nil
    hit.InputBegan:Connect(function(input)
        if not isPointerBegin(input) then
            return
        end
        dragging, dragInput = true, input
        pg.ScrollingEnabled = false
        setFromX(input.Position.X)
        local c
        c = input.Changed:Connect(function()
            if input.UserInputState == Enum.UserInputState.End then
                dragging = false
                pg.ScrollingEnabled = true
                c:Disconnect()
            end
        end)
    end)
    track(UserInputService.InputChanged:Connect(function(input)
        if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement or input == dragInput) then
            setFromX(input.Position.X)
        end
    end))

    register(refresh)
end

-- Dropdown-style selector: tap to go to the next value
local function addCycle(key, valueText, onClick)
    local row = newRow(36)
    local lbl = rowLabel(row, UDim2.new(1, -128, 1, 0))
    local btn = mk("TextButton", {
        Size = UDim2.fromOffset(112, 24),
        Position = UDim2.new(1, -120, 0.5, -12),
        BackgroundColor3 = COLORS.bg,
        AutoButtonColor = false,
        Font = Enum.Font.GothamBold,
        TextSize = 12,
        TextColor3 = COLORS.text,
    }, row)
    corner(btn, 6)
    stroke(btn, COLORS.red, 1)
    local function refresh()
        lbl.Text = T(key)
        btn.Text = valueText() .. "  ▾"
    end
    btn.Activated:Connect(function()
        onClick()
        applyState()
        refreshAll()
    end)
    register(refresh)
end

local function addButton(key, fn)
    local row = newRow(36)
    local btn = mk("TextButton", {
        Size = UDim2.new(1, -16, 0, 26),
        Position = UDim2.new(0, 8, 0.5, -13),
        BackgroundColor3 = COLORS.red,
        AutoButtonColor = false,
        Font = Enum.Font.GothamBold,
        TextSize = 13,
        TextColor3 = COLORS.text,
    }, row)
    corner(btn, 6)
    btn.Activated:Connect(fn)
    register(function()
        btn.Text = T(key)
    end)
end

------------------------------------------------------------------------
-- Tabs and rows
------------------------------------------------------------------------
addTab("aim", "tab_aim")
addSection("sec_main")
addToggle("aimbot", function() return S.aimbot end, function(v) S.aimbot = v end)
addToggle("aimlock", function() return S.aimlock end, function(v) S.aimlock = v end)
addCycle("aimkey",
    function() return S.trigger == "Hold" and T("hold") or T("always") end,
    function() S.trigger = (S.trigger == "Hold") and "Always" or "Hold" end)
addCycle("target",
    function() return T(PART_KEYS[S.part]) end,
    function() S.part = (S.part % #PART_NAMES) + 1 end)
addSlider("fov", 30, 600, 10, function() return S.fov end, function(v) S.fov = v end)
addSlider("speed", 2, 40, 2, function() return S.speed end, function(v) S.speed = v end)
addSlider("dist", 50, 2000, 50, function() return S.maxDist end, function(v) S.maxDist = v end)
addSection("sec_filters")
addToggle("teamcheck", function() return S.teamCheck end, function(v) S.teamCheck = v end)
addToggle("wallcheck", function() return S.wallCheck end, function(v) S.wallCheck = v end)

addTab("visuals", "tab_visuals")
addSection("sec_esp")
addToggle("chams", function() return S.chams end, function(v) S.chams = v end)
addToggle("chamsteam", function() return S.chamsTeamCheck end, function(v) S.chamsTeamCheck = v end)
addSection("sec_overlay")
addToggle("showfov", function() return S.showFov end, function(v) S.showFov = v end)

addTab("settings", "tab_settings")
addSection("sec_interface")
addCycle("language",
    function() return S.lang == "EN" and "English" or "Français" end,
    function() S.lang = (S.lang == "EN") and "FR" or "EN" end)
addToggle("moveaim", function() return aimUnlocked end, function(v) aimUnlocked = v end)

local unload -- assigned below
addButton("unload", function()
    unload()
end)

selectTab("aim")

applyState = function()
    fovCircle.Size = UDim2.fromOffset(S.fov * 2, S.fov * 2)
    local aimOn = S.aimbot or S.aimlock
    fovCircle.Visible = S.showFov and aimOn
    aimBtn.Visible = aimUnlocked or (aimOn and S.trigger == "Hold")
    aimBtn.BackgroundColor3 = aimUnlocked and COLORS.amber or COLORS.red
    if not aimOn or not S.aimlock then
        lockedPlayer = nil
    end
end
applyState()

------------------------------------------------------------------------
-- Open / close: floating button, RightShift, header hide button
------------------------------------------------------------------------
local function setMenuVisible(v)
    main.Visible = v
end

hideBtn.Activated:Connect(function()
    setMenuVisible(false)
end)

local toggleBtn = mk("TextButton", {
    Name = "ToggleButton",
    Size = UDim2.fromOffset(44, 44),
    Position = UDim2.new(0, 70, 0.5, -22),
    BackgroundColor3 = COLORS.red,
    Text = "UG",
    Font = Enum.Font.GothamBold,
    TextSize = 15,
    TextColor3 = COLORS.text,
    AutoButtonColor = false,
}, gui)
circle(toggleBtn)
stroke(toggleBtn, COLORS.text, 1.5)
makeDraggable(toggleBtn, toggleBtn, function()
    setMenuVisible(not main.Visible)
end)

track(UserInputService.InputBegan:Connect(function(input)
    if UserInputService:GetFocusedTextBox() then
        return
    end
    if input.KeyCode == Enum.KeyCode.RightShift then
        setMenuVisible(not main.Visible)
    elseif input.UserInputType == Enum.UserInputType.MouseButton2 then
        rmbHeld = true
    end
end))
track(UserInputService.InputEnded:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton2 then
        rmbHeld = false
    end
end))

------------------------------------------------------------------------
-- Chams (Highlight objects, red fill, visible through walls)
------------------------------------------------------------------------
local MAX_HIGHLIGHTS = 31 -- Roblox limits simultaneously active Highlights
local highlights = {}

local function clearChams()
    for plr, h in pairs(highlights) do
        h:Destroy()
        highlights[plr] = nil
    end
end

local function updateChams()
    if not S.chams then
        clearChams()
        return
    end
    local used = 0
    local present = {}
    for _, plr in ipairs(Players:GetPlayers()) do
        present[plr] = true
        local char = nil
        if plr ~= LocalPlayer then
            char = plr.Character
        end
        local want = false
        if char and char.Parent then
            local hum = char:FindFirstChildOfClass("Humanoid")
            want = hum ~= nil and hum.Health > 0 and (not S.chamsTeamCheck or isEnemy(plr))
        end
        if want and used < MAX_HIGHLIGHTS then
            used += 1
            local h = highlights[plr]
            if not h or not h.Parent then
                h = mk("Highlight", {
                    FillColor = COLORS.red,
                    OutlineColor = Color3.fromRGB(255, 255, 255),
                    FillTransparency = 0.45,
                    OutlineTransparency = 0,
                    DepthMode = Enum.HighlightDepthMode.AlwaysOnTop,
                }, chamsFolder)
                highlights[plr] = h
            end
            if h.Adornee ~= char then
                h.Adornee = char
            end
        else
            local h = highlights[plr]
            if h then
                h:Destroy()
                highlights[plr] = nil
            end
        end
    end
    for plr, h in pairs(highlights) do
        if not present[plr] then
            h:Destroy()
            highlights[plr] = nil
        end
    end
end

local chamsAcc = 0
local chamsErrorShown = false
track(RunService.Heartbeat:Connect(function(dt)
    chamsAcc += dt
    if chamsAcc < 0.25 then
        return
    end
    chamsAcc = 0
    local ok, err = pcall(updateChams)
    if not ok and not chamsErrorShown then
        chamsErrorShown = true
        warn("[UrbanGhost] chams error: " .. tostring(err))
    end
end))

------------------------------------------------------------------------
-- Aim loop and shutdown
------------------------------------------------------------------------
RunService:BindToRenderStep("UrbanGhostAim", Enum.RenderPriority.Camera.Value + 1, aimStep)

unload = function()
    if not alive then
        return
    end
    alive = false
    aimHeld, rmbHeld, lockedPlayer = false, false, nil
    pcall(function()
        RunService:UnbindFromRenderStep("UrbanGhostAim")
    end)
    for _, c in ipairs(conns) do
        pcall(function()
            c:Disconnect()
        end)
    end
    clearChams()
    pcall(function()
        chamsFolder:Destroy()
    end)
    pcall(function()
        gui:Destroy()
    end)
    if env.UrbanGhost == env.__UrbanGhostApi then
        env.UrbanGhost = nil
        env.__UrbanGhostApi = nil
    end
end

local api = { Unload = unload }
env.UrbanGhost = api
env.__UrbanGhostApi = api
