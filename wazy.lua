--[[
    PANEL V2 - Roblox Luau mod menu (target game: Urban Reload)
    Layout: left sidebar tabs (AIM / ESP / WEAPON / PERF / SETTINGS), switches, sliders, yellow + black theme
    (color presets and RGB sliders in SETTINGS > THEME).
    Features: Aimlock (active only while you fire), ESP (line, skeleton, box, name, health, distance), No Recoil, performance system (PERF tab), English / French.
    Menu: floating "V2" button (tap) or RightShift on PC. Language: EN/FR button in the header.

    Firing detection (the aimlock acts ONLY while a fire input is physically held):
      - PC: left mouse button, read from UserInputService:IsMouseButtonPressed every frame
        (a click on this panel, or on a game GUI while the cursor is free, does not count).
      - Controller: GameConfig.fireGamepadKeys (default ButtonR2), read with IsGamepadButtonDown every frame.
      - Mobile (Android/iPhone): a touch that starts inside the lower-right fire zone, is not on this panel,
        and stays within GameConfig.touchFireMaxDrift pixels of where it began (a camera swipe is not a shot),
        PLUS any touch that starts on a GuiButton whose Name matches GameConfig.fireButtonNames
        (that one has no drift limit).
        Fire-zone touches are tracked even when the game consumes the InputBegan (gameProcessed=true).
      - All platforms: the equipped Tool's Activated until Deactivated/Unequipped, trusted only while a
        mouse button, touch or controller fire key is still down.
    Touches are tracked by object identity and their UserInputState is re-checked every frame, so a swallowed
    InputEnded can never leave the aimlock stuck on. A touch or tool hold is also capped at FIRE_HOLD_CAP seconds.
    Window focus loss clears all fire state. A press keeps the lock for at least MIN_FIRE_WINDOW seconds so a
    one-frame tap still gets an aim step. Not firing means no lock, on every device.
    lockedPlayer is also released the instant it leaves the FOV circle or the max distance.

    STATUS: written without running it. Not tested in Roblox, Delta or any PC executor.

    UNKNOWN GAME DATA (not verified for Urban Reload) lives in GameConfig below.
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")
local Lighting = game:GetService("Lighting")
local GuiService = game:GetService("GuiService")

local LocalPlayer = Players.LocalPlayer

------------------------------------------------------------------------
-- Game-specific values. nil = UNKNOWN (not taken from any dump).
------------------------------------------------------------------------
local GameConfig = {
    gameId = nil,
    teamAttribute = nil,
    recoilNamePatterns = { "recoil" },
    recoilSkipPatterns = { "recover", "decay", "reset", "speed", "time", "delay", "duration", "damp", "stiff" },
    fireButtonNames = { "fire", "shoot", "attack", "tire", "tir" },
    touchFallback = true,
    -- Controller fire key. Roblox's default Tool activation is the right trigger; NOT verified for Urban Reload.
    fireGamepadKeys = { Enum.KeyCode.ButtonR2 },
    -- Pixels a fire-zone touch may move before it counts as a camera swipe. nil disables the check. Uncalibrated.
    touchFireMaxDrift = 35,
}

if GameConfig.gameId ~= nil and game.GameId ~= GameConfig.gameId then
    warn("[PanelV2] Wrong game (GameId " .. tostring(game.GameId) .. "). Not loading.")
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
    aimlock = false,
    part = 1,
    fov = 150,
    maxDist = 500,
    teamCheck = true,
    wallCheck = true,
    showFov = true,
    espLine = false,
    espSkeleton = false,
    espBox = false,
    espName = false,
    espHealth = false,
    espDistance = false,
    espTeamCheck = true,
    espMaxDist = 1000,
    noRecoil = false,
    adaptive = true,
    targetFps = 30,
    espRate = 60,
    espMaxPlayers = 25,
    gfxQuality = false,
    gfxShadows = false,
    gfxMaterials = false,
    gfxEffects = false,
    gfxParticles = false,
    gfxWater = false,
}

local PART_NAMES = { { "Head" }, { "UpperTorso", "Torso" }, { "HumanoidRootPart" } }
local PART_KEYS = { "head", "torso", "body" }

local STRINGS = {
    EN = {
        tab_aim = "AIM", tab_esp = "ESP", tab_weapon = "WEAPON", tab_settings = "SETTINGS",
        sec_main = "AIM ASSIST", sec_filters = "FILTERS", sec_esp = "PLAYER ESP", sec_overlay = "OVERLAY", sec_weapon = "WEAPON",
        sec_interface = "INTERFACE", sec_theme = "THEME",
        aimlock = "Aimlock (sticky)",
        target = "Target", head = "Head", torso = "Torso", body = "Body",
        fov = "FOV radius", dist = "Max distance",
        teamcheck = "Team check", wallcheck = "Wall check", showfov = "Show FOV circle",
        esp_line = "Line (from top)", esp_skeleton = "Skeleton", esp_box = "Box", esp_name = "Name",
        esp_health = "Health", esp_dist = "Distance", esp_team = "ESP team check", esp_maxdist = "ESP range",
        norecoil = "No Recoil", recoil_off = "No Recoil is off.", recoil_patched = "Patched values:",
        recoil_none = "Nothing found yet. Equip a weapon. If it stays at 0, the game keeps its recoil somewhere this scan cannot reach.",
        language = "Language", unload = "Unload script",
        theme_preset = "Color preset", theme_r = "Red", theme_g = "Green", theme_b = "Blue",
        theme_reset = "Reset to yellow",
        pr_yellow = "Yellow", pr_orange = "Orange", pr_red = "Red", pr_green = "Green",
        pr_blue = "Blue", pr_purple = "Purple", pr_custom = "Custom",
        tab_perf = "PERF", sec_perf = "SCRIPT PERFORMANCE", sec_gfx = "GRAPHICS BOOSTER",
        adaptive = "Auto optimize (FPS)", target_fps = "Target FPS",
        esp_rate = "ESP refresh rate", esp_players = "ESP max players",
        gfx_quality = "Lowest graphics level", gfx_shadows = "Shadows off", gfx_materials = "Plain materials",
        gfx_effects = "Post effects off", gfx_particles = "Particles & trails off", gfx_water = "Simple water",
        gfx_all_on = "Boost everything", gfx_all_off = "Restore graphics",
        perf_line1 = "FPS: %d   ESP rate: %d Hz   Auto level: %d",
        perf_line2 = "ESP players drawn: %d   Graphics changes: %d",
    },
    FR = {
        tab_aim = "VISÉE", tab_esp = "ESP", tab_weapon = "ARME", tab_settings = "RÉGLAGES",
        sec_main = "AIDE À LA VISÉE", sec_filters = "FILTRES", sec_esp = "ESP JOUEURS", sec_overlay = "AFFICHAGE", sec_weapon = "ARME",
        sec_interface = "INTERFACE", sec_theme = "THÈME",
        aimlock = "Aimlock (verrou)",
        target = "Cible", head = "Tête", torso = "Torse", body = "Corps",
        fov = "Rayon FOV", dist = "Distance max",
        teamcheck = "Vérif. équipe", wallcheck = "Vérif. mur", showfov = "Cercle FOV",
        esp_line = "Ligne (du haut)", esp_skeleton = "Squelette", esp_box = "Boîte", esp_name = "Nom",
        esp_health = "Santé", esp_dist = "Distance", esp_team = "ESP vérif. équipe", esp_maxdist = "Portée ESP",
        norecoil = "Sans recul", recoil_off = "Sans recul désactivé.", recoil_patched = "Valeurs modifiées :",
        recoil_none = "Rien trouvé. Équipe une arme. Si ça reste à 0, le jeu garde son recul ailleurs.",
        language = "Langue", unload = "Décharger le script",
        theme_preset = "Couleur", theme_r = "Rouge", theme_g = "Vert", theme_b = "Bleu",
        theme_reset = "Remettre en jaune",
        pr_yellow = "Jaune", pr_orange = "Orange", pr_red = "Rouge", pr_green = "Vert",
        pr_blue = "Bleu", pr_purple = "Violet", pr_custom = "Perso",
        tab_perf = "PERF", sec_perf = "PERFORMANCE SCRIPT", sec_gfx = "BOOST GRAPHIQUE",
        adaptive = "Optimisation auto (FPS)", target_fps = "FPS cible",
        esp_rate = "Fréquence ESP", esp_players = "ESP joueurs max",
        gfx_quality = "Qualité graphique min", gfx_shadows = "Sans ombres", gfx_materials = "Matériaux simples",
        gfx_effects = "Sans effets post", gfx_particles = "Sans particules", gfx_water = "Eau simple",
        gfx_all_on = "Tout optimiser", gfx_all_off = "Restaurer graphismes",
        perf_line1 = "FPS : %d   Fréquence ESP : %d Hz   Niveau auto : %d",
        perf_line2 = "Joueurs ESP affichés : %d   Changements graphiques : %d",
    },
}

local function T(key)
    local t = STRINGS[S.lang] or STRINGS.EN
    return t[key] or STRINGS.EN[key] or key
end

------------------------------------------------------------------------
-- Cleanup bookkeeping and small helpers
------------------------------------------------------------------------
local alive = true
local conns = {}
local function track(conn)
    table.insert(conns, conn)
    return conn
end

local function nameHasAny(name, patterns)
    local lower = string.lower(tostring(name))
    for _, pat in ipairs(patterns) do
        if string.find(lower, pat, 1, true) then
            return true
        end
    end
    return false
end

local playerList = Players:GetPlayers()
track(Players.PlayerAdded:Connect(function(p)
    for _, q in ipairs(playerList) do
        if q == p then
            return
        end
    end
    table.insert(playerList, p)
end))
track(Players.PlayerRemoving:Connect(function(p)
    for i = #playerList, 1, -1 do
        if playerList[i] == p then
            table.remove(playerList, i)
            break
        end
    end
end))

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

local ignoreList = { false, false }

local function isVisible(origin, part, targetChar)
    ignoreList[1] = LocalPlayer.Character or targetChar
    ignoreList[2] = targetChar
    rayParams.FilterDescendantsInstances = ignoreList
    return Workspace:Raycast(origin, part.Position - origin, rayParams) == nil
end

local function findTarget(cam)
    local vp = cam.ViewportSize
    local center = Vector2.new(vp.X / 2, vp.Y / 2)
    local camPos = cam.CFrame.Position
    local best, bestDist = nil, S.fov
    for _, plr in ipairs(playerList) do
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

------------------------------------------------------------------------
-- Firing detection.
-- The aimlock may act ONLY while a real fire input is physically held.
--   Mouse      : IsMouseButtonPressed, polled every frame (ground truth).
--   Controller : IsGamepadButtonDown for GameConfig.fireGamepadKeys, polled every frame.
--   Touch      : InputObjects tracked by identity, UserInputState re-checked every frame.
--   Tool       : Activated until Deactivated/Unequipped, only trusted while a pointer is down.
-- Presses on this panel's own UI never count as firing.
------------------------------------------------------------------------
local MIN_FIRE_WINDOW = 0.1 -- seconds a press keeps the lock at minimum, so a one-frame tap still gets an aim step. 0 disables.
local FIRE_HOLD_CAP = 15 -- seconds; fail-safe that drops a touch or tool hold that never reported its end.

local touches = {} -- [InputObject] = { startPos, since, fire, anchored }
local toolHeld = false
local toolSince = 0
local fireTool = nil
local toolConns = {}
local fireUntil = 0
local mouseBlocked = false
local mouseAnchored = false
local windowFocused = true
local ownUiObjects = {}

local function registerOwnUi(obj)
    table.insert(ownUiObjects, obj)
end

local function pointInGui(obj, x, y)
    local p, s = obj.AbsolutePosition, obj.AbsoluteSize
    return x >= p.X and x <= p.X + s.X and y >= p.Y and y <= p.Y + s.Y
end

-- The panel's ScreenGui ignores the GUI inset while input positions may include it,
-- so the point is tested both raw and shifted by the inset. A false hit only costs a thin strip.
local function overOwnUi(pos)
    local inset = GuiService:GetGuiInset()
    for _, obj in ipairs(ownUiObjects) do
        if obj.Parent ~= nil and obj.Visible then
            if pointInGui(obj, pos.X, pos.Y)
                or pointInGui(obj, pos.X + inset.X, pos.Y + inset.Y) then
                return true
            end
        end
    end
    return false
end

local function bumpFire()
    fireUntil = math.max(fireUntil, os.clock() + MIN_FIRE_WINDOW)
end

local function resetFireState()
    for input in pairs(touches) do
        touches[input] = nil
    end
    toolHeld = false
    fireUntil = 0
    mouseBlocked = false
    mouseAnchored = false
end

local function clearToolConns()
    for _, c in ipairs(toolConns) do
        pcall(function()
            c:Disconnect()
        end)
    end
    toolConns = {}
end

local function bindFireTool(tool)
    clearToolConns()
    fireTool = tool
    toolHeld = false
    if not tool then
        return
    end
    table.insert(toolConns, tool.Activated:Connect(function()
        toolHeld = true
        toolSince = os.clock()
        bumpFire()
    end))
    table.insert(toolConns, tool.Deactivated:Connect(function()
        toolHeld = false
    end))
    table.insert(toolConns, tool.Unequipped:Connect(function()
        toolHeld = false
    end))
end

local function isFireZoneTouch(input)
    if not GameConfig.touchFallback then
        return false
    end
    local cam = Workspace.CurrentCamera
    if not cam then
        return false
    end
    local vp = cam.ViewportSize
    local p = input.Position
    return p.X > vp.X * 0.5 and p.Y > vp.Y * 0.4
end

-- Every touch is recorded (the tool check needs to know whether any finger is down).
-- A touch only ever gets upgraded to "fire", never downgraded by a later handler.
local function registerTouch(input, fire, anchored)
    local e = touches[input]
    if not e then
        e = { startPos = input.Position, since = os.clock(), fire = false, anchored = false }
        touches[input] = e
    end
    if fire then
        e.fire = true
        if anchored then
            e.anchored = true
        end
        bumpFire()
    end
end

local function pruneTouches(now)
    local limit = GameConfig.touchFireMaxDrift
    for input, e in pairs(touches) do
        local state = input.UserInputState
        if state == Enum.UserInputState.End or state == Enum.UserInputState.Cancel then
            touches[input] = nil
        elseif e.fire then
            if now - e.since > FIRE_HOLD_CAP then
                e.fire = false
            elseif limit ~= nil and not e.anchored and (input.Position - e.startPos).Magnitude > limit then
                e.fire = false
            end
        end
    end
end

local function isGamepadFireKey(input)
    local keys = GameConfig.fireGamepadKeys
    if keys == nil then
        return false
    end
    if not string.find(input.UserInputType.Name, "^Gamepad%d") then
        return false
    end
    for _, key in ipairs(keys) do
        if input.KeyCode == key then
            return true
        end
    end
    return false
end

local function gamepadFireDown()
    local keys = GameConfig.fireGamepadKeys
    if keys == nil then
        return false
    end
    local ok, down = pcall(function()
        for _, pad in ipairs(UserInputService:GetConnectedGamepads()) do
            for _, key in ipairs(keys) do
                if UserInputService:IsGamepadButtonDown(pad, key) then
                    return true
                end
            end
        end
        return false
    end)
    return ok and down == true
end

local function watchFireButton(obj)
    if not obj:IsA("GuiButton") then
        return
    end
    if GameConfig.fireButtonNames == nil then
        return
    end
    if not nameHasAny(obj.Name, GameConfig.fireButtonNames) then
        return
    end
    track(obj.InputBegan:Connect(function(input)
        local t = input.UserInputType
        if t == Enum.UserInputType.Touch then
            registerTouch(input, true, true)
        elseif t == Enum.UserInputType.MouseButton1 then
            mouseAnchored = true
            mouseBlocked = false
            bumpFire()
        end
    end))
end

do
    local playerGui = LocalPlayer:FindFirstChildOfClass("PlayerGui")
    if playerGui then
        for _, d in ipairs(playerGui:GetDescendants()) do
            watchFireButton(d)
        end
        track(playerGui.DescendantAdded:Connect(watchFireButton))
    end
end

track(UserInputService.InputBegan:Connect(function(input, gameProcessed)
    local t = input.UserInputType
    if t == Enum.UserInputType.Touch then
        if overOwnUi(input.Position) then
            registerTouch(input, false, false)
        else
            registerTouch(input, isFireZoneTouch(input), false)
        end
    elseif t == Enum.UserInputType.MouseButton1 then
        if not mouseAnchored then
            -- With the cursor locked to the center (first person / shift lock) a click can only be a game click.
            -- With a free cursor, a click on this panel or one the game's GUI consumed is not a shot.
            local locked = UserInputService.MouseBehavior == Enum.MouseBehavior.LockCenter
            mouseBlocked = (not locked) and (gameProcessed or overOwnUi(UserInputService:GetMouseLocation()))
        end
        if not mouseBlocked then
            bumpFire()
        end
    elseif isGamepadFireKey(input) then
        bumpFire()
    end
end))
track(UserInputService.InputEnded:Connect(function(input)
    touches[input] = nil
end))
track(UserInputService.WindowFocusReleased:Connect(function()
    windowFocused = false
    resetFireState()
end))
track(UserInputService.WindowFocused:Connect(function()
    windowFocused = true
end))

local function isFiring()
    local char = LocalPlayer.Character
    local tool = char and char:FindFirstChildOfClass("Tool") or nil
    if tool ~= fireTool then
        bindFireTool(tool)
    end

    if not windowFocused then
        return false
    end

    local now = os.clock()
    pruneTouches(now)

    local anyTouch = next(touches) ~= nil
    local mouseDown = UserInputService:IsMouseButtonPressed(Enum.UserInputType.MouseButton1)
    if not mouseDown then
        mouseBlocked = false
        mouseAnchored = false
    end
    local padDown = gamepadFireDown()

    local held = false
    if mouseDown and not mouseBlocked then
        held = true
    elseif padDown then
        held = true
    else
        for _, e in pairs(touches) do
            if e.fire then
                held = true
                break
            end
        end
    end

    if toolHeld then
        if now - toolSince > FIRE_HOLD_CAP or not (mouseDown or anyTouch or padDown) then
            toolHeld = false
        else
            held = true
        end
    end

    return held or now < fireUntil
end

------------------------------------------------------------------------
-- Performance core.
------------------------------------------------------------------------
local ADAPT_LEVELS = {
    [0] = { rate = math.huge, players = math.huge, skeleton = true, lines = true, search = 0 },
    [1] = { rate = 40, players = math.huge, skeleton = true, lines = true, search = 0.05 },
    [2] = { rate = 30, players = 15, skeleton = false, lines = true, search = 0.05 },
    [3] = { rate = 20, players = 10, skeleton = false, lines = false, search = 0.08 },
}

local perf = { level = 0, fps = 0, espHz = 0, drawn = 0, frames = 0, espSteps = 0, acc = 0, good = 0, bad = 0 }
local perfInfoUpdate = nil

------------------------------------------------------------------------
-- Aimlock: only while firing. Not firing -> released. Leaving the FOV
-- circle or the max distance also releases immediately.
------------------------------------------------------------------------
local lockedPlayer = nil
local lastSearch = 0

local function aimStepInner()
    local cam = Workspace.CurrentCamera
    if not cam then
        return
    end
    local firing = isFiring()
    if not S.aimlock or not firing then
        lockedPlayer = nil
        return
    end

    local camPos = cam.CFrame.Position
    local part = nil

    if lockedPlayer then
        local c, p = getTargetParts(lockedPlayer)
        if c and (p.Position - camPos).Magnitude <= S.maxDist then
            -- Also verify the target is still inside the FOV circle.
            local vp = cam.ViewportSize
            local center = Vector2.new(vp.X / 2, vp.Y / 2)
            local sp, onScreen = cam:WorldToViewportPoint(p.Position)
            if onScreen and sp.Z > 0
                and (Vector2.new(sp.X, sp.Y) - center).Magnitude <= S.fov then
                part = p
            else
                lockedPlayer = nil
            end
        else
            lockedPlayer = nil
        end
    end
    if not part then
        local now = os.clock()
        if now - lastSearch >= ADAPT_LEVELS[perf.level].search then
            lastSearch = now
            lockedPlayer = findTarget(cam)
            if lockedPlayer then
                local _, p = getTargetParts(lockedPlayer)
                part = p
            end
        end
    end

    if not part then
        return
    end

    cam.CFrame = CFrame.lookAt(camPos, part.Position)
end

local aimErrorShown = false
local function aimStep()
    local ok, err = pcall(aimStepInner)
    if not ok and not aimErrorShown then
        aimErrorShown = true
        warn("[PanelV2] aim error: " .. tostring(err))
    end
end

------------------------------------------------------------------------
-- No Recoil
------------------------------------------------------------------------
local recoilList = {}
local recoilSeen = setmetatable({}, { __mode = "k" })
local recoilNotified = 0
local onRecoilChanged = nil

local function isRecoilName(name)
    return nameHasAny(name, GameConfig.recoilNamePatterns)
        and not nameHasAny(name, GameConfig.recoilSkipPatterns)
end

local function zeroOf(value)
    local t = typeof(value)
    if t == "number" then
        return 0
    elseif t == "Vector3" then
        return Vector3.zero
    elseif t == "Vector2" then
        return Vector2.zero
    end
    return nil
end

local function writeEntry(e, value)
    pcall(function()
        if e.kind == "attr" then
            e.target:SetAttribute(e.key, value)
        elseif e.kind == "value" then
            e.target.Value = value
        else
            e.target[e.key] = value
        end
    end)
end

local function readEntry(e)
    local ok, v = pcall(function()
        if e.kind == "attr" then
            return e.target:GetAttribute(e.key)
        elseif e.kind == "value" then
            return e.target.Value
        end
        return e.target[e.key]
    end)
    if ok then
        return v
    end
    return nil
end

local function patchValue(kind, owner, target, key, current)
    local zero = zeroOf(current)
    if zero == nil or current == zero then
        return
    end
    local seen = recoilSeen[target]
    if not seen then
        seen = {}
        recoilSeen[target] = seen
    end
    if seen[key] then
        return
    end
    seen[key] = true
    local entry = { kind = kind, owner = owner, target = target, key = key, original = current, zero = zero }
    table.insert(recoilList, entry)
    writeEntry(entry, zero)
end

local function patchTable(tbl, owner, depth, visited)
    if depth > 3 or visited[tbl] then
        return
    end
    visited[tbl] = true
    pcall(function()
        for k, v in pairs(tbl) do
            if type(v) == "table" then
                patchTable(v, owner, depth + 1, visited)
            elseif type(k) == "string" and isRecoilName(k) then
                patchValue("table", owner, tbl, k, v)
            end
        end
    end)
end

local function scanInstance(root)
    local list = root:GetDescendants()
    table.insert(list, 1, root)
    for _, inst in ipairs(list) do
        for name, val in pairs(inst:GetAttributes()) do
            if isRecoilName(name) then
                patchValue("attr", inst, inst, name, val)
            end
        end
        if (inst:IsA("NumberValue") or inst:IsA("IntValue") or inst:IsA("Vector3Value"))
            and isRecoilName(inst.Name) then
            patchValue("value", inst, inst, "Value", inst.Value)
        end
        if inst:IsA("ModuleScript") then
            local ok, result = pcall(require, inst)
            if ok and type(result) == "table" then
                patchTable(result, inst, 0, {})
            end
        end
    end
end

local function scanRecoil()
    for i = #recoilList, 1, -1 do
        if not recoilList[i].owner:IsDescendantOf(game) then
            table.remove(recoilList, i)
        end
    end
    for _, e in ipairs(recoilList) do
        if readEntry(e) ~= e.zero then
            writeEntry(e, e.zero)
        end
    end

    local tools = {}
    local char = LocalPlayer.Character
    if char then
        for _, c in ipairs(char:GetChildren()) do
            if c:IsA("Tool") then
                table.insert(tools, c)
            end
        end
    end
    local backpack = LocalPlayer:FindFirstChildOfClass("Backpack")
    if backpack then
        for _, c in ipairs(backpack:GetChildren()) do
            if c:IsA("Tool") then
                table.insert(tools, c)
            end
        end
    end
    for _, tool in ipairs(tools) do
        scanInstance(tool)
    end

    if #recoilList ~= recoilNotified then
        recoilNotified = #recoilList
        if onRecoilChanged then
            onRecoilChanged()
        end
    end
end

local function restoreRecoil()
    for _, e in ipairs(recoilList) do
        writeEntry(e, e.original)
    end
    recoilList = {}
    for k in pairs(recoilSeen) do
        recoilSeen[k] = nil
    end
    recoilNotified = 0
    if onRecoilChanged then
        onRecoilChanged()
    end
end

------------------------------------------------------------------------
-- Graphics booster
------------------------------------------------------------------------
local GFX_BUDGET = 0.003
local GFX_ORDER = { "quality", "shadows", "materials", "effects", "particles", "water" }
local GFX_INSTANCE_FEATURES = { "shadows", "materials", "effects", "particles" }
local GFX_FLAG = {
    quality = "gfxQuality", shadows = "gfxShadows", materials = "gfxMaterials",
    effects = "gfxEffects", particles = "gfxParticles", water = "gfxWater",
}

local function weakKeys()
    return setmetatable({}, { __mode = "k" })
end

local P_SHADOW = { CastShadow = false }
local P_MATERIAL = { Material = Enum.Material.Plastic, Reflectance = 0 }
local P_DISABLE = { Enabled = false }
local EFFECT_CLASSES = { BloomEffect = true, BlurEffect = true, SunRaysEffect = true, DepthOfFieldEffect = true }
local PARTICLE_CLASSES = { ParticleEmitter = true, Trail = true, Beam = true, Smoke = true, Fire = true, Sparkles = true }

local GFX_MATCH = {
    shadows = function(inst)
        if inst:IsA("BasePart") and not inst:IsA("Terrain") then
            return P_SHADOW
        end
        return nil
    end,
    materials = function(inst)
        if inst:IsA("BasePart") and not inst:IsA("Terrain") then
            return P_MATERIAL
        end
        return nil
    end,
    effects = function(inst)
        if EFFECT_CLASSES[inst.ClassName] then
            return P_DISABLE
        end
        return nil
    end,
    particles = function(inst)
        if PARTICLE_CLASSES[inst.ClassName] then
            return P_DISABLE
        end
        return nil
    end,
}

local GFX_ORIG = {
    shadows = { CastShadow = weakKeys() },
    materials = { Material = weakKeys(), Reflectance = weakKeys() },
    effects = { Enabled = weakKeys() },
    particles = { Enabled = weakKeys() },
}

local gfxGen = { shadows = 0, materials = 0, effects = 0, particles = 0 }
local gfxJobs = {}
local gfxChanged = 0
local gfxGlobal = {}
local gfxHooks = {}
local onGfxChanged = nil

local function gfxApplyProps(orig, props, inst)
    for prop, target in pairs(props) do
        local cur = inst[prop]
        if cur ~= target then
            local store = orig[prop]
            if store[inst] == nil then
                store[inst] = cur
                gfxChanged += 1
            end
            inst[prop] = target
        end
    end
end

local function gfxSetProp(inst, prop, value)
    inst[prop] = value
end

local function gfxOnAdded(inst)
    for _, f in ipairs(GFX_INSTANCE_FEATURES) do
        if S[GFX_FLAG[f]] then
            local props = GFX_MATCH[f](inst)
            if props then
                pcall(gfxApplyProps, GFX_ORIG[f], props, inst)
            end
        end
    end
end

local function gfxUpdateHooks()
    local any = false
    for _, f in ipairs(GFX_INSTANCE_FEATURES) do
        if S[GFX_FLAG[f]] then
            any = true
        end
    end
    if any and #gfxHooks == 0 then
        gfxHooks[1] = Workspace.DescendantAdded:Connect(gfxOnAdded)
        gfxHooks[2] = Lighting.DescendantAdded:Connect(gfxOnAdded)
    elseif not any and #gfxHooks > 0 then
        for _, c in ipairs(gfxHooks) do
            pcall(function()
                c:Disconnect()
            end)
        end
        gfxHooks = {}
    end
end

local function gfxQueueApply(feature)
    local list = Workspace:GetDescendants()
    if feature == "effects" or feature == "particles" then
        for _, d in ipairs(Lighting:GetDescendants()) do
            table.insert(list, d)
        end
    end
    table.insert(gfxJobs, { kind = "apply", feature = feature, gen = gfxGen[feature], list = list, i = 1 })
end

local function gfxQueueRestore(feature)
    local insts, props, vals, n = {}, {}, {}, 0
    for prop, store in pairs(GFX_ORIG[feature]) do
        for inst, value in pairs(store) do
            n += 1
            insts[n], props[n], vals[n] = inst, prop, value
            store[inst] = nil
        end
    end
    gfxChanged = math.max(0, gfxChanged - n)
    if n > 0 then
        table.insert(gfxJobs, { kind = "restore", list = insts, props = props, vals = vals, i = 1 })
    end
end

local function gfxPump()
    local job = gfxJobs[1]
    if not job then
        return
    end
    local t0 = os.clock()
    local list = job.list
    local n = #list
    local i = job.i
    if job.kind == "apply" then
        if job.gen ~= gfxGen[job.feature] or not S[GFX_FLAG[job.feature]] then
            table.remove(gfxJobs, 1)
            return
        end
        local match, orig = GFX_MATCH[job.feature], GFX_ORIG[job.feature]
        while i <= n do
            local inst = list[i]
            i += 1
            local props = match(inst)
            if props then
                pcall(gfxApplyProps, orig, props, inst)
            end
            if i % 128 == 0 and os.clock() - t0 > GFX_BUDGET then
                break
            end
        end
    else
        local props, vals = job.props, job.vals
        while i <= n do
            local inst = list[i]
            if inst.Parent ~= nil then
                pcall(gfxSetProp, inst, props[i], vals[i])
            end
            i += 1
            if i % 128 == 0 and os.clock() - t0 > GFX_BUDGET then
                break
            end
        end
    end
    job.i = i
    if i > n then
        table.remove(gfxJobs, 1)
        if onGfxChanged then
            onGfxChanged()
        end
    end
end
track(RunService.Heartbeat:Connect(gfxPump))

local function gfxApplyGlobal(feature)
    if feature == "quality" then
        if gfxGlobal.quality == nil then
            local ok = pcall(function()
                local r = settings().Rendering
                gfxGlobal.quality = r.QualityLevel
                r.QualityLevel = Enum.QualityLevel.Level01
            end)
            if ok then
                gfxChanged += 1
            else
                gfxGlobal.quality = nil
            end
        end
    elseif feature == "water" then
        local terrain = Workspace:FindFirstChildOfClass("Terrain")
        if terrain and gfxGlobal.water == nil then
            local ok = pcall(function()
                gfxGlobal.water = { terrain.WaterWaveSize, terrain.WaterWaveSpeed, terrain.WaterReflectance }
                terrain.WaterWaveSize = 0
                terrain.WaterWaveSpeed = 0
                terrain.WaterReflectance = 0
            end)
            if ok then
                gfxChanged += 1
            else
                gfxGlobal.water = nil
            end
        end
    elseif feature == "shadows" then
        if gfxGlobal.shadows == nil then
            local ok = pcall(function()
                gfxGlobal.shadows = Lighting.GlobalShadows
                Lighting.GlobalShadows = false
            end)
            if ok then
                gfxChanged += 1
            else
                gfxGlobal.shadows = nil
            end
        end
    end
end

local function gfxRestoreGlobal(feature)
    if feature == "quality" and gfxGlobal.quality ~= nil then
        pcall(function()
            settings().Rendering.QualityLevel = gfxGlobal.quality
        end)
        gfxGlobal.quality = nil
        gfxChanged = math.max(0, gfxChanged - 1)
    elseif feature == "water" and gfxGlobal.water ~= nil then
        local w = gfxGlobal.water
        local terrain = Workspace:FindFirstChildOfClass("Terrain")
        if terrain then
            pcall(function()
                terrain.WaterWaveSize = w[1]
                terrain.WaterWaveSpeed = w[2]
                terrain.WaterReflectance = w[3]
            end)
        end
        gfxGlobal.water = nil
        gfxChanged = math.max(0, gfxChanged - 1)
    elseif feature == "shadows" and gfxGlobal.shadows ~= nil then
        local value = gfxGlobal.shadows
        pcall(function()
            Lighting.GlobalShadows = value
        end)
        gfxGlobal.shadows = nil
        gfxChanged = math.max(0, gfxChanged - 1)
    end
end

local function gfxSet(feature, on)
    local perInstance = gfxGen[feature] ~= nil
    if perInstance then
        gfxGen[feature] += 1
    end
    if on then
        gfxApplyGlobal(feature)
        if perInstance then
            gfxQueueApply(feature)
        end
    else
        gfxRestoreGlobal(feature)
        if perInstance then
            gfxQueueRestore(feature)
        end
    end
    gfxUpdateHooks()
    if onGfxChanged then
        onGfxChanged()
    end
end

local function gfxShutdown()
    for _, c in ipairs(gfxHooks) do
        pcall(function()
            c:Disconnect()
        end)
    end
    gfxHooks = {}
    for i = #gfxJobs, 1, -1 do
        if gfxJobs[i].kind == "apply" then
            table.remove(gfxJobs, i)
        end
    end
    for _, f in ipairs(GFX_INSTANCE_FEATURES) do
        gfxQueueRestore(f)
    end
    for _, job in ipairs(gfxJobs) do
        for i = job.i, #job.list do
            local inst = job.list[i]
            if inst.Parent ~= nil then
                pcall(gfxSetProp, inst, job.props[i], job.vals[i])
            end
        end
    end
    gfxJobs = {}
    for _, f in ipairs(GFX_ORDER) do
        gfxRestoreGlobal(f)
    end
    gfxChanged = 0
end

------------------------------------------------------------------------
-- UI helpers and theme
------------------------------------------------------------------------
local COLORS = {
    bg = Color3.fromRGB(14, 14, 16),
    panel = Color3.fromRGB(20, 20, 24),
    row = Color3.fromRGB(30, 30, 35),
    off = Color3.fromRGB(62, 62, 70),
    text = Color3.fromRGB(235, 235, 238),
    dim = Color3.fromRGB(150, 150, 156),
}

local PRESETS = {
    { key = "pr_yellow", color = Color3.fromRGB(255, 204, 0) },
    { key = "pr_orange", color = Color3.fromRGB(255, 128, 0) },
    { key = "pr_red", color = Color3.fromRGB(210, 32, 44) },
    { key = "pr_green", color = Color3.fromRGB(46, 204, 90) },
    { key = "pr_blue", color = Color3.fromRGB(52, 152, 255) },
    { key = "pr_purple", color = Color3.fromRGB(160, 90, 255) },
}
local DEFAULT_ACCENT = PRESETS[1].color

local theme = { accent = DEFAULT_ACCENT }
local themed = {}

local function channel(c, k)
    return math.floor(c[k] * 255 + 0.5)
end

local function onAccentColor(c)
    local lum = 0.299 * c.R + 0.587 * c.G + 0.114 * c.B
    return (lum > 0.55) and COLORS.bg or COLORS.text
end

local function bindTheme(inst, prop, kind)
    table.insert(themed, { inst = inst, prop = prop, kind = kind })
    inst[prop] = (kind == "accent") and theme.accent or onAccentColor(theme.accent)
    return inst
end

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

local function accentStroke(inst, thickness)
    return bindTheme(stroke(inst, theme.accent, thickness), "Color", "accent")
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
    Name = "PanelV2",
    ResetOnSpawn = false,
    IgnoreGuiInset = true,
    ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
    DisplayOrder = 100,
}, guiParent)

local espGui = mk("ScreenGui", {
    Name = "PanelV2Esp",
    ResetOnSpawn = false,
    IgnoreGuiInset = true,
    ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
    DisplayOrder = 50,
}, guiParent)
local espLayer = mk("Frame", {
    Size = UDim2.new(1, 0, 1, 0),
    BackgroundTransparency = 1,
    BorderSizePixel = 0,
    Active = false,
}, espGui)

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
-- FOV circle
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
accentStroke(fovCircle, 1.5)

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
-- Main window
------------------------------------------------------------------------
local applyTheme

local main = mk("Frame", {
    Name = "Main",
    Size = UDim2.fromOffset(460, 290),
    Position = UDim2.new(0.5, -230, 0.5, -145),
    BackgroundColor3 = COLORS.bg,
    BorderSizePixel = 0,
    Active = true,
}, gui)
corner(main, 8)
accentStroke(main, 1.5)
registerOwnUi(main)

local header = mk("Frame", {
    Size = UDim2.new(1, 0, 0, 38),
    BackgroundColor3 = COLORS.panel,
    BorderSizePixel = 0,
}, main)
corner(header, 8)
local headerLine = mk("Frame", {
    Size = UDim2.new(1, 0, 0, 2),
    Position = UDim2.new(0, 0, 0, 38),
    BorderSizePixel = 0,
}, main)
bindTheme(headerLine, "BackgroundColor3", "accent")

local titleLabel = mk("TextLabel", {
    BackgroundTransparency = 1,
    Position = UDim2.new(0, 14, 0, 0),
    Size = UDim2.new(1, -120, 1, 0),
    Font = Enum.Font.GothamBold,
    TextSize = 16,
    TextColor3 = COLORS.text,
    TextXAlignment = Enum.TextXAlignment.Left,
    RichText = true,
    Text = "",
}, header)

local function hexOf(c)
    return string.format("%02X%02X%02X", channel(c, "R"), channel(c, "G"), channel(c, "B"))
end
local function updateTitle()
    titleLabel.Text = 'PANEL <font color="#' .. hexOf(theme.accent) .. '">V2</font>'
end
updateTitle()

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
accentStroke(langBtn, 1)
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
    AutoButtonColor = false,
    Font = Enum.Font.GothamBold,
    TextSize = 14,
    Text = "–",
}, header)
corner(hideBtn, 6)
bindTheme(hideBtn, "BackgroundColor3", "accent")
bindTheme(hideBtn, "TextColor3", "onAccent")

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
local currentTab = "aim"
local buildPage = nil
local applyState

local function selectTab(name)
    currentTab = name
    for n, page in pairs(pages) do
        page.Visible = (n == name)
    end
    for n, btn in pairs(tabButtons) do
        local active = (n == name)
        btn.BackgroundColor3 = active and theme.accent or COLORS.row
        btn.TextColor3 = active and onAccentColor(theme.accent) or COLORS.text
    end
end

local function addTab(name, labelKey)
    local page = mk("ScrollingFrame", {
        Position = UDim2.new(0, 4, 0, 4),
        Size = UDim2.new(1, -8, 1, -8),
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        ScrollBarThickness = 3,
        CanvasSize = UDim2.new(0, 0, 0, 0),
        AutomaticCanvasSize = Enum.AutomaticSize.Y,
        Visible = false,
    }, pageHolder)
    bindTheme(page, "ScrollBarImageColor3", "accent")
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
        TextXAlignment = Enum.TextXAlignment.Left,
        LayoutOrder = nextOrder(),
    }, buildPage)
    bindTheme(lbl, "TextColor3", "accent")
    register(function()
        lbl.Text = T(key)
    end)
end

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
        local col = on and theme.accent or COLORS.off
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
        TextXAlignment = Enum.TextXAlignment.Right,
    }, row)
    bindTheme(valLbl, "TextColor3", "accent")
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
        BorderSizePixel = 0,
    }, rail)
    bindTheme(fill, "BackgroundColor3", "accent")
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
    accentStroke(btn, 1)
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
        AutoButtonColor = false,
        Font = Enum.Font.GothamBold,
        TextSize = 13,
    }, row)
    corner(btn, 6)
    bindTheme(btn, "BackgroundColor3", "accent")
    bindTheme(btn, "TextColor3", "onAccent")
    btn.Activated:Connect(fn)
    register(function()
        btn.Text = T(key)
    end)
end

local function addInfo(textFn)
    local row = newRow(72)
    local lbl = mk("TextLabel", {
        BackgroundTransparency = 1,
        Position = UDim2.new(0, 10, 0, 4),
        Size = UDim2.new(1, -20, 1, -8),
        Font = Enum.Font.Gotham,
        TextSize = 12,
        TextColor3 = COLORS.dim,
        TextXAlignment = Enum.TextXAlignment.Left,
        TextYAlignment = Enum.TextYAlignment.Top,
        TextWrapped = true,
    }, row)
    local function update()
        lbl.Text = textFn()
    end
    register(update)
    return update
end

local function recoilStatusText()
    if not S.noRecoil then
        return T("recoil_off")
    end
    local n = #recoilList
    if n == 0 then
        return T("recoil_patched") .. " 0\n" .. T("recoil_none")
    end
    return T("recoil_patched") .. " " .. tostring(n)
end

------------------------------------------------------------------------
-- Theme actions
------------------------------------------------------------------------
local function setAccent(color)
    theme.accent = color
    applyTheme()
end

local function setChannel(k, v)
    local r, g, b = channel(theme.accent, "R"), channel(theme.accent, "G"), channel(theme.accent, "B")
    if k == "R" then
        r = v
    elseif k == "G" then
        g = v
    else
        b = v
    end
    setAccent(Color3.fromRGB(r, g, b))
end

local function currentPreset()
    local r, g, b = channel(theme.accent, "R"), channel(theme.accent, "G"), channel(theme.accent, "B")
    for i, p in ipairs(PRESETS) do
        if channel(p.color, "R") == r and channel(p.color, "G") == g and channel(p.color, "B") == b then
            return i
        end
    end
    return nil
end

------------------------------------------------------------------------
-- Tabs and rows
------------------------------------------------------------------------
addTab("aim", "tab_aim")
addSection("sec_main")
addToggle("aimlock", function() return S.aimlock end, function(v) S.aimlock = v end)
addCycle("target",
    function() return T(PART_KEYS[S.part]) end,
    function() S.part = (S.part % #PART_NAMES) + 1 end)
addSlider("fov", 30, 600, 10, function() return S.fov end, function(v) S.fov = v end)
addSlider("dist", 50, 2000, 50, function() return S.maxDist end, function(v) S.maxDist = v end)
addSection("sec_filters")
addToggle("teamcheck", function() return S.teamCheck end, function(v) S.teamCheck = v end)
addToggle("wallcheck", function() return S.wallCheck end, function(v) S.wallCheck = v end)

addTab("esp", "tab_esp")
addSection("sec_esp")
addToggle("esp_line", function() return S.espLine end, function(v) S.espLine = v end)
addToggle("esp_skeleton", function() return S.espSkeleton end, function(v) S.espSkeleton = v end)
addToggle("esp_box", function() return S.espBox end, function(v) S.espBox = v end)
addToggle("esp_name", function() return S.espName end, function(v) S.espName = v end)
addToggle("esp_health", function() return S.espHealth end, function(v) S.espHealth = v end)
addToggle("esp_dist", function() return S.espDistance end, function(v) S.espDistance = v end)
addToggle("esp_team", function() return S.espTeamCheck end, function(v) S.espTeamCheck = v end)
addSlider("esp_maxdist", 100, 3000, 100, function() return S.espMaxDist end, function(v) S.espMaxDist = v end)
addSection("sec_overlay")
addToggle("showfov", function() return S.showFov end, function(v) S.showFov = v end)

addTab("weapon", "tab_weapon")
addSection("sec_weapon")
addToggle("norecoil", function() return S.noRecoil end, function(v)
    S.noRecoil = v
    if v then
        pcall(scanRecoil)
    else
        restoreRecoil()
    end
    refreshAll()
end)
addInfo(recoilStatusText)
onRecoilChanged = refreshAll

local function perfStatusText()
    return string.format(T("perf_line1"), math.floor(perf.fps + 0.5), math.floor(perf.espHz + 0.5), perf.level)
        .. "\n" .. string.format(T("perf_line2"), perf.drawn, gfxChanged)
end

local function gfxAll(on)
    for _, f in ipairs(GFX_ORDER) do
        local flag = GFX_FLAG[f]
        if S[flag] ~= on then
            S[flag] = on
            gfxSet(f, on)
        end
    end
    refreshAll()
end

addTab("perf", "tab_perf")
addSection("sec_perf")
addToggle("adaptive", function() return S.adaptive end, function(v) S.adaptive = v end)
addSlider("target_fps", 20, 60, 5, function() return S.targetFps end, function(v) S.targetFps = v end)
addSlider("esp_rate", 10, 120, 5, function() return S.espRate end, function(v) S.espRate = v end)
addSlider("esp_players", 5, 50, 5, function() return S.espMaxPlayers end, function(v) S.espMaxPlayers = v end)
perfInfoUpdate = addInfo(perfStatusText)
onGfxChanged = function()
    if perfInfoUpdate then
        perfInfoUpdate()
    end
end
addSection("sec_gfx")
addToggle("gfx_quality", function() return S.gfxQuality end, function(v)
    S.gfxQuality = v
    gfxSet("quality", v)
end)
addToggle("gfx_shadows", function() return S.gfxShadows end, function(v)
    S.gfxShadows = v
    gfxSet("shadows", v)
end)
addToggle("gfx_materials", function() return S.gfxMaterials end, function(v)
    S.gfxMaterials = v
    gfxSet("materials", v)
end)
addToggle("gfx_effects", function() return S.gfxEffects end, function(v)
    S.gfxEffects = v
    gfxSet("effects", v)
end)
addToggle("gfx_particles", function() return S.gfxParticles end, function(v)
    S.gfxParticles = v
    gfxSet("particles", v)
end)
addToggle("gfx_water", function() return S.gfxWater end, function(v)
    S.gfxWater = v
    gfxSet("water", v)
end)
addButton("gfx_all_on", function() gfxAll(true) end)
addButton("gfx_all_off", function() gfxAll(false) end)

addTab("settings", "tab_settings")
addSection("sec_interface")
addCycle("language",
    function() return S.lang == "EN" and "English" or "Français" end,
    function() S.lang = (S.lang == "EN") and "FR" or "EN" end)

addSection("sec_theme")
addCycle("theme_preset",
    function()
        local i = currentPreset()
        return i and T(PRESETS[i].key) or T("pr_custom")
    end,
    function()
        local i = currentPreset() or 0
        setAccent(PRESETS[(i % #PRESETS) + 1].color)
    end)
addSlider("theme_r", 0, 255, 1, function() return channel(theme.accent, "R") end, function(v) setChannel("R", v) end)
addSlider("theme_g", 0, 255, 1, function() return channel(theme.accent, "G") end, function(v) setChannel("G", v) end)
addSlider("theme_b", 0, 255, 1, function() return channel(theme.accent, "B") end, function(v) setChannel("B", v) end)
addButton("theme_reset", function()
    setAccent(DEFAULT_ACCENT)
end)

local unload
addButton("unload", function()
    unload()
end)

selectTab("aim")

applyTheme = function()
    local acc = theme.accent
    local onAcc = onAccentColor(acc)
    for _, b in ipairs(themed) do
        b.inst[b.prop] = (b.kind == "accent") and acc or onAcc
    end
    updateTitle()
    selectTab(currentTab)
    refreshAll()
end

applyState = function()
    fovCircle.Size = UDim2.fromOffset(S.fov * 2, S.fov * 2)
    fovCircle.Visible = S.showFov and S.aimlock
    if not S.aimlock then
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
    Text = "V2",
    Font = Enum.Font.GothamBold,
    TextSize = 15,
    AutoButtonColor = false,
}, gui)
circle(toggleBtn)
bindTheme(toggleBtn, "BackgroundColor3", "accent")
bindTheme(toggleBtn, "TextColor3", "onAccent")
stroke(toggleBtn, COLORS.text, 1.5)
registerOwnUi(toggleBtn)
makeDraggable(toggleBtn, toggleBtn, function()
    setMenuVisible(not main.Visible)
end)

track(UserInputService.InputBegan:Connect(function(input, gameProcessed)
    if gameProcessed then
        return
    end
    if UserInputService:GetFocusedTextBox() then
        return
    end
    if input.KeyCode == Enum.KeyCode.RightShift then
        setMenuVisible(not main.Visible)
    end
end))

------------------------------------------------------------------------
-- ESP
------------------------------------------------------------------------
local ESP_COLOR = Color3.fromRGB(210, 32, 44)

local BONES_R15 = {
    { "Head", "UpperTorso" }, { "UpperTorso", "LowerTorso" },
    { "UpperTorso", "LeftUpperArm" }, { "LeftUpperArm", "LeftLowerArm" }, { "LeftLowerArm", "LeftHand" },
    { "UpperTorso", "RightUpperArm" }, { "RightUpperArm", "RightLowerArm" }, { "RightLowerArm", "RightHand" },
    { "LowerTorso", "LeftUpperLeg" }, { "LeftUpperLeg", "LeftLowerLeg" }, { "LeftLowerLeg", "LeftFoot" },
    { "LowerTorso", "RightUpperLeg" }, { "RightUpperLeg", "RightLowerLeg" }, { "RightLowerLeg", "RightFoot" },
}
local BONES_R6 = {
    { "Head", "Torso" }, { "Torso", "Left Arm" }, { "Torso", "Right Arm" },
    { "Torso", "Left Leg" }, { "Torso", "Right Leg" },
}

local espObjects = {}
local espCand, espCandChar, espCandHum, espCandRoot, espCandDist, espOrder = {}, {}, {}, {}, {}, {}
local espStamp = 0

local function put(o, inst, prop, value)
    local c = o.cache[inst]
    if c == nil then
        c = {}
        o.cache[inst] = c
    end
    if c[prop] ~= value then
        c[prop] = value
        inst[prop] = value
    end
end

local function setLine(o, frame, a, b, thickness)
    local d = b - a
    local len = d.Magnitude
    if len < 1 then
        put(o, frame, "Visible", false)
        return
    end
    put(o, frame, "Size", UDim2.fromOffset(len, thickness))
    put(o, frame, "Position", UDim2.fromOffset((a.X + b.X) / 2, (a.Y + b.Y) / 2))
    put(o, frame, "Rotation", math.deg(math.atan2(d.Y, d.X)))
    put(o, frame, "Visible", true)
end

local function createEspObject()
    local o = { all = {}, bones = {}, cache = {}, hidden = true, stamp = 0 }
    local function add(inst)
        table.insert(o.all, inst)
        return inst
    end
    local function label(anchor)
        return add(mk("TextLabel", {
            AnchorPoint = anchor,
            Size = UDim2.fromOffset(160, 14),
            BackgroundTransparency = 1,
            Font = Enum.Font.GothamBold,
            TextSize = 12,
            TextColor3 = COLORS.text,
            TextStrokeTransparency = 0.4,
            Visible = false,
        }, espLayer))
    end
    local function lineFrame()
        return add(mk("Frame", {
            AnchorPoint = Vector2.new(0.5, 0.5),
            BackgroundColor3 = ESP_COLOR,
            BorderSizePixel = 0,
            Visible = false,
        }, espLayer))
    end
    o.makeLine = lineFrame

    o.box = add(mk("Frame", { BackgroundTransparency = 1, BorderSizePixel = 0, Visible = false }, espLayer))
    stroke(o.box, ESP_COLOR, 1.5)
    o.name = label(Vector2.new(0.5, 1))
    o.dist = label(Vector2.new(0.5, 0))
    o.hpBack = add(mk("Frame", {
        BackgroundColor3 = Color3.fromRGB(0, 0, 0),
        BackgroundTransparency = 0.35,
        BorderSizePixel = 0,
        Visible = false,
    }, espLayer))
    o.hpFill = mk("Frame", {
        AnchorPoint = Vector2.new(0, 1),
        Position = UDim2.new(0, 0, 1, 0),
        Size = UDim2.new(1, 0, 1, 0),
        BorderSizePixel = 0,
    }, o.hpBack)
    o.snap = lineFrame()
    return o
end

local function hideEsp(o)
    for _, inst in ipairs(o.all) do
        put(o, inst, "Visible", false)
    end
    o.hidden = true
end

local function destroyEsp(o)
    for _, inst in ipairs(o.all) do
        inst:Destroy()
    end
end

local function destroyAllEsp()
    for plr, o in pairs(espObjects) do
        destroyEsp(o)
        espObjects[plr] = nil
    end
end

track(Players.PlayerRemoving:Connect(function(p)
    local o = espObjects[p]
    if o then
        destroyEsp(o)
        espObjects[p] = nil
    end
end))

local function drawEsp(o, plr, char, hum, root, cam, vp, dist, lvl)
    local head = char:FindFirstChild("Head")
    local headPos
    if head and head:IsA("BasePart") then
        headPos = head.Position
    else
        headPos = root.Position + Vector3.new(0, 2, 0)
    end
    local top = cam:WorldToViewportPoint(headPos + Vector3.new(0, 0.7, 0))
    local bottom = cam:WorldToViewportPoint(root.Position - Vector3.new(0, 3, 0))
    if top.Z <= 0 or bottom.Z <= 0 then
        return false
    end
    local h = bottom.Y - top.Y
    if h < 4 then
        return false
    end
    local w = h * 0.55
    local cx = (top.X + bottom.X) / 2
    if cx + w < 0 or cx - w > vp.X or bottom.Y < 0 or top.Y > vp.Y then
        return false
    end
    local left = cx - w / 2

    if S.espBox then
        put(o, o.box, "Position", UDim2.fromOffset(left, top.Y))
        put(o, o.box, "Size", UDim2.fromOffset(w, h))
        put(o, o.box, "Visible", true)
    else
        put(o, o.box, "Visible", false)
    end

    if S.espName then
        put(o, o.name, "Text", (plr.DisplayName ~= "") and plr.DisplayName or plr.Name)
        put(o, o.name, "Position", UDim2.fromOffset(cx, top.Y - 2))
        put(o, o.name, "Visible", true)
    else
        put(o, o.name, "Visible", false)
    end

    if S.espDistance then
        put(o, o.dist, "Text", string.format("%dm", math.floor(dist + 0.5)))
        put(o, o.dist, "Position", UDim2.fromOffset(cx, bottom.Y + 2))
        put(o, o.dist, "Visible", true)
    else
        put(o, o.dist, "Visible", false)
    end

    if S.espHealth then
        local maxHp = hum.MaxHealth
        local ratio = 0
        if maxHp > 0 then
            ratio = math.clamp(hum.Health / maxHp, 0, 1)
        end
        put(o, o.hpBack, "Position", UDim2.fromOffset(left - 6, top.Y))
        put(o, o.hpBack, "Size", UDim2.fromOffset(3, h))
        put(o, o.hpFill, "Size", UDim2.new(1, 0, ratio, 0))
        put(o, o.hpFill, "BackgroundColor3", Color3.fromHSV(ratio * 0.33, 1, 1))
        put(o, o.hpBack, "Visible", true)
    else
        put(o, o.hpBack, "Visible", false)
    end

    if S.espLine and lvl.lines then
        setLine(o, o.snap, Vector2.new(vp.X / 2, 0), Vector2.new(cx, bottom.Y), 1.5)
    else
        put(o, o.snap, "Visible", false)
    end

    if S.espSkeleton and lvl.skeleton then
        local bones = (hum.RigType == Enum.HumanoidRigType.R15) and BONES_R15 or BONES_R6
        for i, pair in ipairs(bones) do
            local line = o.bones[i]
            if not line then
                line = o.makeLine()
                o.bones[i] = line
            end
            local a, b = char:FindFirstChild(pair[1]), char:FindFirstChild(pair[2])
            if a and b and a:IsA("BasePart") and b:IsA("BasePart") then
                local pa = cam:WorldToViewportPoint(a.Position)
                local pb = cam:WorldToViewportPoint(b.Position)
                if pa.Z > 0 and pb.Z > 0 then
                    setLine(o, line, Vector2.new(pa.X, pa.Y), Vector2.new(pb.X, pb.Y), 1.5)
                else
                    put(o, line, "Visible", false)
                end
            else
                put(o, line, "Visible", false)
            end
        end
        for i = #bones + 1, #o.bones do
            put(o, o.bones[i], "Visible", false)
        end
    else
        for _, line in ipairs(o.bones) do
            put(o, line, "Visible", false)
        end
    end

    return true
end

local function espAnyOn()
    return S.espLine or S.espSkeleton or S.espBox or S.espName or S.espHealth or S.espDistance
end

local function espDistLess(a, b)
    return espCandDist[a] < espCandDist[b]
end

local function espStepInner()
    if not espAnyOn() then
        destroyAllEsp()
        perf.drawn = 0
        return
    end
    local cam = Workspace.CurrentCamera
    if not cam then
        return
    end
    perf.espSteps += 1
    local vp = cam.ViewportSize
    local camPos = cam.CFrame.Position
    local lvl = ADAPT_LEVELS[perf.level]
    local limit = math.min(S.espMaxPlayers, lvl.players)

    local n = 0
    for _, plr in ipairs(playerList) do
        if plr ~= LocalPlayer then
            local char = plr.Character
            local hum = char and char:FindFirstChildOfClass("Humanoid")
            local root = char and char:FindFirstChild("HumanoidRootPart")
            if hum and root and root:IsA("BasePart") and hum.Health > 0
                and (not S.espTeamCheck or isEnemy(plr)) then
                local dist = (root.Position - camPos).Magnitude
                if dist <= S.espMaxDist then
                    n += 1
                    espCand[n], espCandChar[n], espCandHum[n], espCandRoot[n], espCandDist[n] = plr, char, hum, root, dist
                    espOrder[n] = n
                end
            end
        end
    end
    for i = #espCand, n + 1, -1 do
        espCand[i], espCandChar[i], espCandHum[i], espCandRoot[i], espCandDist[i], espOrder[i] =
            nil, nil, nil, nil, nil, nil
    end

    if n > limit then
        table.sort(espOrder, espDistLess)
    end

    espStamp += 1
    local drawnCount = 0
    for k = 1, n do
        if k > limit then
            break
        end
        local idx = espOrder[k]
        local plr = espCand[idx]
        local o = espObjects[plr]
        if not o then
            o = createEspObject()
            espObjects[plr] = o
        end
        if drawEsp(o, plr, espCandChar[idx], espCandHum[idx], espCandRoot[idx], cam, vp, espCandDist[idx], lvl) then
            o.stamp = espStamp
            o.hidden = false
            drawnCount += 1
        end
    end
    perf.drawn = drawnCount

    for _, o in pairs(espObjects) do
        if o.stamp ~= espStamp and not o.hidden then
            hideEsp(o)
        end
    end
end

local espAcc = 0
local espErrorShown = false
local function espStep(dt)
    espAcc += dt
    local rate = math.min(S.espRate, ADAPT_LEVELS[perf.level].rate)
    local interval = 1 / rate
    if espAcc < interval * 0.9 then
        return
    end
    espAcc -= interval
    if espAcc > interval then
        espAcc = 0
    end
    local ok, err = pcall(espStepInner)
    if not ok and not espErrorShown then
        espErrorShown = true
        warn("[PanelV2] esp error: " .. tostring(err))
    end
end

local function perfStepInner(dt)
    perf.frames += 1
    perf.acc += dt
    if perf.acc < 1 then
        return
    end
    perf.fps = perf.frames / perf.acc
    perf.espHz = perf.espSteps / perf.acc
    perf.frames, perf.espSteps, perf.acc = 0, 0, 0
    if S.adaptive and espAnyOn() then
        if perf.fps < S.targetFps * 0.9 then
            perf.good = 0
            perf.bad += 1
            if perf.bad >= 2 and perf.level < 3 then
                perf.level += 1
                perf.bad = 0
            end
        elseif perf.fps > S.targetFps * 1.2 then
            perf.bad = 0
            perf.good += 1
            if perf.good >= 6 and perf.level > 0 then
                perf.level -= 1
                perf.good = 0
            end
        else
            perf.bad, perf.good = 0, 0
        end
    else
        perf.level, perf.bad, perf.good = 0, 0, 0
    end
    if perfInfoUpdate and main.Visible and currentTab == "perf" then
        perfInfoUpdate()
    end
end

local perfErrorShown = false
local function perfStep(dt)
    local ok, err = pcall(perfStepInner, dt)
    if not ok and not perfErrorShown then
        perfErrorShown = true
        warn("[PanelV2] perf error: " .. tostring(err))
    end
end

local recoilAcc = 0
local recoilErrorShown = false
track(RunService.Heartbeat:Connect(function(dt)
    if not S.noRecoil then
        return
    end
    recoilAcc += dt
    if recoilAcc < 1 then
        return
    end
    recoilAcc = 0
    local ok, err = pcall(scanRecoil)
    if not ok and not recoilErrorShown then
        recoilErrorShown = true
        warn("[PanelV2] no-recoil error: " .. tostring(err))
    end
end))

------------------------------------------------------------------------
-- Aim loop and shutdown
------------------------------------------------------------------------
RunService:BindToRenderStep("PanelV2Aim", Enum.RenderPriority.Camera.Value + 1, aimStep)
RunService:BindToRenderStep("PanelV2Esp", Enum.RenderPriority.Camera.Value + 2, espStep)
RunService:BindToRenderStep("PanelV2Perf", Enum.RenderPriority.Camera.Value + 3, perfStep)

unload = function()
    if not alive then
        return
    end
    alive = false
    resetFireState()
    lockedPlayer = nil
    pcall(function()
        RunService:UnbindFromRenderStep("PanelV2Aim")
    end)
    pcall(function()
        RunService:UnbindFromRenderStep("PanelV2Esp")
    end)
    pcall(function()
        RunService:UnbindFromRenderStep("PanelV2Perf")
    end)
    for _, c in ipairs(conns) do
        pcall(function()
            c:Disconnect()
        end)
    end
    clearToolConns()
    destroyAllEsp()
    restoreRecoil()
    pcall(gfxShutdown)
    pcall(function()
        espGui:Destroy()
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
