local screen = {}
local Config = Config
local listSprite = {}

---------------------------------------
--- Source: https://github.com/citizenfx/lua/blob/luaglm-dev/cfx/libs/scripts/examples/scripting_gta.lua
--- Credits to gottfriedleibniz
local glm = require 'glm'

-- Cache common functions
local glm_rad = glm.rad
local glm_quatEuler = glm.quatEulerAngleZYX
local glm_rayPicking = glm.rayPicking

-- Cache direction vectors
local glm_up = glm.up()
local glm_forward = glm.forward()

local function ScreenPositionToCameraRay()
    local pos = GetFinalRenderedCamCoord()
    local rot = glm_rad(GetFinalRenderedCamRot(2))
    local q = glm_quatEuler(rot.z, rot.y, rot.x)
    return pos, glm_rayPicking(
        q * glm_forward,
        q * glm_up,
        glm_rad(screen.fov),
        screen.ratio,
        0.10000, -- GetFinalRenderedCamNearClip(),
        10000.0, -- GetFinalRenderedCamFarClip(),
        0, 0
    )
end
---------------------------------------
local playerPed
local GetEntityCoords = GetEntityCoords
local Wait = Wait

---@param flag number
---@param playerCoords vector
---@return number flag
---@return vector coords
---@return number distance
---@return number entity
---@return number entity_type
local function RaycastCamera(flag, playerCoords)
	if not playerPed then playerPed = PlayerPedId() end
	if not playerCoords then playerCoords = GetEntityCoords(playerPed) end

	local rayPos, rayDir = ScreenPositionToCameraRay()
	local destination = rayPos + 10000 * rayDir
	local rayHandle = StartShapeTestLosProbe(rayPos.x, rayPos.y, rayPos.z, destination.x, destination.y, destination.z, flag or -1, playerPed, 0)

	while true do
		local result, _, endCoords, _, entityHit = GetShapeTestResult(rayHandle)

		if result ~= 1 then
			local distance = playerCoords and #(playerCoords - endCoords)
			return endCoords, distance, entityHit, entityHit and GetEntityType(entityHit) or 0
		end

		Wait(0)
	end
end
exports('raycast', RaycastCamera)

local hasFocus = false

local function DisableNUI()
	SetNuiFocus(false, false)
	SetNuiFocusKeepInput(false)
	hasFocus = false
end

exports('DisableNUI', DisableNUI)

local targetActive = false

local function EnableNUI()
	if not targetActive or hasFocus then return end
	SetCursorLocation(0.5, 0.5)
	SetNuiFocus(true, true)
	SetNuiFocusKeepInput(true)
	hasFocus = true
end

local success  = false
local sendData = {}
local sendDistance = {}
local nuiData = {}
local table_wipe = table.wipe
local pairs = pairs
local CheckOptions

local function LeaveTarget()
	SetNuiFocus(false, false)
	SetNuiFocusKeepInput(false)
	success, hasFocus = false, false
	table_wipe(sendData)
	SendNUIMessage({response = 'leftTarget'})
end

exports('LeaveTarget', LeaveTarget)

local function DisableTarget(forcedisable)
	if (not targetActive and hasFocus and not Config.Toggle) or not forcedisable then return end
	SetNuiFocus(false, false)
	SetNuiFocusKeepInput(false)
	Wait(100)
	targetActive, success, hasFocus = false, false, false
	SendNUIMessage({response = "closeTarget"})
end

exports('DisableTarget', DisableTarget)

---@param entity number
---@param bool boolean
local function DrawOutlineEntity(entity, bool)
	if not Config.EnableOutline or IsEntityAPed(entity) then return end
	SetEntityDrawOutline(entity, bool)
	SetEntityDrawOutlineColor(Config.OutlineColor[1], Config.OutlineColor[2], Config.OutlineColor[3], Config.OutlineColor[4])
end

exports('DrawOutlineEntity', DrawOutlineEntity)

local IsDisabledControlPressed = IsDisabledControlPressed

---@param flag number
---@param data table
---@param entity number
---@param distance number
local function CheckEntity(flag, data, entity, distance)
	if not next(data) then return end
	table_wipe(sendDistance)
	table_wipe(nuiData)
	local slot = 0
	for _, data in pairs(data) do
		if CheckOptions(data, entity, distance) then
			slot += 1
			sendData[slot] = data
			sendData[slot].entity = entity
			nuiData[slot] = {
				icon = data.icon,
				label = data.label
			}
			sendDistance[data.distance] = true
		else sendDistance[data.distance] = false end
	end
	if not next(nuiData) then
		LeaveTarget()
		DrawOutlineEntity(entity, false)
		return
	end
	success = true
	SendNUIMessage({response = 'validTarget', data = nuiData})
	DrawOutlineEntity(entity, true)
	while targetActive and success do
		local _, dist, entity2, _ = RaycastCamera(flag)
		if entity ~= entity2 then
			LeaveTarget()
			DrawOutlineEntity(entity, false)
			break
		elseif not hasFocus and IsDisabledControlPressed(0, Config.MenuControlKey) then
			EnableNUI()
			DrawOutlineEntity(entity, false)
		else
			for k, v in pairs(sendDistance) do
				if v and dist > k then
					LeaveTarget()
					DrawOutlineEntity(entity, false)
					break
				end
			end
		end
		Wait(0)
	end
	LeaveTarget()
	DrawOutlineEntity(entity, false)
end

exports('CheckEntity', CheckEntity)

local Bones = Load('bones')
local GetEntityBoneIndexByName = GetEntityBoneIndexByName
local GetWorldPositionOfEntityBone = GetWorldPositionOfEntityBone

---@param coords vector
---@param entity number
---@param bonelist table
---@return boolean | number
---@return number?
---@return string?
local function CheckBones(coords, entity, bonelist)
	local closestBone = -1
	local closestDistance = 20
	local closestPos, closestBoneName
	for _, v in pairs(bonelist) do
		if Bones.Options[v] then
			local boneId = GetEntityBoneIndexByName(entity, v)
			local bonePos = GetWorldPositionOfEntityBone(entity, boneId)
			local distance = #(coords - bonePos)
			if closestBone == -1 or distance < closestDistance then
				closestBone, closestDistance, closestPos, closestBoneName = boneId, distance, bonePos, v
			end
		end
	end
	if closestBone ~= -1 then return closestBone, closestPos, closestBoneName
	else return false end
end

exports('CheckBones', CheckBones)

local Types    = {{}, {}, {}}
local Players  = {}
local Entities = {}
local Models   = {}
local Zones    = {}
local allowTarget = true

local SetPauseMenuActive = SetPauseMenuActive
local DisableAllControlActions = DisableAllControlActions
local EnableControlAction = EnableControlAction
local NetworkGetEntityIsNetworked = NetworkGetEntityIsNetworked
local NetworkGetNetworkIdFromEntity = NetworkGetNetworkIdFromEntity
local GetEntityModel = GetEntityModel
local IsPedAPlayer = IsPedAPlayer
local SetDrawOrigin = SetDrawOrigin
local DrawSprite = DrawSprite
local ClearDrawOrigin = ClearDrawOrigin
local HasStreamedTextureDictLoaded = HasStreamedTextureDictLoaded
local RequestStreamedTextureDict = RequestStreamedTextureDict

local function DrawTarget()
	CreateThread(function()
		while not HasStreamedTextureDictLoaded("shared") do Wait(10) RequestStreamedTextureDict("shared", true) end
		local sleep
		local r, g, b, a
		while targetActive do
			sleep = 500
			for _, zone in pairs(listSprite) do
				sleep = 0

				r = zone.targetoptions.drawColor?[1] or Config.DrawColor[1]
				g = zone.targetoptions.drawColor?[2] or Config.DrawColor[2]
				b = zone.targetoptions.drawColor?[3] or Config.DrawColor[3]
				a = zone.targetoptions.drawColor?[4] or Config.DrawColor[4]

				if zone.success then
					r = zone.targetoptions.successDrawColor?[1] or Config.SuccessDrawColor[1]
					g = zone.targetoptions.successDrawColor?[2] or Config.SuccessDrawColor[2]
					b = zone.targetoptions.successDrawColor?[3] or Config.SuccessDrawColor[3]
					a = zone.targetoptions.successDrawColor?[4] or Config.SuccessDrawColor[4]
				end

				SetDrawOrigin(zone.center.x, zone.center.y, zone.center.z, 0)
				DrawSprite("shared", "emptydot_32", 0, 0, 0.02, 0.035, 0, r, g, b, a)
				ClearDrawOrigin()
			end
			Wait(sleep)
		end
		listSprite = {}
	end)
end

local function EnableTarget()
	if not allowTarget or success or (Config.Framework == 'QB' and not LocalPlayer.state.isLoggedIn) or IsNuiFocused() then return end
	if not CheckOptions then CheckOptions = _ENV.CheckOptions end
	if targetActive or not CheckOptions then return end

	targetActive = true
	playerPed = PlayerPedId()
	screen.ratio = GetAspectRatio(true)
	screen.fov = GetFinalRenderedCamFov()
	if Config.DrawSprite then DrawTarget() end

	SendNUIMessage({response = 'openTarget'})
	CreateThread(function()
		repeat
			SetPauseMenuActive(false)
			DisableAllControlActions(0)
			EnableControlAction(0, 30, true)
			EnableControlAction(0, 31, true)

			if not hasFocus then
				EnableControlAction(0, 1, true)
				EnableControlAction(0, 2, true)
			end

			Wait(0)
		until not targetActive
	end)

	local flag

	while targetActive do
		local sleep = 0
		if flag == 30 then flag = -1 else flag = 30 end

		local coords, distance, entity, entityType = RaycastCamera(flag)
		if distance <= Config.MaxDistance then
			if entityType > 0 then

				-- Local(non-net) entity targets
				if Entities[entity] then
					CheckEntity(flag, Entities[entity], entity, distance)
				end

				-- Owned entity targets
				if NetworkGetEntityIsNetworked(entity) then
					local data = Entities[NetworkGetNetworkIdFromEntity(entity)]
					if data then CheckEntity(flag, data, entity, distance) end
				end

				-- Player and Ped targets
				if entityType == 1 then
					local data = Models[GetEntityModel(entity)]
					if IsPedAPlayer(entity) then data = Players end
					if data and next(data) then CheckEntity(flag, data, entity, distance) end

				-- Vehicle bones
				elseif entityType == 2 then
					local closestBone, _, closestBoneName = CheckBones(coords, entity, Bones.Vehicle)
					local data = Bones.Options[closestBoneName]
					if data and next(data) and closestBone then
						table_wipe(sendDistance)
						table_wipe(nuiData)
						local slot = 0
						for _, data in pairs(data) do
							if CheckOptions(data, entity, distance) then
								slot += 1
								sendData[slot] = data
								sendData[slot].entity = entity
								nuiData[slot] = {
									icon = data.icon,
									label = data.label
								}
								sendDistance[data.distance] = true
							else sendDistance[data.distance] = false end
						end
						if next(nuiData) then
							success = true
							SendNUIMessage({response = 'validTarget', data = nuiData})
							DrawOutlineEntity(entity, true)
							while targetActive and success do
								local _, dist, entity2 = RaycastCamera(flag)
								if entity == entity2 then
									local closestBone2 = CheckBones(coords, entity, Bones.Vehicle)
									if closestBone ~= closestBone2 then
										LeaveTarget()
										DrawOutlineEntity(entity, false)
										break
									elseif not hasFocus and IsDisabledControlPressed(0, Config.MenuControlKey) then
										EnableNUI()
										DrawOutlineEntity(entity, false)
									else
										for k, v in pairs(sendDistance) do
											if v and dist > k then
												LeaveTarget()
												DrawOutlineEntity(entity, false)
												break
											end
										end
									end
								else
									LeaveTarget()
									DrawOutlineEntity(entity, false)
									break
								end
								Wait(0)
							end
							LeaveTarget()
							DrawOutlineEntity(entity, false)
						end
					else
						-- Vehicle Model targets
						local data = Models[GetEntityModel(entity)]
						if data then CheckEntity(flag, data, entity, distance) end
					end

				-- Entity targets
				else
					local data = Models[GetEntityModel(entity)]
					if data then CheckEntity(flag, data, entity, distance) end
				end

				-- Generic targets
				if not success then
					local data = Types[entityType]
					if data then CheckEntity(flag, data, entity, distance) end
				end
			else sleep += 20 end
			if not success then
				local closestDis, closestZone, playerCoords
				if Config.DrawSprite then playerCoords = GetEntityCoords(playerPed) end
				for k, zone in pairs(Zones) do
					if distance < (closestDis or Config.MaxDistance) and distance <= zone.targetoptions.distance and zone:isPointInside(coords) then
						closestDis = distance
						closestZone = zone
					end
					if Config.DrawSprite then
						if #(playerCoords - zone.center) < (zone.targetoptions.drawDistance or Config.DrawDistance) then
							listSprite[k] = zone
						else
							listSprite[k] = nil
						end
					end
				end
				if closestZone then
					table_wipe(nuiData)
					local slot = 0
					for _, data in pairs(closestZone.targetoptions.options) do
						if CheckOptions(data, entity, distance) then
							slot += 1
							sendData[slot] = data
							sendData[slot].entity = entity
							nuiData[slot] = {
								icon = data.icon,
								label = data.label
							}
						end
					end
					if next(nuiData) then
						success = true
						SendNUIMessage({response = 'validTarget', data = nuiData})
						if Config.DrawSprite then
							listSprite[closestZone.name].success = true
						end
						DrawOutlineEntity(entity, true)
						while targetActive and success do
							local coords, distance = RaycastCamera(flag)
							if not closestZone:isPointInside(coords) or distance > closestZone.targetoptions.distance then
								LeaveTarget()
								DrawOutlineEntity(entity, false)
								break
							elseif not hasFocus and IsDisabledControlPressed(0, Config.MenuControlKey) then
								EnableNUI()
								DrawOutlineEntity(entity, false)
							end
							Wait(0)
						end
						if Config.DrawSprite and listSprite[closestZone.name] then -- Check for when the targetActive is false and it removes the zone from listSprite
							listSprite[closestZone.name].success = false
						end
						LeaveTarget()
						DrawOutlineEntity(entity, false)
					else
						repeat
							Wait(20)
							local coords, _, entity2 = RaycastCamera(flag)
						until not targetActive or entity ~= entity2 or not closestZone:isPointInside(coords)
					end
				else sleep += 20 end
			else LeaveTarget() DrawOutlineEntity(entity, false) end
		else sleep += 20 end
		Wait(sleep)
	end
	DisableTarget(false)
end

RegisterNUICallback('selectTarget', function(option)
	SetNuiFocus(false, false)
	SetNuiFocusKeepInput(false)
	Wait(100)
	targetActive, success, hasFocus = false, false, false
	if not next(sendData) then return end
	local data = sendData[option]
	if not data then return end
	CreateThread(function()
		Wait(0)
		if data.action then
			data.action(data.entity)
		elseif data.event then
			if data.type == "client" then
				TriggerEvent(data.event, data)
			elseif data.type == "server" then
				TriggerServerEvent(data.event, data)
			elseif data.type == "command" then
				ExecuteCommand(data.event)
			elseif data.type == "qbcommand" then
				TriggerServerEvent('QBCore:CallCommand', data.event, data)
			else
				TriggerEvent(data.event, data)
			end
		else
			error("No trigger setup")
		end
	end)
end)

RegisterNUICallback('closeTarget', function()
	SetNuiFocus(false, false)
	SetNuiFocusKeepInput(false)
	Wait(100)
	targetActive, success, hasFocus = false, false, false
end)

RegisterNUICallback('leftTarget', function()
	if Config.Toggle then
		SetNuiFocus(false, false)
		SetNuiFocusKeepInput(false)
		Wait(100)
		table_wipe(sendData)
		success, hasFocus = false, false
	else
		DisableTarget(true)
	end
end)

if Config.Toggle then
	RegisterCommand('playerTarget', function()
		if targetActive then
			DisableTarget(true)
		else
			EnableTarget()
		end
	end, false)
	RegisterKeyMapping("playerTarget", "Toggle targeting~", "keyboard", Config.OpenKey)
	TriggerEvent('chat:removeSuggestion', '/playerTarget')
else
	RegisterCommand('+playerTarget', EnableTarget, false)
	RegisterCommand('-playerTarget', DisableTarget, false)
	RegisterKeyMapping("+playerTarget", "Enable targeting~", "keyboard", Config.OpenKey)
	TriggerEvent('chat:removeSuggestion', '/+playerTarget')
	TriggerEvent('chat:removeSuggestion', '/-playerTarget')
end

-------------------------------------------------------------------------------
-- Exports
-------------------------------------------------------------------------------

local function AddCircleZone(name, center, radius, options, targetoptions)
	center = type(center) == 'table' and vec3(center.x, center.y, center.z) or center
	Zones[name] = CircleZone:Create(center, radius, options)
	targetoptions.distance = targetoptions.distance or Config.MaxDistance
	Zones[name].targetoptions = targetoptions
	return Zones[name]
end
exports('AddCircleZone', AddCircleZone)

local function AddBoxZone(name, center, length, width, options, targetoptions)
	center = type(center) == 'table' and vec3(center.x, center.y, center.z) or center
	Zones[name] = BoxZone:Create(center, length, width, options)
	targetoptions.distance = targetoptions.distance or Config.MaxDistance
	Zones[name].targetoptions = targetoptions
	return Zones[name]
end
exports('AddBoxZone', AddBoxZone)

local function AddPolyZone(name, points, options, targetoptions)
	local _points = {}
	if type(points[1]) == 'table' then
		for i = 1, #points do
			_points[i] = vec2(points[i].x, points[i].y)
		end
	end
	Zones[name] = PolyZone:Create(#_points > 0 and _points or points, options)
	targetoptions.distance = targetoptions.distance or Config.MaxDistance
	Zones[name].targetoptions = targetoptions
	return Zones[name]
end
exports('AddPolyZone', AddPolyZone)

local function AddComboZone(zones, options, targetoptions)
	Zones[options.name] = ComboZone:Create(zones, options)
	targetoptions.distance = targetoptions.distance or Config.MaxDistance
	Zones[options.name].targetoptions = targetoptions
	return Zones[options.name]
end
exports("AddComboZone", AddComboZone)

local function AddEntityZone(name, entity, options, targetoptions)
	Zones[name] = EntityZone:Create(entity, options)
	targetoptions.distance = targetoptions.distance or Config.MaxDistance
	Zones[name].targetoptions = targetoptions
	return Zones[name]
end

exports("AddEntityZone", AddEntityZone)

local function RemoveZone(name)
	if not Zones[name] then return end
	if Zones[name].destroy then Zones[name]:destroy() end
	Zones[name] = nil
end
exports('RemoveZone', RemoveZone)

local function SetOptions(tbl, distance, options)
	for _, v in pairs(options) do
		if v.required_item then
			v.item = v.required_item
			v.required_item = nil
		end
		if not v.distance or v.distance > distance then v.distance = distance end
		tbl[v.label] = v
	end
end

local function AddTargetBone(bones, parameters)
	local distance, options = parameters.distance or Config.MaxDistance, parameters.options
	if type(bones) == 'table' then
		for _, bone in pairs(bones) do
			if not Bones.Options[bone] then Bones.Options[bone] = {} end
			SetOptions(Bones.Options[bone], distance, options)
		end
	elseif type(bones) == 'string' then
		if not Bones.Options[bones] then Bones.Options[bones] = {} end
		SetOptions(Bones.Options[bones], distance, options)
	end
end
exports('AddTargetBone', AddTargetBone)

local function RemoveTargetBone(bones, labels)
	if type(bones) == 'table' then
		for _, bone in pairs(bones) do
			if type(labels) == 'table' then
				for _, v in pairs(labels) do
					if Bones.Options[bone] then
						Bones.Options[bone][v] = nil
					end
				end
			elseif type(labels) == 'string' then
				if Bones.Options[bone] then
					Bones.Options[bone][labels] = nil
				end
			end
		end
	else
		if type(labels) == 'table' then
			for _, v in pairs(labels) do
				if Bones.Options[bones] then
					Bones.Options[bones][v] = nil
				end
			end
		elseif type(labels) == 'string' then
			if Bones.Options[bones] then
				Bones.Options[bones][labels] = nil
			end
		end
	end
end
exports("RemoveTargetBone", RemoveTargetBone)

local function AddTargetEntity(entities, parameters)
	local distance, options = parameters.distance or Config.MaxDistance, parameters.options
	if type(entities) == 'table' then
		for _, entity in pairs(entities) do
			if NetworkGetEntityIsNetworked(entity) then entity = NetworkGetNetworkIdFromEntity(entity) end -- Allow non-networked entities to be targeted
			if not Entities[entity] then Entities[entity] = {} end
			SetOptions(Entities[entity], distance, options)
		end
	elseif type(entities) == 'number' then
		if NetworkGetEntityIsNetworked(entities) then entities = NetworkGetNetworkIdFromEntity(entities) end -- Allow non-networked entities to be targeted
		if not Entities[entities] then Entities[entities] = {} end
		SetOptions(Entities[entities], distance, options)
	end
end
exports('AddTargetEntity', AddTargetEntity)

local function RemoveTargetEntity(entities, labels)
	if type(entities) == 'table' then
		for _, entity in pairs(entities) do
			if NetworkGetEntityIsNetworked(entity) then entity = NetworkGetNetworkIdFromEntity(entity) end -- Allow non-networked entities to be targeted
			if type(labels) == 'table' then
				for _, v in pairs(labels) do
					if Entities[entity] then
						Entities[entity][v] = nil
					end
				end
			elseif type(labels) == 'string' then
				if Entities[entity] then
					Entities[entity][labels] = nil
				end
			end
		end
	elseif type(entities) == 'number' then
		if NetworkGetEntityIsNetworked(entities) then entities = NetworkGetNetworkIdFromEntity(entities) end -- Allow non-networked entities to be targeted
		if type(labels) == 'table' then
			for _, v in pairs(labels) do
				if Entities[entities] then
					Entities[entities][v] = nil
				end
			end
		elseif type(labels) == 'string' then
			if Entities[entities] then
				Entities[entities][labels] = nil
			end
		end
	end
end
exports('RemoveTargetEntity', RemoveTargetEntity)

local function AddTargetModel(models, parameters)
	local distance, options = parameters.distance or Config.MaxDistance, parameters.options
	if type(models) == 'table' then
		for _, model in pairs(models) do
			if type(model) == 'string' then model = joaat(model) end
			if not Models[model] then Models[model] = {} end
			SetOptions(Models[model], distance, options)
		end
	else
		if type(models) == 'string' then models = joaat(models) end
		if not Models[models] then Models[models] = {} end
		SetOptions(Models[models], distance, options)
	end
end
exports('AddTargetModel', AddTargetModel)

local function RemoveTargetModel(models, labels)
	if type(models) == 'table' then
		for _, model in pairs(models) do
			if type(model) == 'string' then model = joaat(model) end
			if type(labels) == 'table' then
				for k, v in pairs(labels) do
					if Models[model] then
						Models[model][v] = nil
					end
				end
			elseif type(labels) == 'string' then
				if Models[model] then
					Models[model][labels] = nil
				end
			end
		end
	else
		if type(models) == 'string' then models = joaat(models) end
		if type(labels) == 'table' then
			for k, v in pairs(labels) do
				if Models[models] then
					Models[models][v] = nil
				end
			end
		elseif type(labels) == 'string' then
			if Models[models] then
				Models[models][labels] = nil
			end
		end
	end
end
exports('RemoveTargetModel', RemoveTargetModel)

local function AddType(type, parameters)
	local distance, options = parameters.distance or Config.MaxDistance, parameters.options
	SetOptions(Types[type], distance, options)
end

local function AddPed(parameters) AddType(1, parameters) end
exports('Ped', AddPed)

local function AddVehicle(parameters) AddType(2, parameters) end
exports('Vehicle', AddVehicle)

local function AddObject(parameters) AddType(3, parameters) end
exports('Object', AddObject)

local function AddPlayer(parameters)
	local distance, options = parameters.distance or Config.MaxDistance, parameters.options
	SetOptions(Players, distance, options)
end
exports('Player', AddPlayer)

local function RemoveType(typ, labels)
	if type(labels) == 'table' then
		for _, v in pairs(labels) do
			Types[typ][v] = nil
		end
	elseif type(labels) == 'string' then
		Types[typ][labels] = nil
	end
end

local function RemovePed(labels) RemoveType(1, labels) end
exports('RemovePed', RemovePed)

local function RemoveVehicle(labels) RemoveType(2, labels) end
exports('RemoveVehicle', RemoveVehicle)

local function RemoveObject(labels) RemoveType(3, labels) end
exports('RemoveObject', RemoveObject)

local function RemovePlayer(labels)
	if type(labels) == 'table' then
		for _, v in pairs(labels) do
			Players[v] = nil
		end
	elseif type(labels) == 'string' then
		Players[labels] = nil
	end
end
exports('RemovePlayer', RemovePlayer)

-- Misc. Exports

exports("IsTargetActive", function() return targetActive end)

exports("IsTargetSuccess", function() return success end)

exports("GetType", function(type, label) return Types[type][label] end)

exports("GetZone", function(name) return Zones[name] end)

exports("GetTargetBone", function(bone) return Bones.Options[bone][label] end)

exports("GetTargetEntity", function(entity, label) return Entities[entity][label] end)

exports("GetTargetModel", function(model, label) return Models[model][label] end)

exports("GetPed", function(label) return Types[1][label] end)

exports("GetVehicle", function(label) return Types[2][label] end)

exports("GetObject", function(label) return Types[3][label] end)

exports("GetPlayer", function(label) return Players[label] end)

exports("UpdateType", function(type, label, data) Types[type][label] = data end)

exports("UpdateZone", function(name, data) Zones[name] = data end)

exports("UpdateTargetBone", function(bone, label, data) Bones.Options[bone][label] = data end)

exports("UpdateTargetEntity", function(entity, label, data) Entities[entity][label] = data end)

exports("UpdateTargetModel", function(model, label, data) Models[model][label] = data end)

exports("UpdatePed", function(label, data) Types[1][label] = data end)

exports("UpdateVehicle", function(label, data) Types[2][label] = data end)

exports("UpdateObject", function(label, data) Types[3][label] = data end)

exports("UpdatePlayer", function(label, data) Players[label] = data end)

exports("AllowTargeting", function(bool)
	allowTarget = bool
	if not allowTarget then
		DisableTarget(true)
	end
end)

-- Debug Option

if Config.Debug then Load('debug') end