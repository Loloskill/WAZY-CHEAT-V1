-- WAZY CHEAT V1 : universal Roblox shooter menu (Luau executor script)
-- Layout adapts to PC, iPhone and Android. Public Roblox APIs only: no offsets, no signatures.
-- Optional executor functions (features degrade if missing):
--   gethui, mousemoverel, mouse1click, writefile / readfile / isfile, setclipboard.
-- Screen coordinates are viewport pixels. World space is Y-up, right-handed.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UIS = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")
local Lighting = game:GetService("Lighting")
local StarterGui = game:GetService("StarterGui")
local TeleportService = game:GetService("TeleportService")
local TweenService = game:GetService("TweenService")
local HttpService = game:GetService("HttpService")

local LP = Players.LocalPlayer

-- Reload safety: unload a previous copy first
local genv = (getgenv and getgenv()) or _G
if genv.WAZY_UNLOAD then pcall(genv.WAZY_UNLOAD) end

-- Touch-only device (phone / tablet) vs. keyboard device
local isTouch = UIS.TouchEnabled and not UIS.KeyboardEnabled

---------------------------------------------------------------- settings
local S = {
	Target = { Team = true, SkipFF = true, MaxDist = 1000 },
	Aim = { Enabled = false, Key = isTouch and "On-Screen Button" or "Right Mouse", Method = "Camera",
		Part = "Auto", Priority = "Closest to Cursor", Fov = 150, Speed = 10, Humanize = 3, Predict = 0,
		Wall = true, Sticky = true, ShowFov = true },
	Trigger = { Enabled = false, DelayMs = 60 },
	Hitbox = { Enabled = false, Size = 8 },
	ESP = { Enabled = false, Chams = true, Boxes = true, HealthBar = true, Tracers = false, TracerFrom = "Top",
		HeadDot = false, Skeleton = false, Names = true, Health = true, Distance = true, Team = false, MaxDist = 2000 },
	Radar = { Enabled = false, Range = 150, Size = 140 },
	Player = { Speed = false, SpeedValue = 32, Jump = false, JumpValue = 70, InfJump = false,
		Noclip = false, Fly = false, FlySpeed = 60 },
	Visual = { Fullbright = false, CustomFov = false, FovValue = 90, Crosshair = false, CrossSize = 8 },
	Misc = { AntiAfk = true },
	Menu = { Key = "RightShift" },
	Binds = { Aimbot = "None", Triggerbot = "None", ESP = "None", Radar = "None", Hitbox = "None",
		Fly = "None", Noclip = "None", Speed = "None" },
	Config = { Slot = "1" },
}

local Theme = {
	Bg = Color3.fromRGB(8, 13, 28), Panel = Color3.fromRGB(15, 24, 48),
	Accent = Color3.fromRGB(0, 140, 255), AccentDark = Color3.fromRGB(0, 80, 170),
	Text = Color3.fromRGB(230, 240, 255), Sub = Color3.fromRGB(140, 165, 210),
	Off = Color3.fromRGB(32, 44, 80), Team = Color3.fromRGB(70, 220, 120),
}

-- Executor functions (all optional)
local moveRel = mousemoverel
local writeFile, readFile, isFile, setClip = writefile, readfile, isfile, setclipboard

---------------------------------------------------------------- core utilities
local conns = {}
local function bind(signal, fn)
	local c = signal:Connect(fn)
	table.insert(conns, c)
	return c
end

local function notify(text)
	pcall(function()
		StarterGui:SetCore("SendNotification", { Title = "WAZY CHEAT V1", Text = text, Duration = 5 })
	end)
end

-- Errors are shown in the Settings tab (phones have no console) and printed once per feature.
local errors = {}
local seenErrors = {}
local errRefresh = nil
local function safe(tag, fn, ...)
	local ok, err = pcall(fn, ...)
	if not ok and not seenErrors[tag] then
		seenErrors[tag] = true
		warn("[WAZY] " .. tag .. ": " .. tostring(err))
		table.insert(errors, tag .. ": " .. tostring(err))
		if #errors > 20 then table.remove(errors, 1) end
		if errRefresh then errRefresh() end
	end
end

local function new(class, props, parent)
	local o = Instance.new(class)
	for k, v in pairs(props) do o[k] = v end
	o.Parent = parent
	return o
end
local function round(o, r) new("UICorner", { CornerRadius = UDim.new(0, r or 6) }, o) end
local function outline(o, c, t)
	return new("UIStroke", { Color = c or Theme.Accent, Thickness = t or 1,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, o)
end

local function getChar() return LP.Character end
local function getHum()
	local c = getChar()
	return c and c:FindFirstChildOfClass("Humanoid")
end
local function getRoot()
	local c = getChar()
	return c and c:FindFirstChild("HumanoidRootPart")
end

local function sameTeam(plr)
	return plr.Team ~= nil and plr.Team == LP.Team
end
local function isEnemy(plr)
	if plr == LP then return false end
	if S.Target.Team and sameTeam(plr) then return false end
	return true
end

local function aliveCharacter(plr)
	local char = plr.Character
	if not char then return nil end
	local hum = char:FindFirstChildOfClass("Humanoid")
	if not hum or hum.Health <= 0 then return nil end
	return char, hum
end

---------------------------------------------------------------- GUI root
local gui = new("ScreenGui", { Name = "WAZY_CHEAT_V1", ResetOnSpawn = false,
	IgnoreGuiInset = true, DisplayOrder = 999, ZIndexBehavior = Enum.ZIndexBehavior.Sibling })
local okParent = pcall(function()
	gui.Parent = (gethui and gethui()) or game:GetService("CoreGui")
end)
if not okParent or not gui.Parent then gui.Parent = LP:WaitForChild("PlayerGui") end

-- Sizes adapt to the device: bigger touch targets on phones, menu scales to the screen.
local ROW_H = isTouch and 42 or 36
local SW_W, SW_H, KNOB = 44, 22, 16
if isTouch then SW_W, SW_H, KNOB = 54, 28, 22 end

local main = new("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5),
	Size = UDim2.fromScale(0.94, 0.88), BackgroundColor3 = Theme.Bg, BorderSizePixel = 0 }, gui)
new("UISizeConstraint", { MaxSize = Vector2.new(560, 390), MinSize = Vector2.new(300, 230) }, main)
round(main, 10); outline(main, Theme.Accent, 1.5)

local openBtn = new("TextButton", { Size = UDim2.fromOffset(isTouch and 56 or 48, isTouch and 56 or 48),
	Position = UDim2.new(0, 18, 0.5, -24), BackgroundColor3 = Theme.Accent, Text = "W",
	TextColor3 = Color3.new(1, 1, 1), Font = Enum.Font.GothamBlack, TextSize = 24, AutoButtonColor = false,
	Visible = false }, gui)
round(openBtn, 28); outline(openBtn, Color3.new(1, 1, 1), 1.5)

local function setMenu(open)
	main.Visible = open
	openBtn.Visible = not open
end

-- Drag a target by a handle. Released without moving: onClick runs. canDrag (optional) gates dragging.
local function makeDraggable(handle, target, onClick, canDrag)
	local dragging, moved, startPos, startMouse = false, false, nil, nil
	bind(handle.InputBegan, function(i)
		if i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch then
			if canDrag and not canDrag() then return end
			dragging, moved, startPos, startMouse = true, false, target.Position, i.Position
		end
	end)
	bind(UIS.InputChanged, function(i)
		if dragging and (i.UserInputType == Enum.UserInputType.MouseMovement or i.UserInputType == Enum.UserInputType.Touch) then
			local d = i.Position - startMouse
			if d.Magnitude > 6 then moved = true end
			if moved then
				target.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + d.X, startPos.Y.Scale, startPos.Y.Offset + d.Y)
			end
		end
	end)
	bind(UIS.InputEnded, function(i)
		if dragging and (i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch) then
			dragging = false
			if not moved and onClick then onClick() end
		end
	end)
end

local titleBar = new("Frame", { Size = UDim2.new(1, 0, 0, 42), BackgroundColor3 = Theme.Panel, BorderSizePixel = 0 }, main)
round(titleBar, 10)
new("TextLabel", { Size = UDim2.new(0.4, 0, 1, 0), Position = UDim2.fromOffset(14, 0), BackgroundTransparency = 1,
	Text = "WAZY CHEAT V1", TextColor3 = Theme.Accent, Font = Enum.Font.GothamBlack, TextSize = 18,
	TextXAlignment = Enum.TextXAlignment.Left }, titleBar)
local hint = new("TextLabel", { Size = UDim2.new(0.6, -64, 1, 0), Position = UDim2.new(0.4, 0, 0, 0),
	BackgroundTransparency = 1, TextColor3 = Theme.Sub, Font = Enum.Font.Gotham, TextSize = 11,
	TextXAlignment = Enum.TextXAlignment.Right, TextWrapped = true,
	Text = isTouch and "X closes, W button reopens" or ("Menu key: " .. S.Menu.Key) }, titleBar)
local closeBtn = new("TextButton", { Size = UDim2.fromOffset(isTouch and 40 or 30, isTouch and 32 or 26),
	Position = UDim2.new(1, isTouch and -48 or -40, 0.5, isTouch and -16 or -13), BackgroundColor3 = Theme.AccentDark,
	Text = "X", TextColor3 = Color3.new(1, 1, 1), Font = Enum.Font.GothamBlack, TextSize = 14 }, titleBar)
round(closeBtn, 6)
bind(closeBtn.Activated, function() setMenu(false) end)

makeDraggable(titleBar, main, nil)
makeDraggable(openBtn, openBtn, function() setMenu(true) end)

local tabList = new("ScrollingFrame", { Size = UDim2.new(0, 112, 1, -54), Position = UDim2.fromOffset(8, 48),
	BackgroundTransparency = 1, BorderSizePixel = 0, ScrollBarThickness = 0, CanvasSize = UDim2.new(),
	AutomaticCanvasSize = Enum.AutomaticSize.Y }, main)
new("UIListLayout", { Padding = UDim.new(0, 6) }, tabList)
local content = new("Frame", { Size = UDim2.new(1, -134, 1, -54), Position = UDim2.fromOffset(126, 48),
	BackgroundTransparency = 1 }, main)

local tabs = {}
local function selectTab(name)
	for n, t in pairs(tabs) do
		local on = (n == name)
		t.page.Visible = on
		t.btn.BackgroundColor3 = on and Theme.Accent or Theme.Panel
		t.btn.TextColor3 = on and Color3.new(1, 1, 1) or Theme.Sub
	end
end
local function addTab(name)
	local btn = new("TextButton", { Size = UDim2.new(1, 0, 0, isTouch and 38 or 34), BackgroundColor3 = Theme.Panel,
		Text = name, TextColor3 = Theme.Sub, Font = Enum.Font.GothamBold, TextSize = 14, AutoButtonColor = false }, tabList)
	round(btn, 6)
	local page = new("ScrollingFrame", { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, BorderSizePixel = 0,
		ScrollBarThickness = 3, ScrollBarImageColor3 = Theme.Accent, CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.Y, Visible = false }, content)
	new("UIListLayout", { Padding = UDim.new(0, 6) }, page)
	new("UIPadding", { PaddingRight = UDim.new(0, 6) }, page)
	tabs[name] = { btn = btn, page = page }
	bind(btn.Activated, function() selectTab(name) end)
	return page
end

---------------------------------------------------------------- components
local refreshers = {} -- functions that re-read S into their widget (used after loading a profile)
local sliderRanges, cycleOptions = {}, {} -- let a loaded profile be clamped / validated against the real widgets
local bindActions, bindButtons, listening = {}, {}, nil -- PC keybinds

local function row(page, h)
	local r = new("Frame", { Size = UDim2.new(1, 0, 0, h or ROW_H), BackgroundColor3 = Theme.Panel, BorderSizePixel = 0 }, page)
	round(r, 6)
	return r
end
local function label(parent, text)
	return new("TextLabel", { Size = UDim2.new(1, -150, 1, 0), Position = UDim2.fromOffset(12, 0), BackgroundTransparency = 1,
		Text = text, TextColor3 = Theme.Text, Font = Enum.Font.GothamMedium, TextSize = 14,
		TextXAlignment = Enum.TextXAlignment.Left, TextTruncate = Enum.TextTruncate.AtEnd }, parent)
end

local function addSection(page, text)
	new("TextLabel", { Size = UDim2.new(1, 0, 0, 20), BackgroundTransparency = 1, Text = string.upper(text),
		TextColor3 = Theme.Accent, Font = Enum.Font.GothamBlack, TextSize = 12,
		TextXAlignment = Enum.TextXAlignment.Left }, page)
end

-- cb(newValue) may return false to refuse the change; the switch then flips back.
local function addToggle(page, text, tbl, key, cb, bindId)
	local r = row(page)
	local lbl = label(r, text)
	local hasBind = bindId ~= nil and not isTouch
	lbl.Size = UDim2.new(1, -(SW_W + 24 + (hasBind and 70 or 0)), 1, 0)
	local sw = new("TextButton", { Size = UDim2.fromOffset(SW_W, SW_H), Position = UDim2.new(1, -(SW_W + 12), 0.5, -SW_H / 2),
		Text = "", AutoButtonColor = false }, r)
	round(sw, SW_H / 2)
	local knob = new("Frame", { Size = UDim2.fromOffset(KNOB, KNOB), BackgroundColor3 = Color3.new(1, 1, 1) }, sw)
	round(knob, KNOB / 2)
	local offX, onX, y = 3, SW_W - KNOB - 3, (SW_H - KNOB) / 2
	local function paint(animate)
		local on = tbl[key]
		sw.BackgroundColor3 = on and Theme.Accent or Theme.Off
		local goal = UDim2.fromOffset(on and onX or offX, y)
		if animate then
			TweenService:Create(knob, TweenInfo.new(0.12), { Position = goal }):Play()
		else
			knob.Position = goal
		end
	end
	paint(false)
	table.insert(refreshers, function() paint(false) end)
	local function toggle()
		tbl[key] = not tbl[key]
		local res = cb and cb(tbl[key])
		if res == false then tbl[key] = not tbl[key] end
		paint(true)
	end
	bind(sw.Activated, toggle)
	if hasBind then
		bindActions[bindId] = toggle
		local bb = new("TextButton", { Size = UDim2.fromOffset(62, 22), Position = UDim2.new(1, -(SW_W + 12 + 68), 0.5, -11),
			BackgroundColor3 = Theme.Off, TextColor3 = Theme.Sub, Font = Enum.Font.GothamBold, TextSize = 11,
			AutoButtonColor = false, Text = "None", TextTruncate = Enum.TextTruncate.AtEnd }, r)
		round(bb, 5)
		bindButtons[bindId] = bb
		local function paintBind() bb.Text = S.Binds[bindId] or "None" end
		paintBind()
		table.insert(refreshers, paintBind)
		bind(bb.Activated, function()
			listening = bindId
			bb.Text = "..."
		end)
	end
end

local function addSlider(page, text, min, max, tbl, key)
	sliderRanges[tbl] = sliderRanges[tbl] or {}
	sliderRanges[tbl][key] = { min, max }
	local r = row(page, isTouch and 56 or 50)
	local lbl = label(r, text)
	lbl.Size = UDim2.new(1, -90, 0, 24)
	local val = new("TextLabel", { Size = UDim2.fromOffset(70, 24), Position = UDim2.new(1, -82, 0, 0),
		BackgroundTransparency = 1, Text = tostring(tbl[key]), TextColor3 = Theme.Accent, Font = Enum.Font.GothamBold,
		TextSize = 14, TextXAlignment = Enum.TextXAlignment.Right }, r)
	local barH = isTouch and 12 or 8
	local bar = new("Frame", { Size = UDim2.new(1, -24, 0, barH), Position = UDim2.new(0, 12, 0, isTouch and 36 or 34),
		BackgroundColor3 = Theme.Off, BorderSizePixel = 0 }, r)
	round(bar, barH / 2)
	local fill = new("Frame", { Size = UDim2.fromScale(0, 1), BackgroundColor3 = Theme.Accent, BorderSizePixel = 0 }, bar)
	round(fill, barH / 2)
	local function paint()
		fill.Size = UDim2.fromScale(math.clamp((tbl[key] - min) / (max - min), 0, 1), 1)
		val.Text = tostring(tbl[key])
	end
	paint()
	table.insert(refreshers, paint)
	local dragging = false
	local function setFromX(x)
		local rel = math.clamp((x - bar.AbsolutePosition.X) / math.max(bar.AbsoluteSize.X, 1), 0, 1)
		tbl[key] = math.floor(min + (max - min) * rel + 0.5)
		paint()
	end
	local function startDrag(i)
		dragging = true
		page.ScrollingEnabled = false -- stop the page from scrolling while the slider is dragged
		setFromX(i.Position.X)
	end
	local function stopDrag()
		dragging = false
		page.ScrollingEnabled = true
	end
	bind(bar.InputBegan, function(i)
		if i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch then startDrag(i) end
	end)
	-- a taller invisible hit area on the whole row makes sliders easier to grab on phones
	bind(r.InputBegan, function(i)
		if (i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch)
			and i.Position.Y >= bar.AbsolutePosition.Y - 10 then
			startDrag(i)
		end
	end)
	bind(UIS.InputChanged, function(i)
		if dragging and (i.UserInputType == Enum.UserInputType.MouseMovement or i.UserInputType == Enum.UserInputType.Touch) then
			setFromX(i.Position.X)
		end
	end)
	bind(UIS.InputEnded, function(i)
		if dragging and (i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch) then
			stopDrag()
		end
	end)
end

local function addCycle(page, text, options, tbl, key, cb)
	cycleOptions[tbl] = cycleOptions[tbl] or {}
	cycleOptions[tbl][key] = options
	local r = row(page)
	label(r, text)
	local b = new("TextButton", { Size = UDim2.fromOffset(isTouch and 124 or 130, isTouch and 30 or 24),
		Position = UDim2.new(1, -(isTouch and 136 or 142), 0.5, isTouch and -15 or -12), BackgroundColor3 = Theme.AccentDark,
		Text = tostring(tbl[key]), TextColor3 = Theme.Text, Font = Enum.Font.GothamBold, TextSize = 12,
		AutoButtonColor = false, TextTruncate = Enum.TextTruncate.AtEnd }, r)
	round(b, 6)
	table.insert(refreshers, function() b.Text = tostring(tbl[key]) end)
	bind(b.Activated, function()
		local idx = table.find(options, tbl[key]) or 0
		tbl[key] = options[(idx % #options) + 1]
		b.Text = tostring(tbl[key])
		if cb then cb(tbl[key]) end
	end)
end

local function addButton(page, text, cb)
	local b = new("TextButton", { Size = UDim2.new(1, 0, 0, ROW_H), BackgroundColor3 = Theme.Accent, Text = text,
		TextColor3 = Color3.new(1, 1, 1), Font = Enum.Font.GothamBold, TextSize = 14, AutoButtonColor = true }, page)
	round(b, 6)
	bind(b.Activated, cb)
	return b
end

---------------------------------------------------------------- aim: input, cursor, visibility
local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Exclude

-- On-screen AIM button (hold). Drag it while the menu is open to reposition it.
local aimBtn = new("TextButton", { Size = UDim2.fromOffset(isTouch and 78 or 64, isTouch and 78 or 64),
	AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.82, 0.45), BackgroundColor3 = Theme.AccentDark,
	BackgroundTransparency = 0.2, Text = "AIM", TextColor3 = Color3.new(1, 1, 1), Font = Enum.Font.GothamBlack,
	TextSize = 18, AutoButtonColor = false, Visible = false }, gui)
round(aimBtn, 40); outline(aimBtn, Theme.Accent, 2)
local touchAim, aimInput = false, nil
local function releaseTouchAim()
	touchAim, aimInput = false, nil
	aimBtn.BackgroundColor3 = Theme.AccentDark
end
bind(aimBtn.InputBegan, function(i)
	if (i.UserInputType == Enum.UserInputType.Touch or i.UserInputType == Enum.UserInputType.MouseButton1) and not main.Visible then
		touchAim, aimInput = true, i
		aimBtn.BackgroundColor3 = Theme.Accent
	end
end)
bind(aimBtn.InputEnded, function(i)
	if i.UserInputType == Enum.UserInputType.Touch or i.UserInputType == Enum.UserInputType.MouseButton1 then
		releaseTouchAim()
	end
end)
bind(UIS.InputEnded, function(i)
	if aimInput and i == aimInput then releaseTouchAim() end
end)
makeDraggable(aimBtn, aimBtn, nil, function() return main.Visible end)

local function aimHeld()
	local k = S.Aim.Key
	if k == "Always On" then return true end
	if k == "On-Screen Button" then
		if aimInput and aimInput.UserInputState == Enum.UserInputState.End then releaseTouchAim() end
		return touchAim
	end
	if k == "Left Mouse" then return UIS:IsMouseButtonPressed(Enum.UserInputType.MouseButton1) end
	return UIS:IsMouseButtonPressed(Enum.UserInputType.MouseButton2)
end

-- Aim reference point: the mouse on PC, the screen center on touch devices (where the crosshair is).
local function aimCursor(cam)
	if UIS.MouseEnabled then return UIS:GetMouseLocation() end
	return cam.ViewportSize / 2
end

local ignoreList = { nil, nil }
local function visible(cam, char, part)
	ignoreList[1], ignoreList[2] = char, getChar()
	rayParams.FilterDescendantsInstances = ignoreList
	local origin = cam.CFrame.Position
	local ok, res = pcall(Workspace.Raycast, Workspace, origin, part.Position - origin, rayParams)
	return ok and res == nil
end

---------------------------------------------------------------- aim: target selection
local AUTO_PARTS = { "Head", "UpperTorso", "Torso", "HumanoidRootPart" }
local lockedPlayer = nil

-- Returns predicted position and screen distance, or nil if the part is not a valid target.
local function scorePart(cam, char, part, cursor, camPos, limit)
	local pos = part.Position + part.AssemblyLinearVelocity * (S.Aim.Predict / 100)
	if pos.X ~= pos.X or pos.Y ~= pos.Y or pos.Z ~= pos.Z then return nil end
	if (pos - camPos).Magnitude > S.Target.MaxDist then return nil end
	local sp = cam:WorldToViewportPoint(pos)
	if sp.Z <= 0 then return nil end
	local d = (Vector2.new(sp.X, sp.Y) - cursor).Magnitude
	if d > limit then return nil end
	if S.Aim.Wall and not visible(cam, char, part) then return nil end
	return pos, d
end

local function evaluate(plr, cam, cursor, camPos, limit)
	local char, hum = aliveCharacter(plr)
	if not char then return nil end
	if S.Target.SkipFF and char:FindFirstChildOfClass("ForceField") then return nil end
	local bestPart, bestPos, bestD
	if S.Aim.Part == "Auto" then
		-- Auto: the visible body part closest to the aim point
		for i = 1, #AUTO_PARTS do
			local p = char:FindFirstChild(AUTO_PARTS[i])
			if p then
				local pos, d = scorePart(cam, char, p, cursor, camPos, bestD or limit)
				if pos then bestPart, bestPos, bestD = p, pos, d end
			end
		end
	else
		local p = char:FindFirstChild(S.Aim.Part) or char:FindFirstChild("Head") or char:FindFirstChild("HumanoidRootPart")
		if p then
			local pos, d = scorePart(cam, char, p, cursor, camPos, limit)
			if pos then bestPart, bestPos, bestD = p, pos, d end
		end
	end
	if not bestPart then return nil end
	return bestPart, bestPos, bestD, char, hum
end

local function findTarget(cam)
	local cursor = aimCursor(cam)
	local camPos = cam.CFrame.Position
	local prio = S.Aim.Priority
	local bestPlr, bestPart, bestPos, bestScore
	for _, plr in ipairs(Players:GetPlayers()) do
		if isEnemy(plr) then
			local sticky = S.Aim.Sticky and plr == lockedPlayer
			local limit = sticky and S.Aim.Fov * 1.5 or S.Aim.Fov -- a locked target is kept a bit longer
			local part, pos, d, _c, hum = evaluate(plr, cam, cursor, camPos, limit)
			if part then
				local score
				if prio == "Lowest Health" then
					score = hum.Health
				elseif prio == "Closest Distance" then
					score = (pos - camPos).Magnitude
				else
					score = d
				end
				if sticky then score = score - 1e9 end
				if not bestScore or score < bestScore then
					bestPlr, bestPart, bestPos, bestScore = plr, part, pos, score
				end
			end
		end
	end
	return bestPart, bestPos, bestPlr
end

---------------------------------------------------------------- aimbot step + camera visuals
local function makeRing(color)
	local f = new("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), BackgroundTransparency = 1, Visible = false,
		Size = UDim2.fromOffset(300, 300) }, gui)
	round(f, 1000); outline(f, color, 1.5)
	return f
end
local aimRing = makeRing(Theme.Accent)

local crossH = new("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5),
	BackgroundColor3 = Theme.Accent, BorderSizePixel = 0, Visible = false }, gui)
local crossV = new("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5),
	BackgroundColor3 = Theme.Accent, BorderSizePixel = 0, Visible = false }, gui)

local origFov = nil
local accX, accY = 0, 0

local function aimStep(dt)
	crossH.Visible = S.Visual.Crosshair
	crossV.Visible = S.Visual.Crosshair
	crossH.Size = UDim2.fromOffset(S.Visual.CrossSize * 2, 2)
	crossV.Size = UDim2.fromOffset(2, S.Visual.CrossSize * 2)
	aimBtn.Visible = S.Aim.Enabled and S.Aim.Key == "On-Screen Button"

	local cam = Workspace.CurrentCamera
	if not cam then return end

	local cursor = aimCursor(cam)
	aimRing.Visible = S.Aim.Enabled and S.Aim.ShowFov
	aimRing.Size = UDim2.fromOffset(S.Aim.Fov * 2, S.Aim.Fov * 2)
	aimRing.Position = UDim2.fromOffset(cursor.X, cursor.Y)

	if S.Visual.CustomFov then
		if origFov == nil then origFov = cam.FieldOfView end
		cam.FieldOfView = S.Visual.FovValue
	elseif origFov ~= nil then
		cam.FieldOfView = origFov
		origFov = nil
	end

	if not S.Aim.Enabled or not aimHeld() or UIS:GetFocusedTextBox() then
		lockedPlayer = nil
		accX, accY = 0, 0
		return
	end
	local part, pos, plr = findTarget(cam)
	lockedPlayer = plr
	if not part then return end

	if S.Aim.Humanize > 0 then
		-- slow organic drift so the aim path is not a perfect line
		local t, m = os.clock() * 2.5, S.Aim.Humanize * 0.04
		pos = pos + Vector3.new(math.noise(t, 0.1) * m, math.noise(t, 7.3) * m, math.noise(t, 13.7) * m)
	end

	local alpha = 1 - math.exp(-S.Aim.Speed * dt)
	if S.Aim.Method == "Mouse Move" and moveRel then
		local sp = cam:WorldToViewportPoint(pos)
		accX = accX + (sp.X - cursor.X) * alpha
		accY = accY + (sp.Y - cursor.Y) * alpha
		local ix = accX >= 0 and math.floor(accX) or math.ceil(accX)
		local iy = accY >= 0 and math.floor(accY) or math.ceil(accY)
		if ix ~= 0 or iy ~= 0 then
			moveRel(ix, iy)
			accX, accY = accX - ix, accY - iy
		end
	else
		local cf = cam.CFrame
		cam.CFrame = cf:Lerp(CFrame.lookAt(cf.Position, pos), alpha)
	end
end
RunService:BindToRenderStep("WAZY_AIM", Enum.RenderPriority.Camera.Value + 1, function(dt)
	safe("aimbot", aimStep, dt)
end)

---------------------------------------------------------------- triggerbot (ray through the aim point, works on touch too)
local lastShot = 0
local clickFn = mouse1click
if not clickFn then
	local okV, vim = pcall(function() return game:GetService("VirtualInputManager") end)
	if okV and vim then
		clickFn = function()
			local p = UIS.MouseEnabled and UIS:GetMouseLocation() or Workspace.CurrentCamera.ViewportSize / 2
			vim:SendMouseButtonEvent(p.X, p.Y, 0, true, game, 0)
			vim:SendMouseButtonEvent(p.X, p.Y, 0, false, game, 0)
		end
	end
end

local function triggerStep()
	if not S.Trigger.Enabled or not clickFn or UIS:GetFocusedTextBox() then return end
	if (os.clock() - lastShot) * 1000 < S.Trigger.DelayMs then return end
	local cam = Workspace.CurrentCamera
	if not cam then return end
	local c = aimCursor(cam)
	local ray = cam:ViewportPointToRay(c.X, c.Y)
	ignoreList[1], ignoreList[2] = getChar(), nil
	rayParams.FilterDescendantsInstances = ignoreList
	local res = Workspace:Raycast(ray.Origin, ray.Direction * 2000, rayParams)
	if not res then return end
	local model = res.Instance:FindFirstAncestorOfClass("Model")
	local plr = model and Players:GetPlayerFromCharacter(model)
	if plr and isEnemy(plr) and aliveCharacter(plr) then
		if S.Target.SkipFF and model:FindFirstChildOfClass("ForceField") then return end
		lastShot = os.clock()
		pcall(clickFn)
	end
end

---------------------------------------------------------------- hitbox expander
local hbOrig = {}
local function hitboxStep()
	for part in pairs(hbOrig) do
		if not part.Parent then hbOrig[part] = nil end
	end
	if S.Hitbox.Enabled then
		local s = S.Hitbox.Size
		for _, plr in ipairs(Players:GetPlayers()) do
			if isEnemy(plr) then
				local char = aliveCharacter(plr)
				local root = char and char:FindFirstChild("HumanoidRootPart")
				if root then
					if not hbOrig[root] then
						hbOrig[root] = { root.Size, root.Transparency, root.CanCollide }
					end
					root.Size = Vector3.new(s, s, s)
					root.Transparency = 0.7
					root.CanCollide = false
				end
			end
		end
	elseif next(hbOrig) then
		for part, o in pairs(hbOrig) do
			if part.Parent then
				part.Size, part.Transparency, part.CanCollide = o[1], o[2], o[3]
			end
		end
		table.clear(hbOrig)
	end
end

---------------------------------------------------------------- ESP
-- Draws a thin rotated frame between two screen points. Returns false if the line is too short to show.
local function setLine(f, a, b, thickness)
	local d = b - a
	local len = d.Magnitude
	if len < 1 then
		f.Visible = false
		return false
	end
	local mid = (a + b) / 2
	f.Size = UDim2.fromOffset(len, thickness)
	f.Position = UDim2.fromOffset(mid.X, mid.Y)
	f.Rotation = math.deg(math.atan2(d.Y, d.X))
	f.Visible = true
	return true
end

local R15_BONES = {
	{ "Head", "UpperTorso" }, { "UpperTorso", "LowerTorso" },
	{ "UpperTorso", "LeftUpperArm" }, { "LeftUpperArm", "LeftLowerArm" }, { "LeftLowerArm", "LeftHand" },
	{ "UpperTorso", "RightUpperArm" }, { "RightUpperArm", "RightLowerArm" }, { "RightLowerArm", "RightHand" },
	{ "LowerTorso", "LeftUpperLeg" }, { "LeftUpperLeg", "LeftLowerLeg" }, { "LeftLowerLeg", "LeftFoot" },
	{ "LowerTorso", "RightUpperLeg" }, { "RightUpperLeg", "RightLowerLeg" }, { "RightLowerLeg", "RightFoot" },
}
local R6_BONES = {
	{ "Head", "Torso" }, { "Torso", "Left Arm" }, { "Torso", "Right Arm" },
	{ "Torso", "Left Leg" }, { "Torso", "Right Leg" },
}

local ESP_KEYS = { "hl", "bb", "box", "hpBack", "tracer", "dot" }
local ENEMY_ESP_COLOR = Theme.Accent
local UP, DOWN = Vector3.new(0, 3, 0), Vector3.new(0, -3.5, 0)
local esp = {}

local function removeESP(plr)
	local o = esp[plr]
	if not o then return end
	for i = 1, #ESP_KEYS do
		local inst = o[ESP_KEYS[i]]
		if inst then inst:Destroy() end
	end
	for i = 1, #o.bones do o.bones[i]:Destroy() end
	esp[plr] = nil
end

local function makeESP(char, root)
	local hl = new("Highlight", { Adornee = char, FillColor = Theme.Accent, OutlineColor = Color3.new(1, 1, 1),
		FillTransparency = 0.6, DepthMode = Enum.HighlightDepthMode.AlwaysOnTop }, gui)
	local bb = new("BillboardGui", { Adornee = root, AlwaysOnTop = true, Size = UDim2.fromOffset(180, 44),
		StudsOffset = Vector3.new(0, 3.6, 0) }, gui)
	local tl = new("TextLabel", { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, TextColor3 = Theme.Text,
		TextStrokeTransparency = 0.4, Font = Enum.Font.GothamBold, TextSize = 13 }, bb)
	local box = new("Frame", { BackgroundTransparency = 1, BorderSizePixel = 0, Visible = false }, gui)
	local boxStroke = outline(box, Theme.Accent, 1.5)
	local hpBack = new("Frame", { BackgroundColor3 = Color3.new(0, 0, 0), BackgroundTransparency = 0.4,
		BorderSizePixel = 0, Visible = false }, gui)
	local hpFill = new("Frame", { AnchorPoint = Vector2.new(0, 1), Position = UDim2.fromScale(0, 1),
		Size = UDim2.fromScale(1, 1), BorderSizePixel = 0, BackgroundColor3 = Color3.new(0, 1, 0) }, hpBack)
	local tracer = new("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), BorderSizePixel = 0,
		BackgroundColor3 = Theme.Accent, Visible = false }, gui)
	local dot = new("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Size = UDim2.fromOffset(6, 6), BorderSizePixel = 0,
		BackgroundColor3 = Theme.Accent, Visible = false }, gui)
	round(dot, 3)
	return { char = char, hl = hl, bb = bb, tl = tl, box = box, boxStroke = boxStroke,
		hpBack = hpBack, hpFill = hpFill, tracer = tracer, dot = dot, bones = {}, nextText = 0 }
end

local function espStep()
	local cam = Workspace.CurrentCamera
	if not cam or not S.ESP.Enabled then
		for plr in pairs(esp) do removeESP(plr) end
		return
	end
	local camPos = cam.CFrame.Position
	local vp = cam.ViewportSize
	local myRoot = getRoot()
	local now = os.clock()
	local fromY = (S.ESP.TracerFrom == "Top" and 0) or (S.ESP.TracerFrom == "Center" and vp.Y / 2) or vp.Y
	for _, plr in ipairs(Players:GetPlayers()) do
		local char, hum, root, show = nil, nil, nil, false
		if plr ~= LP and (S.ESP.Team or not sameTeam(plr)) then
			char, hum = aliveCharacter(plr)
			root = char and char:FindFirstChild("HumanoidRootPart")
			show = root ~= nil and (root.Position - camPos).Magnitude <= S.ESP.MaxDist
		end
		if not show then
			removeESP(plr)
		else
			local o = esp[plr]
			if o and o.char ~= char then removeESP(plr); o = nil end
			if not o then
				o = makeESP(char, root)
				esp[plr] = o
			end
			local col = sameTeam(plr) and Theme.Team or ENEMY_ESP_COLOR

			o.hl.Enabled = S.ESP.Chams
			o.hl.FillColor = col

			if now >= o.nextText then -- text refreshes 10 times a second, not every frame
				o.nextText = now + 0.1
				local lines = {}
				if S.ESP.Names then lines[#lines + 1] = plr.DisplayName end
				if S.ESP.Health then
					lines[#lines + 1] = string.format("HP %d / %d", math.floor(hum.Health), math.floor(hum.MaxHealth))
				end
				if S.ESP.Distance and myRoot then
					lines[#lines + 1] = string.format("%d studs", math.floor((root.Position - myRoot.Position).Magnitude))
				end
				o.bb.Enabled = #lines > 0
				o.tl.Text = table.concat(lines, "\n")
			end

			local rp = cam:WorldToViewportPoint(root.Position)
			local top = cam:WorldToViewportPoint(root.Position + UP)
			local bot = cam:WorldToViewportPoint(root.Position + DOWN)
			local onScreen = top.Z > 0 and bot.Z > 0
			local h = bot.Y - top.Y
			local w = h * 0.6

			local showBox = onScreen and S.ESP.Boxes and h > 2
			o.box.Visible = showBox
			if showBox then
				o.box.Position = UDim2.fromOffset(top.X - w / 2, top.Y)
				o.box.Size = UDim2.fromOffset(w, h)
				o.boxStroke.Color = col
			end

			local showHp = onScreen and S.ESP.HealthBar and h > 2
			o.hpBack.Visible = showHp
			if showHp then
				local ratio = math.clamp(hum.Health / math.max(hum.MaxHealth, 1), 0, 1)
				o.hpBack.Position = UDim2.fromOffset(top.X - w / 2 - 6, top.Y)
				o.hpBack.Size = UDim2.fromOffset(3, h)
				o.hpFill.Size = UDim2.fromScale(1, ratio)
				o.hpFill.BackgroundColor3 = Color3.fromRGB(255, 60, 60):Lerp(Color3.fromRGB(60, 255, 90), ratio)
			end

			local showTracer = rp.Z > 0 and S.ESP.Tracers
			o.tracer.Visible = showTracer
			if showTracer then
				local a = Vector2.new(vp.X / 2, fromY)
				local b = Vector2.new(rp.X, rp.Y)
				local mid = (a + b) / 2
				o.tracer.Size = UDim2.fromOffset((b - a).Magnitude, 1.5)
				o.tracer.Position = UDim2.fromOffset(mid.X, mid.Y)
				o.tracer.Rotation = math.deg(math.atan2(b.Y - a.Y, b.X - a.X))
				o.tracer.BackgroundColor3 = col
			end

			local head = char:FindFirstChild("Head")
			if S.ESP.HeadDot and head and onScreen then
				local hp = cam:WorldToViewportPoint(head.Position)
				o.dot.Visible = hp.Z > 0
				o.dot.Position = UDim2.fromOffset(hp.X, hp.Y)
				o.dot.BackgroundColor3 = col
			else
				o.dot.Visible = false
			end

			if S.ESP.Skeleton and onScreen then
				local def = char:FindFirstChild("UpperTorso") and R15_BONES or R6_BONES
				for idx = 1, #def do
					local line = o.bones[idx]
					if not line then
						line = new("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), BorderSizePixel = 0,
							BackgroundColor3 = col, Visible = false }, gui)
						o.bones[idx] = line
					end
					local a, b = char:FindFirstChild(def[idx][1]), char:FindFirstChild(def[idx][2])
					local drawn = false
					if a and b then
						local pa, pb = cam:WorldToViewportPoint(a.Position), cam:WorldToViewportPoint(b.Position)
						if pa.Z > 0 and pb.Z > 0 then
							line.BackgroundColor3 = col
							drawn = setLine(line, Vector2.new(pa.X, pa.Y), Vector2.new(pb.X, pb.Y), 1.5)
						end
					end
					if not drawn then line.Visible = false end
				end
				for idx = #def + 1, #o.bones do o.bones[idx].Visible = false end
			else
				for idx = 1, #o.bones do o.bones[idx].Visible = false end
			end
		end
	end
end
bind(Players.PlayerRemoving, removeESP)

---------------------------------------------------------------- radar
local radar = new("Frame", { BackgroundColor3 = Theme.Panel, BackgroundTransparency = 0.25, BorderSizePixel = 0,
	ClipsDescendants = true, Visible = false }, gui)
round(radar, 1000); outline(radar, Theme.Accent, 1.5)
local radarSelf = new("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5),
	Size = UDim2.fromOffset(6, 6), BackgroundColor3 = Color3.new(1, 1, 1), BorderSizePixel = 0 }, radar)
round(radarSelf, 3)

local radarDots = {}
local function removeRadarDot(plr)
	local d = radarDots[plr]
	if d then d:Destroy(); radarDots[plr] = nil end
end
bind(Players.PlayerRemoving, removeRadarDot)

local function radarStep()
	radar.Visible = S.Radar.Enabled
	if not S.Radar.Enabled then
		for plr in pairs(radarDots) do removeRadarDot(plr) end
		return
	end
	local size = S.Radar.Size
	radar.Size = UDim2.fromOffset(size, size)
	radar.Position = UDim2.new(1, -(size + 16), 0, 56)
	local cam, myRoot = Workspace.CurrentCamera, getRoot()
	if not cam or not myRoot then return end
	local rad = size / 2
	for _, plr in ipairs(Players:GetPlayers()) do
		local char, root
		if plr ~= LP and (S.ESP.Team or not sameTeam(plr)) then
			char = aliveCharacter(plr)
			root = char and char:FindFirstChild("HumanoidRootPart")
		end
		if not root then
			removeRadarDot(plr)
		else
			local dot = radarDots[plr]
			if not dot then
				dot = new("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Size = UDim2.fromOffset(6, 6),
					BorderSizePixel = 0 }, radar)
				round(dot, 3)
				radarDots[plr] = dot
			end
			local rel = cam.CFrame:VectorToObjectSpace(root.Position - myRoot.Position)
			local v = Vector2.new(rel.X, rel.Z) / S.Radar.Range * rad -- forward is up on the radar
			if v.Magnitude > rad - 4 then v = v.Unit * (rad - 4) end
			dot.Position = UDim2.fromOffset(rad + v.X, rad + v.Y)
			dot.BackgroundColor3 = sameTeam(plr) and Theme.Team or ENEMY_ESP_COLOR
		end
	end
end

---------------------------------------------------------------- player mods
local orig = {}
local noclipped = {}
local fbOrig = nil

local function playerStep()
	local hum = getHum()
	if hum then
		if S.Player.Speed then
			if orig.ws == nil then orig.ws = hum.WalkSpeed end
			hum.WalkSpeed = S.Player.SpeedValue
		elseif orig.ws ~= nil then
			hum.WalkSpeed = orig.ws; orig.ws = nil
		end
		if S.Player.Jump then
			if orig.jp == nil then orig.jp = { hum.UseJumpPower, hum.JumpPower } end
			hum.UseJumpPower = true
			hum.JumpPower = S.Player.JumpValue
		elseif orig.jp ~= nil then
			hum.UseJumpPower = orig.jp[1]; hum.JumpPower = orig.jp[2]; orig.jp = nil
		end
	end
	local char = getChar()
	if S.Player.Noclip and char then
		for _, p in ipairs(char:GetDescendants()) do
			if p:IsA("BasePart") and p.CanCollide then
				noclipped[p] = true
				p.CanCollide = false
			end
		end
	elseif not S.Player.Noclip and next(noclipped) then
		for p in pairs(noclipped) do
			if p.Parent then p.CanCollide = true end
		end
		table.clear(noclipped)
	end
end

-- Fly: the move stick / WASD steers, the camera pitch sets climb or dive, jump = up, Shift/Ctrl = down.
local function flyStep()
	if not S.Player.Fly then return end
	local root, hum, cam = getRoot(), getHum(), Workspace.CurrentCamera
	if not root or not hum or not cam then return end
	local dir = Vector3.new(0, 0, 0)
	if not UIS:GetFocusedTextBox() then
		local md = hum.MoveDirection
		if md.Magnitude > 0 then
			dir = md
			local look = cam.CFrame.LookVector
			local flat = Vector3.new(look.X, 0, look.Z)
			if flat.Magnitude > 0.01 then
				dir = md + Vector3.new(0, (look.Y / flat.Magnitude) * md:Dot(flat.Unit), 0)
			end
		end
		if UIS:IsKeyDown(Enum.KeyCode.Space) or hum.Jump then dir = dir + Vector3.new(0, 1, 0) end
		if UIS:IsKeyDown(Enum.KeyCode.LeftShift) or UIS:IsKeyDown(Enum.KeyCode.LeftControl) then
			dir = dir - Vector3.new(0, 1, 0)
		end
	end
	if dir.Magnitude > 0 then dir = dir.Unit end
	root.AssemblyLinearVelocity = dir * S.Player.FlySpeed -- zero when idle, which also cancels gravity
end

bind(UIS.JumpRequest, function()
	local hum = getHum()
	if S.Player.InfJump and hum then hum:ChangeState(Enum.HumanoidStateType.Jumping) end
end)

local function setFullbright(on)
	if on then
		fbOrig = fbOrig or { Lighting.Brightness, Lighting.ClockTime, Lighting.FogEnd, Lighting.GlobalShadows,
			Lighting.Ambient, Lighting.OutdoorAmbient }
		Lighting.Brightness = 2; Lighting.ClockTime = 14; Lighting.FogEnd = 1e6
		Lighting.GlobalShadows = false
		Lighting.Ambient = Color3.new(1, 1, 1); Lighting.OutdoorAmbient = Color3.new(1, 1, 1)
	elseif fbOrig then
		Lighting.Brightness, Lighting.ClockTime, Lighting.FogEnd = fbOrig[1], fbOrig[2], fbOrig[3]
		Lighting.GlobalShadows, Lighting.Ambient, Lighting.OutdoorAmbient = fbOrig[4], fbOrig[5], fbOrig[6]
		fbOrig = nil
	end
end

local okVU, VirtualUser = pcall(function() return game:GetService("VirtualUser") end)
bind(LP.Idled, function()
	if S.Misc.AntiAfk and okVU then
		pcall(function()
			VirtualUser:CaptureController()
			VirtualUser:ClickButton2(Vector2.new(0, 0))
		end)
	end
end)

bind(RunService.RenderStepped, function()
	safe("esp", espStep)
	safe("radar", radarStep)
end)
bind(RunService.Heartbeat, function()
	safe("triggerbot", triggerStep)
	safe("hitbox", hitboxStep)
	safe("player", playerStep)
	safe("fly", flyStep)
end)

---------------------------------------------------------------- config profiles (needs writefile / readfile)
local function mergeSettings(src)
	for group, vals in pairs(src) do
		local dst = S[group]
		if group ~= "Config" and type(vals) == "table" and type(dst) == "table" then
			for k, v in pairs(vals) do
				if dst[k] ~= nil and type(dst[k]) == type(v) then
					local range = sliderRanges[dst] and sliderRanges[dst][k]
					local opts = cycleOptions[dst] and cycleOptions[dst][k]
					if range then
						dst[k] = math.clamp(v, range[1], range[2])
					elseif opts then
						if table.find(opts, v) then dst[k] = v end
					else
						dst[k] = v
					end
				end
			end
		end
	end
end

local function applyAll()
	if not pcall(function() return Enum.KeyCode[S.Menu.Key] end) then S.Menu.Key = "RightShift" end
	if not isTouch then hint.Text = "Menu key: " .. S.Menu.Key end
	setFullbright(S.Visual.Fullbright)
	for _, fn in ipairs(refreshers) do fn() end
end

local function configPath()
	return "WAZY_CHEAT_V1_profile" .. S.Config.Slot .. ".json"
end

local function saveConfig()
	if not writeFile then
		notify("This executor cannot save files (no writefile).")
		return
	end
	local ok, err = pcall(function()
		writeFile(configPath(), HttpService:JSONEncode(S))
		writeFile("WAZY_CHEAT_V1_last.txt", S.Config.Slot)
	end)
	notify(ok and ("Saved profile " .. S.Config.Slot) or ("Save failed: " .. tostring(err)))
end

local function loadConfig()
	if not (readFile and isFile) then
		notify("This executor cannot read files (no readfile / isfile).")
		return
	end
	local ok, data = pcall(function()
		if not isFile(configPath()) then return nil end
		return HttpService:JSONDecode(readFile(configPath()))
	end)
	if not ok or type(data) ~= "table" then
		notify("No saved profile " .. S.Config.Slot .. " found.")
		return
	end
	mergeSettings(data)
	applyAll()
	notify("Loaded profile " .. S.Config.Slot)
end

---------------------------------------------------------------- unload
local function unload()
	S.Aim.Enabled, S.Trigger.Enabled, S.ESP.Enabled, S.Radar.Enabled = false, false, false, false
	S.Hitbox.Enabled, S.Visual.CustomFov = false, false
	S.Player.Speed, S.Player.Jump, S.Player.Noclip, S.Player.Fly = false, false, false, false
	pcall(RunService.UnbindFromRenderStep, RunService, "WAZY_AIM")
	pcall(espStep); pcall(playerStep); pcall(hitboxStep); pcall(setFullbright, false)
	pcall(function()
		local cam = Workspace.CurrentCamera
		if cam and origFov ~= nil then cam.FieldOfView = origFov; origFov = nil end
	end)
	for _, c in ipairs(conns) do c:Disconnect() end
	table.clear(conns)
	for plr in pairs(esp) do removeESP(plr) end
	gui:Destroy()
	genv.WAZY_UNLOAD = nil
end
genv.WAZY_UNLOAD = unload

---------------------------------------------------------------- tabs
local PARTS = { "Auto", "Head", "UpperTorso", "Torso", "HumanoidRootPart" }

local pAim = addTab("Aimbot")
addSection(pAim, "Targeting (shared by all modules)")
addToggle(pAim, "Team Check", S.Target, "Team")
addToggle(pAim, "Skip ForceField Players", S.Target, "SkipFF")
addSlider(pAim, "Max Distance (studs)", 50, 3000, S.Target, "MaxDist")
addSection(pAim, "Aim assist")
addToggle(pAim, "Enable Aimbot", S.Aim, "Enabled", nil, "Aimbot")
addCycle(pAim, "Aim Key", { "Right Mouse", "Left Mouse", "On-Screen Button", "Always On" }, S.Aim, "Key")
addCycle(pAim, "Aim Method", { "Camera", "Mouse Move" }, S.Aim, "Method")
addCycle(pAim, "Target Priority", { "Closest to Cursor", "Lowest Health", "Closest Distance" }, S.Aim, "Priority")
addCycle(pAim, "Target Part", PARTS, S.Aim, "Part")
addSlider(pAim, "FOV Radius (px)", 20, 600, S.Aim, "Fov")
addSlider(pAim, "Aim Speed (higher = faster)", 1, 40, S.Aim, "Speed")
addSlider(pAim, "Humanize", 0, 10, S.Aim, "Humanize")
addSlider(pAim, "Prediction (0.01 s)", 0, 30, S.Aim, "Predict")
addToggle(pAim, "Wall Check", S.Aim, "Wall")
addToggle(pAim, "Sticky Target", S.Aim, "Sticky")
addToggle(pAim, "Show FOV Circle", S.Aim, "ShowFov")
addSection(pAim, "Triggerbot")
addToggle(pAim, "Enable Triggerbot", S.Trigger, "Enabled", function(on)
	if on and not clickFn then
		notify("No click method available here: triggerbot cannot fire.")
		return false
	end
end, "Triggerbot")
addSlider(pAim, "Trigger Delay (ms)", 0, 500, S.Trigger, "DelayMs")
addSection(pAim, "Hitbox")
addToggle(pAim, "Hitbox Expander", S.Hitbox, "Enabled", nil, "Hitbox")
addSlider(pAim, "Hitbox Size", 2, 30, S.Hitbox, "Size")

local pVis = addTab("Visuals")
addSection(pVis, "ESP")
addToggle(pVis, "Enable ESP", S.ESP, "Enabled", nil, "ESP")
addToggle(pVis, "Boxes", S.ESP, "Boxes")
addToggle(pVis, "Health Bar", S.ESP, "HealthBar")
addToggle(pVis, "Tracers", S.ESP, "Tracers")
addCycle(pVis, "Tracer Starts From", { "Top", "Center", "Bottom" }, S.ESP, "TracerFrom")
addToggle(pVis, "Head Dot", S.ESP, "HeadDot")
addToggle(pVis, "Skeleton", S.ESP, "Skeleton")
addToggle(pVis, "Chams (Highlight)", S.ESP, "Chams")
addToggle(pVis, "Names", S.ESP, "Names")
addToggle(pVis, "Health Text", S.ESP, "Health")
addToggle(pVis, "Distance", S.ESP, "Distance")
addToggle(pVis, "Show Teammates", S.ESP, "Team")
addSlider(pVis, "Max ESP Distance", 100, 5000, S.ESP, "MaxDist")
addSection(pVis, "Radar")
addToggle(pVis, "Enable Radar", S.Radar, "Enabled", nil, "Radar")
addSlider(pVis, "Radar Range (studs)", 50, 500, S.Radar, "Range")
addSlider(pVis, "Radar Size", 90, 240, S.Radar, "Size")
addSection(pVis, "World / camera")
addToggle(pVis, "Fullbright", S.Visual, "Fullbright", setFullbright)
addToggle(pVis, "Custom Camera FOV", S.Visual, "CustomFov")
addSlider(pVis, "Camera FOV", 40, 120, S.Visual, "FovValue")
addToggle(pVis, "Crosshair", S.Visual, "Crosshair")
addSlider(pVis, "Crosshair Size", 3, 30, S.Visual, "CrossSize")

local pPlr = addTab("Player")
addSection(pPlr, "Movement")
addToggle(pPlr, "Speed", S.Player, "Speed", nil, "Speed")
addSlider(pPlr, "Walk Speed", 16, 150, S.Player, "SpeedValue")
addToggle(pPlr, "Jump Power", S.Player, "Jump")
addSlider(pPlr, "Jump Value", 50, 250, S.Player, "JumpValue")
addToggle(pPlr, "Infinite Jump", S.Player, "InfJump")
addToggle(pPlr, "Noclip", S.Player, "Noclip", nil, "Noclip")
addToggle(pPlr, "Fly (stick steers, jump up)", S.Player, "Fly", nil, "Fly")
addSlider(pPlr, "Fly Speed", 10, 300, S.Player, "FlySpeed")

local pMisc = addTab("Misc")
addSection(pMisc, "Utility")
addToggle(pMisc, "Anti-AFK", S.Misc, "AntiAfk")
addButton(pMisc, "Rejoin Server", function()
	pcall(function() TeleportService:Teleport(game.PlaceId, LP) end)
end)

local pSet = addTab("Settings")
addSection(pSet, "Menu")
if not isTouch then
	addCycle(pSet, "Menu Key", { "RightShift", "Insert", "Delete", "RightControl", "K", "M" }, S.Menu, "Key", function(k)
		hint.Text = "Menu key: " .. k
	end)
end
addButton(pSet, "Close Menu (W button reopens)", function() setMenu(false) end)
addSection(pSet, "Profiles")
addCycle(pSet, "Profile Slot", { "1", "2", "3" }, S.Config, "Slot")
addButton(pSet, "Save Profile", saveConfig)
addButton(pSet, "Load Profile", loadConfig)
addSection(pSet, "Errors")
local errLabel = new("TextLabel", { Size = UDim2.new(1, 0, 0, 72), BackgroundColor3 = Theme.Panel, TextWrapped = true,
	TextXAlignment = Enum.TextXAlignment.Left, TextYAlignment = Enum.TextYAlignment.Top, TextColor3 = Theme.Sub,
	Font = Enum.Font.Gotham, TextSize = 11, Text = "No errors." }, pSet)
round(errLabel, 6)
errRefresh = function()
	if #errors == 0 then
		errLabel.Text = "No errors."
	else
		errLabel.Text = table.concat(errors, "\n", math.max(1, #errors - 3), #errors)
	end
end
addButton(pSet, "Copy Errors", function()
	if setClip then
		pcall(setClip, table.concat(errors, "\n"))
		notify("Errors copied.")
	else
		notify("This executor has no clipboard function.")
	end
end)
addButton(pSet, "Clear Errors", function()
	table.clear(errors)
	table.clear(seenErrors)
	errRefresh()
end)
local function yn(v) return v and "yes" or "no" end
new("TextLabel", { Size = UDim2.new(1, 0, 0, 104), BackgroundTransparency = 1, TextWrapped = true,
	TextXAlignment = Enum.TextXAlignment.Left, TextYAlignment = Enum.TextYAlignment.Top,
	TextColor3 = Theme.Sub, Font = Enum.Font.Gotham, TextSize = 12,
	Text = "Detected on this device:\n" ..
		"Touch device: " .. yn(isTouch) .. "\n" ..
		"mousemoverel (Mouse Move aim): " .. yn(moveRel ~= nil) .. "\n" ..
		"Click for triggerbot: " .. yn(clickFn ~= nil) .. "\n" ..
		"File saving (profiles): " .. yn(writeFile ~= nil and readFile ~= nil and isFile ~= nil) .. "\n" ..
		"Clipboard: " .. yn(setClip ~= nil) }, pSet)
addButton(pSet, "Unload Cheat", unload)

selectTab("Aimbot")

-- Auto-load the profile slot saved last time (only if the executor can read files and the file exists)
if readFile and isFile then
	local okSlot, slot = pcall(function()
		if isFile("WAZY_CHEAT_V1_last.txt") then return readFile("WAZY_CHEAT_V1_last.txt") end
		return nil
	end)
	if okSlot and (slot == "1" or slot == "2" or slot == "3") then
		S.Config.Slot = slot
		local okFile, exists = pcall(isFile, configPath())
		if okFile and exists then loadConfig() else applyAll() end
	end
end

bind(UIS.InputBegan, function(i, processed)
	if isTouch then return end
	if listening then
		-- the next keyboard key becomes the bind; Escape / Backspace clears it
		if i.UserInputType == Enum.UserInputType.Keyboard then
			local id = listening
			listening = nil
			if i.KeyCode == Enum.KeyCode.Escape or i.KeyCode == Enum.KeyCode.Backspace then
				S.Binds[id] = "None"
			else
				S.Binds[id] = i.KeyCode.Name
			end
			if bindButtons[id] then bindButtons[id].Text = S.Binds[id] end
		end
		return
	end
	if processed or i.UserInputType ~= Enum.UserInputType.Keyboard then return end
	local ok, kc = pcall(function() return Enum.KeyCode[S.Menu.Key] end)
	if ok and i.KeyCode == kc then
		setMenu(not main.Visible)
		return
	end
	local name = i.KeyCode.Name
	for id, k in pairs(S.Binds) do
		if k == name and bindActions[id] then safe("keybind " .. id, bindActions[id]) end
	end
end)

notify(isTouch and "Loaded. Tap X to close the menu, the W button reopens it."
	or ("Loaded. " .. S.Menu.Key .. " or the W button opens / closes the menu."))
