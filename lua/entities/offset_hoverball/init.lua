AddCSLuaFile("cl_init.lua")
AddCSLuaFile("shared.lua")

include("shared.lua")

local statInfo = {"Brake enabled", "Hover disabled"}
local formInfoBT = "%g,%g,%g,%g,%g,%g" -- For better tooltip.
local CoBrake1 = Color(255, 100, 100)
local CoBrake2 = Color(255, 255, 255)

-- https://wiki.facepunch.com/gmod/Enums/MASK
function ENT:UpdateMask(mask)
	self.mask = mask or MASK_NPCWORLDSTATIC
	if (self.detects_water) then
		self.mask = bit.bor(self.mask, MASK_WATER)
	end
end

-- https://wiki.facepunch.com/gmod/Enums/COLLISION_GROUP
function ENT:UpdateCollide()
	local phy = self:GetPhysicsObject()
	if (self.nocollide) then
		if (IsValid(phy)) then phy:EnableCollisions(false) end
		self:SetCollisionGroup(COLLISION_GROUP_WORLD)
	else
		if (IsValid(phy)) then phy:EnableCollisions(true) end
		self:SetCollisionGroup(COLLISION_GROUP_DISSOLVING)
	end
end

function ENT:UpdateHoverText(str)
	self:SetNWString("OHB-BetterTip", tostring(str or "")..","..
		formInfoBT:format(self.hoverdistance, self.hoverforce, self.damping,
		                  self.rotdamping   , self.hovdamping, self.brakeresistance))
end

function ENT:Initialize()

	self:PhysicsInit(SOLID_VPHYSICS)
	self:SetMoveType(MOVETYPE_VPHYSICS)
	self:SetSolid(SOLID_VPHYSICS)

	self:UpdateMask()
	self:UpdateCollide()

	self.delayedForce = 0
	self.hoverenabled = self.start_on -- Do we spawn enabled?
	self.damping_actual = self.damping -- Need an extra var to account for braking.
	self.hovdamping = 10 -- Controls the vertical damping when going up/down
	self.up_input = 0
	self.down_input = 0
	self.slip = 0
	self.minslipangle = 0.1
	
	local phys = self:GetPhysicsObject()
	if (phys:IsValid()) then
		phys:Wake() -- Starts calling `PhysicsUpdate`
		phys:SetDamping(0.4, 1)
		phys:SetMass(50)
	end

	-- If wiremod is installed then add some wire inputs to our ball.
	if WireLib then self.Inputs = WireLib.CreateInputs(self, {"Enable", "Height", "Brake", "Force", "Damping", "Brake strength"}) end
end

function ENT:PhysicsUpdate()
	-- Don't bother doing anything if we're switched off.
	if (not self.hoverenabled) then return end

	-- Pulling the physics object from PhysicsUpdate()
	-- Doesn't seem to work quite right this will do for now.
	local phys = self:GetPhysicsObject()
	if (not phys:IsValid()) then return end
	if (FrameTime() == 0) then return end

	local hbpos = self:GetPos()
	local force, vforce = 0, Vector()
	local hoverdistance = self.hoverdistance

	-- Handle smoothly adjusting up and down. Controlled by above inputs
	-- If this is 0 we do nothing, if it is -1 we go down, 1 we go up
	local smoothadjust = (self.up_input + self.down_input)

	if smoothadjust ~= 0 then -- Smooth adjustment is +1/-1
		self.hoverdistance = self.hoverdistance + smoothadjust * self.adjustspeed
		self.hoverdistance = math.max(0.01, self.hoverdistance)
		self:UpdateHoverText() -- Update hover text accordingly
	end

	phys:SetDamping(self.damping_actual, self.rotdamping)

	local tr = self:GetTrace()

	if (tr.distance < hoverdistance) then
		force = (hoverdistance - tr.distance) * self.hoverforce
		-- Apply hover damping. Defines transition process when
		-- the ball goes up/down. This is the derivative term of
		-- the PD-controller. It is tuned by the hover_damping value
		vforce.z = vforce.z - phys:GetVelocity().z * self.hovdamping

		-- Experimental sliding physics:
		if tr.Hit then
			if math.abs(tr.HitNormal.x) > self.minslipangle or
				 math.abs(tr.HitNormal.y) > self.minslipangle
			then
				vforce.x = vforce.x + tr.HitNormal.x * self.slip
				vforce.y = vforce.y + tr.HitNormal.y * self.slip
			end
		end
	end

	if (force > self.delayedForce) then
		self.delayedForce = (self.delayedForce * 2 + force) / 3
	else
		self.delayedForce = self.delayedForce * 0.7
	end
	vforce.z = vforce.z + self.delayedForce

	phys:ApplyForceCenter(vforce)
end

numpad.Register("offset_hoverball_heightup", function(pl, ent, keydown)
	if (not IsValid(ent)) then return false end
	ent.down_input = keydown and 1 or 0
	return true
end)

numpad.Register("offset_hoverball_heightdown", function(pl, ent, keydown)
	if (not IsValid(ent)) then return false end
	ent.down_input = keydown and -1 or 0
	return true
end)

numpad.Register("offset_hoverball_toggle", function(pl, ent, keydown)
	if (not IsValid(ent)) then return false end
	ent.hoverenabled = (not ent.hoverenabled)

	if (not ent.hoverenabled) then
		ent.damping_actual = ent.damping
		ent:SetColor(CoBrake2)

		ent:UpdateHoverText(statInfo[2] .. "\n") -- Shows disabled header on tooltip.
	else
		ent:UpdateHoverText()
		ent:PhysWake() -- Nudges the physics entity out of sleep, was sometimes causing issues.
	end

	ent:PhysicsUpdate()
	return true
end)

numpad.Register("offset_hoverball_brake", function(pl, ent, keydown)
	if (not IsValid(ent)) then return false end
	if not ent.hoverenabled then return end

	if (keydown and ent.hoverenabled) then -- Brakes won't work if hovering is disabled.
		ent.damping_actual = ent.brakeresistance
		ent:UpdateHoverText(statInfo[1] .. "\n")
		ent:SetColor(CoBrake1)
	else
		ent.damping_actual = ent.damping
		ent:UpdateHoverText()
		ent:SetColor(CoBrake2)
	end

	ent:PhysicsUpdate()
	return true
end)

-- Manage wiremod inputs.
if WireLib then
	function ENT:TriggerInput(name, value)

		if (not IsValid(self)) then return false end

		title = ""

		if name == "Brake" then
			if value >= 1 then
				self.damping_actual = self.brakeresistance
				title = statInfo[1] .. "\n"
				self:SetColor(CoBrake1)
				self:PhysicsUpdate()
			else
				self.damping_actual = self.damping
				self:SetColor(CoBrake2)
				self:PhysicsUpdate()
			end

		elseif name == "Enable" then
			if value >= 1 then
				self.hoverenabled = true
			else
				self.hoverenabled = false
				title = statInfo[2] .. "\n"
			end
			
			self:PhysicsUpdate()

		elseif name == "Height" then
			self.hoverdistance = value

		elseif name == "Force" then
			self.hoverforce = value

		elseif name == "Damping" then
			self.damping = value

		elseif name == "Brake strength" then

			-- Update brakes if they're on.
			if self.damping_actual == self.brakeresistance then
				self.brakeresistance = value
				self.damping_actual = self.brakeresistance
			else
				self.brakeresistance = value
			end
		end

		self:UpdateHoverText(title)
	end
end
