local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")
local GuiService = game:GetService("GuiService")

local LocalPlayer = Players.LocalPlayer
local PlayerGui = LocalPlayer:WaitForChild("PlayerGui")

local CFG = {
    taskFPS = 30,
    poll = 0.04,

    castSettle = 0.08,
    castAfter = 0.25,
    afterMinigame = 2.0,
    collectHold = 3.0,
    afterCollect = 0.35,

    waitStart = 20.0,
    waitEnd = 120.0,
    falseStart = 2.0,
    lostTimeout = 1.5,
    startConfirmFrames = 4,

    accelHold = 900,
    accelRelease = 900,
    ballRefPx = 24,
    latency = 0.10,
    hysteresis = 6,
    aimOffset = 0,
    zoneHold = 1.0,

    keyHold = 0.1,
    rodKey = "",
    collectHoldT = true,
    tInterval = false,
    tIntervalHold = 3.0,
    tIntervalSec = 2.0,

    scanArea = {
        x = 0.20,
        y = 0.28,
        w = 0.60,
        h = 0.44,
    },

    points = {
        cast = nil,       -- {x=0..1,y=0..1}
        collect = nil,    -- {x=0..1,y=0..1}
    },

    movement = {
        enabled = false,
        w = {on = true, sec = 0.5},
        a = {on = false, sec = 0.5},
        s = {on = false, sec = 0.5},
        d = {on = false, sec = 0.5},
    },

    detector = {
        enabled = true,
        whiteMin = 0.80,
        whiteMax = 1.00,

        greenMin = 0.18,
        greenDominance = 0.05,

        maxBall = 90,
        minBall = 6,
        maxZone = 180,
        minZone = 8,
    },

    autoCollect = true,
    collectKey = "T",

    useVirtualInput = true,
}

local function clamp(v, a, b)
    return math.max(a, math.min(b, v))
end

local function lerp(a, b, t)
    return a + (b - a) * t
end

local function now()
    return os.clock()
end

local function v2(x, y)
    return Vector2.new(x, y)
end

local function center(gui)
    return gui.AbsolutePosition + gui.AbsoluteSize * 0.5
end

local function pointInside(p, pos, size, pad)
    pad = pad or 0
    return p.X >= pos.X - pad
       and p.X <= pos.X + size.X + pad
       and p.Y >= pos.Y - pad
       and p.Y <= pos.Y + size.Y + pad
end

local function rgb(c)
    return c.R, c.G, c.B
end

local function isVisible(gui)
    if not gui:IsA("GuiObject") then
        return false
    end
    if gui.AbsoluteSize.X <= 0 or gui.AbsoluteSize.Y <= 0 then
        return false
    end

    local p = gui
    while p and p ~= PlayerGui do
        if p:IsA("GuiObject") and not p.Visible then
            return false
        end
        p = p.Parent
    end

    return true
end

local function guiColor(gui)
    if gui:IsA("Frame") or gui:IsA("ScrollingFrame") then
        return gui.BackgroundColor3, gui.BackgroundTransparency
    elseif gui:IsA("ImageLabel") or gui:IsA("ImageButton") then
        return gui.ImageColor3, gui.ImageTransparency
    elseif gui:IsA("TextLabel") or gui:IsA("TextButton") then
        return gui.TextColor3, gui.TextTransparency
    end
    return nil, 1
end

local function normalizedFromScreen(p)
    local camera = workspace.CurrentCamera
    if not camera then
        return 0.5, 0.5
    end
    local vp = camera.ViewportSize
    return clamp(p.X / math.max(vp.X, 1), 0, 1),
           clamp(p.Y / math.max(vp.Y, 1), 0, 1)
end

local function screenFromNormalized(pt)
    local camera = workspace.CurrentCamera
    if not camera then
        return Vector2.zero
    end
    local vp = camera.ViewportSize
    return Vector2.new(pt.x * vp.X, pt.y * vp.Y)
end

local function inScanArea(p)
    local camera = workspace.CurrentCamera
    if not camera then return false end
    local vp = camera.ViewportSize
    local x = CFG.scanArea.x * vp.X
    local y = CFG.scanArea.y * vp.Y
    local w = CFG.scanArea.w * vp.X
    local h = CFG.scanArea.h * vp.Y
    return pointInside(p, Vector2.new(x, y), Vector2.new(w, h), 20)
end

local function waitInterruptible(seconds, shouldStop)
    local deadline = now() + math.max(0, seconds)
    while now() < deadline do
        if shouldStop and shouldStop() then
            return false
        end
        RunService.Heartbeat:Wait()
    end
    return true
end

local Input = {}

local VIM = nil
pcall(function()
    VIM = game:GetService("VirtualInputManager")
end)

function Input.tapScreen(p, hold)
    hold = hold or 0.05
    if not CFG.useVirtualInput or not VIM then
        return false
    end

    pcall(function()
        VIM:SendMouseButtonEvent(p.X, p.Y, 0, true, game, 0)
        task.wait(hold)
        VIM:SendMouseButtonEvent(p.X, p.Y, 0, false, game, 0)
    end)
    return true
end

function Input.holdScreen(p, duration, shouldStop)
    if not CFG.useVirtualInput or not VIM then
        return false
    end

    local ok = pcall(function()
        VIM:SendMouseButtonEvent(p.X, p.Y, 0, true, game, 0)
        local deadline = now() + math.max(0.05, duration)
        while now() < deadline do
            if shouldStop and shouldStop() then break end
            RunService.Heartbeat:Wait()
        end
        VIM:SendMouseButtonEvent(p.X, p.Y, 0, false, game, 0)
    end)

    return ok
end

function Input.mouse(down, p)
    if not CFG.useVirtualInput or not VIM then
        return false
    end

    p = p or Vector2.zero
    local ok = pcall(function()
        VIM:SendMouseButtonEvent(p.X, p.Y, 0, down, game, 0)
    end)
    return ok
end

function Input.key(key, down)
    if not CFG.useVirtualInput or not VIM then
        return false
    end

    local ok = pcall(function()
        local keyCode = Enum.KeyCode[key]
        if keyCode then
            VIM:SendKeyEvent(down, keyCode, false, game)
        end
    end)

    return ok
end

function Input.holdKey(key, duration, shouldStop)
    if not Input.key(key, true) then
        return false
    end

    waitInterruptible(duration, shouldStop)
    Input.key(key, false)
    return true
end

function Input.releaseAll()
    for _, k in ipairs({"W", "A", "S", "D", "T"}) do
        pcall(function()
            Input.key(k, false)
        end)
    end

    pcall(function()
        if VIM then
            VIM:SendMouseButtonEvent(0, 0, 0, false, game, 0)
        end
    end)
end

local Detector = {}
Detector.__index = Detector

function Detector.new()
    return setmetatable({
        descendants = {},
        lastRefresh = 0,
        previous = nil,
        lock = nil,
        hits = 0,
        bestScore = 0,
        reason = "",
    }, Detector)
end

function Detector:refresh()
    local t = now()
    if t - self.lastRefresh < 0.35 then
        return
    end

    self.lastRefresh = t
    self.descendants = PlayerGui:GetDescendants()
end

local function whiteScore(gui, color, transparency)
    if not color or transparency > 0.35 then
        return 0
    end

    local r, g, b = rgb(color)
    local mn = math.min(r, g, b)
    local mx = math.max(r, g, b)
    local spread = mx - mn

    if mn < CFG.detector.whiteMin or mx > CFG.detector.whiteMax then
        return 0
    end

    if spread > 0.15 then
        return 0
    end

    local s = gui.AbsoluteSize
    if s.X < CFG.detector.minBall
       or s.Y < CFG.detector.minBall
       or s.X > CFG.detector.maxBall
       or s.Y > CFG.detector.maxBall then
        return 0
    end

    local ratio = s.X / math.max(s.Y, 1)
    if ratio < 0.55 or ratio > 1.8 then
        return 0
    end

    return 1 - math.abs(1 - ratio) * 0.35
end

local function zoneScore(gui, color, transparency)
    if not color or transparency > 0.5 then
        return 0
    end

    local r, g, b = rgb(color)
    local green = g - math.max(r, b)

    local cyan = math.min(g, b) - r
    local score = math.max(green, cyan)

    local s = gui.AbsoluteSize
    if s.X < CFG.detector.minZone
       or s.X > CFG.detector.maxZone
       or s.Y < 3
       or s.Y > CFG.detector.maxZone then
        return 0
    end

    if score < CFG.detector.greenDominance then
        return 0
    end

    return score
end

function Detector:find()
    if not CFG.detector.enabled then
        return nil
    end

    self:refresh()

    local balls = {}
    local zones = {}

    for _, gui in ipairs(self.descendants) do
        if isVisible(gui) then
            local color, transparency = guiColor(gui)
            local ws = whiteScore(gui, color, transparency)

            if ws > 0 then
                local c = center(gui)
                if inScanArea(c) then
                    table.insert(balls, {
                        gui = gui,
                        p = c,
                        size = gui.AbsoluteSize,
                        score = ws,
                    })
                end
            end

            local zs = zoneScore(gui, color, transparency)
            if zs > 0 then
                local c = center(gui)
                if inScanArea(c) then
                    table.insert(zones, {
                        gui = gui,
                        p = c,
                        size = gui.AbsoluteSize,
                        score = zs,
                    })
                end
            end
        end
    end

    if #balls == 0 then
        self.reason = "no white square"
        return nil
    end

    table.sort(balls, function(a, b)
        if self.previous then
            local da = (a.p - self.previous.ball).Magnitude
            local db = (b.p - self.previous.ball).Magnitude
            return da < db
        end
        return a.score > b.score
    end)

    local ball = balls[1]
    local bestZone = nil
    local bestZoneScore = -math.huge

    for _, z in ipairs(zones) do
        local dx = math.abs(z.p.X - ball.p.X)
        local dy = math.abs(z.p.Y - ball.p.Y)

        if dx <= math.max(180, ball.size.X * 8)
           and dy <= math.max(180, ball.size.Y * 8) then
            local s = z.score
            if self.previous then
                s = s + 0.25 / (1 + (z.p.Y - self.previous.ball.Y) ^ 2 * 0.0001)
            end
            if s > bestZoneScore then
                bestZoneScore = s
                bestZone = z
            end
        end
    end

    local result = {
        ballX = ball.p.X,
        ballY = ball.p.Y,
        ballW = ball.size.X,
        ballH = ball.size.Y,
        zoneX0 = nil,
        zoneX1 = nil,
        zoneTop = nil,
        zoneBot = nil,
        hasZone = false,
    }

    if bestZone then
        local p = bestZone.gui.AbsolutePosition
        local s = bestZone.gui.AbsoluteSize

        result.zoneX0 = p.X
        result.zoneX1 = p.X + s.X
        result.zoneTop = p.Y
        result.zoneBot = p.Y + s.Y
        result.hasZone = true
    end

    self.previous = {
        ball = ball.p,
        result = result,
    }

    return result
end

local Motion = {}
Motion.__index = Motion

function Motion.new(alpha, beta)
    return setmetatable({
        alpha = alpha or 0.8,
        beta = beta or 0.6,
        y = nil,
        v = 0,
        t = now(),
    }, Motion)
end

function Motion:reset(y, t)
    self.y = y
    self.v = 0
    self.t = t
end

function Motion:predict(t, a)
    if self.y == nil then
        return 0, 0
    end
    local dt = math.max(0, t - self.t)
    return self.y + self.v * dt + 0.5 * a * dt * dt,
           self.v + a * dt
end

function Motion:update(measured, t, a, jump)
    if self.y == nil then
        self:reset(measured, t)
        return
    end

    local yp, vp = self:predict(t, a)
    local dt = math.max(0.001, t - self.t)
    local r = measured - yp

    if math.abs(r) > jump then
        self.y = measured
        self.v = vp
    else
        self.y = yp + self.alpha * r
        self.v = vp + self.beta * r / dt
    end

    self.t = t
end

local Tracker = {}
Tracker.__index = Tracker

function Tracker.new()
    local self = setmetatable({}, Tracker)
    self:reset()
    return self
end

function Tracker:reset()
    self.ball = Motion.new(0.8, 0.6)
    self.zone = Motion.new(0.6, 0.3)
    self.held = false
    self.bh = 0
    self.zoneSeen = 0
    self.lastRead = nil
    self.lastNew = 0
end

function Tracker:start(ballY, zoneY, ballH, t)
    self:reset()
    self.ball:reset(ballY, t)
    self.zone:reset(zoneY or ballY, t)
    self.bh = ballH
    self.zoneSeen = t
end

function Tracker:observe(ballY, ballH, zoneTop, zoneY, t)
    if self.bh > 0 then
        self.bh = self.bh * 0.8 + ballH * 0.2
    else
        self.bh = ballH
    end

    local readKey = tostring(math.floor(ballY * 10) / 10) .. ":" .. tostring(zoneTop)
    local same = readKey == self.lastRead and t - self.lastNew < 0.15

    if not same then
        self.lastRead = readKey
        self.lastNew = t

        local s = self.bh / math.max(1, CFG.ballRefPx)
        local accel = self.held and (-CFG.accelHold * s) or (CFG.accelRelease * s)

        self.ball:update(ballY, t, accel, 4 * self.bh)

        if zoneY then
            self.zone:update(zoneY, t, 0, 4 * self.bh)
            self.zoneSeen = t
        end
    end
end

function Tracker:decide(t)
    if t - self.zoneSeen > CFG.zoneHold then
        self.held = false
        return nil
    end

    if t - self.zoneSeen > 0.1 then
        self.zone.v = 0
    end

    local s = self.bh / math.max(1, CFG.ballRefPx)
    local aUp = CFG.accelHold * s
    local aDown = CFG.accelRelease * s
    local aNow = self.held and -aUp or aDown

    local y, v = self.ball:predict(t + CFG.latency, aNow)
    local ty, tv = self.zone:predict(t + CFG.latency, 0)

    local target = ty + CFG.aimOffset * self.bh
    local vRel = v - tv

    local stop
    if vRel < 0 then
        stop = y - vRel * vRel / math.max(1, 2 * aDown)
    else
        stop = y + vRel * vRel / math.max(1, 2 * aUp)
    end

    local band = CFG.hysteresis * s

    if self.held then
        self.held = stop > target - band
    else
        self.held = stop > target + band
    end

    return self.held
end

local UI = {}
UI.__index = UI

function UI.new()
    local self = setmetatable({}, UI)

    local gui = Instance.new("ScreenGui")
    gui.Name = "Slayers2FishingMobile"
    gui.ResetOnSpawn = false
    gui.IgnoreGuiInset = true
    gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
    gui.Parent = PlayerGui

    self.gui = gui

    local shadow = Instance.new("Frame")
    shadow.Name = "Shadow"
    shadow.AnchorPoint = Vector2.new(0.5, 0.5)
    shadow.Position = UDim2.fromScale(0.5, 0.52)
    shadow.Size = UDim2.fromScale(0.90, 0.64)
    shadow.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
    shadow.BackgroundTransparency = 0.55
    shadow.BorderSizePixel = 0
    shadow.Parent = gui

    local main = Instance.new("Frame")
    main.Name = "Main"
    main.AnchorPoint = Vector2.new(0.5, 0.5)
    main.Position = UDim2.fromScale(0.5, 0.50)
    main.Size = UDim2.fromScale(0.88, 0.62)
    main.BackgroundColor3 = Color3.fromRGB(18, 22, 31)
    main.BorderSizePixel = 0
    main.ClipsDescendants = true
    main.Parent = gui

    local corner = Instance.new("UICorner")
    corner.CornerRadius = UDim.new(0, 18)
    corner.Parent = main

    local stroke = Instance.new("UIStroke")
    stroke.Color = Color3.fromRGB(64, 82, 112)
    stroke.Thickness = 1
    stroke.Transparency = 0.25
    stroke.Parent = main

    local top = Instance.new("Frame")
    top.Size = UDim2.new(1, 0, 0, 54)
    top.BackgroundColor3 = Color3.fromRGB(25, 31, 44)
    top.BorderSizePixel = 0
    top.Parent = main

    local title = Instance.new("TextLabel")
    title.BackgroundTransparency = 1
    title.Position = UDim2.fromOffset(16, 8)
    title.Size = UDim2.new(1, -100, 0, 22)
    title.Font = Enum.Font.GothamBold
    title.Text = "SLAYERS 2"
    title.TextColor3 = Color3.fromRGB(235, 241, 255)
    title.TextSize = 17
    title.TextXAlignment = Enum.TextXAlignment.Left
    title.Parent = top

    local subtitle = Instance.new("TextLabel")
    subtitle.BackgroundTransparency = 1
    subtitle.Position = UDim2.fromOffset(17, 29)
    subtitle.Size = UDim2.new(1, -110, 0, 18)
    subtitle.Font = Enum.Font.Gotham
    subtitle.Text = "Fishing • Mobile Edition"
    subtitle.TextColor3 = Color3.fromRGB(142, 158, 184)
    subtitle.TextSize = 10
    subtitle.TextXAlignment = Enum.TextXAlignment.Left
    subtitle.Parent = top

    local minimize = Instance.new("TextButton")
    minimize.AnchorPoint = Vector2.new(1, 0.5)
    minimize.Position = UDim2.new(1, -14, 0.5, 0)
    minimize.Size = UDim2.fromOffset(36, 32)
    minimize.BackgroundColor3 = Color3.fromRGB(35, 43, 59)
    minimize.Text = "—"
    minimize.TextColor3 = Color3.fromRGB(220, 228, 242)
    minimize.TextSize = 18
    minimize.Font = Enum.Font.GothamBold
    minimize.Parent = top

    local mc = Instance.new("UICorner")
    mc.CornerRadius = UDim.new(0, 10)
    mc.Parent = minimize

    local tabs = Instance.new("Frame")
    tabs.Position = UDim2.fromOffset(12, 64)
    tabs.Size = UDim2.new(1, -24, 0, 38)
    tabs.BackgroundTransparency = 1
    tabs.Parent = main

    local content = Instance.new("Frame")
    content.Position = UDim2.fromOffset(12, 108)
    content.Size = UDim2.new(1, -24, 1, -160)
    content.BackgroundTransparency = 1
    content.Parent = main

    local footer = Instance.new("TextLabel")
    footer.AnchorPoint = Vector2.new(0.5, 1)
    footer.Position = UDim2.new(0.5, 0, 1, -8)
    footer.Size = UDim2.new(1, -28, 0, 20)
    footer.BackgroundTransparency = 1
    footer.Font = Enum.Font.Gotham
    footer.Text = "Idle"
    footer.TextColor3 = Color3.fromRGB(126, 143, 168)
    footer.TextSize = 10
    footer.Parent = main

    self.main = main
    self.content = content
    self.footer = footer
    self.minimize = minimize
    self.tabs = tabs
    self.tabButtons = {}
    self.pages = {}

    local dragging = false
    local dragStart
    local startPos

    top.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.Touch
           or input.UserInputType == Enum.UserInputType.MouseButton1 then
            dragging = true
            dragStart = input.Position
            startPos = main.Position
        end
    end)

    UserInputService.InputChanged:Connect(function(input)
        if dragging and (input.UserInputType == Enum.UserInputType.Touch
            or input.UserInputType == Enum.UserInputType.MouseMovement) then
            local delta = input.Position - dragStart
            main.Position = UDim2.new(
                startPos.X.Scale, startPos.X.Offset + delta.X,
                startPos.Y.Scale, startPos.Y.Offset + delta.Y
            )
            shadow.Position = main.Position + UDim2.fromOffset(0, 7)
        end
    end)

    UserInputService.InputEnded:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.Touch
           or input.UserInputType == Enum.UserInputType.MouseButton1 then
            dragging = false
        end
    end)

    local minimized = false
    minimize.Activated:Connect(function()
        minimized = not minimized
        content.Visible = not minimized
        tabs.Visible = not minimized
        footer.Visible = not minimized
        main.Size = minimized and UDim2.fromScale(0.88, 0.11) or UDim2.fromScale(0.88, 0.62)
        shadow.Size = minimized and UDim2.fromScale(0.90, 0.13) or UDim2.fromScale(0.90, 0.64)
    end)

    return self
end

function UI:label(parent, text, y, size)
    local l = Instance.new("TextLabel")
    l.BackgroundTransparency = 1
    l.Position = UDim2.new(0, 4, 0, y)
    l.Size = UDim2.new(1, -8, 0, size or 24)
    l.Font = Enum.Font.Gotham
    l.Text = text
    l.TextColor3 = Color3.fromRGB(162, 176, 199)
    l.TextSize = 11
    l.TextXAlignment = Enum.TextXAlignment.Left
    l.Parent = parent
    return l
end

function UI:button(parent, text, pos, size, callback)
    local b = Instance.new("TextButton")
    b.Position = pos
    b.Size = size
    b.BackgroundColor3 = Color3.fromRGB(35, 43, 59)
    b.BorderSizePixel = 0
    b.Font = Enum.Font.GothamSemibold
    b.Text = text
    b.TextColor3 = Color3.fromRGB(224, 232, 247)
    b.TextSize = 11
    b.AutoButtonColor = false
    b.Parent = parent

    local c = Instance.new("UICorner")
    c.CornerRadius = UDim.new(0, 10)
    c.Parent = b

    local s = Instance.new("UIStroke")
    s.Color = Color3.fromRGB(61, 75, 101)
    s.Transparency = 0.35
    s.Parent = b

    b.Activated:Connect(function()
        TweenService:Create(b, TweenInfo.new(0.08), {
            BackgroundColor3 = Color3.fromRGB(52, 64, 86)
        }):Play()
        task.delay(0.09, function()
            if b.Parent then
                TweenService:Create(b, TweenInfo.new(0.12), {
                    BackgroundColor3 = Color3.fromRGB(35, 43, 59)
                }):Play()
            end
        end)
        if callback then callback() end
    end)

    return b
end

function UI:tab(name, index, callback)
    local b = self:button(
        self.tabs,
        name,
        UDim2.new((index - 1) / 3, 3, 0, 0),
        UDim2.new(1 / 3, -6, 1, 0),
        callback
    )
    self.tabButtons[name] = b
    return b
end

function UI:page(name)
    local p = Instance.new("Frame")
    p.Name = name
    p.Size = UDim2.fromScale(1, 1)
    p.BackgroundTransparency = 1
    p.Visible = false
    p.Parent = self.content
    self.pages[name] = p
    return p
end

function UI:show(name)
    for n, p in pairs(self.pages) do
        p.Visible = n == name
    end
    for n, b in pairs(self.tabButtons) do
        b.BackgroundColor3 = n == name
            and Color3.fromRGB(52, 72, 104)
            or Color3.fromRGB(35, 43, 59)
    end
end

function UI:status(text)
    self.footer.Text = text
end

local App = {}
App.__index = App

function App.new()
    local self = setmetatable({}, App)

    self.ui = UI.new()
    self.detector = Detector.new()
    self.tracker = Tracker.new()

    self.running = false
    self.phase = "Idle"
    self.startedAt = 0
    self.catches = 0
    self.lastGame = nil
    self.hits = 0
    self.stopToken = 0
    self.manualAssist = false
    self.tIntervalBusy = false
    self.tIntervalToken = 0
    self.questRunning = false
    self.questToken = 0

    self:_buildPages()
    self.ui:show("Fishing")

    return self
end

function App:_buildPages()
    local ui = self.ui

    local fishing = ui:page("Fishing")
    ui:tab("Fishing", 1, function()
        ui:show("Fishing")
    end)

    local quest = ui:page("Quest")
    ui:tab("Quest", 2, function()
        ui:show("Quest")
    end)

    local settings = ui:page("Settings")
    ui:tab("Settings", 3, function()
        ui:show("Settings")
    end)

    ui:label(fishing, "AUTOMATION", 4, 22)

    local state = Instance.new("TextLabel")
    state.BackgroundTransparency = 1
    state.Position = UDim2.fromOffset(4, 30)
    state.Size = UDim2.new(1, -8, 0, 42)
    state.Font = Enum.Font.GothamBold
    state.Text = "READY"
    state.TextColor3 = Color3.fromRGB(103, 206, 165)
    state.TextSize = 25
    state.TextXAlignment = Enum.TextXAlignment.Left
    state.Parent = fishing
    self.stateLabel = state

    local stats = Instance.new("TextLabel")
    stats.BackgroundTransparency = 1
    stats.Position = UDim2.fromOffset(4, 73)
    stats.Size = UDim2.new(1, -8, 0, 34)
    stats.Font = Enum.Font.Gotham
    stats.Text = "Catches: 0   •   Detector: GUI"
    stats.TextColor3 = Color3.fromRGB(142, 158, 184)
    stats.TextSize = 10
    stats.TextXAlignment = Enum.TextXAlignment.Left
    stats.Parent = fishing
    self.statsLabel = stats

    self.startButton = ui:button(
        fishing,
        "START FISHING",
        UDim2.new(0, 4, 0, 115),
        UDim2.new(0.60, -6, 0, 48),
        function()
            self:setRunning(not self.running)
        end
    )

    ui:button(
        fishing,
        "SCAN",
        UDim2.new(0.60, 6, 0, 115),
        UDim2.new(0.40, -10, 0, 48),
        function()
            local g = self.detector:find()
            if g then
                ui:status(string.format("Found • ball %.0f,%.0f", g.ballX, g.ballY))
            else
                ui:status("No minigame found in scan area")
            end
        end
    )

    ui:label(fishing, "POINTS", 176, 22)

    ui:button(
        fishing, "SET CAST POINT",
        UDim2.new(0, 4, 0, 202),
        UDim2.new(0.5, -8, 0, 40),
        function()
            self:capturePoint("cast")
        end
    )

    ui:button(
        fishing, "SET COLLECT POINT",
        UDim2.new(0.5, 4, 0, 202),
        UDim2.new(0.5, -8, 0, 40),
        function()
            self:capturePoint("collect")
        end
    )

    local pInfo = ui:label(fishing, "Cast: not set   •   Collect: not set", 248, 34)
    pInfo.TextWrapped = true
    self.pointLabel = pInfo

    ui:button(
        fishing, "MANUAL ASSIST",
        UDim2.new(0, 4, 0, 292),
        UDim2.new(1, -8, 0, 38),
        function()
            self.manualAssist = not self.manualAssist
            ui:status(self.manualAssist and "Manual assist ON" or "Manual assist OFF")
        end
    )

    ui:label(quest, "QUEST CYCLE", 4, 24)
    ui:label(quest, "45/60 quest flow: T → dialogue clicks → accept → move out → hold T → move back → complete → exit.", 31, 42)

    ui:button(quest, "QUEST: START / STOP", UDim2.new(0, 4, 0, 84), UDim2.new(1, -8, 0, 44), function()
        self:setQuestRunning(not self.questRunning)
    end)

    ui:button(quest, "CAPTURE DIALOGUE", UDim2.new(0, 4, 0, 138), UDim2.new(0.5, -8, 0, 36), function()
        self:capturePoint("quest_dialogue")
    end)
    ui:button(quest, "CAPTURE ACCEPT", UDim2.new(0.5, 4, 0, 138), UDim2.new(0.5, -8, 0, 36), function()
        self:capturePoint("quest_accept")
    end)
    ui:button(quest, "CAPTURE COMPLETE", UDim2.new(0, 4, 0, 182), UDim2.new(0.5, -8, 0, 36), function()
        self:capturePoint("quest_complete")
    end)
    ui:button(quest, "CAPTURE EXIT", UDim2.new(0.5, 4, 0, 182), UDim2.new(0.5, -8, 0, 36), function()
        self:capturePoint("quest_exit")
    end)
    ui:button(quest, "CAPTURE LVL 60", UDim2.new(0, 4, 0, 226), UDim2.new(0.5, -8, 0, 36), function()
        self:capturePoint("quest_lvl60")
    end)
    ui:button(quest, "RESET INPUTS", UDim2.new(0.5, 4, 0, 226), UDim2.new(0.5, -8, 0, 36), function()
        Input.releaseAll()
        ui:status("Inputs released.")
    end)

    ui:label(quest, "Capture each dialogue point by opening the corresponding Roblox UI, then touching the button itself. For movement, enable W/A/S/D in Settings/code config.", 272, 56)

    ui:label(settings, "TRACK CONTROLLER", 4, 24)
    ui:label(settings, string.format(
        "Latency %.2fs   •   Hysteresis %.1f   •   Hold accel %.0f",
        CFG.latency, CFG.hysteresis, CFG.accelHold
    ), 31, 24)

    ui:button(settings, "LATENCY  -", UDim2.new(0, 4, 0, 66), UDim2.new(0.5, -8, 0, 38), function()
        CFG.latency = clamp(CFG.latency - 0.01, 0, 0.5)
        ui:status("Latency: " .. string.format("%.2f", CFG.latency))
    end)

    ui:button(settings, "LATENCY  +", UDim2.new(0.5, 4, 0, 66), UDim2.new(0.5, -8, 0, 38), function()
        CFG.latency = clamp(CFG.latency + 0.01, 0, 0.5)
        ui:status("Latency: " .. string.format("%.2f", CFG.latency))
    end)

    ui:button(settings, "HYSTERESIS  -", UDim2.new(0, 4, 0, 112), UDim2.new(0.5, -8, 0, 38), function()
        CFG.hysteresis = clamp(CFG.hysteresis - 1, 0, 20)
        ui:status("Hysteresis: " .. string.format("%.1f", CFG.hysteresis))
    end)

    ui:button(settings, "HYSTERESIS  +", UDim2.new(0.5, 4, 0, 112), UDim2.new(0.5, -8, 0, 38), function()
        CFG.hysteresis = clamp(CFG.hysteresis + 1, 0, 20)
        ui:status("Hysteresis: " .. string.format("%.1f", CFG.hysteresis))
    end)

    ui:button(settings, "SCAN WIDTH  -", UDim2.new(0, 4, 0, 158), UDim2.new(0.5, -8, 0, 38), function()
        CFG.scanArea.w = clamp(CFG.scanArea.w - 0.05, 0.2, 1)
        ui:status("Scan width: " .. string.format("%.0f%%", CFG.scanArea.w * 100))
    end)

    ui:button(settings, "SCAN WIDTH  +", UDim2.new(0.5, 4, 0, 158), UDim2.new(0.5, -8, 0, 38), function()
        CFG.scanArea.w = clamp(CFG.scanArea.w + 0.05, 0.2, 1)
        ui:status("Scan width: " .. string.format("%.0f%%", CFG.scanArea.w * 100))
    end)

    ui:button(settings, "COLLECT: T / CLICK", UDim2.new(0, 4, 0, 204), UDim2.new(1, -8, 0, 38), function()
        CFG.collectHoldT = not CFG.collectHoldT
        ui:status(CFG.collectHoldT and "Collect mode: T" or "Collect mode: click point")
    end)

    ui:button(settings, "T INTERVAL: ON / OFF", UDim2.new(0, 4, 0, 250), UDim2.new(1, -8, 0, 38), function()
        CFG.tInterval = not CFG.tInterval
        if CFG.tInterval then
            self:startTInterval()
        else
            self.tIntervalToken += 1
        end
        ui:status(CFG.tInterval and "T interval enabled" or "T interval disabled")
    end)

    ui:button(settings, "RESET TRACKER", UDim2.new(0, 4, 0, 296), UDim2.new(1, -8, 0, 38), function()
        self.tracker:reset()
        self.detector.previous = nil
        ui:status("Tracker reset.")
    end)

    ui:button(settings, "RELEASE ALL INPUTS", UDim2.new(0, 4, 0, 342), UDim2.new(1, -8, 0, 38), function()
        Input.releaseAll()
        ui:status("All synthetic inputs released.")
    end)
end

function App:capturePoint(name)
    self.ui:status("Tap the " .. name .. " location...")

    local conn
    conn = UserInputService.InputBegan:Connect(function(input, processed)
        if processed then return end
        if input.UserInputType ~= Enum.UserInputType.Touch
           and input.UserInputType ~= Enum.UserInputType.MouseButton1 then
            return
        end

        local x, y = normalizedFromScreen(input.Position)
        CFG.points[name] = {x = x, y = y}

        self.pointLabel.Text = string.format(
            "Cast: %s   •   Collect: %s",
            CFG.points.cast and string.format("%.2f, %.2f", CFG.points.cast.x, CFG.points.cast.y) or "not set",
            CFG.points.collect and string.format("%.2f, %.2f", CFG.points.collect.x, CFG.points.collect.y) or "not set"
        )

        self.ui:status(name .. " point saved.")
        conn:Disconnect()
    end)
end

function App:setState(text, color)
    self.phase = text
    self.stateLabel.Text = text
    self.stateLabel.TextColor3 = color or Color3.fromRGB(103, 206, 165)
end

function App:cast()
    if not CFG.points.cast then
        self.ui:status("Set Cast Point first.")
        return false
    end

    self:setState("CASTING", Color3.fromRGB(111, 173, 235))
    local p = screenFromNormalized(CFG.points.cast)
    Input.tapScreen(p, CFG.castSettle)
    return waitInterruptible(CFG.castAfter, function()
        return not self.running
    end)
end

function App:collect()
    self:setState("COLLECTING", Color3.fromRGB(235, 193, 103))

    self.tIntervalBusy = true
    if CFG.collectHoldT then
        Input.holdKey("T", CFG.collectHold, function()
            return not self.running
        end)
    elseif CFG.points.collect then
        Input.holdScreen(
            screenFromNormalized(CFG.points.collect),
            CFG.collectHold,
            function() return not self.running end
        )
    end
    self.tIntervalBusy = false

    return waitInterruptible(CFG.afterCollect, function()
        return not self.running
    end)
end

function App:move()
    if not CFG.movement.enabled then
        return true
    end

    local keys = {}
    for _, key in ipairs({"w", "a", "s", "d"}) do
        local m = CFG.movement[key]
        if m.on and m.sec > 0 then
            keys[string.upper(key)] = m.sec
        end
    end

    if next(keys) == nil then
        return true
    end

    self.tIntervalBusy = true
    local aborted = false
    for key, duration in pairs(keys) do
        if not Input.holdKey(key, duration, function()
            return not self.running
        end) then
        else
            aborted = true
            break
        end
    end
    self.tIntervalBusy = false
    return not aborted and self.running
end

function App:startTInterval()
    if not CFG.tInterval then return end
    self.tIntervalToken += 1
    local token = self.tIntervalToken
    task.spawn(function()
        while self.running and token == self.tIntervalToken do
            task.wait(math.max(0.1, CFG.tIntervalSec))
            if not self.running or token ~= self.tIntervalToken then break end
            if self.tIntervalBusy then continue end
            Input.holdKey("T", CFG.tIntervalHold, function()
                return not self.running or self.tIntervalBusy
            end)
        end
    end)
end

function App:runMinigame()
    self:setState("WAITING", Color3.fromRGB(153, 165, 185))

    local startDeadline = now() + CFG.waitStart
    local endDeadline = now() + CFG.waitEnd
    local started = false
    local real = false
    local hits = 0
    local zoneFrames = 0
    local zoneLast = now()
    local lastSeen = now()
    local lastGame = nil
    local near = nil
    local holding = false

    self.tracker:reset()
    self.detector.previous = nil

    while self.running do
        local t0 = now()
        local game = self.detector:find()

        if not started then
            if game and game.hasZone then
                local same = false
                if lastGame then
                    local d = math.abs(game.ballX - lastGame.ballX)
                    local dh = math.abs(game.ballH - lastGame.ballH)
                    same = d <= math.max(8, game.ballW)
                        and dh <= math.max(4, game.ballH * 0.30)
                end

                hits = same and hits + 1 or 1
                if hits >= CFG.startConfirmFrames then
                    started = true
                    real = false
                    zoneFrames = 1
                    zoneLast = t0
                    lastSeen = t0
                    endDeadline = t0 + CFG.waitEnd
                    self.tracker:start(
                        game.ballY,
                        game.zoneY,
                        game.ballH,
                        t0
                    )
                    self:setState("TRACKING", Color3.fromRGB(93, 202, 159))
                end
            else
                hits = 0
            end

            lastGame = game

            if not started and t0 >= startDeadline then
                self:setState("FAIL CAST", Color3.fromRGB(235, 105, 105))
                Input.releaseAll()
                return false
            end
        else
            if game == nil then
                if real and t0 - lastSeen > CFG.lostTimeout then
                    Input.releaseAll()
                    self:setState("CAUGHT", Color3.fromRGB(103, 206, 165))
                    return true
                end

                if t0 - lastSeen > 0.30 and holding then
                    Input.mouse(false, near or Vector2.zero)
                    holding = false
                end
            else
                lastSeen = t0
                near = Vector2.new(game.ballX, game.ballY)

                if game.hasZone then
                    zoneFrames += 1
                    zoneLast = t0
                end

                self.tracker:observe(
                    game.ballY,
                    game.ballH,
                    game.zoneTop,
                    game.zoneY,
                    t0
                )

                local wantHold = self.tracker:decide(t0)
                if wantHold ~= nil then
                    real = zoneFrames >= CFG.startConfirmFrames
                    if wantHold and not holding then
                        Input.mouse(true, near)
                        holding = true
                    elseif not wantHold and holding then
                        Input.mouse(false, near)
                        holding = false
                    end
                end
            end

            if not real and t0 - zoneLast > CFG.falseStart then
                if holding then
                    Input.mouse(false, near or Vector2.zero)
                    holding = false
                end
                started = false
                hits = 0
                lastGame = nil
                near = nil
                zoneFrames = 0
                startDeadline = math.max(startDeadline, t0 + CFG.falseStart)
                self:setState("FALSE START", Color3.fromRGB(235, 193, 103))
            elseif t0 >= endDeadline then
                if holding then
                    Input.mouse(false, near or Vector2.zero)
                    holding = false
                end
                self:setState("MINIGAME TIMEOUT", Color3.fromRGB(235, 193, 103))
                return true
            end
        end

        local work = now() - t0
        local budget = 1 / CFG.taskFPS
        if not started and not hits then
            budget = math.max(budget, 0.10)
        end
        if budget > work then
            task.wait(budget - work)
        else
            task.wait()
        end
    end

    Input.releaseAll()
    return false
end

function App:cycle()
    while self.running do
        if not self:cast() then
            break
        end

        if not self:runMinigame() then
            task.wait(0.5)
            if self.running then
                continue
            end
            break
        end

        if not self.running then break end

        self.catches += 1
        self.statsLabel.Text = string.format(
            "Catches: %d   •   Detector: %s",
            self.catches,
            CFG.detector.enabled and "GUI" or "OFF"
        )

        waitInterruptible(CFG.afterMinigame, function()
            return not self.running
        end)

        if not self.running then break end

        if CFG.autoCollect then
            if not self:collect() then
                break
            end
        end

        if not self:move() then
            break
        end

        self:setState("NEXT CAST", Color3.fromRGB(111, 173, 235))
        task.wait(0.15)
    end

    Input.releaseAll()

    if not self.running then
        self:setState("STOPPED", Color3.fromRGB(235, 105, 105))
    end
end

function App:questPointSet(key)
    return CFG.points[key] ~= nil
end

function App:questClick(key, count)
    local pt = CFG.points[key]
    if not pt then
        self.ui:status("Quest point missing: " .. key)
        return false
    end

    for _ = 1, count do
        if not self.questRunning then return false end
        Input.tapScreen(screenFromNormalized(pt), CFG.keyHold)
        if not waitInterruptible(0.5, function() return not self.questRunning end) then
            return false
        end
    end
    return true
end

function App:questMove(side)
    local movement = CFG.movement
    if not movement.enabled then return true end
    for _, key in ipairs({"w", "a", "s", "d"}) do
        local m = movement[key]
        if m.on and m.sec > 0 then
            if not Input.holdKey(string.upper(key), m.sec, function()
                return not self.questRunning
            end) then
                return false
            end
        end
    end
    return true
end

function App:setQuestRunning(value)
    if value then
        if self.questRunning then return end
        self.questRunning = true
        self.questToken += 1
        local token = self.questToken
        self.ui:status("Quest started.")

        task.spawn(function()
            local dialogueClicks = 6
            local questLevel = 45

            local function stopCheck()
                return not self.questRunning or token ~= self.questToken
            end

            local function wait(s)
                return waitInterruptible(s, stopCheck)
            end

            local ok = true
            ok = ok and self:questClick("quest_dialogue", dialogueClicks)
            ok = ok and wait(0.5)

            if ok and questLevel == 60 then
                ok = self:questClick("quest_lvl60", 1)
                ok = ok and self:questClick("quest_dialogue", dialogueClicks)
            end

            ok = ok and self:questClick("quest_accept", 1)
            ok = ok and wait(0.5)
            ok = ok and self:questMove("out")
            ok = ok and wait(0.5)

            if ok then
                self.ui:status("Quest: holding T...")
                Input.holdKey("T", 3.0, stopCheck)
                ok = not stopCheck()
            end

            ok = ok and self:questMove("back")
            ok = ok and wait(0.5)
            ok = ok and self:questClick("quest_dialogue", dialogueClicks)
            ok = ok and self:questClick("quest_complete", 1)
            ok = ok and self:questClick("quest_exit", 1)
            ok = ok and wait(0.5)

            if token == self.questToken then
                self.questRunning = false
                self.ui:status(ok and "Quest cycle complete." or "Quest stopped / point missing.")
            end
        end)
    else
        self.questRunning = false
        self.questToken += 1
        Input.releaseAll()
        self.ui:status("Quest stopped.")
    end
end

function App:setRunning(value)
    if value then
        if self.running then return end
        self.running = true
        self.stopToken += 1
        self.startedAt = now()
        self.startButton.Text = "STOP FISHING"
        self.ui:status("Fishing started.")
        self:startTInterval()
        task.spawn(function()
            local token = self.stopToken
            self:cycle()
            if token == self.stopToken then
                self.startButton.Text = "START FISHING"
            end
        end)
    else
        self.running = false
        self.stopToken += 1
        self.tIntervalToken += 1
        Input.releaseAll()
        self.startButton.Text = "START FISHING"
        self:setState("STOPPED", Color3.fromRGB(235, 105, 105))
        self.ui:status("Stopped and released inputs.")
    end
end

local app = App.new()

UserInputService.InputBegan:Connect(function(input, processed)
    if processed then return end

    if input.KeyCode == Enum.KeyCode.F8 then
        app:setRunning(false)
    end
end)

game:GetService("GuiService").MenuOpened:Connect(function()
    if app.running then
        Input.releaseAll()
    end
end)

print("[Slayers2FishingMobile] loaded.")
