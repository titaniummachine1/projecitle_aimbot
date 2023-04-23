--[[
    Custom Aimbot for Lmaobox
    Author: github.com/lnx00
]]

---@alias AimTarget { entity : Entity, pos : Vector3, angles : EulerAngles, factor : number }

---@type boolean, lnxLib
local libLoaded, lnxLib = pcall(require, "lnxLib")
assert(libLoaded, "lnxLib not found, please install it!")
assert(lnxLib.GetVersion() >= 0.967, "LNXlib version is too old, please update it!")

local menuLoaded, MenuLib = pcall(require, "Menu")                                -- Load MenuLib
assert(menuLoaded, "MenuLib not found, please install it!")                       -- If not found, throw error
assert(MenuLib.Version >= 1.44, "MenuLib version is too old, please update it!")  -- If version is too old, throw error

--[[ Menu ]]--
local menu = MenuLib.Create("Projectile aimbot", MenuFlags.AutoSize)
menu.Style.TitleBg = { 205, 95, 50, 255 } -- Title Background Color (Flame Pea)
menu.Style.Outline = true                 -- Outline around the menu

local mAimbot       = menu:AddComponent(MenuLib.Checkbox("Aimbot", true))
local mSilent       = menu:AddComponent(MenuLib.Checkbox("Silent", true))
local mAutoshoot    = menu:AddComponent(MenuLib.Checkbox("AutoShoot", true))
local mtime         = menu:AddComponent(MenuLib.Slider("time", 1 ,50, 2 ))
local mmVisuals     = menu:AddComponent(MenuLib.Checkbox("fov Circle", false))
local mFov          = menu:AddComponent(MenuLib.Slider("fov", 1 ,360, 360 ))
local mKey          = menu:AddComponent(MenuLib.Keybind("LAimbot Key", key))
local mdelay        = menu:AddComponent(MenuLib.Slider("dt delay", 1 ,24, 20 ))

local Hitbox = {
    Head = 1,
    Neck = 2,
    Pelvis = 4,
    Body = 5,
    Chest = 7
}

local Hitboxes = {
    1,
    2,
    4,
    5,
    7
}

local mhibox = menu:AddComponent(MenuLib.Combo("^Hitboxes", Hitboxes, ItemFlags.FullWidth))

local Math = lnxLib.Utils.Math
local WPlayer = lnxLib.TF2.WPlayer
local Helpers = lnxLib.TF2.Helpers

local targetFuture = nil -- added line to store target future vector

local options = {
    AimKey      = KEY_LSHIFT,
    AutoShoot   = mAutoshoot:GetValue(),
    Silent      = mSilent:GetValue(),
    AimFov      = mFov:GetValue()
}

local currentTarget = nil


function TargetPositionPrediction(targetLastPos, tickRate, time, targetEntity)
    -- If the last known position of the target is nil, return nil.
    if targetLastPos == nil then
        return nil
    end

    -- Initialize targetVelocitySamples as a table if it doesn't exist.
    if not targetVelocitySamples then
        targetVelocitySamples = {}
    end

    -- Initialize the table for this target if it doesn't exist.
    local targetKey = tostring(targetLastPos)
    if not targetVelocitySamples[targetKey] then
        targetVelocitySamples[targetKey] = {}
    end

    -- Insert the latest velocity sample into the table.
    local targetVelocity = targetEntity:EstimateAbsVelocity()
    if targetVelocity == nil then
        targetVelocity = targetLastPos - targetEntity:GetOrigin()
    end
    table.insert(targetVelocitySamples[targetKey], 1, targetVelocity)

    local samples = 2
    -- Remove the oldest sample if there are more than maxSamples.
    if #targetVelocitySamples[targetKey] > samples then
        table.remove(targetVelocitySamples[targetKey], samples + 1)
    end

    -- Calculate the average velocity from the samples.
    local totalVelocity = Vector3(0, 0, 0)
    for i = 1, #targetVelocitySamples[targetKey] do
        totalVelocity = totalVelocity + targetVelocitySamples[targetKey][i]
    end
    local averageVelocity = totalVelocity / #targetVelocitySamples[targetKey]

    -- Initialize the curve to a zero vector.
    local curve = Vector3(0, 0, 0)

    -- Calculate the curve of the path if there are enough samples.
    if #targetVelocitySamples[targetKey] >= 2 then
        local previousVelocity = targetVelocitySamples[targetKey][1]
        for i = 2, #targetVelocitySamples[targetKey] do
            local currentVelocity = targetVelocitySamples[targetKey][i]
            curve = curve + (previousVelocity - currentVelocity)
            previousVelocity = currentVelocity
        end
        curve = curve / (#targetVelocitySamples[targetKey] - 1)
    end

    -- Scale the curve by the tick rate and time to predict.
    curve = curve * 66

    -- Calculate the current predicted position.
    targetFuture = targetLastPos + (averageVelocity) + curve

    -- Return the predicted future position.
    return targetFuture
end








-- Returns the best target (lowest fov)
---@param me WPlayer
---@return AimTarget? target
local function GetBestTarget(me)
    local players = entities.FindByClass("CTFPlayer")
    local target = nil
    local lastFov = math.huge

    for _, entity in pairs(players) do
        if not entity then goto continue end
        if not entity:IsAlive() then goto continue end
        if entity:GetTeamNumber() == entities.GetLocalPlayer():GetTeamNumber() then goto continue end
        local pLocal = entities.GetLocalPlayer()
        local pLocalOriginLast = me:GetAbsOrigin()
        local targetOrigin = entity:GetAbsOrigin()
        local pLocalOrigin = me:GetEyePos()
        local tickRate = 66
        local targetEntity = entity
        local bulletNozzleVelocity = 1100
        -- Calculate the predicted position of the target
        targetFuture = (entity:GetAbsOrigin() + entity:EstimateAbsVelocity())
        if not targetFuture then goto continue end
        local targetVelocity = targetEntity:EstimateAbsVelocity()
        local predictedPos = targetOrigin + targetVelocity * tickRate
        
        local distance = (predictedPos - pLocalOrigin):Length()
        local travelTime = distance / bulletNozzleVelocity
       -- local predictedSpeed = distance / travelTime
        --local averageSpeed = (targetVelocity:Length() + predictedSpeed) / 2
        
        targetFuture = TargetPositionPrediction(targetOrigin, tickRate, travelTime, targetEntity)
        
        -- FOV Check
        local player = WPlayer.FromEntity(entity)
        local aimPos = targetFuture
        local angles = Math.PositionAngles(me:GetEyePos(), aimPos)
        local fov = Math.AngleFov(angles, engine.GetViewAngles())
        
        if fov > options.AimFov then goto continue end

        -- Visiblity Check
        if not Helpers.VisPos(entity, me:GetEyePos(), aimPos) then goto continue end

        -- Add valid target
        if fov < lastFov then
            lastFov = fov
            target = { entity = entity, pos = aimPos, angles = angles, factor = fov }
        end
        
        ::continue::
    end

    return target
end

lasttarget = Vector3(0, 0, 0)

---@param userCmd UserCmd
local function OnCreateMove(userCmd)

    options = {
        AimKey      = KEY_LSHIFT,
        AutoShoot   = mAutoshoot:GetValue(),
        Silent      = mSilent:GetValue(),
        AimPos      = Hitbox.Head,
        AimFov      = mFov:GetValue()
    }

    local me = WPlayer.GetLocal()
    if not me then return end

    -- Get the best target
    currentTarget = GetBestTarget(me)
    if not currentTarget then return end
    --predict position
    --currentTarget = TargetPositionPrediction(currentTarget.pos, lasttarget.pos, mtime, currentTarget)
    if not input.IsButtonDown(options.AimKey) then return end
    -- Aim at the target
    userCmd:SetViewAngles(currentTarget.angles:Unpack())
    if not options.Silent then
        engine.SetViewAngles(currentTarget.angles)
    end
    local pWeapon = me:GetPropEntity("m_hActiveWeapon")
    -- Auto Shoot
    
    if options.AutoShoot then
        userCmd.buttons = userCmd.buttons | IN_ATTACK
    end
    lasttarget = currentTarget
end

local myfont = draw.CreateFont( "Verdana", 16, 800 ) -- Create a font for doDraw
local function OnDraw()
    if not currentTarget then return end

    local me = WPlayer.GetLocal()
    if not me then return end

    if engine.Con_IsVisible() or engine.IsGameUIVisible() then
        return
    end
        draw.SetFont( myfont )
        draw.Color( 255, 255, 255, 255 )
        local w, h = draw.GetScreenSize()
        local screenPos = { w / 2 - 15, h / 2 + 35}

        -- draw predicted enemy position with strafe prediction connecting his local point and predicted position with line.
            screenPos = client.WorldToScreen(targetFuture)
            if screenPos ~= nil then
                draw.Line( screenPos[1] + 10, screenPos[2], screenPos[1] - 10, screenPos[2])
                draw.Line( screenPos[1], screenPos[2] - 10, screenPos[1], screenPos[2] + 10)
            end
end

--[[ Remove the menu when unloaded ]]--
local function OnUnload()                                -- Called when the script is unloaded
    MenuLib.RemoveMenu(menu)                             -- Remove the menu
    client.Command('play "ui/buttonclickrelease"', true) -- Play the "buttonclickrelease" sound
end

client.Command('play "ui/buttonclickrelease"', true) -- Play the "buttonclickrelease" sound               
callbacks.Unregister("CreateMove", "LNX.Aimbot.CreateMove")
callbacks.Unregister("Unload", "MCT_Unload")                    -- Unregister the "Unload" callback
callbacks.Unregister("Draw", "LNX.Aimbot.Draw")

callbacks.Register("CreateMove", "LNX.Aimbot.CreateMove", OnCreateMove)
callbacks.Register("Unload", "MCT_Unload", OnUnload) -- Register the "Unload" callback
callbacks.Register("Draw", "LNX.Aimbot.Draw", OnDraw)

