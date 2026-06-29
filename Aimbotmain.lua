task.spawn(function()
    local dots = {"", ".", "..", "..."}
    for i = 1, 12 do
        print("Loading" .. dots[(i % 4) + 1])
        task.wait(0.25)
    end
    print("✨ Load Script Thanh Cong! ✨")
end)

task.wait(3)

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")

local CoreGui = nil
pcall(function()
    CoreGui = game:GetService("CoreGui")
end)

local LocalPlayer = Players.LocalPlayer
local Mouse = LocalPlayer:GetMouse()
local Camera = workspace.CurrentCamera

local AimAssistEnabled = false
local CurrentTarget = nil
local lastScanTime = 0
local scanInterval = 0.03

local originalHitboxes = {}
local HITBOX_SIZE = Vector3.new(10, 10, 10)

local function resetHitbox(hrp, originalSize)
    if hrp and hrp.Parent then
        hrp.Size = originalSize
        hrp.Massless = false
        hrp.CanCollide = true
    end
end

local function cleanAllHitboxes()
    for hrp, originalSize in pairs(originalHitboxes) do
        pcall(function()
            resetHitbox(hrp, originalSize)
        end)
    end
    table.clear(originalHitboxes)
end

local function findNearestPlayer()
    local character = LocalPlayer.Character
    if not character or not character:FindFirstChild("HumanoidRootPart") then return nil end
    
    local myHrp = character.HumanoidRootPart
    local closestTarget = nil
    local maxDistance = math.huge
    
    for _, p in pairs(Players:GetPlayers()) do
        if p ~= LocalPlayer and p.Character then
            local hrp = p.Character:FindFirstChild("HumanoidRootPart")
            local hum = p.Character:FindFirstChildOfClass("Humanoid")
            if hrp and hum and hum.Health > 0 then
                local distance = (myHrp.Position - hrp.Position).Magnitude
                if distance < maxDistance then
                    maxDistance = distance
                    closestTarget = hrp
                end
            end
        end
    end
    return closestTarget
end

local mt = getrawmetatable(game)
local oldIndex = mt.__index
local oldNamecall = mt.__namecall
setreadonly(mt, false)

mt.__index = newcclosure(function(self, key)
    if AimAssistEnabled and CurrentTarget and checkcaller() == false then
        if self == Mouse and (key == "Hit" or key == "CFrame") then
            return CurrentTarget.CFrame
        elseif self == Mouse and key == "Target" then
            return CurrentTarget
        end
    end
    return oldIndex(self, key)
end)

mt.__namecall = newcclosure(function(self, ...)
    local method = getnamecallmethod()
    local args = {...}
    
    if AimAssistEnabled and CurrentTarget and checkcaller() == false then
        if method == "FireServer" or method == "InvokeServer" then
            for i, arg in pairs(args) do
                if typeof(arg) == "Vector3" then
                    args[i] = CurrentTarget.Position
                elseif typeof(arg) == "CFrame" then
                    args[i] = CurrentTarget.CFrame
                end
            end
            return oldNamecall(self, unpack(args))
        end
        if method == "GetMouseLocation" then
            local screenPos, onScreen = Camera:WorldToViewportPoint(CurrentTarget.Position)
            return Vector2.new(screenPos.X, screenPos.Y)
        end
        if method == "GetMouseRay" or method == "ViewportPointToRay" or method == "ScreenPointToRay" then
            return Ray.new(Camera.CFrame.Position, (CurrentTarget.Position - Camera.CFrame.Position).Unit * 1000)
        end
        if method == "GetMouseProductInfo" or method == "FindPartOnRay" or method == "FindPartOnRayWithIgnoreList" then
            return CurrentTarget, CurrentTarget.Position
        end
    end
    return oldNamecall(self, ...)
end)

setreadonly(mt, true)

local function createUI()
    local screenGui = Instance.new("ScreenGui")
    screenGui.Name = "AimAssistGUI"
    screenGui.ResetOnSpawn = false
    
    if CoreGui then
        screenGui.Parent = CoreGui
    else
        screenGui.Parent = LocalPlayer:WaitForChild("PlayerGui")
    end
    
    local aimButton = Instance.new("TextButton")
    aimButton.Name = "AimButton"
    aimButton.Size = UDim2.new(0, 120, 0, 50)
    aimButton.Position = UDim2.new(0.5, -60, 0.3, 0)
    aimButton.BackgroundColor3 = Color3.fromRGB(200, 50, 50)
    aimButton.Text = "AIM: OFF"
    aimButton.TextColor3 = Color3.fromRGB(255, 255, 255)
    aimButton.Font = Enum.Font.SourceSansBold
    aimButton.TextSize = 18
    aimButton.Active = true
    aimButton.Parent = screenGui
    
    local uiCorner = Instance.new("UICorner")
    uiCorner.CornerRadius = UDim.new(0, 8)
    uiCorner.Parent = aimButton
    
    local dragging = false
    local dragInput = nil
    local dragStart = nil
    local startPos = nil
    
    local function updateInput(input)
        local delta = input.Position - dragStart
        aimButton.Position = UDim2.new(
            startPos.X.Scale, 
            startPos.X.Offset + delta.X, 
            startPos.Y.Scale, 
            startPos.Y.Offset + delta.Y
        )
    end
    
    aimButton.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
            dragging = true
            dragStart = input.Position
            startPos = aimButton.Position
            
            input.Changed:Connect(function()
                if input.UserInputState == Enum.UserInputState.End then
                    dragging = false
                end
            end)
        end
    end)
    
    aimButton.InputChanged:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch then
            dragInput = input
        end
    end)
    
    UserInputService.InputChanged:Connect(function(input)
        if input == dragInput and dragging then
            updateInput(input)
        end
    end)
    
    aimButton.MouseButton1Click:Connect(function()
        AimAssistEnabled = not AimAssistEnabled
        if AimAssistEnabled then
            aimButton.Text = "AIM: ON"
            aimButton.BackgroundColor3 = Color3.fromRGB(50, 200, 50)
        else
            aimButton.Text = "AIM: OFF"
            aimButton.BackgroundColor3 = Color3.fromRGB(200, 50, 50)
            CurrentTarget = nil
            cleanAllHitboxes()
        end
    end)
end

createUI()

RunService.Heartbeat:Connect(function()
    if AimAssistEnabled then
        local currentTime = os.clock()
        if currentTime - lastScanTime >= scanInterval then
            lastScanTime = currentTime
            
            local target = findNearestPlayer()
            if target then
                CurrentTarget = target
                
                if not originalHitboxes[target] then
                    originalHitboxes[target] = target.Size
                end
                
                target.Size = HITBOX_SIZE
                target.Massless = true
                target.CanCollide = false
            else
                CurrentTarget = nil
            end
            
            for hrp, originalSize in pairs(originalHitboxes) do
                if hrp ~= CurrentTarget then
                    pcall(function()
                        resetHitbox(hrp, originalSize)
                    end)
                    originalHitboxes[hrp] = nil
                end
            end
        end
    else
        CurrentTarget = nil
        cleanAllHitboxes()
    end
end)
