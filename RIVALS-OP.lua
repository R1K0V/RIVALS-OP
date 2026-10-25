--[[
    RIVALS HUB — PATCHED + FOV + MISC + UNLOCK ALL + CONFIG
    Aimbot sticky head | Silent Aim | ESP | Filter Lobby
    Camera FOV Changer (viewmodel más lejos)
    Unlock All Skins / Wraps / Charms (botón en Misc)
    Config Save/Load (R1K0V Flags)
    Todo OFF al ejecutar
    UI: R1K0V UI2.0
]]

local LIB_URL = "https://raw.githubusercontent.com/R1K0V/UI2.0/refs/heads/main/UI2.0.lua"
local okLib, Library = pcall(function()
    return loadstring(game:HttpGet(LIB_URL))()
end)
if not okLib or not Library then
    warn("[Hub] UI2.0 fail:", Library)
    return
end

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local HttpService = game:GetService("HttpService")

local LocalPlayer = Players.LocalPlayer
local Camera = Workspace.CurrentCamera

local Notification = Library:CreateNotification()
local function notify(t, x)
    pcall(function() Notification:Notify(t, x or "", 2) end)
end

-- ======================== STATE ========================
local State = {
    Aimbot = false,
    SilentAim = false,
    StickyAim = false,
    TeamCheck = true,
    VisibleCheck = false,
    FilterLobby = false,

    FOV = 140,
    ShowFOV = false,
    Smooth = 0.42,
    AimPart = "Head",
    MaxDist = 2500,
    Prediction = 0.06,
    StickyFovMult = 1.6,
    AimKey = "MB2",
    Sensitivity = 0.85,
    MatchRadius = 450,

    SilentHitChance = 100,
    SilentHeadChance = 100,

    ESP = false,
    ESPBox = false,
    ESPName = false,
    ESPDistance = false,
    ESPHealth = false,
    ESPTracer = false,
    ESPSkeleton = false,
    ESPChams = false,
    ESPHeadDot = false,
    TracerFrom = "Bottom",
    ESPColor = Color3.fromRGB(0, 255, 120),
    MaxESPDist = 3000,

    -- MISC / CAMERA FOV
    CamFOVEnabled = false,
    CamFOV = 100,
    DefaultCamFOV = 70,

    UnlockAllActive = false,
}

pcall(function()
    State.DefaultCamFOV = Camera.FieldOfView
end)

local FOVCircle = nil
local ESPCache = {}
local CurrentTarget = nil
local HoldingAim = false

local function hasDrawing()
    return typeof(Drawing) == "table" or type(Drawing) == "table"
end

-- ======================== UTILS ========================
local function isAlive(plr)
    local char = plr.Character
    if not char then return false end
    local hum = char:FindFirstChildOfClass("Humanoid")
    local root = char:FindFirstChild("HumanoidRootPart")
    return hum and hum.Health > 0 and root ~= nil
end

local function getMyRoot()
    local char = LocalPlayer.Character
    return char and char:FindFirstChild("HumanoidRootPart")
end

local function isInSameMatch(plr)
    if not State.FilterLobby then return true end
    if plr == LocalPlayer then return false end
    if not isAlive(plr) then return false end

    local myRoot = getMyRoot()
    local theirRoot = plr.Character and plr.Character:FindFirstChild("HumanoidRootPart")
    if not myRoot or not theirRoot then return false end

    local dist = (theirRoot.Position - myRoot.Position).Magnitude
    if dist > State.MatchRadius then return false end

    local yDiff = math.abs(theirRoot.Position.Y - myRoot.Position.Y)
    if yDiff > 120 then return false end

    return true
end

-- Returns a comparable team key for a player (string/number/nil)
local function getTeamKey(plr)
    if not plr then return nil end

    -- 1) Official Team object
    local t = plr.Team
    if t then
        return "T:" .. tostring(t.Name)
    end

    -- 2) TeamColor (skip pure White which is often default/unset)
    local tc = plr.TeamColor
    if tc and typeof(tc) == "BrickColor" and tc.Name ~= "White" and tc.Name ~= "Medium stone grey" then
        return "C:" .. tc.Name
    end

    -- 3) Common attributes on Player
    local attrs = { "Team", "TeamName", "TeamId", "Side", "Faction", "Alliance" }
    for _, a in ipairs(attrs) do
        local v = plr:GetAttribute(a)
        if v ~= nil and v ~= "" and v ~= "None" then
            return "A:" .. tostring(v)
        end
    end

    -- 4) Character attributes / values (Rivals sometimes puts team on char)
    local char = plr.Character
    if char then
        for _, a in ipairs(attrs) do
            local v = char:GetAttribute(a)
            if v ~= nil and v ~= "" and v ~= "None" then
                return "CA:" .. tostring(v)
            end
        end
        local teamVal = char:FindFirstChild("Team") or char:FindFirstChild("TeamValue")
        if teamVal and teamVal:IsA("ValueBase") then
            return "CV:" .. tostring(teamVal.Value)
        end
        -- BodyColors / shirt tint as weak last resort (same team often same shirt)
        local shirt = char:FindFirstChildOfClass("Shirt")
        if shirt and shirt.ShirtTemplate and shirt.ShirtTemplate ~= "" then
            return "S:" .. tostring(shirt.ShirtTemplate)
        end
    end

    -- 5) leaderstats Team if present
    local ls = plr:FindFirstChild("leaderstats")
    if ls then
        local tv = ls:FindFirstChild("Team") or ls:FindFirstChild("Side")
        if tv and tv:IsA("ValueBase") then
            return "L:" .. tostring(tv.Value)
        end
    end

    return nil
end

local function isEnemy(plr)
    if plr == LocalPlayer then return false end
    if not isInSameMatch(plr) then return false end
    if not State.TeamCheck then return true end

    local myKey = getTeamKey(LocalPlayer)
    local theirKey = getTeamKey(plr)

    -- Both have team data → compare
    if myKey and theirKey then
        return myKey ~= theirKey
    end

    -- One has team, other doesn't → treat as enemy (safer)
    if myKey or theirKey then
        return true
    end

    -- No team data on either → Neutral / FFA-like, treat as enemy
    if LocalPlayer.Neutral or plr.Neutral then
        return true
    end

    -- Last ditch: name color above head (Roblox colors names by team)
    -- Not always available; skip if equal unknown
    return true
end

local function getPart(char, name)
    if not char then return nil end
    if name == "Head" then
        return char:FindFirstChild("Head")
    elseif name == "UpperTorso" or name == "Torso" then
        return char:FindFirstChild("UpperTorso")
            or char:FindFirstChild("Torso")
            or char:FindFirstChild("HumanoidRootPart")
    end
    return char:FindFirstChild(name)
        or char:FindFirstChild("Head")
        or char:FindFirstChild("HumanoidRootPart")
end

local function worldToScreen(pos)
    local v, on = Camera:WorldToViewportPoint(pos)
    return Vector2.new(v.X, v.Y), on and v.Z > 0, v.Z
end

local function mousePos()
    return UserInputService:GetMouseLocation()
end

local function isVisible(part)
    if not State.VisibleCheck then return true end
    local origin = Camera.CFrame.Position
    local dir = part.Position - origin
    local params = RaycastParams.new()
    params.FilterType = Enum.RaycastFilterType.Exclude
    params.FilterDescendantsInstances = { LocalPlayer.Character, Camera }
    params.IgnoreWater = true
    local hit = Workspace:Raycast(origin, dir, params)
    if not hit then return true end
    return hit.Instance:IsDescendantOf(part.Parent)
end

local function getAimWorldPos(part, plr)
    if not part then return nil end
    local pos = part.Position
    if part.Name == "Head" then
        pos = part.CFrame.Position + part.CFrame.UpVector * 0.05
    end
    local root = plr.Character and plr.Character:FindFirstChild("HumanoidRootPart")
    local vel = root and (root.AssemblyLinearVelocity or root.Velocity) or Vector3.zero
    return pos + Vector3.new(vel.X, vel.Y * 0.2, vel.Z) * State.Prediction
end

local function getClosest()
    local best, bestDist = nil, State.FOV
    local mouse = mousePos()
    local myRoot = getMyRoot()

    for _, plr in ipairs(Players:GetPlayers()) do
        if isEnemy(plr) and isAlive(plr) then
            local part = getPart(plr.Character, State.AimPart)
            if part and isVisible(part) then
                local screen, onScreen, depth = worldToScreen(part.Position)
                if onScreen then
                    local d2 = (screen - mouse).Magnitude
                    local wd = myRoot and (part.Position - myRoot.Position).Magnitude or depth
                    if wd <= State.MaxDist and d2 < bestDist then
                        bestDist = d2
                        best = plr
                    end
                end
            end
        end
    end
    return best
end

local function getTarget()
    if State.StickyAim and CurrentTarget and isAlive(CurrentTarget) and isEnemy(CurrentTarget) then
        local part = getPart(CurrentTarget.Character, State.AimPart)
        if part then
            local screen, on = worldToScreen(part.Position)
            if on then
                local d = (screen - mousePos()).Magnitude
                if d <= State.FOV * State.StickyFovMult then
                    return CurrentTarget
                end
            end
        end
    end
    CurrentTarget = getClosest()
    return CurrentTarget
end

-- ======================== CAMERA FOV ========================
local function applyCamFOV()
    if not Camera then return end
    if State.CamFOVEnabled then
        Camera.FieldOfView = math.clamp(State.CamFOV, 1, 120)
    else
        Camera.FieldOfView = State.DefaultCamFOV
    end
end

-- ======================== FOV CIRCLE (aim) ========================
local function createFOV()
    if not hasDrawing() then return end
    if FOVCircle then pcall(function() FOVCircle:Remove() end) end
    FOVCircle = Drawing.new("Circle")
    FOVCircle.Thickness = 1.5
    FOVCircle.NumSides = 64
    FOVCircle.Radius = State.FOV
    FOVCircle.Filled = false
    FOVCircle.Color = Color3.fromRGB(255, 255, 255)
    FOVCircle.Transparency = 0.6
    FOVCircle.Visible = false
end
createFOV()

-- ======================== AIMBOT ========================
local function canAim()
    if not State.Aimbot then return false end
    if State.AimKey == "Always" then return true end
    if State.AimKey == "MB2" then return HoldingAim end
    if State.AimKey == "MB1" then
        return UserInputService:IsMouseButtonPressed(Enum.UserInputType.MouseButton1)
    end
    return false
end

local function moveMouseTowards(screenPos)
    local mouse = mousePos()
    local dx = screenPos.X - mouse.X
    local dy = screenPos.Y - mouse.Y
    local dist = math.sqrt(dx * dx + dy * dy)
    if dist < 3 then return end

    local smooth = math.clamp(State.Smooth, 0.12, 0.9)
    local sens = State.Sensitivity
    local closeFactor = dist < 45 and (dist / 45) or 1

    local mx = dx * (1 - smooth) * sens * closeFactor
    local my = dy * (1 - smooth) * sens * closeFactor
    local maxStep = dist < 50 and 16 or 38
    mx = math.clamp(mx, -maxStep, maxStep)
    my = math.clamp(my, -maxStep, maxStep)

    if mousemoverel then
        mousemoverel(mx, my)
    end
end

local function runAimbot()
    if not canAim() then return end
    local target = getTarget()
    if not target then return end
    local part = getPart(target.Character, State.AimPart)
    if not part then return end
    local aimWorld = getAimWorldPos(part, target)
    if not aimWorld then return end
    local screen, onScreen = worldToScreen(aimWorld)
    if not onScreen then return end
    moveMouseTowards(screen)
end

-- ======================== SILENT AIM ========================
local mt = getrawmetatable(game)
local oldNamecall
local silentHooked = false

local function setupSilent()
    if silentHooked or not mt then return end
    pcall(function()
        setreadonly(mt, false)
        oldNamecall = mt.__namecall
        mt.__namecall = newcclosure(function(self, ...)
            local method = getnamecallmethod()
            local args = {...}

            if State.SilentAim and method == "Raycast" and self == Workspace then
                local target = getTarget()
                if target and math.random(1, 100) <= State.SilentHitChance then
                    local pname = (math.random(1, 100) <= State.SilentHeadChance) and "Head" or State.AimPart
                    local part = getPart(target.Character, pname)
                    if part then
                        local origin, dir = args[1], args[2]
                        if typeof(origin) == "Vector3" and typeof(dir) == "Vector3" then
                            local aim = getAimWorldPos(part, target)
                            if aim then
                                args[2] = (aim - origin).Unit * dir.Magnitude
                                return oldNamecall(self, unpack(args))
                            end
                        end
                    end
                end
            end

            if State.SilentAim and (method == "FindPartOnRay" or method == "FindPartOnRayWithIgnoreList" or method == "FindPartOnRayWithWhitelist") then
                local target = getTarget()
                if target and math.random(1, 100) <= State.SilentHitChance then
                    local part = getPart(target.Character, (math.random(1, 100) <= State.SilentHeadChance) and "Head" or State.AimPart)
                    if part and typeof(args[1]) == "Ray" then
                        local aim = getAimWorldPos(part, target)
                        if aim then
                            args[1] = Ray.new(args[1].Origin, (aim - args[1].Origin).Unit * 9999)
                            return oldNamecall(self, unpack(args))
                        end
                    end
                end
            end

            return oldNamecall(self, ...)
        end)
        setreadonly(mt, true)
        silentHooked = true
    end)
end
setupSilent()

UserInputService.InputBegan:Connect(function(input, gp)
    if gp then return end
    if input.UserInputType == Enum.UserInputType.MouseButton2 then
        HoldingAim = true
    end
end)
UserInputService.InputEnded:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton2 then
        HoldingAim = false
    end
end)

-- ======================== ESP ========================
local function clearESP(plr)
    local cache = ESPCache[plr]
    if not cache then return end
    for _, obj in pairs(cache) do
        pcall(function()
            if typeof(obj) == "Instance" then
                obj:Destroy()
            elseif type(obj) == "table" then
                for _, l in pairs(obj) do
                    if l and l.Remove then l:Remove() end
                end
            elseif obj.Remove then
                obj:Remove()
            end
        end)
    end
    ESPCache[plr] = nil
end

local function makeDrawing(class, props)
    if not hasDrawing() then return nil end
    local d = Drawing.new(class)
    for k, v in pairs(props or {}) do d[k] = v end
    return d
end

local function ensureESP(plr)
    if ESPCache[plr] then return ESPCache[plr] end
    local c = {}
    if hasDrawing() then
        c.box = makeDrawing("Square", { Thickness = 1, Filled = false, Visible = false })
        c.boxOutline = makeDrawing("Square", { Thickness = 3, Filled = false, Color = Color3.new(0,0,0), Visible = false })
        c.name = makeDrawing("Text", { Size = 14, Center = true, Outline = true, Visible = false })
        c.dist = makeDrawing("Text", { Size = 12, Center = true, Outline = true, Visible = false })
        c.healthBg = makeDrawing("Square", { Filled = true, Color = Color3.new(0,0,0), Visible = false })
        c.health = makeDrawing("Square", { Filled = true, Visible = false })
        c.tracer = makeDrawing("Line", { Thickness = 1, Visible = false })
        c.headDot = makeDrawing("Circle", { Thickness = 1, Filled = true, NumSides = 16, Visible = false })
        c.skel = {}
        for i = 1, 12 do
            c.skel[i] = makeDrawing("Line", { Thickness = 1.5, Visible = false })
        end
    end
    c.highlight = Instance.new("Highlight")
    c.highlight.FillTransparency = 0.65
    c.highlight.OutlineTransparency = 0.2
    c.highlight.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
    c.highlight.Enabled = false
    ESPCache[plr] = c
    return c
end

local SKELETON = {
    {"Head","UpperTorso"},{"UpperTorso","LowerTorso"},
    {"UpperTorso","LeftUpperArm"},{"LeftUpperArm","LeftLowerArm"},{"LeftLowerArm","LeftHand"},
    {"UpperTorso","RightUpperArm"},{"RightUpperArm","RightLowerArm"},{"RightLowerArm","RightHand"},
    {"LowerTorso","LeftUpperLeg"},{"LeftUpperLeg","LeftLowerLeg"},
    {"LowerTorso","RightUpperLeg"},{"RightUpperLeg","RightLowerLeg"},
}

local function updateESP(plr)
    if not State.ESP or not isEnemy(plr) or not isAlive(plr) then
        clearESP(plr)
        return
    end

    local char = plr.Character
    local root = char:FindFirstChild("HumanoidRootPart")
    local head = char:FindFirstChild("Head")
    local hum = char:FindFirstChildOfClass("Humanoid")
    if not root or not head or not hum then
        clearESP(plr)
        return
    end

    local myRoot = getMyRoot()
    local worldDist = myRoot and (root.Position - myRoot.Position).Magnitude or 0
    if worldDist > State.MaxESPDist then
        clearESP(plr)
        return
    end

    local c = ensureESP(plr)
    local col = State.ESPColor
    local topPos, topOn = worldToScreen((head.CFrame * CFrame.new(0, 0.85, 0)).Position)
    local botPos, botOn = worldToScreen((root.CFrame * CFrame.new(0, -3, 0)).Position)
    local headScreen, headOn = worldToScreen(head.Position)

    if not (topOn and botOn) then
        if c.box then c.box.Visible = false end
        if c.boxOutline then c.boxOutline.Visible = false end
        if c.name then c.name.Visible = false end
        if c.dist then c.dist.Visible = false end
        if c.health then c.health.Visible = false end
        if c.healthBg then c.healthBg.Visible = false end
        if c.tracer then c.tracer.Visible = false end
        if c.headDot then c.headDot.Visible = false end
        if c.skel then for _,l in pairs(c.skel) do l.Visible = false end end
        if c.highlight then c.highlight.Enabled = false end
        return
    end

    local h = math.abs(topPos.Y - botPos.Y)
    local w = h * 0.55
    local boxPos = Vector2.new(topPos.X - w/2, topPos.Y)

    if c.box then
        c.boxOutline.Visible = State.ESPBox
        c.box.Visible = State.ESPBox
        c.boxOutline.Size = Vector2.new(w, h)
        c.boxOutline.Position = boxPos
        c.box.Size = Vector2.new(w, h)
        c.box.Position = boxPos
        c.box.Color = col
    end
    if c.name then
        c.name.Visible = State.ESPName
        c.name.Text = plr.DisplayName or plr.Name
        c.name.Position = Vector2.new(topPos.X, topPos.Y - 16)
        c.name.Color = col
    end
    if c.dist then
        c.dist.Visible = State.ESPDistance
        c.dist.Text = string.format("[%dm]", math.floor(worldDist))
        c.dist.Position = Vector2.new(botPos.X, botPos.Y + 2)
        c.dist.Color = Color3.fromRGB(200,200,200)
    end
    if c.health and c.healthBg then
        local pct = math.clamp(hum.Health / math.max(hum.MaxHealth, 1), 0, 1)
        c.healthBg.Visible = State.ESPHealth
        c.health.Visible = State.ESPHealth
        c.healthBg.Size = Vector2.new(3, h)
        c.healthBg.Position = Vector2.new(boxPos.X - 6, boxPos.Y)
        c.health.Size = Vector2.new(3, h * pct)
        c.health.Position = Vector2.new(boxPos.X - 6, boxPos.Y + h * (1 - pct))
        c.health.Color = Color3.fromRGB(255*(1-pct), 255*pct, 40)
    end
    if c.tracer then
        c.tracer.Visible = State.ESPTracer
        local from = State.TracerFrom == "Bottom" and Vector2.new(Camera.ViewportSize.X/2, Camera.ViewportSize.Y)
            or State.TracerFrom == "Top" and Vector2.new(Camera.ViewportSize.X/2, 0)
            or mousePos()
        c.tracer.From = from
        c.tracer.To = botPos
        c.tracer.Color = col
    end
    if c.headDot then
        c.headDot.Visible = State.ESPHeadDot and headOn
        c.headDot.Position = headScreen
        c.headDot.Radius = math.clamp(h * 0.08, 3, 8)
        c.headDot.Color = col
    end
    if c.skel then
        for i, pair in ipairs(SKELETON) do
            local line = c.skel[i]
            if line then
                local a, b = char:FindFirstChild(pair[1]), char:FindFirstChild(pair[2])
                if State.ESPSkeleton and a and b then
                    local sa, oa = worldToScreen(a.Position)
                    local sb, ob = worldToScreen(b.Position)
                    if oa and ob then
                        line.From, line.To, line.Color, line.Visible = sa, sb, col, true
                    else
                        line.Visible = false
                    end
                else
                    line.Visible = false
                end
            end
        end
    end
    if c.highlight then
        if State.ESPChams then
            c.highlight.Adornee = char
            c.highlight.FillColor = col
            c.highlight.OutlineColor = col
            c.highlight.Parent = char
            c.highlight.Enabled = true
        else
            c.highlight.Enabled = false
            c.highlight.Parent = nil
        end
    end
end

Players.PlayerRemoving:Connect(function(plr)
    clearESP(plr)
    if CurrentTarget == plr then CurrentTarget = nil end
end)

-- ======================== LOOP ========================
RunService.RenderStepped:Connect(function()
    if State.CamFOVEnabled and Camera then
        if math.abs(Camera.FieldOfView - State.CamFOV) > 0.5 then
            Camera.FieldOfView = math.clamp(State.CamFOV, 1, 120)
        end
    end

    if FOVCircle then
        FOVCircle.Visible = State.ShowFOV and (State.Aimbot or State.SilentAim)
        FOVCircle.Radius = State.FOV
        FOVCircle.Position = mousePos()
    end
    runAimbot()
    for _, plr in ipairs(Players:GetPlayers()) do
        if plr ~= LocalPlayer then updateESP(plr) end
    end
end)

-- ======================== UNLOCK ALL (skins/wraps/charms) ========================
local UnlockAll = {
    ready = false,
    running = false,
    eq = {},
    favs = {},
}

local function runUnlockAll()
    if UnlockAll.running then
        notify("Unlock All", "Ya activo")
        return
    end
    UnlockAll.running = true
    State.UnlockAllActive = true
    notify("Unlock All", "Iniciando...")

    task.spawn(function()
        local ok, err = pcall(function()
            -- AC Bypass (lightweight)
            pcall(function()
                local _stbl
                _stbl = hookfunction(getrenv().setmetatable, newcclosure(function(tbl, mt)
                    if mt and typeof(mt) == "table" and rawget(mt, "__mode") == "kv" then
                        local tr = debug.traceback()
                        if tr:find("MiscellaneousController") then
                            return _stbl({1, 2, 3}, {})
                        end
                    end
                    return _stbl(tbl, mt)
                end))
            end)

            pcall(function()
                local function _proc(o)
                    pcall(function()
                        if o:IsA("LocalScript") or o:IsA("ModuleScript") then
                            local _s, nm = pcall(function() return o.Name:lower() end)
                            if not _s or not nm then return end
                            local _tags = {"anticheat", "ac", "detection", "ban", "kick", "security", "moderation"}
                            for _i = 1, #_tags do
                                if nm:find(_tags[_i]) then
                                    pcall(function() o.Disabled = true end)
                                    break
                                end
                            end
                        end
                    end)
                end
                pcall(function()
                    local _desc = game:GetDescendants()
                    for _i = 1, #_desc do _proc(_desc[_i]) end
                end)
                pcall(function() game.DescendantAdded:Connect(_proc) end)
            end)

            pcall(function()
                local _fakeEv = Instance.new("RemoteEvent")
                _fakeEv.Name = "ClientAlert"
                _fakeEv.Parent = LocalPlayer
            end)

            task.wait(0.5)

            local _pscripts = LocalPlayer:WaitForChild("PlayerScripts", 10)
            local _ctrl = _pscripts and _pscripts:WaitForChild("Controllers", 10)
            local _mods = ReplicatedStorage:WaitForChild("Modules", 10)
            if not _mods or not _ctrl then
                error("Modules/Controllers no encontrados")
            end

            local _enumLib = require(_mods:WaitForChild("EnumLibrary", 10))
            if _enumLib then pcall(function() _enumLib:WaitForEnumBuilder() end) end

            local _cosLib = require(_mods:WaitForChild("CosmeticLibrary", 10))
            local _itmLib = require(_mods:WaitForChild("ItemLibrary", 10))
            local _datCtrl = require(_ctrl:WaitForChild("PlayerDataController", 10))

            local _eq, _favs = UnlockAll.eq, UnlockAll.favs
            local _buildingWep, _viewProf = nil, nil
            local _lastWep = nil

            local function _mkCosmetic(nm, ctype, opts)
                local _base = _cosLib.Cosmetics[nm]
                if not _base then return nil end
                local _d = {}
                for k, v in pairs(_base) do _d[k] = v end
                _d.Name = nm
                _d.Type = _d.Type or ctype
                _d.Seed = _d.Seed or math.random(1, 1000000)
                if _enumLib then
                    local _s, _eid = pcall(_enumLib.ToEnum, _enumLib, nm)
                    if _s and _eid then
                        _d.Enum = _eid
                        _d.ObjectID = _d.ObjectID or _eid
                    end
                end
                if opts then
                    if opts.inverted ~= nil then _d.Inverted = opts.inverted end
                    if opts.favoritesOnly ~= nil then _d.OnlyUseFavorites = opts.favoritesOnly end
                end
                return _d
            end

            local _cfgFile = "rivals_unlocker_config.json"
            local _saveLock = false

            local function _stripForSave()
                local _out = {}
                for wn, cos in pairs(_eq) do
                    _out[wn] = {}
                    for ct, cd in pairs(cos) do
                        if cd and cd.Name then
                            _out[wn][ct] = {
                                Name = cd.Name,
                                Inverted = cd.Inverted,
                                OnlyUseFavorites = cd.OnlyUseFavorites
                            }
                        end
                    end
                end
                return { equipped = _out, favorites = _favs }
            end

            local function _loadCfg()
                if not isfile or not readfile then return end
                local _ok1, _ex = pcall(isfile, _cfgFile)
                if not _ok1 or not _ex then return end
                local _ok2, _raw = pcall(readfile, _cfgFile)
                if not _ok2 or not _raw or _raw == "" then return end
                local _ok3, _dec = pcall(HttpService.JSONDecode, HttpService, _raw)
                if not _ok3 or not _dec then return end
                if _dec.favorites then
                    for k, v in pairs(_dec.favorites) do _favs[k] = v end
                end
                if _dec.equipped then
                    for wn, cos in pairs(_dec.equipped) do
                        _eq[wn] = {}
                        for ct, sd in pairs(cos) do
                            if sd and sd.Name and _cosLib.Cosmetics[sd.Name] then
                                local _cloned = _mkCosmetic(sd.Name, ct, {
                                    inverted = sd.Inverted,
                                    favoritesOnly = sd.OnlyUseFavorites
                                })
                                if _cloned then
                                    _eq[wn][ct] = _cloned
                                end
                            end
                        end
                        if not next(_eq[wn]) then _eq[wn] = nil end
                    end
                end
            end

            local function _saveCfg()
                if not writefile or _saveLock then return end
                _saveLock = true
                task.spawn(function()
                    task.wait(1)
                    local _payload = _stripForSave()
                    local _ok, _enc = pcall(HttpService.JSONEncode, HttpService, _payload)
                    if _ok then
                        pcall(writefile, _cfgFile, _enc)
                    end
                    _saveLock = false
                end)
            end

            _loadCfg()

            local _cosTypes = {"Skin", "Wrap", "Charm", "Dance", "Emote"}
            local function _isCosType(cosObj)
                if not cosObj then return false end
                for _, t in ipairs(_cosTypes) do
                    if cosObj.Type == t then return true end
                end
                return false
            end

            _cosLib.OwnsCosmeticNormally = function(self, inv, nm, wep)
                local c = _cosLib.Cosmetics[nm]
                if c and c.Type == "Skin" then return true end
                return false
            end
            _cosLib.OwnsCosmeticUniversally = function(self, inv, nm, wep)
                local c = _cosLib.Cosmetics[nm]
                if c and c.Type == "Skin" then return true end
                return false
            end
            _cosLib.OwnsCosmeticForWeapon = function(self, inv, nm, wep)
                local c = _cosLib.Cosmetics[nm]
                if c and c.Type == "Skin" then return true end
                return false
            end

            local _origOwns = _cosLib.OwnsCosmetic
            _cosLib.OwnsCosmetic = function(self, inv, nm, wep)
                if nm:find("MISSING_") or nm == "Bubble Gun" then
                    return _origOwns(self, inv, nm, wep)
                end
                local c = _cosLib.Cosmetics[nm]
                if c and _isCosType(c) then return true end
                return _origOwns(self, inv, nm, wep)
            end

            local _origGet = _datCtrl.Get
            _datCtrl.Get = function(self, key)
                local _val = _origGet(self, key)
                if key == "CosmeticInventory" then
                    local _prx = {}
                    if _val then
                        for k, v in pairs(_val) do
                            local c = _cosLib.Cosmetics[k]
                            if c and _isCosType(c) then _prx[k] = v end
                        end
                    end
                    return setmetatable(_prx, {
                        __index = function(t, k)
                            local c = _cosLib.Cosmetics[k]
                            if c and _isCosType(c) then return true end
                            return nil
                        end
                    })
                end
                if key == "FavoritedCosmetics" then
                    local _res = _val and table.clone(_val) or {}
                    for wep, fv in pairs(_favs) do
                        _res[wep] = _res[wep] or {}
                        for nm, isFav in pairs(fv) do
                            local c = _cosLib.Cosmetics[nm]
                            if c and _isCosType(c) then
                                _res[wep][nm] = isFav
                            end
                        end
                    end
                    return _res
                end
                return _val
            end

            local _origGetWep = _datCtrl.GetWeaponData
            _datCtrl.GetWeaponData = function(self, wn)
                local _d = _origGetWep(self, wn)
                if not _d then return nil end
                local _m = {}
                for k, v in pairs(_d) do _m[k] = v end
                _m.Name = wn
                if _eq[wn] then
                    for ct, cd in pairs(_eq[wn]) do
                        _m[ct] = cd
                    end
                end
                return _m
            end

            local _fightCtrl
            pcall(function()
                _fightCtrl = require(_ctrl:WaitForChild("FighterController", 10))
            end)

            if hookmetamethod then
                local _remotes = ReplicatedStorage:FindFirstChild("Remotes")
                local _dataRem = _remotes and _remotes:FindFirstChild("Data")
                local _equipRem = _dataRem and _dataRem:FindFirstChild("EquipCosmetic")
                local _favRem = _dataRem and _dataRem:FindFirstChild("FavoriteCosmetic")
                local _repRem = _remotes and _remotes:FindFirstChild("Replication")
                local _fightRem = _repRem and _repRem:FindFirstChild("Fighter")
                local _useItmRem = _fightRem and _fightRem:FindFirstChild("UseItem")

                if _equipRem then
                    local _onc
                    _onc = hookmetamethod(game, "__namecall", function(self, ...)
                        if getnamecallmethod() ~= "FireServer" then
                            return _onc(self, ...)
                        end
                        local _a = {...}

                        if _useItmRem and self == _useItmRem then
                            local _oid = _a[1]
                            if _fightCtrl then
                                pcall(function()
                                    local _f = _fightCtrl:GetFighter(LocalPlayer)
                                    if _f and _f.Items then
                                        for _, itm in pairs(_f.Items) do
                                            if itm:Get("ObjectID") == _oid then
                                                _lastWep = itm.Name
                                                break
                                            end
                                        end
                                    end
                                end)
                            end
                        end

                        if self == _equipRem then
                            local _wn = _a[1]
                            local _ct = _a[2]
                            local _cn = _a[3]
                            local _opts = _a[4] or {}
                            if _cn and _cn ~= "None" and _cn ~= "" then
                                local _inv = _datCtrl:Get("CosmeticInventory")
                                if _inv and rawget(_inv, _cn) then
                                    return _onc(self, ...)
                                end
                            end
                            _eq[_wn] = _eq[_wn] or {}
                            if not _cn or _cn == "None" or _cn == "" then
                                _eq[_wn][_ct] = nil
                                if not next(_eq[_wn]) then _eq[_wn] = nil end
                            else
                                local _cloned = _mkCosmetic(_cn, _ct, {
                                    inverted = _opts.IsInverted,
                                    favoritesOnly = _opts.OnlyUseFavorites
                                })
                                if _cloned then _eq[_wn][_ct] = _cloned end
                            end
                            task.defer(function()
                                pcall(function() _datCtrl.CurrentData:Replicate("WeaponInventory") end)
                            end)
                            _saveCfg()
                            return
                        end

                        if self == _favRem then
                            local _cos = _cosLib.Cosmetics[_a[2]]
                            if _cos then
                                _favs[_a[1]] = _favs[_a[1]] or {}
                                _favs[_a[1]][_a[2]] = _a[3] or nil
                                task.spawn(function()
                                    pcall(function() _datCtrl.CurrentData:Replicate("FavoritedCosmetics") end)
                                end)
                                _saveCfg()
                            end
                            return
                        end

                        return _onc(self, ...)
                    end)
                end
            end

            local _cliItem
            pcall(function()
                _cliItem = require(LocalPlayer.PlayerScripts.Modules.ClientReplicatedClasses.ClientFighter.ClientItem)
            end)

            if _cliItem and _cliItem._CreateViewModel then
                local _origCVM = _cliItem._CreateViewModel
                _cliItem._CreateViewModel = function(self, vmRef)
                    local _wn = self.Name
                    local _wp = self.ClientFighter and self.ClientFighter.Player
                    _buildingWep = (_wp == LocalPlayer) and _wn or nil
                    if _wp == LocalPlayer and _eq[_wn] then
                        local _dk = self:ToEnum("Data")
                        if vmRef[_dk] then
                            if _eq[_wn].Skin then
                                vmRef[_dk][self:ToEnum("Skin")] = _eq[_wn].Skin
                                vmRef[_dk][self:ToEnum("Name")] = _eq[_wn].Skin.Name
                            end
                            if _eq[_wn].Charm then vmRef[_dk][self:ToEnum("Charm")] = _eq[_wn].Charm end
                            if _eq[_wn].Wrap then vmRef[_dk][self:ToEnum("Wrap")] = _eq[_wn].Wrap end
                        elseif vmRef.Data then
                            if _eq[_wn].Skin then vmRef.Data.Skin = _eq[_wn].Skin; vmRef.Data.Name = _eq[_wn].Skin.Name end
                            if _eq[_wn].Charm then vmRef.Data.Charm = _eq[_wn].Charm end
                            if _eq[_wn].Wrap then vmRef.Data.Wrap = _eq[_wn].Wrap end
                        end
                    end
                    local _r = _origCVM(self, vmRef)
                    _buildingWep = nil
                    return _r
                end
            end

            local _vmMod = LocalPlayer.PlayerScripts.Modules.ClientReplicatedClasses.ClientFighter.ClientItem:FindFirstChild("ClientViewModel")
            if _vmMod then
                local _CVM = require(_vmMod)
                local _origNew = _CVM.new
                _CVM.new = function(repData, cliItm)
                    local _wp = cliItm.ClientFighter and cliItm.ClientFighter.Player
                    local _wn = _buildingWep or cliItm.Name
                    if _wp == LocalPlayer and _eq[_wn] then
                        local _RC = require(ReplicatedStorage.Modules.ReplicatedClass)
                        local _dk = _RC:ToEnum("Data")
                        repData[_dk] = repData[_dk] or {}
                        local _cos = _eq[_wn]
                        if _cos.Skin then repData[_dk][_RC:ToEnum("Skin")] = _cos.Skin end
                        if _cos.Charm then repData[_dk][_RC:ToEnum("Charm")] = _cos.Charm end
                        if _cos.Wrap then repData[_dk][_RC:ToEnum("Wrap")] = _cos.Wrap end
                    end
                    return _origNew(repData, cliItm)
                end
            end

            UnlockAll.ready = true
        end)

        if ok then
            notify("Unlock All", "Skins / Wraps / Charms desbloqueados")
        else
            UnlockAll.running = false
            State.UnlockAllActive = false
            notify("Unlock All", "Error: " .. tostring(err))
            warn("[RIVALS HUB] Unlock All fail:", err)
        end
    end)
end

-- ======================== UI ========================
local window = Library:CreateWindow({
    Name = "RIVALS HUB",
    Content = "Aim + FOV + Misc + Unlock + Config",
    Keybind = "RightShift",
})

window:AddTabLabel("COMBAT")
local TabCombat = window:AddTab({ Name = "Aim", Icon = 6034767608 })
local CL = TabCombat:AddSection({ Name = "AIMBOT", Position = "left" })
local CR = TabCombat:AddSection({ Name = "SILENT / FILTER", Position = "right" })

CL:AddToggle({
    Name = "Aimbot",
    Flag = "Aimbot",
    Default = false,
    Callback = function(v)
        State.Aimbot = v
        notify("Aimbot", v and "ON" or "OFF")
    end,
})
CL:AddToggle({
    Name = "Sticky Aim",
    Flag = "Sticky",
    Default = false,
    Callback = function(v) State.StickyAim = v end,
})
CL:AddSlider({
    Name = "FOV",
    Flag = "FOV",
    Min = 40, Max = 400, Default = 140,
    Callback = function(v)
        State.FOV = v
        if FOVCircle then FOVCircle.Radius = v end
    end,
})
CL:AddToggle({
    Name = "Show FOV",
    Flag = "ShowFOV",
    Default = false,
    Callback = function(v) State.ShowFOV = v end,
})
CL:AddSlider({
    Name = "Smooth",
    Flag = "Smooth",
    Min = 0.15, Max = 0.85, Default = 0.42,
    Callback = function(v) State.Smooth = v end,
})
CL:AddSlider({
    Name = "Sensitivity",
    Flag = "Sens",
    Min = 0.4, Max = 2.0, Default = 0.85,
    Callback = function(v) State.Sensitivity = v end,
})
CL:AddDropdown({
    Name = "Aim Part",
    Flag = "AimPart",
    Items = {"Head", "UpperTorso", "HumanoidRootPart"},
    Default = "Head",
    Callback = function(v) State.AimPart = v end,
})
CL:AddDropdown({
    Name = "Aim Key",
    Flag = "AimKey",
    Items = {"MB2", "MB1", "Always"},
    Default = "MB2",
    Callback = function(v) State.AimKey = v end,
})

CR:AddToggle({
    Name = "Silent Aim",
    Flag = "Silent",
    Default = false,
    Callback = function(v)
        State.SilentAim = v
        notify("Silent", v and "ON" or "OFF")
    end,
})
CR:AddToggle({
    Name = "Filter Lobby",
    Flag = "FilterLobby",
    Default = false,
    Callback = function(v)
        State.FilterLobby = v
        notify("Filter Lobby", v and "ON" or "OFF")
        for plr in pairs(ESPCache) do
            if not isEnemy(plr) then clearESP(plr) end
        end
    end,
})
CR:AddSlider({
    Name = "Match Radius",
    Flag = "MatchRadius",
    Min = 200, Max = 800, Default = 450,
    Callback = function(v) State.MatchRadius = v end,
})
CR:AddSlider({
    Name = "Hit Chance %",
    Flag = "HitChance",
    Min = 1, Max = 100, Default = 100,
    Callback = function(v) State.SilentHitChance = v end,
})
CR:AddSlider({
    Name = "Head Chance %",
    Flag = "HeadChance",
    Min = 0, Max = 100, Default = 100,
    Callback = function(v) State.SilentHeadChance = v end,
})
CR:AddSlider({
    Name = "Prediction",
    Flag = "Pred",
    Min = 0, Max = 0.25, Default = 0.06,
    Callback = function(v) State.Prediction = v end,
})
CR:AddSlider({
    Name = "Max Distance",
    Flag = "MaxDist",
    Min = 100, Max = 5000, Default = 2500,
    Callback = function(v) State.MaxDist = v end,
})
CR:AddToggle({
    Name = "Team Check",
    Flag = "TeamCheck",
    Default = true,
    Callback = function(v)
        State.TeamCheck = v
        CurrentTarget = nil
        for plr in pairs(ESPCache) do
            if not isEnemy(plr) then clearESP(plr) end
        end
        notify("Team Check", v and "ON — solo enemigos" or "OFF — todos")
    end,
})
CR:AddToggle({
    Name = "Visible Check",
    Flag = "VisCheck",
    Default = false,
    Callback = function(v) State.VisibleCheck = v end,
})

window:AddTabLabel("VISUALS")
local TabESP = window:AddTab({ Name = "ESP", Icon = 6034287594 })
local EL = TabESP:AddSection({ Name = "ESP", Position = "left" })
local ER = TabESP:AddSection({ Name = "STYLE", Position = "right" })

EL:AddToggle({
    Name = "ESP Master",
    Flag = "ESP",
    Default = false,
    Callback = function(v)
        State.ESP = v
        if not v then
            for p in pairs(ESPCache) do clearESP(p) end
        end
    end,
})
EL:AddToggle({ Name = "Box", Flag = "ESPBox", Default = false, Callback = function(v) State.ESPBox = v end })
EL:AddToggle({ Name = "Name", Flag = "ESPName", Default = false, Callback = function(v) State.ESPName = v end })
EL:AddToggle({ Name = "Distance", Flag = "ESPDist", Default = false, Callback = function(v) State.ESPDistance = v end })
EL:AddToggle({ Name = "Health Bar", Flag = "ESPHp", Default = false, Callback = function(v) State.ESPHealth = v end })
EL:AddToggle({ Name = "Tracer", Flag = "ESPTracer", Default = false, Callback = function(v) State.ESPTracer = v end })
EL:AddToggle({ Name = "Skeleton", Flag = "ESPSkel", Default = false, Callback = function(v) State.ESPSkeleton = v end })
EL:AddToggle({ Name = "Chams", Flag = "ESPChams", Default = false, Callback = function(v) State.ESPChams = v end })
EL:AddToggle({ Name = "Head Dot", Flag = "ESPHead", Default = false, Callback = function(v) State.ESPHeadDot = v end })

ER:AddDropdown({
    Name = "Tracer From",
    Flag = "TracerFrom",
    Items = {"Bottom","Top","Mouse"},
    Default = "Bottom",
    Callback = function(v) State.TracerFrom = v end,
})
ER:AddColorPicker({
    Name = "ESP Color",
    Flag = "ESPColor",
    Default = Color3.fromRGB(0,255,120),
    Callback = function(c) State.ESPColor = c end,
})
ER:AddSlider({
    Name = "Max ESP Distance",
    Flag = "MaxESP",
    Min = 200, Max = 5000, Default = 3000,
    Callback = function(v) State.MaxESPDist = v end,
})

-- ======================== MISC (FOV + UNLOCK ALL) ========================
window:AddTabLabel("MISC")
local TabMisc = window:AddTab({ Name = "Misc", Icon = 6031280882 })
local ML = TabMisc:AddSection({ Name = "CAMERA FOV", Position = "left" })
local MR = TabMisc:AddSection({ Name = "OPTIONS", Position = "right" })

ML:AddToggle({
    Name = "Camera FOV Changer",
    Flag = "CamFOVEnabled",
    Default = false,
    Callback = function(v)
        State.CamFOVEnabled = v
        applyCamFOV()
        notify("Camera FOV", v and ("ON — " .. tostring(State.CamFOV)) or "OFF")
    end,
})

ML:AddSlider({
    Name = "Camera FOV",
    Flag = "CamFOV",
    Min = 50,
    Max = 120,
    Default = 100,
    Callback = function(v)
        State.CamFOV = v
        if State.CamFOVEnabled then
            applyCamFOV()
        end
    end,
})

ML:AddButton({
    Name = "Reset FOV (default)",
    Callback = function()
        State.CamFOVEnabled = false
        Camera.FieldOfView = State.DefaultCamFOV
        notify("Camera FOV", "Reset → " .. tostring(math.floor(State.DefaultCamFOV)))
    end,
})

ML:AddLabel("Más FOV = manos/arma más lejos")
ML:AddLabel("Recomendado: 95–110")

MR:AddButton({
    Name = "Unlock All",
    Callback = function()
        runUnlockAll()
    end,
})

MR:AddButton({
    Name = "Clear All ESP",
    Callback = function()
        for plr in pairs(ESPCache) do clearESP(plr) end
        notify("ESP", "Cleared")
    end,
})

MR:AddButton({
    Name = "Re-apply Camera FOV",
    Callback = function()
        applyCamFOV()
        notify("FOV", State.CamFOVEnabled and tostring(State.CamFOV) or "Default")
    end,
})

MR:AddButton({
    Name = "Debug Team Keys",
    Callback = function()
        local my = getTeamKey(LocalPlayer)
        print("[TEAM] ME =", tostring(my), "Team=", tostring(LocalPlayer.Team), "Color=", tostring(LocalPlayer.TeamColor))
        local enemies, teammates = 0, 0
        for _, plr in ipairs(Players:GetPlayers()) do
            if plr ~= LocalPlayer then
                local k = getTeamKey(plr)
                local enemy = isEnemy(plr)
                if enemy then enemies = enemies + 1 else teammates = teammates + 1 end
                print(string.format("[TEAM] %s key=%s enemy=%s Team=%s Color=%s",
                    plr.Name, tostring(k), tostring(enemy), tostring(plr.Team), tostring(plr.TeamColor)))
            end
        end
        notify("Team Debug", string.format("me=%s | enemies=%d mates=%d (F9)", tostring(my), enemies, teammates))
    end,
})

MR:AddLabel("Unlock All = skins/wraps/charms")
MR:AddLabel("Pulsa una vez. Persistente en sesión.")
MR:AddLabel("Debug Team Keys → F9 console")

-- ======================== CONFIG ========================
window:AddTabLabel("CONFIG")
local TabCfg = window:AddTab({ Name = "Config", Icon = 6034508292 })
local CFG_L = TabCfg:AddSection({ Name = "SAVE / LOAD", Position = "left" })
local CFG_R = TabCfg:AddSection({ Name = "INFO", Position = "right" })

local ConfigNameBox
ConfigNameBox = CFG_L:AddTextBox({
    Name = "Config Name",
    Flag = "ConfigName",
    Default = "default",
    Placeholder = "default",
    Callback = function(txt)
        if type(txt) == "string" and txt ~= "" then
            Library.ConfigName = txt
        end
    end,
})

CFG_L:AddButton({
    Name = "Save Config",
    Callback = function()
        local name = Library.ConfigName or "default"
        local ok = pcall(function()
            Library:SaveConfig(name)
        end)
        if ok then
            notify("Config", "Saved → " .. tostring(name))
        else
            notify("Config", "Save failed")
        end
    end,
})

CFG_L:AddButton({
    Name = "Load Config",
    Callback = function()
        local name = Library.ConfigName or "default"
        local ok = Library:LoadConfig(name)
        if ok then
            -- sync State from Flags after load (elements already applied by Library)
            local F = Library.Flags
            local map = {
                Aimbot = "Aimbot",
                Sticky = "StickyAim",
                ShowFOV = "ShowFOV",
                Silent = "SilentAim",
                FilterLobby = "FilterLobby",
                TeamCheck = "TeamCheck",
                VisCheck = "VisibleCheck",
                ESP = "ESP",
                ESPBox = "ESPBox",
                ESPName = "ESPName",
                ESPDist = "ESPDistance",
                ESPHp = "ESPHealth",
                ESPTracer = "ESPTracer",
                ESPSkel = "ESPSkeleton",
                ESPChams = "ESPChams",
                ESPHead = "ESPHeadDot",
                CamFOVEnabled = "CamFOVEnabled",
            }
            for flag, stateKey in pairs(map) do
                if F[flag] ~= nil then
                    State[stateKey] = F[flag]
                end
            end
            if F.FOV ~= nil then State.FOV = F.FOV end
            if F.Smooth ~= nil then State.Smooth = F.Smooth end
            if F.Sens ~= nil then State.Sensitivity = F.Sens end
            if F.AimPart ~= nil then State.AimPart = F.AimPart end
            if F.AimKey ~= nil then State.AimKey = F.AimKey end
            if F.MatchRadius ~= nil then State.MatchRadius = F.MatchRadius end
            if F.HitChance ~= nil then State.SilentHitChance = F.HitChance end
            if F.HeadChance ~= nil then State.SilentHeadChance = F.HeadChance end
            if F.Pred ~= nil then State.Prediction = F.Pred end
            if F.MaxDist ~= nil then State.MaxDist = F.MaxDist end
            if F.TracerFrom ~= nil then State.TracerFrom = F.TracerFrom end
            if F.ESPColor ~= nil then State.ESPColor = F.ESPColor end
            if F.MaxESP ~= nil then State.MaxESPDist = F.MaxESP end
            if F.CamFOV ~= nil then State.CamFOV = F.CamFOV end
            applyCamFOV()
            if FOVCircle then FOVCircle.Radius = State.FOV end
            notify("Config", "Loaded → " .. tostring(name))
        else
            notify("Config", "Load failed / not found")
        end
    end,
})

CFG_L:AddButton({
    Name = "Delete Config",
    Callback = function()
        local name = Library.ConfigName or "default"
        local path = (Library.ConfigFolder or "R1K0V_HUB") .. "/" .. name .. ".json"
        local ok = pcall(function()
            if isfile and isfile(path) and delfile then
                delfile(path)
            end
        end)
        if ok then
            notify("Config", "Deleted → " .. tostring(name))
        else
            notify("Config", "Delete failed")
        end
    end,
})

CFG_L:AddButton({
    Name = "List Configs",
    Callback = function()
        local list = {}
        pcall(function()
            list = Library:ListConfigs() or {}
        end)
        if #list == 0 then
            notify("Configs", "Ninguna guardada")
        else
            notify("Configs", table.concat(list, ", "))
        end
    end,
})

CFG_R:AddLabel("Carpeta: R1K0V_HUB/")
CFG_R:AddLabel("Archivo: <nombre>.json")
CFG_R:AddLabel("Save = guarda todos los flags")
CFG_R:AddLabel("Load = aplica a UI + State")
CFG_R:AddLabel("Todo arranca OFF por defecto")

notify("Have a fun ;)")

