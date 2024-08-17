include("shared.lua")

local gsModes = "offset_hoverball"  -- Name of tool, for console commands, etc.

local ToolMode = GetConVar("gmod_toolmode")
local ShouldRenderLasers = GetConVar(gsModes.."_showlasers")
local AlwaysRenderLasers = GetConVar(gsModes.."_alwaysshowlasers")
local ShouldRenderDecimals = GetConVar(gsModes.."_showdecimals")
local DecFormat = (ShouldRenderDecimals:GetBool() and "%.2f" or "%.0f")

cvars.RemoveChangeCallback( ShouldRenderDecimals:GetName(), gsModes.."_showdecimals" )
cvars.AddChangeCallback( ShouldRenderDecimals:GetName(), function(name, o, n)
	if tobool(n) then DecFormat = "%.2f" else DecFormat = "%.0f" end
end, gsModes.."_showdecimals")

-- Localize material as calling the function is expensive
local laser = Material("sprites/bluelaser1")
local light = Material("Sprites/light_glow02_add")

surface.CreateFont("OHBTipFont", {
	font = "Roboto Regular",
	size = 24,
	weight = 13,
	blursize = 0,
	scanlines = 0,
	antialias = true,
	extended = true
})

surface.CreateFont("OHBTipFontGlow", {
	font = "Roboto Regular",
	size = 24,
	weight = 13,
	scanlines = 0,
	antialias = true,
	extended = true,
	blursize = 5
})

surface.CreateFont("OHBTipFontSmall", {
	font = "Roboto Regular",
	size = 20,
	weight = 13,
	blursize = 0,
	scanlines = 0,
	antialias = true,
	extended = true
})

-- UI colors
local CoOHBName     = Color(200, 200, 200)      -- Left-side text.
local CoOHBValue    = Color(80, 220, 80)        -- Right-side text.
local CoOHBBack20   = Color(20, 20, 20)         -- Window outline.
local CoOHBBack60   = Color(60, 60, 60)         -- Main background + pointy thing bg.
local CoOHBBack70   = Color(65, 65, 65)         -- Header background.
local CoMidArrow    = Color(100,100,100,255)    -- Little arrows between text.
local CoHeaderPulse = Color(255,200,0,255)      -- Header text pulse effect.
local CoLaserBeam   = Color(100, 100, 255)      -- Laser beam color

local TableDrPoly = {
	{x = 0, y = 0},
	{x = 0, y = 0},
	{x = 0, y = 0}
}

-- Contains keys & translated strings for the mouse-over UI. Index starts at 2 because 1 is for the header.
local UILabel = {
	[2] = {"tool."..gsModes..".height"},
	[3] = {"tool."..gsModes..".force"},
	[4] = {"tool."..gsModes..".air_resistance"},
	[5] = {"tool."..gsModes..".angular_damping"},
	[6] = {"tool."..gsModes..".hover_damping"},
	[7] = {"tool."..gsModes..".brake_resistance"}
}

local UILabel_Header = {
	[1] = {"tool."..gsModes..".brake_enabled"},
	[2] = {"tool."..gsModes..".hover_disabled"}
}

local UISpacer
local SpacerSpacing -- 10/10 dumb variable name.

local function UpdateTranslations()
	for K,V in pairs(UILabel_Header) do UILabel_Header[K][2] = language.GetPhrase(UILabel_Header[K][1]) end
	for K,V in pairs(UILabel) do UILabel[K][2] = language.GetPhrase(UILabel[K][1]) end
	UISpacer = language.GetPhrase("tool.offset_hoverball.ui_spacer")
	SpacerSpacing = nil -- Reset spacing to nil so we recalculate it on the next frame after drawing the text.
end
UpdateTranslations() -- Call once at start to get initial strings.

-- Re-run UpdateTranslations() whenever the game language changes.
cvars.AddChangeCallback("gmod_language", UpdateTranslations)

-- Various network messages that transfer values server > client
-- These are used to initialize certain values on the client
net.Receive(gsModes.."SendUpdateMask", function(len, ply)
	local ball, mask = net.ReadEntity(), net.ReadUInt(32)
	if(ball and ball:IsValid()) then ball.mask = mask end
end)

net.Receive(gsModes.."SendUpdateFilter", function(len, ply)
	local ball = net.ReadEntity()
	local eids = net.ReadString()
	if(ball and ball:IsValid()) then
		if(eids == "nil") then
			ball.props = nil
		else -- Something is exported
			local etab = (","):Explode(eids)
			for i = 1, #etab do
				etab[i] = Entity(tonumber(etab[i]))
			end; ball.props = etab
		end
	end
end)

function ENT:DrawTablePolygon(co, x1, y1, x2, y2, x3, y3)
	TableDrPoly[1].x = x1; TableDrPoly[1].y = y1
	TableDrPoly[2].x = x2; TableDrPoly[2].y = y2
	TableDrPoly[3].x = x3; TableDrPoly[3].y = y3
	surface.SetDrawColor(co)
	draw.NoTexture()
	surface.DrawPoly(TableDrPoly)
end

-- Draws the pointy arrow using DrawTablePolygon()
function ENT:DrawInfoPointy(PosX, PosY, SizX, SizY)
	local x1, y1 = PosX, PosY+SizY/2    -- Triangle pointy point
	local x2, y2 = PosX+SizX, PosY      -- Triangle top point
	local x3, y3 = PosX+SizX, PosY+SizY -- Triangle bottom point
	self:DrawTablePolygon(CoOHBBack20, x1  , y1, x2, y2  , x3, y3)   -- Outline
	self:DrawTablePolygon(CoOHBBack60, x1+3, y1, x2, y2+2, x3, y3-2) -- Background
end

-- Base functionality for drawing the box container.
function ENT:DrawInfoBox(PosX, PosY, SizX, SizY, TopCorners)
	draw.RoundedBoxEx(8, PosX  , PosY  , SizX  , SizY  , CoOHBBack20, TopCorners, TopCorners, true, true) -- Outline (Black)
	draw.RoundedBoxEx(8, PosX+1, PosY+1, SizX-2, SizY-2, CoOHBBack60, TopCorners, TopCorners, true, true) -- Inner background (Grey)
end

local function RampBetween(from, to, speed)
	local tim = speed * CurTime()
	local frc = tim - math.floor(tim)
	local mco = math.abs(2 * (frc - 0.5))
	return math.Remap(mco, 0, 1, from, to)
end

-- Draws the flashing title on the top of the mouse-over UI. Is only called if there is actually a title.
function ENT:DrawInfoTitle(StrT, PosX, PosY, SizX, SizY)
	local TxtX  = (PosX + (SizX / 2))
	local TxtY  = (PosY-12)
	local StrT  = tostring(StrT)

	-- Tweak position of background box.
	local PosO = PosY-30
	local SizO = SizY-8

	CoHeaderPulse.a = RampBetween(0, 255, 0.8)

	draw.RoundedBoxEx(8, PosX, PosO, SizX, SizO, CoOHBBack20, true, true, false, false)         -- Header Outline
	draw.RoundedBoxEx(8, PosX+1, PosO+1, SizX-2, SizO, CoOHBBack70, true, true, false, false)   -- Header BG

	draw.DrawText(StrT, "OHBTipFont", TxtX+1, TxtY-10, color_black, TEXT_ALIGN_CENTER)
	draw.SimpleText(StrT, "OHBTipFontGlow", TxtX, TxtY, CoHeaderPulse, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
	local TW = draw.SimpleText(StrT, "OHBTipFont", TxtX, TxtY, CoOHBName, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)

	return TW
end

-- Draws the rows of text for the mouse-over UI.
function ENT:DrawInfoContent(HBData, PosX, PosY, SizX, PadX, PadY, PadM)
	local LongestL, LongestR = 0, 0
	local Font, RowY = "OHBTipFontSmall", PosY
	local RhbX, RhvX = (PosX + PadX), (PosX + (SizX - PadX))

	for K,V in pairs(UILabel) do
		local FormattedNum = DecFormat:format(HBData[K])

		-- Add slightly off-center text as a shadow to make the foreground text more readable.
		draw.DrawText(V[2], Font, RhbX+1, RowY-9, color_black, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)

		-- Get string len from left and right side, add them together and return that so we can adjust the size of the panel.
		local StrW1, StrH = draw.SimpleText(V[2], Font, RhbX, RowY, CoOHBName, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
		LongestL = math.max(LongestL, StrW1)

		-- Right-side text shadow.
		draw.DrawText(FormattedNum, Font, RhvX+1, RowY-9, color_black, TEXT_ALIGN_RIGHT)

		local StrW2 = draw.SimpleText(FormattedNum, Font, RhvX, RowY, CoOHBValue, TEXT_ALIGN_RIGHT, TEXT_ALIGN_CENTER)
		LongestR = math.max(LongestR, StrW2)

		-- Draw the little triangle spacers.
		if SpacerSpacing then draw.DrawText(UISpacer, Font, SpacerSpacing, RowY-9, CoMidArrow, TEXT_ALIGN_CENTER) end

		RowY = RowY + (StrH + PadY)
	end

	-- Figure our where we should draw the spacers. Will update if the game language changes.
	if not SpacerSpacing then SpacerSpacing = PosX+LongestL+(PadM/2) end

	return (LongestL+LongestR)
end

function ENT:DrawLaser()
	if not IsValid(self) then return end
	local OwnPlayer = LocalPlayer()
	local OwnWeapon = OwnPlayer:GetActiveWeapon()
	if AlwaysRenderLasers:GetBool() or
		(OwnWeapon and OwnWeapon:IsValid() and
		ToolMode:GetString() == gsModes and
		OwnWeapon:GetClass() == "gmod_tool")
	then

		-- Draw the hoverball lasers
		local hbpos = self:WorldSpaceCenter()
		local tr = self:GetTrace(hbpos, -500)
		-- When the trace hits make 3D rendering context and draw laser
		if tr.Hit then
			cam.Start3D()
				render.SetMaterial(laser)
				render.DrawBeam(hbpos, tr.HitPos, 5, 0, 0, CoLaserBeam)
				render.SetMaterial(light); tr.HitPos.z = tr.HitPos.z + 1
				render.DrawQuadEasy(tr.HitPos, tr.HitNormal, 30, 30, CoLaserBeam)
				render.DrawQuadEasy(hbpos, OwnPlayer:GetAimVector(), 30, 30, CoLaserBeam)
			cam.End3D()
		end
	end
end

local UIContainerWidth = 200

-- Draw the UI that appears when you look at a hoverball.
hook.Add("HUDPaint", "OffsetHoverballs_MouseoverUI", function()
	local OwnPlayer = LocalPlayer()
	local LookingAt = OwnPlayer:GetEyeTrace().Entity

	-- Validate whenever we have to draw something.
	if not IsValid(LookingAt) then return end
	if LookingAt:GetClass() ~= "offset_hoverball" then return end
	local HBPos = LookingAt:WorldSpaceCenter()
	local ASPos = OwnPlayer:GetShootPos()
	if (HBPos:DistToSqr(ASPos) > 90000) then return end

	-- When the HB tip is empty do nothing.
	local TipNW = LookingAt:GetNWString("OHB-BetterTip")
	if not TipNW or TipNW == "" then return end

	local HBData = TipNW:Split(",")

	-- Adjusts position of the UI, including all components. (Polygon, text, etc)
	local BoxX = (ScrW() / 2) + 60
	local BoxY = (ScrH() / 2) - 80

	-- Text padding:
	local PadX = 10   -- Moves text inwards, away from walls.
	local PadY = 2    -- Spacing above/below each text line.
	local PadM = 50   -- Space between left and right text.

	-- Box height, scales with 'PadY' text padding.
	local SizeY = 140 + (PadY*2)

	-- Scaling multiplier for the little pointer arrow thing.
	local SizeP = 25

	-- X draw coordinate for the pointy triangle.
	local PoinX = HBPos:ToScreen().y - SizeP * 0.5

	-- Check to see if we will be drawing a header.
	local IsDrawingHeader = (HBData[1] ~= "")

	-- Draw the background and little pointy arrow thing.
	LookingAt:DrawInfoBox(BoxX, BoxY, UIContainerWidth, SizeY, !IsDrawingHeader)
	LookingAt:DrawInfoPointy(BoxX-SizeP+1, math.Clamp(PoinX, BoxY+10, BoxY+SizeY-32), SizeP, SizeP)

	local WidthContent = 100
	local WidthHeader = 100

	-- Draws the info rows and returns the total width of the widest one.
	WidthContent = LookingAt:DrawInfoContent(HBData, BoxX, BoxY+17, UIContainerWidth, PadX, PadY, PadM)

	-- Draw header.
	if IsDrawingHeader then
		local Key = UILabel_Header[tonumber(HBData[1]) or 0][2]
		WidthHeader = LookingAt:DrawInfoTitle(Key, BoxX, BoxY, UIContainerWidth, 40)
	end

	-- Container width updates 1 frame behind, hopefully it shouldn't be too noticeable.
	UIContainerWidth = math.max(WidthContent, WidthHeader) + PadM
end)

function ENT:Draw()
	self:DrawModel()
	if ShouldRenderLasers:GetBool() or AlwaysRenderLasers:GetBool() then self:DrawLaser() end
end
