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


local _, ns = ...
local spellIdSchoolMap = ns.spellIdSchoolMap

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
	}
}

local castColor, schools, mSchools, db, getOptions, curSpells, idTranslation, idUmbrella = {1, 0.7, 0}, {
	Physical = 1,
	Holy = 2,
	Fire = 4,
	Nature = 8,
	Frost = 16,
	Shadow = 32,
	Arcane = 64
}, {
	Holystrike = 3,
	--Flamestrike = 5,
	Radiant = 6,
	--Stormstrike = 9,
	--Holystorm = 10,
	Volcanic = 12,
	--Froststrike = 17,
	Frostfire = 20,
	Froststorm = 24,
	Elemental = 28,
	--Shadowstrike = 33,
	--Twilight = 34,
	Shadowflame = 36,
	--Plague = 40,
	--Shadowfrost = 48,
	--Spellstrike = 65,
	--Divine = 66,
	Spellfire = 68,
	--Astral = 72,
	Spellfrost = 80,
	--Chimeric = 84,
	Spellshadow = 96,
	Cosmic = 106,
	Chaos = 124,
	--Magic = 126,
	--ChaosFull = 127
}

local defaults = {
	profile = {
		player = {
			cast = 1
		},
		pet = {},
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
			[3] = castColor,
			[4] = {1, 0.5, 0},
			--[5] = castColor,
			[6] = castColor,
			[8] = {0.3, 1, 0.3},
			--[9] = castColor,
			--[10] = castColor,
			[12] = castColor,
			[16] = {0.5, 1, 1},
			--[17] = castColor,
			[20] = castColor,
			[24] = castColor,
			[28] = castColor,
			[32] = {0.5, 0.5, 1},
			--[33] = castColor,
			--[34] = castColor,
			[36] = castColor,
			[40] = castColor,
			--[48] = castColor,
			[64] = {1, 0.5, 1},
			--[65] = castColor,
			--[66] = castColor,
			[68] = castColor,
			--[72] = castColor,
			[80] = castColor,
			--[84] = castColor,
			[96] = castColor,
			[106] = castColor,
			[124] = castColor,
			--[126] = castColor,
			--[127] = castColor
		},
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
	self:RegisterEvent("UNIT_SPELLCAST_CHANNEL_STOP", "UnitSpellcastStop")
	self:RegisterEvent("UNIT_SPELLCAST_STOP", "UnitSpellcastStop")
end

function School:OnDisable()
	self:UnregisterEvent("UNIT_SPELLCAST_CHANNEL_STOP")
	self:UnregisterEvent("UNIT_SPELLCAST_STOP")
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
	if ( not mod.Bar.channeling and not db[unit].cast ) or ( mod.Bar.channeling and not db[unit].channel ) then
		return
	end
	-- prio on unit nointerrupt bar color if enabled on Q unit
	if notInterruptible and mod.db.profile.noInterruptChangeColor then return end
	if db.schoolColor[spellIdSchoolMap[spellId]] == nil then
		--Physical spells are removed from list to save space
		spellSchool = 1
	else
		spellSchool = spellIdSchoolMap[spellId]
	end
	
	if not db.useSchool[spellSchool] then
		return
	end
	
	if not db.schoolColor[spellIdSchoolMap[spellId]] then
		return
	end
	
	mod.Bar.Bar:SetStatusBarColor(unpack(db.schoolColor[spellIdSchoolMap[spellId]]))
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
			[3] = icoTex("inv_weapon_rifle_07", 12) .. " Witchrend (Drustvar zone ability)",
			--[5] = icoTex("spell_fire_felflamering_red", 12) .. " NPC abilities",
			[6] = icoTex("ability_mage_firestarter", 12) .. " Power Word: Radiance (" .. clrStr("Priest", "ffffffff") .. ")",
			--[9] = icoTex("ability_shaman_stormstrike", 12) .. " NPC abilities",
			--[10] = icoTex("inv_poison_mindnumbing", 12) .. " NPC abilities",
			[12] = icoTex("ability_evoker_eruption", 12) .. " Eruption (" .. clrStr("Evoker", "ff33937f") .. ")",
			--[17] = icoTex("spell_deathknight_frozenruneweapon", 12) .. " NPC abilities",
			[20] = icoTex("Inv_ability_frostfiremage_frostfirebolt", 12) .. " Frostfire Bolt (" .. clrStr("Mage", "ff3fc7eb") .. ")",
			[24] = icoTex("Spell_Frost_Ice Shards", 12) .. " Froststorm Breath (Chimaera - Exotic " .. clrStr("Hunter", "ffaad372") .. " Pet)",
			[28] = icoTex("Shaman_Talent_ElementalBlast", 12) .. " Elemental Blast (" .. clrStr("Shaman", "ff2359ff") .. ")",
			--[33] = icoTex("ability_argus_edgeofobliteration", 12) .. " NPC abilities",
			--[34] = icoTex("spell_shadow_twilight", 12) .. " NPC abilities",
			[36] = icoTex("ability_warlock_handofguldan", 12) .. " Hand of Gul'dan (" .. clrStr("Warlock", "ff8788ee") .. ")",
			--[40] = icoTex("spell_shadow_plaguecloud", 12) .. " NPC abilities",
			--[48] = icoTex("spell_priest_mindspike", 12) .. " Mind Spike (" .. clrStr("Priest", "ffffffff") .. ")",
			--[65] = icoTex("spell_arcane_massdispel", 12) .. " NPC abilities",
			--[66] = icoTex("spell_holy_purifyingpower", 12) .. " NPC abilities",
			[68] = icoTex("Inv_ability_chronowardenevoker_chronoflame", 12) .. " Chrono Flames (" .. clrStr("Evoker", "ff33937f") .. ")",
			--[72] = icoTex("ability_druid_stellarflare", 12) .. " Stellar Flare (" .. clrStr("Druid", "ffff7c0a") .. ")",
			[80] = icoTex("ability_evoker_disintegrate", 12) .. " Disintegrate (" .. clrStr("Evoker", "ff33937f") .. ")",
			--[84] = "No cast spells", --SoD only
			[96] = icoTex("inv_12_dh_void_ability_voidray", 12) .. " Void Ray (" .. clrStr("Demon Hunter", "ffa330c9") .. ")",
			[106] = icoTex("inv_12_dh_void_ability_consume", 12) .. " Consume (" .. clrStr("Demon Hunter", "ffa330c9") .. ")",
			[124] = icoTex("ability_warlock_chaosbolt", 12) .. " Chaos Bolt (" .. clrStr("Warlock", "ff8788ee") .. ")",
			--[126] = icoTex("spell_frostfire-orb", 12) .. " NPC abilities",
			--[127] = icoTex("ability_demonhunter_felblade", 12) .. " NPC abilities"
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
					name = clrStr("Version: ", "ff00ff00") .. C_AddOns.GetAddOnMetadata("Quartz_School", "Version"),
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
