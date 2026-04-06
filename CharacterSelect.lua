--[[

	   _____ _                          _               _____      _           _   
	  / ____| |                        | |             / ____|    | |         | |  
	 | |    | |__   __ _ _ __ __ _  ___| |_ ___ _ __  | (___   ___| | ___  ___| |_ 
	 | |    | '_ \ / _` | '__/ _` |/ __| __/ _ \ '__|  \___ \ / _ \ |/ _ \/ __| __|
	 | |____| | | | (_| | | | (_| | (__| ||  __/ |     ____) |  __/ |  __/ (__| |_ 
	  \_____|_| |_|\__,_|_|  \__,_|\___|\__\___|_|    |_____/ \___|_|\___|\___|\__|
	                                                                               
	                                                                               
  

	Written by vladbods for ZSSK Roblox
	@2026 All rights reserved
	
	CharacterSelect is a module that helps with selecting characters of players and/or NPCs for later handling.
]]--

local CharacterSelect = {}
CharacterSelect.__index = CharacterSelect

-- Services
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

function CharacterSelect.new(acceptedParties: "All" | "Players" | "NPCs", useHighlight: boolean, xRayEnabled: boolean, onClickStop: boolean, onDeathStop: boolean)
	local self = setmetatable({}, CharacterSelect)

	self._player = Players.LocalPlayer
	self._mouse = self._player:GetMouse()
	
	self._acceptedParties = acceptedParties or "Players" -- "Players", "NPCs", "All"
	self._xRayEnabled = xRayEnabled or false

	self._useHighlight = useHighlight or false
	self._highlights = {}
	
	self._onClickStop = onClickStop or false
	self._onDeathStop = onDeathStop or false

	self._selectedPlayer = nil
	self._hoveredPlayer = nil
	
	self._connections = {}
	self._running = true

	-- Events
	self.PlayerClicked = Instance.new("BindableEvent")
	self.PlayerHovered = Instance.new("BindableEvent")

	-- Setup players
	if self._acceptedParties == "Players" or self._acceptedParties == "All" then
		for _, player in ipairs(Players:GetPlayers()) do
			if not player:IsA("Player") then continue end
			
			self:_setupPlayer(player)
		end

		table.insert(self._connections,
			Players.PlayerAdded:Connect(function(player)
				if not player:IsA("Player") then return end
				
				self:_setupPlayer(player)
			end)
		)

		table.insert(self._connections,
			Players.PlayerRemoving:Connect(function(player)
				if not player:IsA("Player") then return end
				
				self:_removePlayer(player)
			end)
		)
	end
	
	-- Setup NPCs
	if self._acceptedParties == "NPCs" or self._acceptedParties == "All" then
		for _, npcFolder in ipairs(Players:GetPlayers()) do
			if not npcFolder:IsA("Folder") then continue end

			self:_setupNPC(npcFolder)
		end
		
		table.insert(self._connections,
			Players.DescendantAdded:Connect(function(npcFolder)
				if not npcFolder:IsA("Folder") then return end

				self:_setupNPC(npcFolder)
			end)
		)

		table.insert(self._connections,
			Players.DescendantRemoving:Connect(function(npcFolder)
				if not npcFolder:IsA("Folder") then return end

				self:_removePlayer(npcFolder)
			end)
		)
	end
	
	-- Automatic stop on death
	if self._onDeathStop then
		local function hookCharacter(char)
			local humanoid = char:WaitForChild("Humanoid")
			if humanoid then
				table.insert(self._connections,
					humanoid.Died:Connect(function()
						self:Destroy()
					end)
				)
			end
		end

		if self._player.Character then
			hookCharacter(self._player.Character)
		end

		table.insert(self._connections,
			self._player.CharacterAdded:Connect(hookCharacter)
		)
	end


	-- Hover detection
	table.insert(self._connections,
		RunService.RenderStepped:Connect(function()
			if self._running then
				self:_updateHover()
			end
		end)
	)

	table.insert(self._connections,
		self._mouse.Button1Down:Connect(function()
			if self._running then
				self:_handleClick()
			end
		end)
	)

	return self
end

function CharacterSelect:Destroy()
	if not self._running then return end
	self._running = false

	-- Disconnect everything
	for _, conn in ipairs(self._connections) do
		conn:Disconnect()
	end
	self._connections = {}

	-- Remove highlights
	for player, highlight in pairs(self._highlights) do
		if highlight then
			highlight:Destroy()
		end
	end
	self._highlights = {}

	-- Destroy events
	if self.PlayerClicked then
		self.PlayerClicked:Destroy()
	end
	if self.PlayerHovered then
		self.PlayerHovered:Destroy()
	end

	-- Clear references
	self._selectedPlayer = nil
	self._hoveredPlayer = nil
end


function CharacterSelect:_setupPlayer(player)
	if player == self._player then return end

	table.insert(self._connections, 
		player.CharacterAdded:Connect(function(char)
			if self._useHighlight then
				self:_addHighlight(player, char)
			end
		end)
	)
	
	if player.Character and self._useHighlight then
		self:_addHighlight(player, player.Character)
	end
end

function CharacterSelect:_setupNPC(npcFolder)
	table.insert(self._connections, 
		npcFolder.DescendantAdded:Connect(function(char)
			if char.Name == "Character" and char:IsA("ObjectValue") and char.Value:IsA("Model") then
				if self._useHighlight then
					self:_addHighlight(npcFolder, char.Value)
				end
			end
		end)
	)

	if npcFolder.Character and self._useHighlight then
		self:_addHighlight(npcFolder, npcFolder.Character.Value)
	end
end

function CharacterSelect:_addHighlight(player, character)
	self:_removePlayer(player)

	local highlight = Instance.new("Highlight")
	highlight.FillColor = Color3.fromRGB(85, 170, 255)
	highlight.OutlineColor = Color3.fromRGB(0, 0, 0)
	highlight.Adornee = character
	highlight.Parent = workspace

	self._highlights[player] = highlight
end

function CharacterSelect:_removePlayer(player)
	if self._highlights[player] then
		self._highlights[player]:Destroy()
		self._highlights[player] = nil
	end
end

function CharacterSelect:_getPlayerFromPart(part)
	if not part then return nil end

	local model = part:FindFirstAncestorWhichIsA("Model")
	if not model then return nil end

	-- Check if it’s actually a character
	if model:FindFirstChild("Humanoid") then
		local player = Players:GetPlayerFromCharacter(model)
		if player then
			return player
		else
			return Players:FindFirstChild(model.Name)			
		end
	end

	return nil
end

function CharacterSelect:_getPlayerFromMouse()
	local camera = workspace.CurrentCamera
	local mousePos = UserInputService:GetMouseLocation()

	local ray = camera:ViewportPointToRay(mousePos.X, mousePos.Y)

	local params = RaycastParams.new()
	
	if self._xRayEnabled then
		if self._acceptedParties == "Players" or self._acceptedParties == "All" then
			params.FilterType = Enum.RaycastFilterType.Include
			
			local players = {}
			for _, p in ipairs(Players:GetPlayers()) do
				if p.Character then
					table.insert(players, p.Character)
				end
			end
			
			params.FilterDescendantsInstances = players
		end
	end
	
	-- ignore local player character
	--if self._player.Character then
	--	params.FilterDescendantsInstances = { self._player.Character }
	--end

	local result = workspace:Raycast(ray.Origin, ray.Direction * 1000, params)

	if result then
		return self:_getPlayerFromPart(result.Instance)
	end

	return nil
end

function CharacterSelect:_updateHover()
	local player = self:_getPlayerFromMouse()

	if player ~= self._hoveredPlayer then
		-- Reset previous hover outline
		if self._hoveredPlayer and self._useHighlight then
			local oldHighlight = self._highlights[self._hoveredPlayer]
			if oldHighlight then
				oldHighlight.OutlineColor = Color3.fromRGB(0, 0, 0)
			end
		end
		
		if player == nil then
			self._hoveredPlayer = nil
			self.PlayerHovered:Fire(nil)
		else
			if player:IsA("Player") then
				self._hoveredPlayer = player.Character
				self.PlayerHovered:Fire(player.Character)
			else
				self._hoveredPlayer = player.Character.Value
				self.PlayerHovered:Fire(player.Character.Value)
			end
		end

		-- Apply new hover outline
		if player and self._useHighlight then
			local highlight = self._highlights[player]
			if highlight then
				highlight.OutlineColor = Color3.fromRGB(255, 255, 255) 
			end
		end
	end
end

function CharacterSelect:_handleClick()
	local player = self:_getPlayerFromMouse()

	if player then
		if self._useHighlight then
			-- Reset previous selected
			if self._selectedPlayer then
				local old = self._highlights[self._selectedPlayer]
				if old then
					old.FillColor = Color3.fromRGB(85, 170, 255)
				end
			end

			-- Set new selected (RED)
			self._selectedPlayer = player
			local highlight = self._highlights[player]
			if highlight then
				highlight.FillColor = Color3.fromRGB(255, 0, 0)
			end
		end
		
		if player:IsA("Player") then
			self.PlayerClicked:Fire(player.Character)
		else
			self.PlayerClicked:Fire(player.Character.Value)
		end
		
		if self._onClickStop then
			self:Destroy()
		end
	else
		if self._selectedPlayer then
			local old = self._highlights[self._selectedPlayer]
			if old then
				old.FillColor = Color3.fromRGB(85, 170, 255)
			end
		end
	end
end

return CharacterSelect
