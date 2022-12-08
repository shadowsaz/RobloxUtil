--[[

TouchZone v1.4
--------------
Copyright (c) 2022, shadowsaz
All rights reserved.

This source code is licensed under the MIT-style license found in the
LICENSE file in the root directory of this source tree. 

> Simple Touch event wrapper for wide area player detection.
> Delivers unnoticable performance delays while making your code much cleaner.
> Handles all of the background work used to detect valid characters,
> and gives you easy-to-use events and methods to take advantage of.

DevForum: devforum.roblox.com/t/touchzone-v13-simple-touched-event-wrapper/
Toolbox: www.roblox.com/library/11765196513/TouchZone-v1-3

Code sample:
--------------

local TouchZone = require(game:GetService("ReplicatedStorage"):WaitForChild("TouchZone"))
local MyPart = script.Parent

local ZoneFilter = function(character,part)
	if part:FindFirstAncestorWhichIsA("Accessory") then
		return false
	end
	return true
end

local MyZone = TouchZone.NewZone(MyPart,ZoneFilter)

MyZone.OnEnter:Connect(function(character)
	print("Character entered zone!")
end)

MyZone.OnLeave:Connect(function(character)
	print("Character left zone!")
end)

--------------

API Reference:
--------------
* Words with an asterisk are explained at the bottom
[] Optional arguments are enclosed with square brackets

> TouchZone.NewZone(ZonePart: BasePart, [Callback: function])
- Initiates and enables a zone on the specified part, with the
- callback function being called on each part detected in the zone
- where a truthy return acts as a whitelist for it to be even counted.
-> Callback(Character: model, Part: BasePart)

> TouchZone.FetchZone(ZonePart: BasePart)
- While it sounds similar to NewZone, it doesn't create 
- a new zone and only returns the zone attached to the
- specified part, if it exists.

+ Both of the above functions return a ZoneObject that
+ is the primary way to interact with the module, containing
+ all of the methods and events for you to use.

> ZoneObject.OnEnter
- Event that fires when a character enters the zone.

> ZoneObject.OnLeave
- Event that fires when a character leaves the zone.

+ Both of the above properties are a Signal* object that acts
+ similar how Roblox bindable events act, with some API changes.

> ZoneObject:GetState(void)
- Returns the current State* of the zone as a string.

> ZoneObject:GetMembers(void)
- Returns an array of all characters currently in the zone.

> ZoneObject:Enable(void)
- Enables the zone, reconnecting all connections and
- rendering the majority of methods usable again.

> ZoneObject:Disable(void)
- Disables the zone, disconnecting all touch listeners 
- and rendering most methods unusable until reactivation.

> ZoneObject:Destroy(void)
- Completely destroys the zone, disconnecting all touch
- listeners, resuming all event threads and clearing all
- of the properties, you can now make a new zone on the used part.

* Signal

> Signal:Connect(Callback: function)
- Adds the function to the callback pool, calling
- it every time the event gets fired with the fired arguments.

> Signal:Wait([Timeout: number])
- Functions the same as Connect however it will yield
- the current thread until the event is fired or
- until the specified timeout has been exceeded

* State

> Active
- The zone is running as usual
> Sleep
- The zone has been disabled, properties are cleared and
- none of the events will be fired
> Dead
- The zone has been destroyed, everything is cleaned up
- and none of the events will fire again

--------------
Written by shadowsaz#9639

]]--

--------------------------------------
-- Inital setup

local Objects = {
	TouchZone = {Created = {}},
	Signal = {Spawned = {}},
	Connection = {}
}
for _,mt in pairs(Objects) do mt.__index = mt end
local TouchZone = Objects.TouchZone
local Signal = Objects.Signal
local Connection = Objects.Connection

function Signal:Connect(callback)
	if not self.Active then return nil end
	local connection = Connection:_Spawn(self)
	self.Connections[connection] = callback
	return connection
end
function Signal:Wait(timeout)
	if not self.Active then return nil end
	local connection,thread;
	local called = false
	local function remove(state,...)
		if not called and self.Active then
			called = true
			connection:_Disconnect()
			self.Threads[thread] = nil
			task.spawn(thread,state,...)
		end
	end
	connection = self:Connect(function(...) remove(...) end)
	if timeout then task.delay(timeout,remove,nil) end
	thread = coroutine.running()
	self.Threads[thread] = true
	return coroutine.yield()
end
function Signal:_Fire(...)
	if not self.Active then return end 
	for _,callback in pairs(self.Connections) do task.spawn(callback,...) end 
end
function Signal:_Destroy()
	if not self.Active then return end
	self.Active = false
	for thread in pairs(self.Threads) do task.spawn(thread,nil) end
end
function Connection:_Spawn(signal) 
	return setmetatable({Signal = signal},Connection) 
end
function Connection:_Disconnect() 
	self.Signal.Connections[self] = nil 
end

--------------------------------------
-- Local functions

local function SpawnSignal()
	return setmetatable({Active = true,Connections = {},Threads = {}},Signal)
end
local function ValidPart(object)
	return object and typeof(object) == "Instance" and object:IsA("BasePart")
end
local function ArgumentCheck(arg1,arg2)
	if not ValidPart(arg1) then 
		error("TouchZone | NewZone: Argument 1 must be a BasePart")
	elseif TouchZone.Created[arg1] then
		error("TouchZone | NewZone: Part \""..arg1.."\" already has a zone attached")
	elseif arg2 and type(arg2) ~= "function" then 
		error("TouchZone | NewZone: Argument 2 must be a function or nil")
	end
end

--------------------------------------
-- Private methods

function TouchZone:_ClearConnections()
	for i,con in pairs(self._ZoneCons) do 
		con:Disconnect() 
		con = nil
		self._ZoneCons[i] = nil
	end
end

function TouchZone:_PartTouched(part,initial)
	if not part then return end
	local search,found = part,nil
	while true do
		search = search:FindFirstAncestorWhichIsA("Model")
		if search == workspace then return
		else
			found = search
			if found:FindFirstChildOfClass("Humanoid") then break end
		end
	end
	local character = found.Humanoid:GetState() ~= Enum.HumanoidStateType.Dead and found
	if character then
		if self._Callback and not self._Callback(character,part) then
			return
		end
		local shouldFire = false
		if not self._PartQueue[character] then
			self._PartQueue[character] = {Parts = {}}
			shouldFire = true
		end
		table.insert(self._PartQueue[character].Parts,part)
		if shouldFire then
			local index = #self.Members+1
			self._PartQueue[character].Index = index
			table.insert(self.Members,index,character)
			local con;con=character.Humanoid.Died:Connect(function()
				con:Disconnect()
				con = nil
				self:_RemoveCharacter(character)
			end)
			table.insert(self._ZoneCons,con)
			if not initial then self.OnEnter:_Fire(character) end
		end
	end
end

function TouchZone:_RemoveCharacter(character)
	local tab = self._PartQueue[character]
	if not tab then return end
	table.remove(self.Members,tab.Index)
	self._PartQueue[character] = nil
	self.OnLeave:_Fire(character)
end

--------------------------------------
-- Public methods

function TouchZone.NewZone(zonePart,callback)
	ArgumentCheck(zonePart,callback)
	local self = setmetatable({
		_State = "Sleep",
		_ZonePart = zonePart,
		_Callback = callback,
		_ZoneCons = {},
		_PartQueue = {},
		Members = {},
		OnEnter = SpawnSignal(),
		OnLeave = SpawnSignal(),
	},TouchZone)
	TouchZone.Created[zonePart] = self
	self:Enable()
	warn("TouchZone | Initalized zone for part \""..zonePart.Name.."\"")
	return self
end

function TouchZone.FetchZone(zonePart)
	if not ValidPart(zonePart) then
		error("TouchZone | FetchZone: Argument 1 must be a BasePart")
	end
	return TouchZone.Created[zonePart]
end

function TouchZone:GetState()
	return self._State
end

function TouchZone:GetMembers()
	if self:GetState() == "Dead" then
		warn("TouchZone | GetMembers: Zone has been destroyed")
		return
	elseif self:GetState() == "Sleep" then
		warn("TouchZone | GetMembers: Zone has been disabled")
		return
	end
	return self.Members
end

function TouchZone:Enable()
	if self:GetState() == "Dead" then
		warn("TouchZone | Enable: Zone has been destroyed")
		return
	elseif self:GetState() == "Active" then
		warn("TouchZone | Enable: Zone is already enabled")
		return
	end
	self._State = "Active"
	table.insert(self._ZoneCons,self._ZonePart.Touched:Connect(function(part) 
		if self:GetState() == "Active" then self:_PartTouched(part) end
	end))
	table.insert(self._ZoneCons,self._ZonePart.TouchEnded:Connect(function(part)
		for character,tab in pairs(self._PartQueue) do
			local index = table.find(tab.Parts,part)
			if index then
				table.remove(tab.Parts,index)
				if #tab.Parts == 0 and self:GetState() == "Active" then 
					self:_RemoveCharacter(character) 
				end
				break
			end
		end
	end))
	for _,part in ipairs(workspace:GetPartsInPart(self._ZonePart)) do 
		self:_PartTouched(part,true) 
	end
end

function TouchZone:Disable()
	if self:GetState() == "Dead" then
		warn("TouchZone | Disable: Zone has been destroyed")
		return
	elseif self:GetState() == "Sleep" then
		warn("TouchZone | Disable: Zone is already disabled")
		return
	end
	self._State = "Sleep"
	self:_ClearConnections()
	self._PartQueue,self.Members = {},{}
end

function TouchZone:Destroy()
	if self:GetState() == "Dead" then
		warn("TouchZone | Destroy: Zone has already been destroyed")
		return
	end
	self._State = "Dead"
	TouchZone.Created[self._ZonePart] = nil
	self:_ClearConnections()
	self._PartQueue,self.Members = {},{}
	self.OnEnter:_Destroy()
	self.OnLeave:_Destroy()
end

return TouchZone

--------------------------------------
