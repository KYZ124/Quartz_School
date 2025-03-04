--[[
	Copyright (C) 2006-2007 Nymbia
	Copyright (C) 2010-2017 Hendrik "Nevcairiel" Leppkes < h.leppkes@gmail.com >
	Copyright (C) 2014 ccfreak (erjo__) < ccfreak987+qzsch@gmail.com >

	This program is free software: you can redistribute it and/or modify
	it under the terms of the GNU General Public License as published by
	the Free Software Foundation, either version 3 of the License, or
	(at your option) any later version.

	This program is distributed in the hope that it will be useful,
	but WITHOUT ANY WARRANTY; without even the implied warranty of
	MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
	GNU General Public License for more details.

	You should have received a copy of the GNU General Public License
	along with this program.  If not, see <http://www.gnu.org/licenses/>.
]]
local Quartz3 = LibStub("AceAddon-3.0"):GetAddon("Quartz3")
local L = LibStub("AceLocale-3.0"):GetLocale("Quartz3")

local MODNAME = "School"
local School = Quartz3:NewModule(MODNAME, "AceEvent-3.0", "AceHook-3.0")
School.Update = {}

--[[
	LOCALS
]]
local barInfo = {
	player = {
		module = Quartz3:GetModule("Player"),
		name = "Player"
	},
	pet = {
		module = Quartz3:GetModule("Pet"),
		name = "Pet"
	},
	target = {
		module = Quartz3:GetModule("Target"),
		name = "Target"
	},
	focus = {
		module = Quartz3:GetModule("Focus"),
		name = "Focus"
	}
}

local castColor, schools, mSchools, db, getOptions, cache, curSpells, idTranslation, idUmbrella = {1, 0.7, 0}, {
	Physical = 1,
	Holy = 2,
	Fire = 4,
	Nature = 8,
	Frost = 16,
	Shadow = 32,
	Arcane = 64
}, {
	Radiant = 6, -- (Holyfire)
	Froststorm = 24,
	Elemental = 28,
	Twilight = 34, -- (Shadowlight)
	Shadowflame = 36,
	Plague = 40,
	Shadowfrost = 48,
	Astral = 72, -- (Spellstorm)
	Chaos = 127
}

local defaults = {
	profile = {
		player = {
			cast = 1
		},
		pet = {},
		target = {},
		focus = {},
		useSchool = {
			[1] = 1,
			[2] = 1,
			[4] = 1,
			[8] = 1,
			[16] = 1,
			[32] = 1,
			[64] = 1
		},
		schoolColor = {
			[1] = {1, 1, 0},
			[2] = {1, 0.9, 0.5},
			[4] = {1, 0.5, 0},
			[6] = castColor,
			[8] = {0.3, 1, 0.3},
			[16] = {0.5, 1, 1},
			[24] = castColor,
			[28] = castColor,
			[32] = {0.5, 0.5, 1},
			[34] = castColor,
			[36] = castColor,
			[40] = castColor,
			[48] = castColor,
			[64] = {1, 0.5, 1},
			[72] = castColor,
			[127] = castColor
		}
	}
}

--[[
	INIT
]]
function School:OnInitialize()
	self.db = Quartz3.db:RegisterNamespace(MODNAME, defaults)
	db = self.db.profile
	
	self:SetEnabledState(Quartz3:GetModuleEnabled(MODNAME))
	Quartz3:RegisterModuleOptions(MODNAME, getOptions, MODNAME)
end

function School:OnEnable()
	cache = {
		--[5143] = 64, -- "Arcane Missiles", localized, seems to work without this now
	}
	idUmbrella = {
		[47758] = 47540, -- Penance
		[373129] = 400169 -- Dark Reprimand
	}
	idTranslation = {
		-- unify the ids of the same spell under one id
		[47757] = 47758, -- Penance
		[400171] = 373129 -- Dark Reprimand
	}
	curSpells = {}
	self:RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED")
	self:RegisterEvent("UNIT_SPELLCAST_CHANNEL_STOP", "UnitSpellcastStop")
	self:RegisterEvent("UNIT_SPELLCAST_STOP", "UnitSpellcastStop")
end

function School:OnDisable()
	self:UnregisterEvent("COMBAT_LOG_EVENT_UNFILTERED")
	self:UnregisterEvent("UNIT_SPELLCAST_CHANNEL_STOP")
	self:UnregisterEvent("UNIT_SPELLCAST_STOP")
	cache = nil
	curSpells = nil
	idUmbrella = nil
	idTranslation = nil
end

--[[
	EVENT HANDELERS
]]
function School:UnitSpellcastStop(event, unit)
	if Quartz3:GetModuleEnabled(MODNAME) and curSpells[unit] then
		curSpells[unit] = nil
	end
end

function School:CombatEventTriggered( ... )
	local _, type, _, sourceGUID = ...
	if type == "SPELL_CAST_START" or type == "SPELL_CAST_SUCCESS" then
		local spellId, name, school = select(12, ...)
		
		if cache[spellId] then
			return
		end
		cache[spellId] = school
		-- UNIT_SPELLCAST-events happens before combat log, update bars casting the spell now when it's in the cache, (unit_spellcast-events did not trigger UpdateCastBar)
		for unit, spell in pairs(curSpells) do
			if spell == spellId then
				self:UpdateCastBar(unit --[[, spell]])
			end
		end
	end
end

function School:COMBAT_LOG_EVENT_UNFILTERED(event)
	self:CombatEventTriggered(CombatLogGetCurrentEventInfo())
end

function School:UNIT_SPELLCAST_START(object, bar, unit)
	self.hooks[object].UNIT_SPELLCAST_START(object, bar, unit)
	if Quartz3:GetModuleEnabled(MODNAME) then
		self:UpdateCastBar(unit)
	end
end

for unit, info in pairs(barInfo) do
	if info.module.UNIT_SPELLCAST_START then
		School:RawHook(info.module, "UNIT_SPELLCAST_START")
	else
		function info.module:UNIT_SPELLCAST_START(bar, unit)
			if Quartz3:GetModuleEnabled(MODNAME) then
				School:UpdateCastBar(unit)
			end
		end
	end
end

function School:UpdateCastBar(unit --[[, xspellId]])
	if not barInfo[unit] or not Quartz3:GetModuleEnabled(barInfo[unit].name) then
		return
	end
	local mod = barInfo[unit].module
	--if not spell then
		if mod.Bar.channeling then
			--spell = UnitChannelInfo(unit)
			name, _, _, _, _, _, notInterruptible, spellId = UnitChannelInfo(unit)
		else
			--spell = UnitCastingInfo(unit)
			name, _, _, _, _, _, _, notInterruptible, spellId = UnitCastingInfo(unit)
			
		end
	--end

	if idTranslation[spellId] then
		-- unify the spellIds of the same spell and school under one id, Penance is really odd mechanically..
		spellId = idTranslation[spellId]
	end
	if idUmbrella[spellId] then
		-- "umbrella" spellId from CLEU that has another casting spellId
		spellId = idUmbrella[spellId]
	end

	curSpells[unit] = --[[xspellId or]] spellId -- trying spellids in cache and curSpells, why xspellId tho?, testing w/o
	if ( not mod.Bar.channeling and not db[unit].cast ) or ( mod.Bar.channeling and not db[unit].channel ) or not db.schoolColor[cache[spellId]] or not db.useSchool[cache[spellId]] then
		return
	end
	-- prio on unit nointerrupt bar color if enabled on Q unit
	if notInterruptible and mod.db.profile.noInterruptChangeColor then return end

	mod.Bar.Bar:SetStatusBarColor(unpack(db.schoolColor[cache[spellId]]))
end

--[[
	UTILS
]]
local function clrStr(str, clr)
	return "\124c" .. clr .. str .. "\124r"
end

local function icoTex(...)
	-- ... = TexturePath, size1, size2, xoffset, yoffset, dimx, dimy, coordx1, coordx2, coordy1, coordy2, red, green, blue -- http://www.wowpedia.org/UI_escape_sequences#Textures
	return "\124TInterface\\Icons\\" .. strjoin(":", ...) .. "\124t"
end

--[[
	OPTIONS
]]
function School:WipeSettings()
	self.db:ResetProfile()
	LibStub("AceConfigRegistry-3.0"):NotifyChange("Quartz3")
end

local colorOptions
local function GetColorOptions()
	if not colorOptions then
		local os, defaultColors, mSchoolText, pos = 0, {
			[1] = {1, 1, 0},
			[2] = {1, 0.9, 0.5},
			[4] = {1, 0.5, 0},
			[8] = {0.3, 1, 0.3},
			[16] = {0.5, 1, 1},
			[32] = {0.5, 0.5, 1},
			[64] = {1, 0.5, 1},
		}, {
			[6] = icoTex("inv_staff_2h_artifacttome_d_01", 12) .. " Light's Wrath (" .. clrStr("Priest", "fff0ebe0") .. ")",
			--[20] = icoTex("Ability_Mage_FrostFireBolt", 12) .. " Frostfire Bolt (" .. clrStr("Mage", "ff68ccef") .. ")",
			[24] = icoTex("Spell_Frost_Ice Shards", 12) .. " Froststorm Breath (Chimaera - Exotic " .. clrStr("Hunter", "ffaad372") .. " Pet)",
			[28] = icoTex("Shaman_Talent_ElementalBlast", 12) .. " Elemental Blast (" .. clrStr("Shaman", "ff2359ff") .. ")",
			[34] = icoTex("spell_shadow_shadowbolt", 12) .. " Twilight's Wrath (Twilight Fanatic/Zealot)",
			[36] = icoTex("ability_warlock_handofguldan", 12) .. " Hand of Gul'dan (" .. clrStr("Warlock", "ff8788ee") .. ")\n" .. icoTex("inv__demonbolt", 12) .. " Demonbolt (" .. clrStr("Warlock", "ff8788ee") .. ")",
			[40] = icoTex("ability_deathknight_summongargoyle", 12) .. " Gargoyle Strike (" .. clrStr("Death Knight", "ffc41e3a") .. " Gargoyle)",
			[48] = icoTex("spell_priest_mindspike", 12) .. " Mind Spike (" .. clrStr("Priest", "fff0ebe0") .. ")",
			[72] = icoTex("ability_druid_stellarflare", 12) .. " Stellar Flare (" .. clrStr("Druid", "ffff7c0a") .. ")",
			[127] = icoTex("ability_warlock_chaosbolt", 12) .. " Chaos Bolt (" .. clrStr("Warlock", "ff8788ee") .. ")\n" .. icoTex("ability_demonhunter_eyebeam", 12) .. " Eye Beam (" .. clrStr("Demon Hunter", "ffa330c9") .. ")"
		}
		colorOptions = {
			type = "group",
			name = "Colors",
			desc = "Colors",
			order = 103,
			args = {}
		}
		for school, id in pairs(schools) do
			pos = id * 2
			colorOptions.args[school .. "Color"] = {
				type = "color",
				name = school,
				desc = school .. " color",
				get = function() return unpack(db.schoolColor[id]) end,
				set = function(info, ...) db.schoolColor[id] = {...} end,
				order = pos
			}
			pos = pos + 1
			colorOptions.args[school .. "Enabled"] = {
				type = "toggle",
				name = L["Enable"],
				get = function() return db.useSchool[id] end,
				set = function(info, enabled) db.useSchool[id] = enabled end,
				order = pos
			}
			pos = pos + 1
			colorOptions.args[school .. "Default"] = {
				type = "execute",
				name = "Default",
				func = function() db.schoolColor[id] = defaultColors[id] end,
				order = pos
			}
			if os < pos then -- get the higest position from single-schools
				os = pos
			end
		end
		colorOptions.args["headerMultiSchool"] = {
			type = "header",
			name = "Multi Schools",
			order = os + 1
		}
		colorOptions.args["tipMultiSchool"] = {
			type = "description",
			name = clrStr("Tip:", "ff00ff00") .. " See color tooltips for common spells.",
			order = os + 2
		}
		os = os + 2
		for school, id in pairs(mSchools) do
			pos = id * 2 + os
			colorOptions.args[school .. "Color"] = {
				type = "color",
				name = school,
				desc = school .. " color\n\n" .. clrStr("Common Casts/Channels:", "ff00ff00") .. "\n" .. mSchoolText[id],
				get = function() return unpack(db.schoolColor[id]) end,
				set = function(info, ...) db.schoolColor[id] = {...} end,
				order = pos
			}
			pos = pos + 1
			colorOptions.args[school .. "Enabled"] = {
				type = "toggle",
				name = L["Enable"],
				get = function() return db.useSchool[id] end,
				set = function(info, enabled) db.useSchool[id] = enabled end,
				order = pos
			}
			pos = pos + 1
			colorOptions.args[school .. "Default"] = {
				type = "execute",
				name = "Default",
				func = function() db.schoolColor[id] = castColor end,
				order = pos
			}
		end
	end
	return colorOptions
end

do
	local options
	
	function getOptions()
		if options then
			return options
		end
		options = {
			type = "group",
			name = "School",
			order = 600,
			childGroups = "tab",
			args = {
				toggle = {
					type = "toggle",
					name = L["Enable"],
					desc = L["Enable"],
					get = function() return Quartz3:GetModuleEnabled(MODNAME) end,
					set = function(info, v) Quartz3:SetModuleEnabled(MODNAME, v) end,
					order = 100
				},
				version = {
					type = "description",
					name = clrStr("Version: ", "ff00ff00") .. GetAddOnMetadata("Quartz_School", "Version"),
					order = 101
				},
				general = {
					type = "group",
					name = "General",
					desc = "General",
					order = 102,
					args = {
						generaldesc = {
							type = "description",
							name = "Select what unit cast bars you wish to color.",
							order = 1,
						},
						toggleplayercast = {
							type = "toggle",
							name = "Player Casts",
							desc = "Color player casts",
							get = function()
								return db.player.cast
							end,
							set = function(info, ...)
								db.player.cast = ...
							end,
							order = 2,
						},
						toggleplayerchannel = {
							type = "toggle",
							name = "Player Channels",
							desc = "Color player channels",
							get = function()
								return db.player.channel
							end,
							set = function(info, ...)
								db.player.channel = ...
							end,
							order = 3,
						},
						toggletargetcast = {
							type = "toggle",
							name = "Target Casts",
							desc = "Color target casts",
							get = function()
								return db.target.cast
							end,
							set = function(info, ...)
								db.target.cast = ...
							end,
							order = 4,
						},
						toggletargetchannel = {
							type = "toggle",
							name = "Target Channels",
							desc = "Color target channels",
							get = function()
								return db.target.channel
							end,
							set = function(info, ...)
								db.target.channel = ...
							end,
							order = 5,
						},
						togglepetcast = {
							type = "toggle",
							name = "Pet Casts",
							desc = "Color pet casts",
							get = function()
								return db.pet.cast
							end,
							set = function(info, ...)
								db.pet.cast = ...
							end,
							order = 6,
						},
						togglepetchannel = {
							type = "toggle",
							name = "Pet Channels",
							desc = "Color pet channels",
							get = function()
								return db.pet.channel
							end,
							set = function(info, ...)
								db.pet.channel = ...
							end,
							order = 7,
						},
						togglefocuscast = {
							type = "toggle",
							name = "Focus Casts",
							desc = "Color focus casts",
							get = function()
								return db.focus.cast
							end,
							set = function(info, ...)
								db.focus.cast = ...
							end,
							order = 8,
						},
						togglefocuschannel = {
							type = "toggle",
							name = "Focus Channels",
							desc = "Color focus channels",
							get = function()
								return db.focus.channel
							end,
							set = function(info, ...)
								db.focus.channel = ...
							end,
							order = 9,
						},
						headerSplit = {
							type = "header",
							name = "",
							order = 10,
						},
						wipe = {
							type = "execute",
							name = "Reset",
							desc = "Reset School settings for this profile.",
							func = function()
								School:WipeSettings()
							end,
							confirm = function()
								return "You are about to wipe the School module options for this profile. Are you sure about this?"
							end,
							width = "half",
							order = 11,
						}
					}
				}
			}
		}
		options.args.colors = GetColorOptions()
		return options
	end
end
