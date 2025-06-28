local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Debris = game:GetService("Debris")
local ContextActionService = game:GetService("ContextActionService")

local player = Players.LocalPlayer
local character = player.Character or player.CharacterAdded:Wait()

-- Конфигурация
local TELEPORT_RANGE = 12
local FOLLOW_DURATION = 0.9
local FOLLOW_DISTANCE = -0.1
local TELEPORT_TIME = 0.5
local SPINE_OFFSET = -0.1

-- Поиск ближайшего игрока в радиусе TELEPORT_RANGE
local function findNearestPlayer()
    local closestPlayer = nil
    local closestDistance = TELEPORT_RANGE

    local myRoot = character and character:FindFirstChild("HumanoidRootPart")
    if not myRoot then return nil end

    for _, otherPlayer in pairs(Players:GetPlayers()) do
        if otherPlayer ~= player and otherPlayer.Character then
            local otherCharacter = otherPlayer.Character
            local otherTorso = otherCharacter:FindFirstChild("UpperTorso") or otherCharacter:FindFirstChild("Torso")
            if otherTorso then
                local distance = (otherTorso.Position - myRoot.Position).Magnitude
                if distance < closestDistance then
                    closestDistance = distance
                    closestPlayer = otherPlayer
                end
            end
        end
    end

    return closestPlayer
end

-- Эффекты телепортации
local function createTeleportEffects(hrp)
    local originParticles = Instance.new("ParticleEmitter")
    originParticles.Texture = "rbxassetid://243664672"
    originParticles.LightEmission = 0.8
    originParticles.Size = NumberSequence.new(0.5, 1.5)
    originParticles.Lifetime = NumberRange.new(0.5, 0.8)
    originParticles.Speed = NumberRange.new(2)
    originParticles.Rate = 30
    originParticles.Parent = hrp
    Debris:AddItem(originParticles, 1)

    local sound = Instance.new("Sound")
    sound.SoundId = "rbxassetid://130785805"
    sound.Parent = hrp
    sound:Play()
    Debris:AddItem(sound, 2)
end

local function createAppearEffects(hrp)
    local appearParticles = Instance.new("ParticleEmitter")
    appearParticles.Texture = "rbxassetid://243098098"
    appearParticles.LightEmission = 1
    appearParticles.Size = NumberSequence.new(1, 3)
    appearParticles.Lifetime = NumberRange.new(0.3, 0.6)
    appearParticles.Speed = NumberRange.new(1)
    appearParticles.Rate = 40
    appearParticles.Parent = hrp
    Debris:AddItem(appearParticles, 1)
end

-- Система следования с блокировкой поворота
local following = {
    active = false,
    connections = {},
    startTime = 0,
    originalGravity = nil,
    targetCharacter = nil
}

local function stopFollowing()
    if following.active then
        if following.originalGravity then
            workspace.Gravity = following.originalGravity
            following.originalGravity = nil
        end

        local humanoid = character and character:FindFirstChild("Humanoid")
        if humanoid then
            humanoid.AutoRotate = true
        end

        ContextActionService:UnbindAction("LockCameraRotation")
        ContextActionService:UnbindAction("BlockTurnLeft")
        ContextActionService:UnbindAction("BlockTurnRight")

        for _, connection in pairs(following.connections) do
            connection:Disconnect()
        end

        following.connections = {}
        following.active = false
        following.targetCharacter = nil
    end
end

local function lockCharacterRotation(char, lock)
    local humanoid = char and char:FindFirstChild("Humanoid")
    if humanoid then
        humanoid.AutoRotate = not lock
    end
end

local function blockInputAction(actionName, inputState, inputObject)
    if inputState == Enum.UserInputState.Begin then
        return Enum.ContextActionResult.Sink
    end
    return Enum.ContextActionResult.Pass
end

local function followTarget(targetCharacter)
    if following.active then return end

    following.active = true
    following.startTime = os.clock()
    following.targetCharacter = targetCharacter

    local myHRP = character and character:FindFirstChild("HumanoidRootPart")
    if not myHRP then return end

    lockCharacterRotation(character, true)

    following.originalGravity = workspace.Gravity
    workspace.Gravity = workspace.Gravity * 0.7

    ContextActionService:BindAction("LockCameraRotation", blockInputAction, false, Enum.UserInputType.MouseMovement)
    ContextActionService:BindAction("BlockTurnLeft", blockInputAction, false, Enum.KeyCode.A)
    ContextActionService:BindAction("BlockTurnRight", blockInputAction, false, Enum.KeyCode.D)

    table.insert(following.connections, RunService.Heartbeat:Connect(function()
        if os.clock() > following.startTime + FOLLOW_DURATION or not following.targetCharacter or not myHRP or not following.targetCharacter.Parent then
            stopFollowing()
            return
        end

        local targetTorso = following.targetCharacter:FindFirstChild("UpperTorso") or following.targetCharacter:FindFirstChild("Torso")
        local targetHRP = following.targetCharacter:FindFirstChild("HumanoidRootPart")

        if targetTorso and targetHRP then
            local spineCFrame = targetTorso.CFrame * CFrame.new(0, 0, SPINE_OFFSET)
            local lookVector = targetHRP.CFrame.LookVector
            local behindPosition = spineCFrame.Position - (lookVector * FOLLOW_DISTANCE)
            behindPosition = Vector3.new(behindPosition.X, myHRP.Position.Y, behindPosition.Z)
            local newCFrame = CFrame.new(behindPosition, behindPosition + lookVector)

            myHRP.CFrame = newCFrame
            myHRP.AssemblyLinearVelocity = Vector3.new()
            myHRP.AssemblyAngularVelocity = Vector3.new()
        end
    end))

    table.insert(following.connections, following.targetCharacter.AncestryChanged:Connect(function()
        stopFollowing()
    end))
end

-- Плавный телепорт с эффектами
local function smoothTeleport(char, targetCFrame)
    local hrp = char and char:FindFirstChild("HumanoidRootPart")
    if not hrp then return end

    local originalTransparency = {}

    for _, part in ipairs(char:GetDescendants()) do
        if part:IsA("BasePart") then
            originalTransparency[part] = part.Transparency
            part.Transparency = 0.7
        end
    end

    createTeleportEffects(hrp)

    local tweenInfo = TweenInfo.new(TELEPORT_TIME, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
    local tween = TweenService:Create(hrp, tweenInfo, {CFrame = targetCFrame})
    tween:Play()

    tween.Completed:Connect(function()
        for part, transparency in pairs(originalTransparency) do
            if part.Parent then
                part.Transparency = transparency
            end
        end
        createAppearEffects(hrp)
    end)
end

-- Основная функция телепортации за ближайшим игроком
local function teleportBehindNearestPlayer()
    local nearestPlayer = findNearestPlayer()
    if nearestPlayer and nearestPlayer.Character then
        local targetCharacter = nearestPlayer.Character
        local targetTorso = targetCharacter:FindFirstChild("UpperTorso") or targetCharacter:FindFirstChild("Torso")
        local targetHRP = targetCharacter:FindFirstChild("HumanoidRootPart")
        local myHRP = character and character:FindFirstChild("HumanoidRootPart")

        if targetTorso and targetHRP and myHRP then
            local spineCFrame = targetTorso.CFrame * CFrame.new(0, 0, SPINE_OFFSET)
            local lookVector = targetHRP.CFrame.LookVector
            local teleportCFrame = CFrame.new(spineCFrame.Position - (lookVector * FOLLOW_DISTANCE), spineCFrame.Position)
            teleportCFrame = CFrame.new(Vector3.new(teleportCFrame.Position.X, myHRP.Position.Y, teleportCFrame.Position.Z), teleportCFrame.Position + lookVector)

            smoothTeleport(character, teleportCFrame)
            followTarget(targetCharacter)
        end
    else
        warn("No players found within " .. TELEPORT_RANGE .. " studs")
    end
end

-- Создаем кнопку "TP" внизу экрана
local function createTeleportButton()
    local playerGui = player:WaitForChild("PlayerGui")
    local screenGui = Instance.new("ScreenGui")
    screenGui.Name = "TeleportGui"
    screenGui.ResetOnSpawn = false
    screenGui.Parent = playerGui

    local tpButton = Instance.new("TextButton")
    tpButton.Name = "TPButton"
    tpButton.Text = "TP"
    tpButton.Font = Enum.Font.SourceSansBold
    tpButton.TextSize = 24
    tpButton.TextColor3 = Color3.new(1, 1, 1)
    tpButton.BackgroundColor3 = Color3.fromRGB(0, 120, 255)
    tpButton.BackgroundTransparency = 0.2
    tpButton.Size = UDim2.new(0, 60, 0, 40)
    tpButton.Position = UDim2.new(0.5, -30, 0.85, 0)
    tpButton.AnchorPoint = Vector2.new(0.5, 0)
    tpButton.Parent = screenGui

    tpButton.MouseEnter:Connect(function()
        tpButton.BackgroundTransparency = 0
    end)
    tpButton.MouseLeave:Connect(function()
        tpButton.BackgroundTransparency = 0.2
    end)

    tpButton.MouseButton1Click:Connect(function()
        teleportBehindNearestPlayer()
    end)
end

createTeleportButton()

-- Обработка нажатия клавиши X
UserInputService.InputBegan:Connect(function(input, gameProcessed)
    if not gameProcessed and input.KeyCode == Enum.KeyCode.X then
        teleportBehindNearestPlayer()
    end
end)

-- Обновление персонажа при респавне
player.CharacterAdded:Connect(function(newCharacter)
    character = newCharacter
    stopFollowing()
end)
