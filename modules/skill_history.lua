local GladiusEx = _G.GladiusEx
local L = LibStub("AceLocale-3.0"):GetLocale("GladiusEx")
local fn = LibStub("LibFunctional-1.0")

-- globals

local defaults = {
	MaxIcons = 8,
	IconSize = 24,
	Margin = 2,
	PaddingX = 2,
	PaddingY = 2,
	OffsetX = 0,
	OffsetY = 0,
	BackgroundColor = { r = 0, g = 0, b = 0, a = 0.5 },
	Crop = true,

	Timeout = 10,
	TimeoutAnimDuration = 0.5,

	EnterAnimDuration = 1.0,
	EnterAnimEase = "OUT",
	EnterAnimEaseMode = "CUBIC",
}

local MAX_ICONS = 40

local SkillHistory = GladiusEx:NewGladiusExModule("SkillHistory", false,
	fn.merge(defaults, {
		AttachTo = "ClassIcon",
		Anchor = "BOTTOMLEFT",
		RelativePoint = "TOPLEFT",
		GrowDirection = "RIGHT",
	}),
	fn.merge(defaults, {
		AttachTo = "ClassIcon",
		Anchor = "BOTTOMRIGHT",
		RelativePoint = "TOPRIGHT",
		GrowDirection = "LEFT",
	}))

function SkillHistory:OnEnable()
	if not self.frame then
		self.frame = {}
	end

	--self:RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED")
	self:RegisterEvent("UNIT_SPELLCAST_SUCCEEDED")
	self:RegisterEvent("UNIT_NAME_UPDATE")
end

function SkillHistory:OnDisable()
	self:UnregisterAllEvents()

	for unit in pairs(self.frame) do
		self.frame[unit]:SetAlpha(0)
	end
end

function SkillHistory:CreateFrame(unit)
	local button = GladiusEx.buttons[unit]
	if not button then return end

	-- create frame
	self.frame[unit] = CreateFrame("Frame", "GladiusEx" .. self:GetName() .. unit, button)
end

function SkillHistory:Update(unit)
	local testing = GladiusEx:IsTesting(unit)

	-- create frame
	if not self.frame[unit] then
		self:CreateFrame(unit)
	end

	-- frame
	local parent = GladiusEx:GetAttachFrame(unit, self.db[unit].AttachTo)
	local left, right, top, bottom = parent:GetHitRectInsets()
	self.frame[unit]:ClearAllPoints()
	self.frame[unit]:SetPoint(self.db[unit].Anchor, parent, self.db[unit].RelativePoint, self.db[unit].OffsetX, self.db[unit].OffsetY)

	-- size
	self.frame[unit]:SetWidth(self.db[unit].MaxIcons * self.db[unit].IconSize + (self.db[unit].MaxIcons - 1) * self.db[unit].Margin + self.db[unit].PaddingX * 2)
	self.frame[unit]:SetHeight(self.db[unit].IconSize + self.db[unit].PaddingY * 2)

	-- backdrop
	local bgcolor = self.db[unit].BackgroundColor
	self.frame[unit]:SetBackdrop({ bgFile = [[Interface\Tooltips\UI-Tooltip-Background]], tile = true, tileSize = 16 })
	self.frame[unit]:SetBackdropColor(bgcolor.r, bgcolor.g, bgcolor.b, bgcolor.a)

	-- icons
	if self.frame[unit].enter then self:UpdateIcon(unit, "enter") end
	for i = 1, MAX_ICONS do
		if not self.frame[unit][i] then break end
		self:UpdateIcon(unit, i)
	end

	self.frame[unit]:Hide()
end

function SkillHistory:Show(unit)
	self.frame[unit]:Show()
end

function SkillHistory:Reset(unit)
	if not self.frame[unit] then return end
	-- hide
	self:ClearUnit(unit)
	self.frame[unit]:Hide()
end

function SkillHistory:Test(unit)
	self:ClearUnit(unit)

	-- local spells = { GetSpecializationSpells(GetSpecialization()) }
	-- for i = 1, #spells / 2 do
	-- 	self:QueueSpell(unit, spells[i * 2 - 1], GetTime())
	-- end
	local specID, class, race
	specID = GladiusEx.testing[unit].specID
	class = GladiusEx.testing[unit].unitClass
	race = GladiusEx.testing[unit].unitRace
	local n = 1
	for spellid, spelldata in LibStub("LibCooldownTracker-1.0"):IterateCooldowns(class, specID, race) do
		self:QueueSpell(unit, spellid, GetTime() + n * self.db[unit].EnterAnimDuration)
		n = n + 1
	end
end

function SkillHistory:Refresh(unit)
end

function SkillHistory:UNIT_SPELLCAST_SUCCEEDED(event, unit, spellName, rank, lineID, spellId)
	if self.frame[unit] then
		-- casts with lineID = 0 seem to be secondary effects not directly casted by the unit
		if lineID ~= 0 then
			self:QueueSpell(unit, spellId, GetTime())
			GladiusEx:Log("QUEUEING:", unit, spellName, rank, lineID, spellId)
		else
			GladiusEx:Log("SKIPPING:", unit, spellName, rank, lineID, spellId)
		end
	end
end

function SkillHistory:COMBAT_LOG_EVENT_UNFILTERED(event, timestamp, eventType, hideCaster, sourceGUID, sourceName, sourceFlags, sourceRaidFlags, destGUID, destName, destFlags, destRaidFlags, spellID, spellName, spellSchool, auraType)
	if eventType == "SPELL_CAST_SUCCESS" then
		local unit = GladiusEx:GetUnitIdByGUID(sourceGUID)
		if unit and self.frame[unit] then
			self:QueueSpell(unit, spellID, GetTime())
		end
	end
end

function SkillHistory:UNIT_NAME_UPDATE(event, unit)
	if self.frame[unit] then
		self:ClearUnit(unit)
	end
end

local unit_spells = {}
local unit_queue = {}

function SkillHistory:QueueSpell(unit, spellid, time)
	if not unit_queue[unit] then unit_queue[unit] = {} end
	local uq = unit_queue[unit]

	-- avoid duplicate events
	-- if #uq > 0 then
	-- 	local last = uq[#uq]
	-- 	if last.spellid == spellid and (last.time + 1) > time then
	-- 		return
	-- 	end
	-- end

	-- if spellid == 42292 then
	-- 	icon_alliance = [[Interface\Icons\INV_Jewelry_TrinketPVP_01]]
	-- 	icon_horde = [[Interface\Icons\INV_Jewelry_TrinketPVP_02]]
	-- end

	local entry = {
		["spellid"] = spellid,
		["time"] = time
	}

	tinsert(uq, entry)

	if #uq == 1 then
		self:SetupAnimation(unit)
	end
end

local function InverseDirection(direction)
	if direction == "LEFT" then
		return "RIGHT", -1
	elseif direction == "RIGHT" then
		return "LEFT", 1
	else
		assert(false, "Invalid grow direction")
	end
end

local function GetEaseFunc(type, mod_type)
	local function linear(t) return t end
	local function quad(t) return t * t end
	local function cubic(t) return t * t * t end
	local function reverse(f) return function(t) return 1 - f(1 - t) end end
	local function reflect(f) return function(t) return .5 * (t < .5 and f(2 * t) or (2 - f(2 - 2 * t))) end end
	
	local mod
	if mod_type == "LINEAR" then mod = linear
	elseif mod_type == "QUAD" then mod = quad
	elseif mod_type == "CUBIC" then mod = cubic end
	assert(mod, "Unknown ease function " .. tostring(mod_type))

	if type == "NONE" then return linear
	elseif type == "IN" then return mod
	elseif type == "OUT" then return reverse(mod)
	elseif type == "IN_OUT" then return reflect(mod) end
	error("Invalid ease type " .. tostring(type))
end

function SkillHistory:SetupAnimation(unit)
	local uq = unit_queue[unit]
	local us = unit_spells[unit]
	local entry = uq[1]

	if not self.frame[unit].enter then
		self:CreateIcon(unit, "enter")
		self:UpdateIcon(unit, "enter")
	end

	local dir = self.db[unit].GrowDirection
	local iconsize = self.db[unit].IconSize
	local margin = self.db[unit].Margin
	local maxicons = self.db[unit].MaxIcons
	local st = GetTime()
	local off = iconsize + margin

	self.frame[unit].enter.entry = entry
	self.frame[unit].enter.icon:SetTexture(GetSpellTexture(entry.spellid))
	--self.frame[unit].enter:SetAlpha(0)
	self.frame[unit].enter:Show()

	local ease = GetEaseFunc(self.db[unit].EnterAnimEase, self.db[unit].EnterAnimEaseMode)
	
	-- while this could be implemented with AnimationGroups, they are more
	-- trouble than it worth, sadly
	local function AnimationFrame()
		local t = (GetTime() - st) / self.db[unit].EnterAnimDuration

		if t < 1 then
			t = ease(t)
			local ox = off * t
			local oy = 0
			-- move all but the last icon
			for i = 1, maxicons - 1 do
				if self.frame[unit][i] then
					self:UpdateIconPosition(unit, i, ox, oy)
				end
			end

			if self.frame[unit][maxicons] then
				-- leave the last icon with clipping
				self:UpdateIconPosition(unit, maxicons, ox, oy)
				local left, right
				if dir == "LEFT" then
					left = min(iconsize, ox)
					right = 0
				elseif dir == "RIGHT" then
					left = 0
					right = min(iconsize, ox)
				end
				self.frame[unit][maxicons].icon:ClearAllPoints()
				self.frame[unit][maxicons].icon:SetPoint("TOPLEFT", left, 0)
				self.frame[unit][maxicons].icon:SetPoint("BOTTOMRIGHT", -right, 0)
				if self.db[unit].Crop then
					local n = 5
					local range = 1 - (n / 32)
					local texleft = n / 64 + (left / iconsize * range)
					local texright = n / 64 + ((1 - right / iconsize) * range)
					self.frame[unit][maxicons].icon:SetTexCoord(texleft, texright, n / 64, 1 - n / 64)
				else
					self.frame[unit][maxicons].icon:SetTexCoord(left / iconsize, 1 - right / iconsize, 0, 1)
				end

				-- fade last to alpha 0
				--self.frame[unit][maxicons]:SetAlpha(1 - t)
			end

			-- enter new icon with clipping
			self:UpdateIconPosition(unit, "enter", ox, oy)
			local left, right
			if dir == "LEFT" then
				left = 0
				right = iconsize - max(0, ox - margin)
			elseif dir == "RIGHT" then
				left = iconsize - max(0, ox - margin)
				right = 0
			end
			self.frame[unit].enter.icon:ClearAllPoints()
			self.frame[unit].enter.icon:SetPoint("TOPLEFT", left, 0)
			self.frame[unit].enter.icon:SetPoint("BOTTOMRIGHT", -right, 0)
			if self.db[unit].Crop then
				local n = 5
				local range = 1 - (n / 32)
				local texleft = n / 64 + (left / iconsize * range)
				local texright = n / 64 + ((1 - right / iconsize) * range)
				self.frame[unit].enter.icon:SetTexCoord(texleft, texright, n / 64, 1 - n / 64)
			else
				self.frame[unit].enter.icon:SetTexCoord(left / iconsize, 1 - right / iconsize, 0, 1)
			end

			-- fade tmp1 to alpha 1
			--self.frame[unit].enter:SetAlpha(t)
		else
			-- restore last icon
			if self.frame[unit][maxicons] then
				self:UpdateIcon(unit, maxicons)
			end

			-- after:
			--  updatespells, hide tmp1
			tremove(uq, 1)
			if #uq > 0 then
				self:SetupAnimation(unit)
			else
				self:StopAnimation(unit)
			end

			self:AddSpell(unit, entry.spellid, entry.time)
		end
	end

	self.frame[unit]:SetScript("OnUpdate", AnimationFrame)
	AnimationFrame()
end

function SkillHistory:StopAnimation(unit)
	self.frame[unit]:SetScript("OnUpdate", nil)
	if self.frame[unit].enter then
		self.frame[unit].enter:Hide()
	end
end

function SkillHistory:ClearQueue(unit)
	unit_queue[unit] = {}
	self:StopAnimation(unit)
end

function SkillHistory:AddSpell(unit, spellid, time)
	if not unit_spells[unit] then unit_spells[unit] = {} end
	local us = unit_spells[unit]

	local entry = {
		["spellid"] = spellid,
		["time"] = time
	}

	tremove(us, self.db[unit].MaxIcons)
	tinsert(us, 1, entry)

	self:UpdateSpells(unit)
end

function SkillHistory:ClearSpells(unit)
	unit_spells[unit] = {}
	self:UpdateSpells(unit)
end

function SkillHistory:UpdateSpells(unit)
	local us = unit_spells[unit]
	local now = GetTime()

	local timeout = self.db[unit].Timeout
	local timeout_duration = self.db[unit].TimeoutAnimDuration
	local ease = GetEaseFunc(self.db[unit].EnterAnimEase, self.db[unit].EnterAnimEaseMode)

	-- remove timed out spells
	for i = #us, 1, -1 do
		if (us[i].time + timeout) < now then
			tremove(us, i)
		end
	end

	-- update icons
	local n = min(#us, self.db[unit].MaxIcons)
	for i = 1, n do
		if not self.frame[unit][i] then
			self:CreateIcon(unit, i)
			self:UpdateIcon(unit, i)
		end
	
		self:UpdateIconPosition(unit, i, 0, 0)

		local entry = unit_spells[unit][i]
		self.frame[unit][i].entry = entry
		self.frame[unit][i].icon:SetTexture(GetSpellTexture(entry.spellid))
		self.frame[unit][i]:SetAlpha(1)
		self.frame[unit][i]:Show()

		local function FadeFrame(icon)
			local t = (GetTime() - icon.entry.time - timeout) / timeout_duration
			if t >= 1 then
				icon:Hide()
				icon:SetScript("OnUpdate", nil)
			elseif t >= 0 then
				icon:SetAlpha(1 - ease(t))
			end
		end
		self.frame[unit][i]:SetScript("OnUpdate", FadeFrame)
		FadeFrame(self.frame[unit][i])
	end

	-- hide unused icons
	for i = n + 1, MAX_ICONS do
		if not self.frame[unit][i] then break end
		self.frame[unit][i]:Hide()
		self.frame[unit][i]:SetScript("OnUpdate", nil)
		self.frame[unit][i].entry = nil
	end
end

function SkillHistory:ClearUnit(unit)
	self:ClearQueue(unit)
	self:ClearSpells(unit)
end

function SkillHistory:CreateIcon(unit, i)
	self.frame[unit][i] = CreateFrame("Frame", nil, self.frame[unit])
	self.frame[unit][i].icon = self.frame[unit][i]:CreateTexture(nil, "OVERLAY")

	self.frame[unit][i]:EnableMouse(false)
	self.frame[unit][i]:SetScript("OnEnter", function(self)
		if self.entry then
			GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
			GameTooltip:SetSpellByID(self.entry.spellid)
		end
	end)
	self.frame[unit][i]:SetScript("OnLeave", function(self) GameTooltip:Hide() end)
end

function SkillHistory:UpdateIcon(unit, index)
	self.frame[unit][index]:ClearAllPoints()
	self.frame[unit][index]:SetSize(self.db[unit].IconSize, self.db[unit].IconSize)
	self.frame[unit][index].icon:SetAllPoints()

	-- crop
	if self.db[unit].Crop then
		local n = 5
		self.frame[unit][index].icon:SetTexCoord(n / 64, 1 - n / 64, n / 64, 1 - n / 64)
	else
		self.frame[unit][index].icon:SetTexCoord(0, 1, 0, 1)
	end
end

function SkillHistory:UpdateIconPosition(unit, index, ox, oy)
	local i = index == "enter" and 0 or index

	-- position
	local dir = self.db[unit].GrowDirection
	local invdir, sign = InverseDirection(dir)

	local posx = self.db[unit].PaddingX + (self.db[unit].IconSize + self.db[unit].Margin) * (i - 1)
	self.frame[unit][index]:SetPoint(invdir, self.frame[unit], invdir, sign * (posx + ox), oy)
end

function SkillHistory:GetOptions(unit)
	local options
	options = {
		general = {
			type = "group",
			name = L["General"],
			order = 1,
			args = {
				widget = {
					type = "group",
					name = L["Widget"],
					desc = L["Widget settings"],
					inline = true,
					order = 1,
					args = {
						BackgroundColor = {
							type = "color",
							name = L["Background color"],
							desc = L["Color of the frame background"],
							hasAlpha = true,
							get = function(info) return GladiusEx:GetColorOption(self.db[unit], info) end,
							set = function(info, r, g, b, a) return GladiusEx:SetColorOption(self.db[unit], info, r, g, b, a) end,
							disabled = function() return not self:IsUnitEnabled(unit) end,
							order = 1,
						},
						GrowDirection = {
							type = "select",
							name = L["Grow direction"],
							desc = L["Grow direction of the icons"],
							values = {
								["LEFT"] = L["Left"],
								["RIGHT"] = L["Right"],
							},
							disabled = function() return not self:IsUnitEnabled(unit) end,
							order = 10,
						},
						sep = {
							type = "description",
							name = "",
							width = "full",
							order = 13,
						},
						Crop = {
							type = "toggle",
							name = L["Crop borders"],
							desc = L["Toggle if the icon borders should be cropped or not"],
							disabled = function() return not self:IsUnitEnabled(unit) end,
							hidden = function() return not GladiusEx.db.base.advancedOptions end,
							order = 14,
						},
						sep2 = {
							type = "description",
							name = "",
							width = "full",
							order = 14.5,
						},
						MaxIcons = {
							type = "range",
							name = L["Icons max"],
							desc = L["Number of max icons"],
							min = 1, max = MAX_ICONS, step = 1,
							disabled = function() return not self:IsUnitEnabled(unit) end,
							order = 20,
						},
					},
				},
				enteranim = {
					type = "group",
					name = L["Enter animation"],
					desc = L["Enter animation settings"],
					inline = true,
					order = 2,
					args = {
						EnterAnimDuration = {
							type = "range",
							name = L["Duration"],
							desc = L["Duration of the enter animation, in seconds"],
							min = 0.1, softMax = 5, bigStep = 0.05,
							disabled = function() return not self:IsUnitEnabled(unit) end,
							order = 1,
						},
						EnterAnimEase = {
							type = "select",
							name = L["Ease mode"],
							desc = L["Animation ease mode"],
							values = {
								["IN"] = L["In"],
								["IN_OUT"] = L["In-Out"],
								["OUT"] = L["Out"],
								["NONE"] = L["None"],
							},
							disabled = function() return not self:IsUnitEnabled(unit) end,
							order = 2,
						},
						EnterAnimEaseMode = {
							type = "select",
							name = L["Ease function"],
							desc = L["Animation ease function"],
							values = {
								["QUAD"] = L["Quadratic"],
								["CUBIC"] = L["Cubic"],
							},
							disabled = function() return not self:IsUnitEnabled(unit) end,
							order = 3,
						},
					},
				},
				timeout = {
					type = "group",
					name = L["Timeout"],
					desc = L["Timeout settings"],
					inline = true,
					order = 2,
					args = {
						Timeout = {
							type = "range",
							name = L["Timeout"],
							desc = L["Timeout, in seconds"],
							min = 1, softMax = 30, bigStep = 0.5,
							disabled = function() return not self:IsUnitEnabled(unit) end,
							order = 1,
						},
						TimeoutAnimDuration = {
							type = "range",
							name = L["Fade out duration"],
							desc = L["Duration of the fade out animation, in seconds"],
							min = 0.1, softMax = 3, bigStep = 0.05,
							disabled = function() return not self:IsUnitEnabled(unit) end,
							order = 2,
						},
					},
				},
				size = {
					type = "group",
					name = L["Size"],
					desc = L["Size settings"],
					inline = true,
					order = 3,
					args = {
						IconSize = {
							type = "range",
							name = L["Icon size"],
							desc = L["Size of the cooldown icons"],
							min = 1, softMin = 10, softMax = 100, step = 1,
							disabled = function() return not self:IsUnitEnabled(unit) end,
							order = 5,
						},
						sep = {
							type = "description",
							name = "",
							width = "full",
							order = 13,
						},
						PaddingY = {
							type = "range",
							name = L["Vertical padding"],
							desc = L["Vertical padding of the icons"],
							min = 0, softMax = 30, step = 1,
							disabled = function() return not self:IsUnitEnabled(unit) end,
							order = 15,
						},
						PaddingX = {
							type = "range",
							name = L["Horizontal padding"],
							desc = L["Horizontal padding of the icons"],
							disabled = function() return not self:IsUnitEnabled(unit) end,
							min = 0, softMax = 30, step = 1,
							order = 20,
						},
						sep2 = {
							type = "description",
							name = "",
							width = "full",
							order = 23,
						},
						Margin = {
							type = "range",
							name = L["Horizontal spacing"],
							desc = L["Horizontal spacing of the icons"],
							disabled = function() return not self:IsUnitEnabled(unit) end,
							min = 0, softMax = 30, step = 1,
							order = 30,
						},
					},
				},
				position = {
					type = "group",
					name = L["Position"],
					desc = L["Position settings"],
					inline = true,
					hidden = function() return not GladiusEx.db.base.advancedOptions end,
					order = 4,
					args = {
						AttachTo = {
							type = "select",
							name = L["Attach to"],
							desc = L["Attach to the given frame"],
							values = function() return self:GetOtherAttachPoints(unit) end,
							disabled = function() return not self:IsUnitEnabled(unit) end,
							width = "double",
							order = 5,
						},
						sep = {
							type = "description",
							name = "",
							width = "full",
							order = 7,
						},
						Anchor = {
							type = "select",
							name = L["Anchor"],
							desc = L["Anchor of the frame"],
							values = function() return GladiusEx:GetPositions() end,
							disabled = function() return not self:IsUnitEnabled(unit) end,
							order = 10,
						},
						RelativePoint = {
							type = "select",
							name = L["Relative point"],
							desc = L["Relative point of the frame"],
							values = function() return GladiusEx:GetPositions() end,
							disabled = function() return not self:IsUnitEnabled(unit) end,
							order = 15,
						},
						sep2 = {
							type = "description",
							name = "",
							width = "full",
							order = 17,
						},
						OffsetX = {
							type = "range",
							name = L["Offset X"],
							desc = L["X offset of the frame"],
							softMin = -100, softMax = 100, bigStep = 1,
							disabled = function() return not self:IsUnitEnabled(unit) end,
							order = 20,
						},
						OffsetY = {
							type = "range",
							name = L["Offset Y"],
							desc = L["Y offset of the frame"],
							disabled = function() return not self:IsUnitEnabled(unit) end,
							softMin = -100, softMax = 100, bigStep = 1,
							order = 25,
						},
					},
				},
			},
		},
	}
	
	return options
end