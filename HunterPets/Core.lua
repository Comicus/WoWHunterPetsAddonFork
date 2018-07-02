HunterPets = LibStub("AceAddon-3.0"):NewAddon("HunterPets","AceEvent-3.0", "AceConsole-3.0");
HunterPets.ver = "1.5.34"
local verNumber = 1123
local TAME_SPELL_ID = 1515
local TAME_DONE_SPELL_ID = 13481
local DISMISS_SPELL_ID = 2641
local CALL_PET_SPELL_IDS = {
	0883,
	83242,
	83243,
	83244,
	83245,
};
local playerName

function HunterPets:OnInitialize()
end

function HunterPets:OnEnable()
	playerName = UnitName("player")
	realmName = GetRealmName();
	local _, _, playerClass = UnitClass("player");

	if not HunterPetsSettings then
		HunterPetsSettings = {
			showZoneTamableText = true,
			autoShowBrowser = true		
		}
	end
	if not HunterPetsGlobal then
		HunterPetsGlobal = {}
	end

	if not HunterPetsGlobal.version then
		StaticPopup_Show("HUNTERPETS_DATA_RESET")
		HunterPetsGlobal = {};
		HunterPetsGlobal.version = verNumber
		HunterPetsGlobal.data = {}
	end

	if not HunterPetsGlobal.data[realmName] then
		HunterPetsGlobal.data[realmName] = {}
	end
	if not HunterPetsGlobal.data[realmName][playerName] and playerClass == 3 then
		HunterPetsGlobal.data[realmName][playerName] = { OwnedPets = {} }
	end

	self.currentPetID = 0;
	self.renamed = false
	self:RegisterChatCommand("HunterPets", "ChatCMD")
	local loaded, reason = LoadAddOn("Blizzard_Collections");
	local loaded, reason = LoadAddOn("HunterPets_UI");
	local loaded, reason = LoadAddOn("HunterPets_Owned");

	self:RegisterEvent("ZONE_CHANGED", "ZoneChange")
	self:RegisterEvent("ZONE_CHANGED_NEW_AREA", "ZoneChange")

	if playerClass == 3 then
		self:RegisterEvent("PET_STABLE_SHOW", "UpdateStabledPets");
		self:RegisterEvent("SPELLS_CHANGED", "UpdateStabledPets");
		self:RegisterEvent("UNIT_NAME_UPDATE", "UpdateStabledPets");
		hooksecurefunc('PetAbandon', function(...) HunterPets:UpdateStabledPets("PET_ABANDON", ...) end)
		hooksecurefunc('SetPetSlot', function(...) HunterPets:UpdateStabledPets("SETPETSLOT", ...) end)
	end
end

function HunterPets:OnDisable()
end

StaticPopupDialogs["HUNTERPETS_DATA_RESET"] = {
	text = "|cffff0000Notice:|r |cff33ff99HunterPets "..HunterPets.ver.."|r\n\nTo add support for characters with the same name on different servers any saved data will be reset.\n",
	button1 = "Ok",
	timeout = 0,
	whileDead = true,
	hideOnEscape = true,
	preferredIndex = 3,
}
function HunterPets:UpdateStabledPets(event, ...)
	if (event == "PET_STABLE_SHOW") then
		local totalSlots = (NUM_PET_STABLE_SLOTS*NUM_PET_STABLE_PAGES)+NUM_PET_ACTIVE_SLOTS
		for i=1, totalSlots do
			local icon, name, level, family, talent = GetStablePetInfo(i);
			if icon ~= nil then
				HunterPets:UpdateFromStable(i, icon, name, level, family)
			else
				HunterPetsGlobal.data[realmName][playerName].OwnedPets[i] = nil
			end
		end
		if IsAddOnLoaded("HunterPets_Owned") then
			HunterPetsOwned_Update()
		end
		if (HunterPetsSettings.autoShowBrowser and IsAddOnLoaded("HunterPets_Owned")) then
			HunterPetsOwned:Show()
		end
	end
	if (event == "PET_ABANDON") then
		HunterPetsGlobal.data[realmName][playerName].OwnedPets[HunterPets:GetActiveSpellID()] = nil
	end
	if (event == "SETPETSLOT") then
		local from, to = ...
		HunterPets:SwapData(from, to)
		if IsAddOnLoaded("HunterPets_Owned") then
			HunterPetsOwned_Update()
		end
	end
	if (event == "SPELLS_CHANGED") then
		HunterPets:UpdateOwnedPets()
		if IsAddOnLoaded("HunterPets_Owned") then
			HunterPetsOwned_Update()
		end
	end
	if (event == "UNIT_NAME_UPDATE" and ... == "pet") then
		self.renamed = true
		HunterPets:UpdateOwnedPets()
		if IsAddOnLoaded("HunterPets_Owned") then
			HunterPetsOwned_Update()
		end
	end
end

function HunterPets:FindPetIndex(npc_id)
	for i=1, #HunterPets.Pets.Id do
		if (HunterPets.Pets.Id[i] == tonumber(npc_id)) then
			return i
		end
	end
	return nil
end

function HunterPets:GetActiveSpellID()
	for i=1, #CALL_PET_SPELL_IDS do
		if IsCurrentSpell(CALL_PET_SPELL_IDS[i]) then
			return i
		end
	end
	return 0
end

function HunterPets:SwapData(from, to)
	local fromString, toString
	if HunterPetsGlobal.data[realmName][playerName].OwnedPets[from] then
		fromString = HunterPetsGlobal.data[realmName][playerName].OwnedPets[from]
	end
	if HunterPetsGlobal.data[realmName][playerName].OwnedPets[to] then
		toString = HunterPetsGlobal.data[realmName][playerName].OwnedPets[to]
	end
	HunterPetsGlobal.data[realmName][playerName].OwnedPets[to] = fromString
	HunterPetsGlobal.data[realmName][playerName].OwnedPets[from] = toString

end

function HunterPets:UpdateFromStable(id, icon, name, level, family)
	if not HunterPetsGlobal.data[realmName][playerName].OwnedPets[id] then
		HunterPetsGlobal.data[realmName][playerName].OwnedPets[id] = icon .. ":" .. name .. ":" .. level .. ":" .. family
	end

end

function HunterPets:UpdateOwnedPets()
	local hasPetUI, isHunterPet = HasPetUI();

	if not ( UnitExists("pet") and hasPetUI and isHunterPet ) then
		return
	end
	local activePetSlotID = HunterPets:GetActiveSpellID()
	if (self.currentPetID == activePetSlotID and not self.renamed) then
		return
	end
	self.renamed = false
	self.currentPetID = activePetSlotID
	local guid = UnitGUID("pet");
	local type, zero, server_id, instance_id, zone_uid, npc_id, spawn_uid = strsplit("-",guid);
	local icon = GetSpellTexture(CALL_PET_SPELL_IDS[activePetSlotID])
	local name, level, family = UnitName("pet"), UnitLevel("pet"),UnitCreatureFamily("pet")
	local displayId

	if npc_id then
		petDataIndex = HunterPets:FindPetIndex(npc_id)
	end

	if petDataIndex then
		displayId = HunterPets.Pets.DisplayId[petDataIndex]
	end

	if (activePetSlotID and icon and name and level and family and npc_id and displayId) then
		HunterPetsGlobal.data[realmName][playerName].OwnedPets[activePetSlotID] = icon .. ":" ..  name .. ":" ..  level .. ":" ..  family .. ":" .. npc_id .. ":" ..  displayId
	end
	self.currentPetID = 0
end

function HunterPets:ZoneChange()
	if not self.currentZone then
		self.currentZone = GetRealZoneText()
		if (HunterPetsSettings.showZoneTamableText) then
			self:PrintTamablePetsInZone()
		end
	elseif self.currentZone ~= GetRealZoneText() then
		self.currentZone = GetRealZoneText()
		if (HunterPetsSettings.showZoneTamableText) then
			self:PrintTamablePetsInZone()
		end
	end
end

function HunterPets:PrintTamablePetsInZone()
	local zoneId = nil
	local numPets = 0
	for k in pairs(HunterPets.Locations) do
		if (HunterPets.Locations[k] == GetRealZoneText()) then
			zoneId = k;
		end
    end

	for i=1, #HunterPets.Pets.Location do
		if HunterPets.Pets.Location[i] == zoneId then
			numPets = numPets + 1
		end
	end
	if numPets > 0 then
		self:Print(numPets, "tamable pets in zone!")
	end
end

function HunterPets:GetNumPetsAll()
	local numCharacters = 0;
	local numPets = 0;
	local numPetsFullyScanned = 0;
	for realm in pairs(HunterPetsGlobal.data) do
		for character in pairs(HunterPetsGlobal.data[realm]) do
			numCharacters = numCharacters + 1;
			for pet in pairs(HunterPetsGlobal.data[realm][character].OwnedPets) do
				numPets = numPets + 1;
				local icon, name, level, family, npc_id, displayId = strsplit(":", HunterPetsGlobal.data[realm][character].OwnedPets[pet])
				if displayId then numPetsFullyScanned = numPetsFullyScanned + 1 end
			end
		end
	end
	return numCharacters, numPets, numPetsFullyScanned
end
--[[
function HunterPets:GetNumPets(character)
	local numPets = 0;
	local numPetsFullyScanned = 0;
	for realm in pairs(HunterPetsGlobal.data) do
		for characters in pairs(HunterPetsGlobal.data[realm]) do
			if (characters == character) then
				for pet in pairs(HunterPetsGlobal.data[realm][character].OwnedPets) do
					numPets = numPets + 1;
					local icon, name, level, family, npc_id, displayId = strsplit(":", HunterPetsGlobal.data[realm][character].OwnedPets[pet])
					if displayId then numPetsFullyScanned = numPetsFullyScanned + 1 end
				end
			end
		end
	end
	return numPets, numPetsFullyScanned
end
]]
function HunterPets:GetNumPets(realm, character)
	if not HunterPetsGlobal.data[realm] then return 0,0 end
	if not HunterPetsGlobal.data[realm][character] then return 0,0 end
	local numPets = 0;
	local numPetsFullyScanned = 0;
	for pet in pairs(HunterPetsGlobal.data[realm][character].OwnedPets) do
		numPets = numPets + 1;
		local icon, name, level, family, npc_id, displayId = strsplit(":", HunterPetsGlobal.data[realm][character].OwnedPets[pet])
		if displayId then numPetsFullyScanned = numPetsFullyScanned + 1 end
	end
	return numPets, numPetsFullyScanned
end


function HunterPets:FindDuplicates()
	local ids = {};
	for realm in pairs(HunterPetsGlobal.data) do
		for character in pairs(HunterPetsGlobal.data[realm]) do
			for pet in pairs(HunterPetsGlobal.data[realm][character].OwnedPets) do
				local icon, name, level, family, npc_id, displayId = strsplit(":", HunterPetsGlobal.data[realm][character].OwnedPets[pet])
				if displayId then
					if not ids[displayId] then
						ids[displayId] = { }
						ids[displayId] = { fam = family, pets = { }}
					end
--					tinsert(ids[displayId]["pets"], realm .. " - " .. character .. " : " .. name )
					tinsert(ids[displayId]["pets"], {realm,character,name })
				end
			end
		end
	end
	local temp = nil
	local hasPrinted = false;	
	for id in pairs(ids) do
		if (#ids[id]["pets"] > 1) then
			if not hasPrinted then
				hasPrinted = true
				self:Print("Found duplicates!")
			end

			temp = ids[id]["fam"] .. " "
			for i=1, #ids[id]["pets"] do
				temp = temp .. " ( " .. ids[id]["pets"][i][1] .. " - " .. ids[id]["pets"][i][2] .. " : " .. ids[id]["pets"][i][3] .. " ) "
			end
			self:Print(temp)
		end
	end

	if not hasPrinted then
		self:Print("No duplicates found!")
	end
end

function HunterPets:FindDuplicate(r,c,n, checkDisplayId)
	if not checkDisplayId then return end
	local ids = {};
	for realm in pairs(HunterPetsGlobal.data) do
		for character in pairs(HunterPetsGlobal.data[realm]) do
			for pet in pairs(HunterPetsGlobal.data[realm][character].OwnedPets) do
				local icon, name, level, family, npc_id, displayId = strsplit(":", HunterPetsGlobal.data[realm][character].OwnedPets[pet])

				if displayId then
					if not((r == realm) and (c == character) and (n == name)) then
						if tonumber(displayId) == tonumber(checkDisplayId) then
							if not ids[displayId] then
								ids[displayId] = { }
								ids[displayId] = { fam = family, pets = { }}
							end
		--					tinsert(ids[displayId]["pets"], realm .. " - " .. character .. " : " .. name )
							tinsert(ids[displayId]["pets"], {realm,character,name })
						end
					end
				end
			end
		end
	end
	return (ids[""..checkDisplayId])
end

function HunterPets:Stats()
	local numChars, numPets, numPetsScanned = HunterPets:GetNumPetsAll();
	self:Print(numChars .. " characters scanned.");
--	self:Print(HunterPets:GetNumPets())
	self:Print(numPets .. " pets found (" .. numPetsScanned .. " fully scanned).");
	HunterPets:FindDuplicates()
end

function HunterPets:ChatCMD(input)
	if input == "" then
		self:Print("Commands");
		self:Print("/hunterpets zone - Enable/Disable zone message");
		self:Print("/hunterpets stats - Show statistics");

		if (IsAddOnLoaded("HunterPets_Owned")) then
			self:Print("/hunterpets stable - Show Stabled Pets");
			self:Print("/hunterpets autoshow - Auto open Stabled Browser at Stable Master")
		end
	elseif string.lower(input) == "zone" then
		if HunterPetsSettings.showZoneTamableText then
			self:Print("Disabled tamable pets in zone message!")
			HunterPetsSettings.showZoneTamableText = false;
		else
			self:Print("Enabled tamable pets in zone message!")
			HunterPetsSettings.showZoneTamableText = true;
		end
	elseif string.lower(input) == "stats" then
		HunterPets:Stats();
	elseif string.lower(input) == "stable" then
		if (IsAddOnLoaded("HunterPets_Owned")) then
			HunterPetsOwned:Show()
		end
	elseif string.lower(input) == "autoshow" then
		if (IsAddOnLoaded("HunterPets_Owned")) then
			HunterPetsSettings.autoShowBrowser = not HunterPetsSettings.autoShowBrowser
			if (HunterPetsSettings.autoShowBrowser) then
				self:Print("Enabled auto open Browser at Stable Master")
			else
				self:Print("Disabled auto open Browser at Stable Master")
			end
		end
	end

end

