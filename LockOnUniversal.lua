--[[ 
    Roblox Script: Lock-On Nearest Target (Player or NPC) Button GUI (Retro Roblox UI + SFX)
    - Universal ragdoll detection & lock disables while ragdolled
    - When ragdolled, lock disengages and resumes after ragdoll ends if possible
    - (Rest of the original header...)
]]

--// SERVICES
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local StarterGui = game:GetService("StarterGui")
local TweenService = game:GetService("TweenService")
local SoundService = game:GetService("SoundService")
local CollectionService = game:GetService("CollectionService")
local Workspace = game:GetService("Workspace")
local LocalPlayer = Players.LocalPlayer

--// RETRO SFX SETUP (uses built-in Roblox sound asset)
local retroSFX = Instance.new("Sound")
retroSFX.SoundId = "rbxassetid://12221967" -- Old Roblox button click SFX
retroSFX.Volume = 0.65
retroSFX.Name = "RetroLockSFX"
retroSFX.Parent = SoundService

--// GUI CREATION
local ScreenGui = Instance.new("ScreenGui")
ScreenGui.Name = "LockOnGui"
ScreenGui.ResetOnSpawn = false
ScreenGui.IgnoreGuiInset = true
ScreenGui.Parent = LocalPlayer:WaitForChild("PlayerGui")

local Frame = Instance.new("Frame")
Frame.Name = "LockOnFrame"
Frame.Size = UDim2.new(0, 220, 0, 60)
Frame.Position = UDim2.new(0.5, -110, 0.88, 0)
Frame.AnchorPoint = Vector2.new(0.5, 0)
Frame.BackgroundColor3 = Color3.fromRGB(163, 162, 165) -- Classic Roblox gray
Frame.BorderColor3 = Color3.fromRGB(27, 42, 53) -- Retro border
Frame.BorderSizePixel = 2
Frame.Active = true
Frame.Parent = ScreenGui

local TitleBar = Instance.new("TextLabel")
TitleBar.Name = "TitleBar"
TitleBar.Size = UDim2.new(1, 0, 0, 20)
TitleBar.Position = UDim2.new(0, 0, 0, 0)
TitleBar.BackgroundColor3 = Color3.fromRGB(49, 49, 49)
TitleBar.BorderColor3 = Color3.fromRGB(27, 42, 53)
TitleBar.BorderSizePixel = 1
TitleBar.Text = "Lock-On"
TitleBar.Font = Enum.Font.Legacy
TitleBar.TextColor3 = Color3.fromRGB(255, 255, 255)
TitleBar.TextSize = 16
TitleBar.TextXAlignment = Enum.TextXAlignment.Left
TitleBar.TextYAlignment = Enum.TextYAlignment.Center
TitleBar.ClipsDescendants = true
TitleBar.Parent = Frame

local LockButton = Instance.new("TextButton")
LockButton.Name = "LockOnButton"
LockButton.Size = UDim2.new(1, -14, 0, 28)
LockButton.Position = UDim2.new(0, 7, 0, 26)
LockButton.BackgroundColor3 = Color3.fromRGB(190, 190, 190)
LockButton.BorderColor3 = Color3.fromRGB(27, 42, 53)
LockButton.BorderSizePixel = 2
LockButton.TextColor3 = Color3.fromRGB(33, 33, 33)
LockButton.Text = "Lock-On"
LockButton.Font = Enum.Font.Legacy
LockButton.TextSize = 18
LockButton.AutoButtonColor = false
LockButton.ZIndex = 2
LockButton.Parent = Frame

--// RETRO EFFECT (scanlines overlay)
local Scanlines = Instance.new("ImageLabel")
Scanlines.Name = "Scanlines"
Scanlines.BackgroundTransparency = 1
Scanlines.Image = "rbxassetid://14897047154" -- Free scanline overlay, replaceable
Scanlines.Size = UDim2.new(1, 0, 1, 0)
Scanlines.Position = UDim2.new(0,0,0,0)
Scanlines.ImageTransparency = 0.57
Scanlines.Parent = Frame
Scanlines.ZIndex = 100

--// RETRO BUTTON ANIMATION (pressed color flicker)
local function retroButtonFlicker()
	LockButton.BackgroundColor3 = Color3.fromRGB(180, 140, 60)
	wait(0.08)
	LockButton.BackgroundColor3 = Color3.fromRGB(190, 190, 190)
end

--// VARIABLES
local locked = false
local ignoreTarget = nil
local ignoreUntil = 0
local lockTarget = nil
local targetDeathConn = nil
local targetRemovalConn = nil

--// Universal ragdoll-related variables
local wasRagdolled = false
local preRagdollTarget = nil

--// NOTIFICATION FUNCTION (1 second duration)
local function notify(title, text)
	StarterGui:SetCore("SendNotification", {
		Title = title or "Notice";
		Text = text or "";
		Duration = 1;
	})
end

--// SHOW SpookzWasHere NOTIFICATION ON SCRIPT LOAD
task.spawn(function()
    -- Show for 1.5 seconds so it doesn't overlap with other notifications
    StarterGui:SetCore("SendNotification", {
        Title = "Made by SpookzWasHere";
        Text = "Activate script by pressing the ui button or V";
        Duration = 1.5;
    })
end)

--// CLEANUP OLD CONNECTIONS
local function disconnectTargetEvents()
	if targetDeathConn then
		targetDeathConn:Disconnect()
		targetDeathConn = nil
	end
	if targetRemovalConn then
		targetRemovalConn:Disconnect()
		targetRemovalConn = nil
	end
end

--// AUTO UNLOCK IF TARGET DIES OR REMOVED
local function watchTarget(targetModel)
	disconnectTargetEvents()
	if not targetModel then return end
	local humanoid = targetModel:FindFirstChildOfClass("Humanoid")
	if humanoid then
		targetDeathConn = humanoid.Died:Connect(function()
			locked = false
			LockButton.Text = "Lock-On"
			LockButton.TextColor3 = Color3.fromRGB(33,33,33)
			LockButton.BackgroundColor3 = Color3.fromRGB(190, 190, 190)
			notify("Lock-Off", "Target died!")
			lockTarget = nil
			disconnectTargetEvents()
		end)
	end
	targetRemovalConn = targetModel.AncestryChanged:Connect(function()
		if not targetModel:IsDescendantOf(Workspace) then
			if locked then
				locked = false
				LockButton.Text = "Lock-On"
				LockButton.TextColor3 = Color3.fromRGB(33,33,33)
				LockButton.BackgroundColor3 = Color3.fromRGB(190, 190, 190)
				notify("Lock-Off", "Target removed!")
				lockTarget = nil
				disconnectTargetEvents()
			end
		end
	end)
end

--// GET ALL VALID TARGETS: Players and NPCs
local function getValidTargets()
	local myChar = LocalPlayer.Character
	if not myChar or not myChar:FindFirstChild("HumanoidRootPart") then return {} end

	local valid = {}

	-- Add all players except self and ignored target
	for _, player in ipairs(Players:GetPlayers()) do
		if player ~= LocalPlayer and player.Character and player.Character:FindFirstChild("HumanoidRootPart") then
			local humanoid = player.Character:FindFirstChildOfClass("Humanoid")
			if humanoid and humanoid.Health > 0 and player.Character ~= ignoreTarget then
				table.insert(valid, player.Character)
			end
		end
	end

	-- Add NPCs: Models with HumanoidRootPart, Humanoid, not a player character, alive, and not ignored
	for _, model in ipairs(Workspace:GetDescendants()) do
		if model:IsA("Model") 
			and model ~= myChar
			and model ~= ignoreTarget
			and not Players:GetPlayerFromCharacter(model)
			and model:FindFirstChild("HumanoidRootPart")
		then
			local humanoid = model:FindFirstChildOfClass("Humanoid")
			if humanoid and humanoid.Health > 0 then
				table.insert(valid, model)
			end
		end
	end

	return valid
end

local function getDistance(pos1, pos2)
    return (pos1 - pos2).Magnitude
end

local function getNearestTarget()
    local myChar = LocalPlayer.Character
    if not myChar or not myChar:FindFirstChild("HumanoidRootPart") then return nil end
    local myPos = myChar.HumanoidRootPart.Position

    local nearest, minDist = nil, math.huge
    for _, character in ipairs(getValidTargets()) do
        if character and character:FindFirstChild("HumanoidRootPart") then
            local dist = getDistance(myPos, character.HumanoidRootPart.Position)
            if dist < minDist then
                minDist = dist
                nearest = character
            end
        end
    end
    return nearest
end

local function getTargetName(targetModel)
	local player = Players:GetPlayerFromCharacter(targetModel)
	if player then
		return player.DisplayName or player.Name
	end
	return targetModel.Name
end

local function rotateToTarget(targetModel)
    local myChar = LocalPlayer.Character
    if not (myChar and targetModel) then return end
    local hrp = myChar:FindFirstChild("HumanoidRootPart")
    local targetHRP = targetModel:FindFirstChild("HumanoidRootPart")
    if not (hrp and targetHRP) then return end

    local lookVec = (targetHRP.Position - hrp.Position)
    local flatLook = Vector3.new(lookVec.X, 0, lookVec.Z)
    if flatLook.Magnitude < 0.1 or not flatLook.Unit then return end

    local success, unit = pcall(function() return flatLook.Unit end)
    if not success or not unit then return end

    hrp.CFrame = CFrame.new(hrp.Position, hrp.Position + unit)
end

--// UNIVERSAL RAGDOLL DETECTION FUNCTION
local function isRagdolled()
    local character = LocalPlayer.Character
    if not character then return false end
    
    local humanoid = character:FindFirstChild("Humanoid")
    if not humanoid then return false end

    -- Method 1: Humanoid state is Physics
    if humanoid:GetState() == Enum.HumanoidStateType.Physics then
        return true
    end

    -- Method 2: Attribute "Ragdolled"
    if humanoid:GetAttribute("Ragdolled") or character:GetAttribute("Ragdolled") then
        return true
    end

    -- Method 3: Check for RootJoint/Torso root broken
    local rootPart = character:FindFirstChild("HumanoidRootPart")
    if rootPart then
        local rootJoint = rootPart:FindFirstChild("RootJoint")
        if not rootJoint and character:FindFirstChild("Torso") then
            rootJoint = character.Torso:FindFirstChild("Root")
        end
        if rootJoint and (rootJoint.Enabled == false or rootJoint.Parent == nil) then
            return true
        end
    end

    -- Method 4: PlatformStand true
    if humanoid.PlatformStand then
        return true
    end

    -- Method 5: Child named Ragdolled (Value)
    if character:FindFirstChild("Ragdolled") or humanoid:FindFirstChild("Ragdolled") then
        return true
    end

    return false
end

--// MAIN LOCK-ON LOOP (Updated for universal ragdoll logic)
RunService.RenderStepped:Connect(function()
    local ragdolled = isRagdolled()
    if ragdolled and not wasRagdolled and locked then
        -- Just got ragdolled while locked
        preRagdollTarget = lockTarget
        locked = false
        notify("Lock-Off", "Lock disabled while ragdolled")
    elseif not ragdolled and wasRagdolled and preRagdollTarget then
        -- Just recovered from ragdoll
        if preRagdollTarget:IsDescendantOf(game) then
            lockTarget = preRagdollTarget
            locked = true
            watchTarget(preRagdollTarget)
            notify("Lock-On", "Resumed locking after ragdoll")
            LockButton.Text = "Unlock"
            LockButton.TextColor3 = Color3.fromRGB(33,33,33)
            LockButton.BackgroundColor3 = Color3.fromRGB(190, 190, 190)
        end
        preRagdollTarget = nil
    end
    wasRagdolled = ragdolled
    if locked and lockTarget and lockTarget:FindFirstChild("HumanoidRootPart") and not ragdolled then
        rotateToTarget(lockTarget)
    end
end)

--// LOCK/UNLOCK LOGIC (shared by button and V key)
local function doToggleLock()
	pcall(function() retroSFX:Play() end)
	retroButtonFlicker()

    if locked then
        LockButton.Text = "Lock-On"
        LockButton.TextColor3 = Color3.fromRGB(33,33,33)
        LockButton.BackgroundColor3 = Color3.fromRGB(190, 190, 190)
        ignoreTarget = lockTarget
        ignoreUntil = tick() + 3
        locked = false
        disconnectTargetEvents()
        notify("Lock-Off", "Ignoring last target for 3 seconds...")
        local prevTarget = lockTarget
        lockTarget = nil
        task.spawn(function()
            local remaining = ignoreUntil - tick()
            if remaining > 0 then task.wait(remaining) end
            if ignoreTarget == prevTarget then
                ignoreTarget = nil
            end
        end)
    else
        if isRagdolled() then
            notify("Can't Lock-On", "You are currently ragdolled!")
            return
        end
        local nearest = getNearestTarget()
        if nearest then
            LockButton.Text = "Unlock"
            LockButton.TextColor3 = Color3.fromRGB(33,33,33)
            LockButton.BackgroundColor3 = Color3.fromRGB(190, 190, 190)
            lockTarget = nearest
            locked = true
            watchTarget(nearest)
            notify("Locked-On!", "Now locking on to: " .. (getTargetName(nearest) or "Unknown"))
        else
            LockButton.Text = "Lock-On"
            LockButton.TextColor3 = Color3.fromRGB(33,33,33)
            LockButton.BackgroundColor3 = Color3.fromRGB(190, 190, 190)
            notify("No Targets", "No nearby targets (players or NPCs) found!")
        end
    end
end

--// BUTTON HANDLER
LockButton.MouseButton1Click:Connect(doToggleLock)

--// KEYBOARD HANDLER (V KEY)
local UserInputService = game:GetService("UserInputService")
UserInputService.InputBegan:Connect(function(input, processed)
    if processed then return end
    if input.KeyCode == Enum.KeyCode.V then
        doToggleLock()
    end
end)

LocalPlayer.CharacterAdded:Connect(function()
    locked = false
    lockTarget = nil
    ignoreTarget = nil
    wasRagdolled = false
    preRagdollTarget = nil
    LockButton.Text = "Lock-On"
    LockButton.TextColor3 = Color3.fromRGB(33,33,33)
    LockButton.BackgroundColor3 = Color3.fromRGB(190, 190, 190)
    disconnectTargetEvents()
    notify("Ready", "Ready to Lock-On!")
end)

--// DRAGGABLE UI (mouse & touch, via TitleBar only for retro feel)
local dragging = false
local dragStart, startPos

TitleBar.InputBegan:Connect(function(input)
	if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
		dragging = true
		dragStart = input.Position
		startPos = Frame.Position
		input.Changed:Connect(function()
			if input.UserInputState == Enum.UserInputState.End then
				dragging = false
			end
		end)
	end
end)

TitleBar.InputChanged:Connect(function(input)
	if input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch then
		if dragging then
			local delta = input.Position - dragStart
			Frame.Position = UDim2.new(
				startPos.X.Scale,
				startPos.X.Offset + delta.X,
				startPos.Y.Scale,
				startPos.Y.Offset + delta.Y
			)
		end
	end
end)

UserInputService.InputChanged:Connect(function(input)
	if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
		local delta = input.Position - dragStart
		Frame.Position = UDim2.new(
			startPos.X.Scale,
			startPos.X.Offset + delta.X,
			startPos.Y.Scale,
			startPos.Y.Offset + delta.Y
		)
	end
end)

--// END
