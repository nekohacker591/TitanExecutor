--// 0. CLEANUP EXISTING CONNECTIONS
if _G.Titan_Connection then
	pcall(function()
		_G.Titan_Connection:Disconnect()
	end)
	_G.Titan_Connection = nil
end

--// 1. SERVICES
local CoreGui = game:GetService("CoreGui")
local UserInputService = game:GetService("UserInputService")
local TextService = game:GetService("TextService")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")
local Players = game:GetService("Players")
local HttpService = game:GetService("HttpService")
local Camera = Workspace.CurrentCamera

if not RunService:IsRunning() then return end


local checkduplicate = function()
if CoreGui:FindFirstChild("Titan_V44") then
	CoreGui.Titan_V44:Destroy()
end end
pcall(checkduplicate) -- for roblox studio debugging 


--// 2. FORWARD DECLARATIONS
local ScreenGui, MainFrame, CodeInputBox, SuggestionFrame, InspectorFrame, PreviewWindow
local InspectorScrollFrame, PreviewScrollFrame, HighlightTextLabel, LineNumbersLabel, EditorScrollFrame

--- STATE TRACKING ---
local EditorState = {
	ScanResults = {},           -- The list of auto-complete suggestions found
	CurrentQuery = "",          -- What the user typed to search
	SelectedIndex = 1,          -- Which suggestion is currently highlighted (blue)
	IsMenuActive = false,       -- Is the suggestion menu currently open?
	IgnoreNextUpdate = false,   -- A flag to stop the code from updating while we are inserting text
	ParentObject = nil,         -- The object we are getting children from (e.g., workspace)

	-- Augmented Reality (AR) Variables
	AugmentedRealityClone = nil,      -- The fake 3D object shown in the world
	AugmentedRealityConnection = nil, -- The loop connection that updates the 3D object
	AugmentedRealityLoadThread = nil, -- A separate thread for loading big models so the game doesn't freeze

	LastInspectedObject = nil,  -- The last object we looked at in the Inspector window
	PreviewScale = 1,           -- Zoom scale for the preview
	PreviewMode = "Static",     -- "Static" (spins) or "Live" (follows the real object)

	PartMappingTable = {},      -- Maps real parts to fake parts for the "Live" preview mode

	IsArgumentMode = false,     -- Are we typing inside function brackets? e.g. function(HERE)
	ArgumentQuote = "",         -- Are we inside a string? " or '
	IsNavigating = false,       -- Is the user pressing Up/Down arrows?
	SymbolTable = {},           -- Stores variables defined in the script (local x = ...)

	CurrentParentPath = nil,    -- The path to the object we are typing (e.g. "game.Workspace")
	CurrentSeparator = "."      -- The separator used ("." or ":")
}

--// 3. CONFIGURATION
local Configuration = {
	Colors = {
		MainBackground = Color3.fromRGB(30, 30, 30),
		EditorBackground = Color3.fromRGB(20, 20, 20),
		TopBar = Color3.fromRGB(45, 45, 45),
		Text = Color3.fromRGB(240, 240, 240),
		AccentBlue = Color3.fromRGB(0, 120, 215),
		SuggestionBackground = Color3.fromRGB(40, 40, 40),
		InspectorBackground = Color3.fromRGB(25, 25, 25),

		Syntax = {
			Keyword = "#FF79C6", -- pink (local, function)
			Number = "#BD93F9",  -- purple (123)
			String = "#F1FA8C",  -- yellow ("text")
			Comment = "#6272A4", -- grey (-- comment)
			BuiltIn = "#8BE9FD", -- cyan (game, workspace)
			Method = "#50FA7B",  -- green (functions)
			Variable = "#FFFFFF" -- white
		}
	},
	Font = Enum.Font.Code,
	ItemHeight = 20
}

--// 4. SYNTAX HIGHLIGHTING ENGINE
local SyntaxSystem = {}

function SyntaxSystem.Highlight(rawText)
	rawText = rawText:gsub("&", "&amp;"):gsub("<", "&lt;"):gsub(">", "&gt;")
	local replacementTable = {}
	local uniqueId = 0

	local function createMask(textToColor, colorCode)
		uniqueId = uniqueId + 1
		local key = "\0" .. uniqueId .. "\0"
		replacementTable[key] = string.format('<font color="%s">%s</font>', colorCode, textToColor)
		return key
	end

	rawText = rawText:gsub("(%-%-.+)", function(match) return createMask(match, Configuration.Colors.Syntax.Comment) end)
	rawText = rawText:gsub('(".-")', function(match) return createMask(match, Configuration.Colors.Syntax.String) end)
	rawText = rawText:gsub("('.-')", function(match) return createMask(match, Configuration.Colors.Syntax.String) end)

	local keywords = {
		["local"]=1, ["function"]=1, ["if"]=1, ["then"]=1, ["else"]=1, ["end"]=1, 
		["return"]=1, ["while"]=1, ["do"]=1, ["for"]=1, ["in"]=1, ["true"]=1, 
		["false"]=1, ["nil"]=1
	}

	local builtIns = {
		["game"]=1, ["workspace"]=1, ["script"]=1, ["task"]=1, ["math"]=1, 
		["table"]=1, ["string"]=1, ["coroutine"]=1, ["print"]=1, ["warn"]=1, 
		["error"]=1, ["wait"]=1, ["Enum"]=1, ["Instance"]=1, ["CFrame"]=1, 
		["Vector3"]=1, ["Vector2"]=1, ["Color3"]=1, ["UDim2"]=1, ["UDim"]=1, 
		["Ray"]=1, ["TweenInfo"]=1, ["tick"]=1, ["pcall"]=1, ["typeof"]=1, ["require"]=1
	}

	rawText = rawText:gsub("(%a[%w_]*)", function(word)
		if keywords[word] then return createMask(word, Configuration.Colors.Syntax.Keyword) end
		if builtIns[word] then return createMask(word, Configuration.Colors.Syntax.BuiltIn) end
		return word
	end)

	rawText = rawText:gsub("local%s+([%a_][%w_]*)", function(fullMatch, variableName)
		return fullMatch:gsub(variableName, createMask(variableName, Configuration.Colors.Syntax.Variable))
	end)

	return rawText:gsub("%z%d+%z", function(key) return replacementTable[key] or key end)
end

--// 5. INTELLISENSE ENGINE
local IntellisenseSystem = {}

IntellisenseSystem.Libraries = {task=true, math=true, table=true, string=true, coroutine=true, debug=true, os=true, utf8=true, bit32=true}
IntellisenseSystem.GlobalFunctions = {
	["assert"]=true, ["collectgarbage"]=true, ["error"]=true, ["getfenv"]=true, 
	["getmetatable"]=true, ["ipairs"]=true, ["loadstring"]=true, ["next"]=true, 
	["pairs"]=true, ["pcall"]=true, ["print"]=true, ["rawequal"]=true, 
	["rawget"]=true, ["rawset"]=true, ["require"]=true, ["select"]=true, 
	["setfenv"]=true, ["setmetatable"]=true, ["tonumber"]=true, ["tostring"]=true, 
	["type"]=true, ["unpack"]=true, ["xpcall"]=true, ["_G"]=true, ["_VERSION"]=true, 
	["spawn"]=true, ["delay"]=true, ["wait"]=true, ["tick"]=true, ["time"]=true, 
	["typeof"]=true, ["settings"]=true, ["UserSettings"]=true, ["elapsedTime"]=true, 
	["stats"]=true, ["plugin"]=true, ["warn"]=true
}

IntellisenseSystem.Constructors = {
	"Vector3", "Vector2", "CFrame", "Color3", "UDim2", "UDim", "Ray", "Rect", 
	"Region3", "Region3int16", "NumberRange", "NumberSequence", "ColorSequence", 
	"ColorSequenceKeypoint", "PhysicalProperties", "RaycastParams", "OverlapParams", 
	"TweenInfo", "Axes", "Faces", "Enum", "_G", "shared", "BrickColor", 
	"Vector3int16", "PathWaypoint"
}

-- Priority Weights
IntellisenseSystem.HighPriorityWeights = {
	["Part"] = 100, ["Model"] = 100, ["Folder"] = 100, ["Script"] = 95, 
	["LocalScript"] = 95, ["ModuleScript"] = 95, ["MeshPart"] = 90, 
	["ScreenGui"] = 90, ["Frame"] = 85, ["TextLabel"] = 85, ["TextButton"]= 85, 
	["RemoteEvent"] = 80, ["BindableEvent"] = 80, ["Animation"] = 80, 
	["Humanoid"] = 80, ["Tool"] = 80, ["Sound"] = 75, ["Highlight"] = 75,
	["EditableImage"] = 85, ["EditableMesh"] = 85, ["AudioPlayer"] = 85
}

IntellisenseSystem.Services = {}
IntellisenseSystem.CreatableInstances = {}
IntellisenseSystem.Classes = {}
IntellisenseSystem.Enums = {} 

IntellisenseSystem.Classes["task"] = { Inherits = "<<<ROOT>>>", Properties = {}, Methods = {"wait", "spawn", "defer", "delay", "cancel"}, Events = {}, Callbacks = {}, MemberInfo={ wait = { Type="Function", ReturnType="number" } } }
IntellisenseSystem.Classes["math"] = { Inherits = "<<<ROOT>>>", Properties = {"pi", "huge"}, Methods = {"abs", "acos", "asin", "atan", "ceil", "cos", "deg", "exp", "floor", "fmod", "rad", "log", "log10", "max", "min", "pow", "sin", "sqrt", "tan", "clamp", "sign", "round", "noise"}, Events = {}, Callbacks = {}, MemberInfo={} }
IntellisenseSystem.Classes["string"] = { Inherits = "<<<ROOT>>>", Properties = {}, Methods = {"byte", "char", "find", "format", "gmatch", "gsub", "len", "lower", "match", "rep", "reverse", "sub", "upper", "split", "pack", "unpack"}, Events = {}, Callbacks = {}, MemberInfo={} }
IntellisenseSystem.Classes["table"] = { Inherits = "<<<ROOT>>>", Properties = {}, Methods = {"insert", "remove", "sort", "concat", "create", "find", "getn", "maxn", "pack", "unpack", "move", "clear", "freeze", "isfrozen"}, Events = {}, Callbacks = {}, MemberInfo={} }
IntellisenseSystem.Classes["coroutine"] = { Inherits = "<<<ROOT>>>", Properties = {}, Methods = {"create", "resume", "yield", "wrap", "close", "isyieldable", "status", "running"}, Events = {}, Callbacks = {}, MemberInfo={} }

IntellisenseSystem.ArgumentHandlers = {
	["new"] = function(funcPath, argText)
		local parentClass = funcPath:match("^(.-)%.new$")
		local results = {}
		if parentClass == "Instance" then
			local query = argText:match('^["\']?([%w_]*)["\']?$') or ""
			for _, cls in ipairs(IntellisenseSystem.CreatableInstances) do
				if cls:lower():find(query:lower(), 1, true) then
					local weight = IntellisenseSystem.HighPriorityWeights[cls] or 1
					table.insert(results, {Name=cls, Type="Class", Weight=weight, Extra="Creatable"})
				end
			end
			table.sort(results, function(a,b) return a.Weight > b.Weight end)
		elseif parentClass == "CFrame" then
			table.insert(results, {Name="CFrame.new(x, y, z, ...)", Type="Signature"})
		elseif parentClass == "Vector3" then
			table.insert(results, {Name="Vector3.new(x, y, z)", Type="Signature"})
		elseif parentClass == "Vector2" then
			table.insert(results, {Name="Vector2.new(x, y)", Type="Signature"})
		elseif parentClass == "UDim2" then
			table.insert(results, {Name="UDim2.new(xScale, xOff, yScale, yOff)", Type="Signature"})
		end
		return results
	end,
	["GetService"] = function(funcPath, argText)
		local query = argText:match('^["\']?([%w_]*)["\']?$') or ""
		local results = {}
		for _, svc in ipairs(IntellisenseSystem.Services) do
			if svc:lower():find(query:lower(), 1, true) then
				table.insert(results, {Name=svc, Type="Service", Weight=10, Extra="Service"})
			end
		end
		return results
	end,
	["FindFirstChild"] = function(funcPath, argText)
		local parentPath = funcPath:match("^(.-):FindFirstChild$")
		local parentObj = parentPath and IntellisenseSystem.ResolveLive(parentPath)
		if not parentObj then return {} end
		local query = argText:match('^["\']?([%w_]*)["\']?$') or ""
		local results = {}
		if typeof(parentObj) == "Instance" then
			for _,child in ipairs(parentObj:GetChildren()) do
				if child.Name:lower():find(query:lower(), 1, true) then
					table.insert(results, {Name=child.Name, Type="Child", Weight=60, Extra=child.ClassName})
				end
			end
		end
		return results
	end,
	["require"] = function(funcPath, argText)
		local results = {}
		local seenPaths = {}
		local function search(inst)
			if inst:IsA("ModuleScript") then
				local path = inst:GetFullName()
				if not seenPaths[path] then
					table.insert(results, { Name = path, Type = "Module", Weight = 100, Extra = inst.Name })
					seenPaths[path] = true
				end
			end
			for _, child in ipairs(inst:GetChildren()) do search(child) end
		end
		search(game)
		return results
	end
}

IntellisenseSystem.ArgumentHandlers["WaitForChild"] = IntellisenseSystem.ArgumentHandlers["FindFirstChild"]
IntellisenseSystem.ArgumentHandlers["fromRGB"] = function() return {{Name="Color3.fromRGB(r, g, b)", Type="Signature"}} end
IntellisenseSystem.ArgumentHandlers["fromHSV"] = function() return {{Name="Color3.fromHSV(h, s, v)", Type="Signature"}} end

function IntellisenseSystem.RegisterClass(className, superclass, tags)
	if IntellisenseSystem.Classes[className] then return end

	local isService = false
	local isCreatable = true

	if tags then
		for _, tag in ipairs(tags) do
			if tag == "Service" then isService = true end
			if tag == "NotCreatable" or tag == "Abstract" then isCreatable = false end
		end
	end

	IntellisenseSystem.Classes[className] = {
		Inherits = superclass,
		Properties = {},
		Methods = {},
		Events = {},
		Callbacks = {},
		MemberInfo = {}
	}

	if isService then table.insert(IntellisenseSystem.Services, className) end
	if isCreatable then table.insert(IntellisenseSystem.CreatableInstances, className) end
end

function IntellisenseSystem.RegisterMember(className, member)
	local cls = IntellisenseSystem.Classes[className]
	if not cls then return end

	if member.MemberType == "Property" then
		table.insert(cls.Properties, member.Name)
		cls.MemberInfo[member.Name] = { 
			Type="Property", 
			ValueType = (member.ValueType and member.ValueType.Name or "any") 
		}
	elseif member.MemberType == "Function" then
		table.insert(cls.Methods, member.Name)
		cls.MemberInfo[member.Name] = { 
			Type="Function", 
			ReturnType = (member.ReturnType and member.ReturnType.Name or "any") 
		}
	elseif member.MemberType == "Event" then
		table.insert(cls.Events, member.Name)
		cls.MemberInfo[member.Name] = { Type="Event" }
	elseif member.MemberType == "Callback" then
		table.insert(cls.Callbacks, member.Name)
		cls.MemberInfo[member.Name] = { Type="Callback" }
	end
end

-- Integrated Mini Dump
local function LoadIntegratedDump()
	IntellisenseSystem.RegisterClass("Instance", "<<<ROOT>>>", {})
	IntellisenseSystem.RegisterMember("Instance", {MemberType="Property", Name="Name", ValueType={Name="string"}})
	IntellisenseSystem.RegisterMember("Instance", {MemberType="Property", Name="Parent", ValueType={Name="Instance"}})
	IntellisenseSystem.RegisterMember("Instance", {MemberType="Property", Name="ClassName", ValueType={Name="string"}})
	IntellisenseSystem.RegisterMember("Instance", {MemberType="Function", Name="Destroy", ReturnType={Name="void"}})
	IntellisenseSystem.RegisterMember("Instance", {MemberType="Function", Name="Clone", ReturnType={Name="Instance"}})
	IntellisenseSystem.RegisterMember("Instance", {MemberType="Function", Name="GetChildren", ReturnType={Name="table"}})
	IntellisenseSystem.RegisterMember("Instance", {MemberType="Function", Name="GetDescendants", ReturnType={Name="table"}})
	IntellisenseSystem.RegisterMember("Instance", {MemberType="Function", Name="FindFirstChild", ReturnType={Name="Instance"}})
	IntellisenseSystem.RegisterMember("Instance", {MemberType="Function", Name="WaitForChild", ReturnType={Name="Instance"}})
	IntellisenseSystem.RegisterMember("Instance", {MemberType="Event", Name="Changed"})
	IntellisenseSystem.RegisterMember("Instance", {MemberType="Event", Name="ChildAdded"})
	IntellisenseSystem.RegisterMember("Instance", {MemberType="Event", Name="ChildRemoved"})

	IntellisenseSystem.RegisterClass("PVInstance", "Instance", {"NotCreatable"})
	IntellisenseSystem.RegisterMember("PVInstance", {MemberType="Function", Name="PivotTo", ReturnType={Name="void"}})
	IntellisenseSystem.RegisterMember("PVInstance", {MemberType="Function", Name="GetPivot", ReturnType={Name="CFrame"}})

	IntellisenseSystem.RegisterClass("BasePart", "PVInstance", {"NotCreatable"})
	IntellisenseSystem.RegisterMember("BasePart", {MemberType="Property", Name="Position", ValueType={Name="Vector3"}})
	IntellisenseSystem.RegisterMember("BasePart", {MemberType="Property", Name="CFrame", ValueType={Name="CFrame"}})
	IntellisenseSystem.RegisterMember("BasePart", {MemberType="Property", Name="Size", ValueType={Name="Vector3"}})
	IntellisenseSystem.RegisterMember("BasePart", {MemberType="Property", Name="Color", ValueType={Name="Color3"}})
	IntellisenseSystem.RegisterMember("BasePart", {MemberType="Property", Name="Anchored", ValueType={Name="bool"}})
	IntellisenseSystem.RegisterMember("BasePart", {MemberType="Property", Name="CanCollide", ValueType={Name="bool"}})
	IntellisenseSystem.RegisterMember("BasePart", {MemberType="Property", Name="Transparency", ValueType={Name="float"}})
	IntellisenseSystem.RegisterMember("BasePart", {MemberType="Event", Name="Touched"})

	IntellisenseSystem.RegisterClass("Part", "BasePart", {})
	IntellisenseSystem.RegisterClass("MeshPart", "BasePart", {})
	IntellisenseSystem.RegisterClass("Model", "PVInstance", {})
	IntellisenseSystem.RegisterMember("Model", {MemberType="Property", Name="PrimaryPart", ValueType={Name="BasePart"}})

	IntellisenseSystem.RegisterClass("EditableImage", "Object", {"NotCreatable"})
	IntellisenseSystem.RegisterMember("EditableImage", {MemberType="Function", Name="WritePixels", ReturnType={Name="void"}})
	IntellisenseSystem.RegisterMember("EditableImage", {MemberType="Function", Name="ReadPixels", ReturnType={Name="table"}})

	IntellisenseSystem.RegisterClass("EditableMesh", "Object", {"NotCreatable"})
	IntellisenseSystem.RegisterClass("AudioPlayer", "Instance", {})
	IntellisenseSystem.RegisterMember("AudioPlayer", {MemberType="Function", Name="Play", ReturnType={Name="void"}})
	IntellisenseSystem.RegisterClass("AudioDeviceInput", "Instance", {})
	IntellisenseSystem.RegisterClass("Wire", "Instance", {})

	IntellisenseSystem.RegisterClass("Workspace", "Model", {"Service"})
	IntellisenseSystem.RegisterMember("Workspace", {MemberType="Property", Name="CurrentCamera", ValueType={Name="Camera"}})
	IntellisenseSystem.RegisterClass("Players", "Instance", {"Service"})
	IntellisenseSystem.RegisterMember("Players", {MemberType="Property", Name="LocalPlayer", ValueType={Name="Player"}})
	IntellisenseSystem.RegisterMember("Players", {MemberType="Function", Name="GetPlayers", ReturnType={Name="table"}})
	IntellisenseSystem.RegisterClass("Lighting", "Instance", {"Service"})
	IntellisenseSystem.RegisterClass("ReplicatedStorage", "Instance", {"Service"})
	IntellisenseSystem.RegisterClass("ServerStorage", "Instance", {"Service"})
	IntellisenseSystem.RegisterClass("ServerScriptService", "Instance", {"Service"})
	IntellisenseSystem.RegisterClass("RunService", "Instance", {"Service"})
	IntellisenseSystem.RegisterMember("RunService", {MemberType="Event", Name="RenderStepped"})
	IntellisenseSystem.RegisterMember("RunService", {MemberType="Event", Name="Heartbeat"})

	IntellisenseSystem.RegisterClass("Player", "Instance", {"NotCreatable"})
	IntellisenseSystem.RegisterMember("Player", {MemberType="Property", Name="Character", ValueType={Name="Model"}})
	IntellisenseSystem.RegisterMember("Player", {MemberType="Property", Name="UserId", ValueType={Name="number"}})

	IntellisenseSystem.RegisterClass("Humanoid", "Instance", {})
	IntellisenseSystem.RegisterMember("Humanoid", {MemberType="Property", Name="Health", ValueType={Name="float"}})
	IntellisenseSystem.RegisterMember("Humanoid", {MemberType="Property", Name="MaxHealth", ValueType={Name="float"}})
	IntellisenseSystem.RegisterMember("Humanoid", {MemberType="Property", Name="WalkSpeed", ValueType={Name="float"}})
	IntellisenseSystem.RegisterMember("Humanoid", {MemberType="Property", Name="JumpPower", ValueType={Name="float"}})
	IntellisenseSystem.RegisterMember("Humanoid", {MemberType="Function", Name="LoadAnimation", ReturnType={Name="AnimationTrack"}})
end
LoadIntegratedDump()

local function LoadRobloxAPIDump()
	local url = "https://raw.githubusercontent.com/MaximumADHD/Roblox-Client-Tracker/roblox/Full-API-Dump.json"
	local success, content = pcall(function() return game:HttpGet(url, true) end)
	if not success then return end 

	local dump = HttpService:JSONDecode(content)
	if dump.Enums then
		for _, enumDef in ipairs(dump.Enums) do
			IntellisenseSystem.Enums[enumDef.Name] = {}
			for _, item in ipairs(enumDef.Items) do
				table.insert(IntellisenseSystem.Enums[enumDef.Name], item.Name)
			end
		end
	end
	for _, classDef in ipairs(dump.Classes) do
		local className = classDef.Name
		if not IntellisenseSystem.Classes[className] then
			IntellisenseSystem.RegisterClass(className, classDef.Superclass, classDef.Tags)
		end
		for _, member in ipairs(classDef.Members) do
			local isDeprecated = false
			if member.Tags then
				for _, tag in ipairs(member.Tags) do if tag == "Deprecated" then isDeprecated = true break end end
			end
			if not isDeprecated then
				IntellisenseSystem.RegisterMember(className, member)
			end
		end
	end
end
task.spawn(LoadRobloxAPIDump)

function IntellisenseSystem.GetAllProperties(className)
	local allProps = {}
	local seen = {}
	local currentClass = className
	while currentClass and currentClass ~= "<<<ROOT>>>" do
		local clsDef = IntellisenseSystem.Classes[currentClass]
		if clsDef and clsDef.Properties then
			for _, propName in ipairs(clsDef.Properties) do
				if not seen[propName] then
					table.insert(allProps, propName)
					seen[propName] = true
				end
			end
		end
		currentClass = clsDef and clsDef.Inherits
	end
	table.sort(allProps)
	return allProps
end

function IntellisenseSystem.GetPathContext(text)
	local length = #text
	local i = length
	local depth = 0
	local inQuote = nil
	while i > 0 do
		local char = text:sub(i, i)
		if inQuote then
			if char == inQuote and text:sub(i-1, i-1) ~= "\\" then inQuote = nil end
		elseif char == '"' or char == "'" then
			inQuote = char
		elseif char == "]" or char == ")" or char == "}" then
			depth = depth + 1
		elseif char == "[" or char == "(" or char == "{" then
			depth = depth - 1
		elseif depth == 0 and char:match("[^%w_%.%:%[\"']") then
			return text:sub(i+1)
		end
		i = i - 1
	end
	return text
end

function IntellisenseSystem.TokenizePath(path)
	local tokens = {}
	local i = 1
	local len = #path
	while i <= len do
		local char = path:sub(i,i)
		if char == "." or char == ":" then
			i = i + 1
		elseif char == "[" then
			local endBracket = path:find("]", i, true)
			if not endBracket then break end
			local content = path:sub(i+1, endBracket-1)
			local inner = content:match("^[\"'](.+)[\"']$")
			table.insert(tokens, inner or content)
			i = endBracket + 1
		else
			local nextSep = path:find("[%.%:%[]", i)
			local segment = nextSep and path:sub(i, nextSep-1) or path:sub(i)
			table.insert(tokens, segment)
			i = nextSep or (len + 1)
		end
	end
	return tokens
end

function IntellisenseSystem.ResolvePathVirtually(path, symbolTable)
	if not path or path == "" then return nil end
	local className, remainingPath
	local varName = path:match("^([%a_][%w_]*)")

	if varName and symbolTable and symbolTable[varName] then
		className = symbolTable[varName].ClassName
		remainingPath = path:sub(#varName + 1)
	elseif path:find('^game:GetService%s*%(', 1, true) then
		local service = path:match('^game:GetService%s*%("%s*([%w_]+)%s*"%)')
		local endPos = path:find("%)", 1, true)
		if service and endPos then
			className = service
			remainingPath = path:sub(endPos + 1)
		else return nil end
	elseif path:find('^Instance.new%s*%(', 1, true) then
		local class = path:match('^Instance.new%s*%("%s*([%w_]+)%s*"%)')
		local endPos = path:find("%)", 1, true)
		if class and endPos then
			className = class
			remainingPath = path:sub(endPos + 1)
		else return nil end
	elseif varName then
		if varName == "game" then className = "DataModel"
		elseif varName == "workspace" then className = "Workspace"
		elseif IntellisenseSystem.Libraries[varName] then className = varName
		elseif IntellisenseSystem.Classes[varName] then className = varName
		elseif varName == "Enum" then className = "Enums"
		else return nil end
		remainingPath = path:sub(#varName + 1)
	else return nil end

	while remainingPath and remainingPath ~= "" do
		local separator, memberName = remainingPath:match("^(.)([%a_][%w_]*)")
		if not memberName then break end

		if className == "Enums" then
			if IntellisenseSystem.Enums[memberName] then
				className = "EnumItem" 
				return { ClassName = "EnumItem", EnumName = memberName }
			end
		end

		local memberInfo = nil
		local tempClass = className
		while tempClass and tempClass ~= "<<<ROOT>>>" and not memberInfo do
			if IntellisenseSystem.Classes[tempClass] and IntellisenseSystem.Classes[tempClass].MemberInfo[memberName] then
				memberInfo = IntellisenseSystem.Classes[tempClass].MemberInfo[memberName]
			end
			tempClass = IntellisenseSystem.Classes[tempClass] and IntellisenseSystem.Classes[tempClass].Inherits
		end

		if memberInfo then
			className = memberInfo.ValueType or memberInfo.ReturnType or "any"
			remainingPath = remainingPath:sub(#separator + #memberName + 1)
		else
			local liveParent = IntellisenseSystem.ResolveLive(path:sub(1, #path - #remainingPath))
			if typeof(liveParent) == "Instance" then
				local child = liveParent:FindFirstChild(memberName)
				if child then
					className = child.ClassName
					remainingPath = remainingPath:sub(#separator + #memberName + 1)
					continue
				end
			end
			return { ClassName = "any" }
		end
	end
	return { ClassName = className }
end

function IntellisenseSystem.ParseLocals(fullText)
	local locals = {}
	for name in fullText:gmatch("function%s+([%a_][%w_.:]*)") do
		name = name:match("([^.:]+)$") or name
		locals[name] = { Type = "Function", ClassName = "Function" }
	end
	for name, expr in fullText:gmatch("local%s+([%a_][%w_]*)%s*=%s*(.+)") do
		expr = expr:match("^%s*(.-)%s*$")
		local resolved = IntellisenseSystem.ResolvePathVirtually(expr, locals)
		locals[name] = { Type = "Variable", ClassName = resolved and resolved.ClassName or "any" }
	end
	return locals
end

function IntellisenseSystem.ResolveLive(path)
	if not path or path == "" then return nil end
	local tokens = IntellisenseSystem.TokenizePath(path)
	if #tokens == 0 then return nil end
	local start = tokens[1]
	local root = nil

	-- // IMPROVED INDEXING LOGIC
	if start == "game" then root = game
	elseif start == "workspace" then root = workspace
	elseif start == "script" then root = script
	elseif start == "Enum" then root = Enum
	elseif IntellisenseSystem.Libraries[start] then return start
	elseif start == "Instance" then return Instance
	else
		pcall(function() root = _G[start] or game:GetService(start) end)
	end

	if not root then return nil end
	local currentObj = root

	for k = 2, #tokens do
		local key = tokens[k]
		if key ~= "" then
			-- // CHECK IF WE ARE INDEXING GAME TO GET A SERVICE
			local newObj = nil
			if currentObj == game then
				local s, srv = pcall(function() return game:GetService(key) end)
				if s and srv then
					newObj = srv
				end
			end

			if not newObj then
				local success, result = pcall(function() return currentObj[key] end)
				if success then
					newObj = result
				elseif typeof(currentObj) == "Instance" then
					newObj = currentObj:FindFirstChild(key)
				end
			end

			currentObj = newObj
			if not currentObj then return nil end
		end
	end
	return currentObj
end

function IntellisenseSystem.Scan(currentLineText, fullScriptText)
	EditorState.IsArgumentMode = false
	EditorState.ArgumentQuote = ""
	local locals = IntellisenseSystem.ParseLocals(fullScriptText)
	EditorState.SymbolTable = locals

	local funcPath, argText = currentLineText:match("([%w_.:]+)%s*%(([^)]*)$")
	if funcPath then
		local memberName = funcPath:match("[:.](%w+)$") or funcPath
		if IntellisenseSystem.ArgumentHandlers[memberName] then
			local results = IntellisenseSystem.ArgumentHandlers[memberName](funcPath, argText)
			if #results > 0 then
				EditorState.IsArgumentMode = true
				return results, (argText:match('["\']?([%w_%.]*)["\']?$') or "")
			end
		end
	end

	local context = IntellisenseSystem.GetPathContext(currentLineText) or ""
	local parentPath, separator, query = context:match("^(.-)([:%.])([%w_]*)$")
	if not parentPath then
		query = context
		parentPath = ""
		separator = ""
	end

	local results = {}
	local seen = {}

	local function addResult(name, type, extraInfo, weight)
		if not seen[name] and name:lower():find(query:lower(), 1, true) then
			local finalWeight = weight
			if (name == "Name" or name == "Parent" or name == "CFrame" or name == "Position") then finalWeight = finalWeight + 5 end
			table.insert(results, {Name=name, Type=type, Extra=extraInfo or "", Weight=finalWeight})
			seen[name]=true
		end
	end

	if parentPath == "" then
		for name, info in pairs(locals) do addResult(name, info.Type, info.ClassName, 50) end
		local roots = {"game","workspace","script", "Enum", "Instance"}
		for _,v in ipairs(roots) do addResult(v, "Global", "", 45) end
		for k,_ in pairs(IntellisenseSystem.Libraries) do addResult(k, "Library", "", 40) end
		for k,_ in pairs(IntellisenseSystem.GlobalFunctions) do addResult(k, "Function", "", 35) end
		for _,v in ipairs(IntellisenseSystem.Constructors) do addResult(v, "Constructor", "", 30) end
	else
		local parentObjVirtual = IntellisenseSystem.ResolvePathVirtually(parentPath, locals)

		if parentObjVirtual and parentObjVirtual.ClassName == "Enums" then
			for enumName, _ in pairs(IntellisenseSystem.Enums) do
				addResult(enumName, "Enum", "Enum", 20)
			end
		elseif parentObjVirtual and parentObjVirtual.ClassName == "EnumItem" and parentObjVirtual.EnumName then
			local items = IntellisenseSystem.Enums[parentObjVirtual.EnumName]
			if items then
				for _, item in ipairs(items) do
					addResult(item, "EnumItem", parentObjVirtual.EnumName, 20)
				end
			end
		end

		local parentObjLive = IntellisenseSystem.ResolveLive(parentPath)

		if parentObjVirtual and parentObjVirtual.ClassName ~= "any" and parentObjVirtual.ClassName ~= "Enums" and parentObjVirtual.ClassName ~= "EnumItem" then
			local currentClass = parentObjVirtual.ClassName
			while currentClass and currentClass ~= "<<<ROOT>>>" do
				local clsDef = IntellisenseSystem.Classes[currentClass]
				if clsDef then
					if separator == "." then
						for _,p in ipairs(clsDef.Properties) do 
							local typeName = clsDef.MemberInfo[p].ValueType
							addResult(p, "Property", typeName, 20) 
						end
						for _,e in ipairs(clsDef.Events) do addResult(e, "Event", currentClass, 15) end
						for _,c in ipairs(clsDef.Callbacks) do addResult(c, "Callback", currentClass, 15) end
						for _,m in ipairs(clsDef.Methods) do addResult(m, "Method", currentClass, 5) end
					elseif separator == ":" then
						for _,m in ipairs(clsDef.Methods) do addResult(m, "Method", currentClass, 20) end
					end
					currentClass = clsDef.Inherits
				else break end
			end
		end

		-- // IMPROVED LIVE SCANNING FOR GAME SERVICES
		if separator == "." and typeof(parentObjLive) == "Instance" then
			pcall(function()
				for _,c in ipairs(parentObjLive:GetChildren()) do
					addResult(c.Name, "Child", c.ClassName, 60)
				end
			end)
		elseif separator == "." and parentObjLive == game then
			-- Specific fallback for 'game.' if children scan fails
			for _, svc in ipairs(IntellisenseSystem.Services) do
				addResult(svc, "Service", "Service", 60)
			end
		end
	end
	table.sort(results, function(a,b)
		if a.Weight == b.Weight then return a.Name < b.Name else return a.Weight > b.Weight end
	end)
	return results, query
end

--// 6. UI CONSTRUCTION
ScreenGui = Instance.new("ScreenGui")
ScreenGui.Name = "Titan_V44"
ScreenGui.ResetOnSpawn = false
ScreenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
pcall(function() ScreenGui.Parent = CoreGui end)
if not ScreenGui.Parent then ScreenGui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui") end

MainFrame = Instance.new("Frame", ScreenGui)
MainFrame.Name = "MainFrame"
MainFrame.Size = UDim2.fromOffset(600, 400)
MainFrame.Position = UDim2.fromScale(0.5,0.5)
MainFrame.AnchorPoint = Vector2.new(0.5,0.5)
MainFrame.BackgroundColor3 = Configuration.Colors.MainBackground
MainFrame.Active = true
MainFrame.Draggable = true
Instance.new("UICorner", MainFrame).CornerRadius = UDim.new(0,6)

local TitleBar = Instance.new("Frame", MainFrame)
TitleBar.Size=UDim2.new(1,0,0,30)
TitleBar.BackgroundColor3=Configuration.Colors.TopBar
TitleBar.BorderSizePixel=0

local MainTitleLabel = Instance.new("TextLabel", TitleBar)
MainTitleLabel.Text=" TITAN IDE"
MainTitleLabel.Size=UDim2.new(1,-80,1,0)
MainTitleLabel.BackgroundTransparency=1
MainTitleLabel.TextColor3=Configuration.Colors.Text
MainTitleLabel.TextXAlignment=0
MainTitleLabel.Font=Enum.Font.GothamBold
MainTitleLabel.TextSize=12

local CloseButton = Instance.new("TextButton", TitleBar)
CloseButton.Text="X"
CloseButton.Size=UDim2.new(0,30,1,0)
CloseButton.Position=UDim2.new(1,-30,0,0)
CloseButton.BackgroundTransparency=1
CloseButton.TextColor3=Color3.new(1,0.3,0.3)
CloseButton.Font=Enum.Font.GothamBold
CloseButton.MouseButton1Click:Connect(function() ScreenGui:Destroy() end)

local EditorContainer = Instance.new("Frame", MainFrame)
EditorContainer.Size=UDim2.new(1,0,1,-65)
EditorContainer.Position=UDim2.new(0,0,0,30)
EditorContainer.BackgroundColor3=Configuration.Colors.EditorBackground

LineNumbersLabel = Instance.new("TextLabel", EditorContainer)
LineNumbersLabel.Size=UDim2.new(0,35,1,0)
LineNumbersLabel.BackgroundColor3=Configuration.Colors.TopBar
LineNumbersLabel.TextColor3=Color3.new(0.5,0.5,0.5)
LineNumbersLabel.TextYAlignment=0
LineNumbersLabel.Font=Configuration.Font
LineNumbersLabel.TextSize=14
LineNumbersLabel.Text="1"

EditorScrollFrame = Instance.new("ScrollingFrame", EditorContainer)
EditorScrollFrame.Size=UDim2.new(1,-35,1,0)
EditorScrollFrame.Position=UDim2.new(0,35,0,0)
EditorScrollFrame.BackgroundTransparency=1
EditorScrollFrame.BorderSizePixel=0
EditorScrollFrame.CanvasSize=UDim2.new(0,0,0,0)
EditorScrollFrame.AutomaticCanvasSize=Enum.AutomaticSize.XY

HighlightTextLabel = Instance.new("TextLabel", EditorScrollFrame)
HighlightTextLabel.Size=UDim2.new(1,0,1,0)
HighlightTextLabel.BackgroundTransparency=1
HighlightTextLabel.TextXAlignment=0
HighlightTextLabel.TextYAlignment=0
HighlightTextLabel.Font=Configuration.Font
HighlightTextLabel.TextSize=14
HighlightTextLabel.RichText=true
HighlightTextLabel.Text=""
HighlightTextLabel.ZIndex=2

CodeInputBox = Instance.new("TextBox", EditorScrollFrame)
CodeInputBox.Size=UDim2.new(1,0,1,0)
CodeInputBox.BackgroundTransparency=1
CodeInputBox.TextXAlignment=0
CodeInputBox.TextYAlignment=0
CodeInputBox.Font=Configuration.Font
CodeInputBox.TextSize=14
CodeInputBox.MultiLine=true
CodeInputBox.ClearTextOnFocus=false
CodeInputBox.TextTransparency=0.5
CodeInputBox.TextColor3=Configuration.Colors.Text
CodeInputBox.Text=""
CodeInputBox.ZIndex=3
CodeInputBox.AutomaticSize=Enum.AutomaticSize.XY

SuggestionFrame = Instance.new("ScrollingFrame", ScreenGui)
SuggestionFrame.Name = "SuggestionFrame"
SuggestionFrame.Size = UDim2.fromOffset(250, 200)
SuggestionFrame.BackgroundColor3 = Configuration.Colors.SuggestionBackground
SuggestionFrame.BorderColor3 = Configuration.Colors.AccentBlue
SuggestionFrame.BorderSizePixel = 1
SuggestionFrame.Visible = false
SuggestionFrame.ZIndex = 20
SuggestionFrame.CanvasSize = UDim2.new(0,0,0,0)
SuggestionFrame.AutomaticCanvasSize = Enum.AutomaticSize.Y
SuggestionFrame.ScrollBarThickness = 4
Instance.new("UIListLayout", SuggestionFrame)

local ExecuteButton = Instance.new("TextButton", MainFrame)
ExecuteButton.Text="EXECUTE"
ExecuteButton.Size=UDim2.new(0,100,0,25)
ExecuteButton.Position=UDim2.new(1,-110,1,-30)
ExecuteButton.BackgroundColor3=Configuration.Colors.AccentBlue
ExecuteButton.TextColor3=Color3.new(1,1,1)
ExecuteButton.Font=Enum.Font.GothamBold
ExecuteButton.TextSize=12
Instance.new("UICorner", ExecuteButton).CornerRadius=UDim.new(0,4)
ExecuteButton.MouseButton1Click:Connect(function()
	local functionChunk, errorMsg = loadstring(CodeInputBox.Text)
	if functionChunk then
		task.spawn(functionChunk)
	else
		warn("Titan Error: " .. tostring(errorMsg))
	end
end)

InspectorFrame = Instance.new("Frame", ScreenGui)
InspectorFrame.Name = "Inspector"
InspectorFrame.Size = UDim2.fromOffset(220, 300)
InspectorFrame.Position = UDim2.new(0.7, 0, 0.5, -150)
InspectorFrame.BackgroundColor3 = Configuration.Colors.InspectorBackground
InspectorFrame.BorderColor3 = Configuration.Colors.TopBar
InspectorFrame.BorderSizePixel = 1
InspectorFrame.Visible = false
InspectorFrame.Active = true
InspectorFrame.Draggable = true

local InspectorTitleBar = Instance.new("Frame", InspectorFrame)
InspectorTitleBar.Size=UDim2.new(1,0,0,25)
InspectorTitleBar.BackgroundColor3=Configuration.Colors.TopBar

local InspectorTitleLabel = Instance.new("TextLabel", InspectorTitleBar)
InspectorTitleLabel.Text=" INSPECTOR"
InspectorTitleLabel.Size=UDim2.new(1,-25,1,0)
InspectorTitleLabel.BackgroundTransparency=1
InspectorTitleLabel.TextColor3=Configuration.Colors.Text
InspectorTitleLabel.Font=Enum.Font.GothamBold
InspectorTitleLabel.TextSize=12

local InspectorCloseButton = Instance.new("TextButton", InspectorTitleBar)
InspectorCloseButton.Text="X"
InspectorCloseButton.Size=UDim2.new(0,25,1,0)
InspectorCloseButton.Position=UDim2.new(1,-25,0,0)
InspectorCloseButton.BackgroundTransparency=1
InspectorCloseButton.TextColor3=Color3.new(1,0.3,0.3)
InspectorCloseButton.MouseButton1Click:Connect(function() InspectorFrame.Visible=false; CleanupAugmentedReality() end)

InspectorScrollFrame = Instance.new("ScrollingFrame", InspectorFrame)
InspectorScrollFrame.Size = UDim2.new(1,0,1,-25)
InspectorScrollFrame.Position = UDim2.new(0,0,0,25)
InspectorScrollFrame.BackgroundTransparency = 1
InspectorScrollFrame.BorderSizePixel = 0
InspectorScrollFrame.ScrollBarThickness = 4
InspectorScrollFrame.AutomaticCanvasSize = Enum.AutomaticSize.Y
Instance.new("UIListLayout", InspectorScrollFrame)

PreviewWindow = Instance.new("Frame", ScreenGui)
PreviewWindow.Name = "Preview"
PreviewWindow.Size = UDim2.fromOffset(200, 240)
PreviewWindow.Position = UDim2.new(0.9, 0, 0.5, -150)
PreviewWindow.BackgroundColor3 = Color3.new(0,0,0)
PreviewWindow.BackgroundTransparency = 0.5
PreviewWindow.BorderColor3 = Configuration.Colors.AccentBlue
PreviewWindow.BorderSizePixel = 1
PreviewWindow.Visible = false
PreviewWindow.Active = true
PreviewWindow.Draggable = true

local PreviewTitleLabel = Instance.new("TextLabel", PreviewWindow)
PreviewTitleLabel.Text=" PREVIEW (DRAG)"
PreviewTitleLabel.Size=UDim2.new(1,-25,0,20)
PreviewTitleLabel.BackgroundColor3=Configuration.Colors.AccentBlue
PreviewTitleLabel.TextColor3=Color3.new(1,1,1)
PreviewTitleLabel.Font=Enum.Font.GothamBold
PreviewTitleLabel.TextSize=10

local PreviewCloseButton = Instance.new("TextButton", PreviewWindow)
PreviewCloseButton.Text="X"
PreviewCloseButton.Size=UDim2.new(0,25,0,20)
PreviewCloseButton.Position=UDim2.new(1,-25,0,0)
PreviewCloseButton.BackgroundColor3=Configuration.Colors.AccentBlue
PreviewCloseButton.TextColor3=Color3.new(1,1,1)
PreviewCloseButton.MouseButton1Click:Connect(function() PreviewWindow.Visible=false; CleanupAugmentedReality() end)

local PreviewControlFrame = Instance.new("Frame", PreviewWindow)
PreviewControlFrame.Size = UDim2.new(1,0,0,30)
PreviewControlFrame.Position = UDim2.new(0,0,1,-30)
PreviewControlFrame.BackgroundColor3 = Configuration.Colors.TopBar
PreviewControlFrame.BorderSizePixel = 0

local ScaleLabel = Instance.new("TextLabel", PreviewControlFrame)
ScaleLabel.Text="Scale:"
ScaleLabel.Size=UDim2.new(0,40,1,0)
ScaleLabel.BackgroundTransparency=1
ScaleLabel.TextColor3=Configuration.Colors.Text
ScaleLabel.Font=Configuration.Font
ScaleLabel.TextSize=12

local ScaleSlider = Instance.new("TextButton", PreviewControlFrame)
ScaleSlider.Text=""
ScaleSlider.Size=UDim2.new(0,80,0,4)
ScaleSlider.Position=UDim2.new(0,45,0.5,-2)
ScaleSlider.BackgroundColor3=Color3.new(0.3,0.3,0.3)

local ScaleFill = Instance.new("Frame", ScaleSlider)
ScaleFill.Size=UDim2.new(0.5,0,1,0)
ScaleFill.BackgroundColor3=Configuration.Colors.AccentBlue
ScaleFill.BorderSizePixel=0

local PreviewModeButton = Instance.new("TextButton", PreviewControlFrame)
PreviewModeButton.Text="Static"
PreviewModeButton.Size=UDim2.new(0,60,0,20)
PreviewModeButton.Position=UDim2.new(1,-65,0.5,-10)
PreviewModeButton.BackgroundColor3=Configuration.Colors.EditorBackground
PreviewModeButton.TextColor3=Configuration.Colors.Text
PreviewModeButton.Font=Configuration.Font
PreviewModeButton.TextSize=12
Instance.new("UICorner", PreviewModeButton).CornerRadius=UDim.new(0,4)
PreviewModeButton.MouseButton1Click:Connect(function()
	if EditorState.PreviewMode == "Static" then
		EditorState.PreviewMode = "Live"
		PreviewModeButton.Text = "Live"
		PreviewModeButton.TextColor3 = Color3.new(0,1,0)
	else
		EditorState.PreviewMode = "Static"
		PreviewModeButton.Text = "Static"
		PreviewModeButton.TextColor3 = Configuration.Colors.Text
	end
end)

local IsDraggingSlider = false
ScaleSlider.MouseButton1Down:Connect(function() IsDraggingSlider = true end)
UserInputService.InputEnded:Connect(function(input)
	if input.UserInputType == Enum.UserInputType.MouseButton1 then IsDraggingSlider = false end
end)
UserInputService.InputChanged:Connect(function(input)
	if IsDraggingSlider and input.UserInputType == Enum.UserInputType.MouseMovement then
		local relativeX = math.clamp((input.Position.X - ScaleSlider.AbsolutePosition.X) / ScaleSlider.AbsoluteSize.X, 0, 1)
		ScaleFill.Size = UDim2.new(relativeX, 0, 1, 0)
		EditorState.PreviewScale = 0.5 + (relativeX * 1.5)
	end
end)

--// 7. PREVIEW & INSPECTOR LOGIC
local function ScrollToSelection()
	local itemHeight = Configuration.ItemHeight
	local currentY = (EditorState.SelectedIndex - 1) * itemHeight
	if currentY >= SuggestionFrame.CanvasPosition.Y + SuggestionFrame.AbsoluteSize.Y then
		SuggestionFrame.CanvasPosition = Vector2.new(0, currentY - SuggestionFrame.AbsoluteSize.Y + itemHeight)
	elseif currentY < SuggestionFrame.CanvasPosition.Y then
		SuggestionFrame.CanvasPosition = Vector2.new(0, currentY)
	end
end

function CleanupAugmentedReality()
	if EditorState.AugmentedRealityLoadThread then
		coroutine.close(EditorState.AugmentedRealityLoadThread)
		EditorState.AugmentedRealityLoadThread = nil
	end
	if EditorState.AugmentedRealityClone then
		EditorState.AugmentedRealityClone:Destroy()
		EditorState.AugmentedRealityClone = nil
	end
	if EditorState.AugmentedRealityConnection then
		EditorState.AugmentedRealityConnection:Disconnect()
		EditorState.AugmentedRealityConnection = nil
	end
	EditorState.PartMappingTable = {}
end

local function MapModelHierarchy(realObj, cloneObj)
	if realObj:IsA("BasePart") and cloneObj:IsA("BasePart") then
		EditorState.PartMappingTable[realObj] = cloneObj
		cloneObj.Anchored = true
		cloneObj.CanCollide = false
		cloneObj.CanTouch = false
		cloneObj.CanQuery = false
	end
	local rChildren = realObj:GetChildren()
	local cChildren = cloneObj:GetChildren()
	for i = 1, #rChildren do
		if cChildren[i] then MapModelHierarchy(rChildren[i], cChildren[i]) end
	end
end

local function UpdateAugmentedReality(objectToPreview)
	if not objectToPreview then return end

	-- SAFETY CHECK: Prevent cloning the LocalPlayer character (anti-fling)
	local localPlayer = Players.LocalPlayer
	if localPlayer and localPlayer.Character then
		if objectToPreview == localPlayer.Character or objectToPreview:IsDescendantOf(localPlayer.Character) then
			CleanupAugmentedReality()
			return
		end
	end

	CleanupAugmentedReality()

	local wasArchivable = objectToPreview.Archivable
	objectToPreview.Archivable = true
	local success, clone = pcall(function() return objectToPreview:Clone() end)
	objectToPreview.Archivable = wasArchivable

	if not success or not clone then return end

	-- Case 1: GUI Object
	if clone:IsA("GuiObject") or clone:IsA("ScreenGui") then
		local holder = Instance.new("Part", Workspace)
		holder.Transparency=1
		holder.Anchored=true
		holder.CanCollide=false
		holder.Size=Vector3.new(1,1,1)
		local billboard = Instance.new("BillboardGui", holder)
		billboard.Size=UDim2.fromScale(5, 5)
		billboard.AlwaysOnTop=true
		if clone:IsA("ScreenGui") then
			for _,c in ipairs(clone:GetChildren()) do c.Parent=billboard end
			clone:Destroy()
		else
			clone.Parent=billboard
			clone.Position=UDim2.fromScale(0.5,0.5)
			clone.AnchorPoint=Vector2.new(0.5,0.5)
		end
		EditorState.AugmentedRealityClone = holder
		EditorState.AugmentedRealityConnection = RunService.RenderStepped:Connect(function()
			if not (PreviewWindow and PreviewWindow.Visible) then return end
			local center = PreviewWindow.AbsolutePosition + Vector2.new(PreviewWindow.AbsoluteSize.X/2, -100)
			local ray = Camera:ScreenPointToRay(center.X, center.Y)
			holder.CFrame = CFrame.new(ray.Origin + ray.Direction * (10 / EditorState.PreviewScale))
		end)

		-- Case 2: Folder or Configuration (Generic Container)
	elseif clone:IsA("Folder") or clone:IsA("Configuration") or (not clone:IsA("BasePart") and not clone:IsA("Model") and not clone:IsA("Accessory") and not clone:IsA("Tool")) then
		local tempModel = Instance.new("Model")
		tempModel.Name = "AR_Preview_Container"
		EditorState.AugmentedRealityClone = tempModel

		EditorState.AugmentedRealityLoadThread = coroutine.create(function()
			local children = objectToPreview:GetChildren()
			for i, child in ipairs(children) do
				if not child:IsA("Script") and not child:IsA("LocalScript") and not child:IsA("ModuleScript") then
					local childWasArch = child.Archivable
					child.Archivable = true
					local s, cClone = pcall(function() return child:Clone() end)
					child.Archivable = childWasArch
					if s and cClone then cClone.Parent = tempModel end
				end
				if i % 30 == 0 then task.wait() end
			end
			tempModel.Parent = Workspace
			if tempModel:IsA("Model") then
				local cf, size = tempModel:GetBoundingBox()
				local maxDim = math.max(size.X, size.Y, size.Z)
				if maxDim > 0 then tempModel:ScaleTo(5 / maxDim) end
			end
			local angle = 0
			EditorState.AugmentedRealityConnection = RunService.RenderStepped:Connect(function(deltaTime)
				if not (PreviewWindow and PreviewWindow.Visible and EditorState.AugmentedRealityClone) then return end
				local center = PreviewWindow.AbsolutePosition + Vector2.new(PreviewWindow.AbsoluteSize.X/2, 100)
				local ray = Camera:ScreenPointToRay(center.X, center.Y)
				local depth = 10 / EditorState.PreviewScale
				local targetPos = ray.Origin + ray.Direction * depth
				angle = angle + deltaTime * 0.5
				local rot = CFrame.fromEulerAnglesYXZ(0, angle, 0)
				if EditorState.AugmentedRealityClone:IsA("Model") then EditorState.AugmentedRealityClone:PivotTo(CFrame.new(targetPos) * rot) end
			end)
		end)
		coroutine.resume(EditorState.AugmentedRealityLoadThread)

		-- Case 3: 3D Object (Part, Model, Tool)
	elseif clone:IsA("BasePart") or clone:IsA("Model") or clone:IsA("Tool") or clone:IsA("Accessory") then
		clone.Parent = Workspace
		EditorState.AugmentedRealityClone = clone
		EditorState.PartMappingTable = {}
		MapModelHierarchy(objectToPreview, clone)
		for _, d in ipairs(clone:GetDescendants()) do
			if d:IsA("LuaSourceContainer") then d:Destroy() end
		end
		if clone:IsA("Model") then
			local cf, size = clone:GetBoundingBox()
			local maxDim = math.max(size.X, size.Y, size.Z)
			if maxDim > 0 then clone:ScaleTo(5 / maxDim) end
		end
		local angle = 0
		EditorState.AugmentedRealityConnection = RunService.RenderStepped:Connect(function(deltaTime)
			if not (PreviewWindow and PreviewWindow.Visible and EditorState.AugmentedRealityClone) then return end
			local center = PreviewWindow.AbsolutePosition + Vector2.new(PreviewWindow.AbsoluteSize.X/2, 100)
			local ray = Camera:ScreenPointToRay(center.X, center.Y)
			local depth = 10 / EditorState.PreviewScale
			local targetPos = ray.Origin + ray.Direction * depth

			-- REVERTED LOGIC FOR LIVE PREVIEW
			if EditorState.PreviewMode == "Live" then
				local realPivot = (objectToPreview:IsA("Model") and objectToPreview:GetPivot()) or (objectToPreview:IsA("BasePart") and objectToPreview.CFrame) or CFrame.new()
				local offset = CFrame.new(targetPos) * realPivot:Inverse()
				for realPart, fakePart in pairs(EditorState.PartMappingTable) do
					if realPart and realPart.Parent then
						fakePart.CFrame = offset * realPart.CFrame
						fakePart.Transparency = realPart.Transparency
						fakePart.Color = realPart.Color
					end
				end
			else
				angle = angle + deltaTime * 0.5
				local rot = CFrame.fromEulerAnglesYXZ(0, angle, 0)
				if EditorState.AugmentedRealityClone:IsA("Model") then
					EditorState.AugmentedRealityClone:PivotTo(CFrame.new(targetPos) * rot)
				elseif EditorState.AugmentedRealityClone:IsA("BasePart") then
					EditorState.AugmentedRealityClone.CFrame = CFrame.new(targetPos) * rot
				end
			end
		end)
	else
		clone:Destroy()
	end
end

local function UpdateObjectInspector(overrideObject) 
	local selectedObject = overrideObject
	if not selectedObject and not EditorState.IsArgumentMode then
		local item = EditorState.ScanResults[EditorState.SelectedIndex]
		if item and EditorState.CurrentParentPath and EditorState.CurrentParentPath ~= "" then
			local memberName = item.Name
			local fullPath
			if memberName:match("^[%a_][%w_]*$") then
				fullPath = EditorState.CurrentParentPath .. EditorState.CurrentSeparator .. memberName
			else
				fullPath = EditorState.CurrentParentPath .. '["' .. memberName .. '"]'
			end
			selectedObject = IntellisenseSystem.ResolveLive(fullPath)
		elseif item and not EditorState.CurrentParentPath then
			selectedObject = IntellisenseSystem.ResolveLive(item.Name)
		end
	end

	if selectedObject and typeof(selectedObject) == "Instance" then 
		if EditorState.LastInspectedObject == selectedObject and not overrideObject then return end
		EditorState.LastInspectedObject = selectedObject
		InspectorFrame.Visible = true
		PreviewWindow.Visible = true

		local title = InspectorFrame:FindFirstChild("Frame") and InspectorFrame.Frame:FindFirstChild("TextLabel")
		if title then title.Text = " " .. selectedObject.Name .. " ["..selectedObject.ClassName.."]" end

		for _,v in pairs(InspectorScrollFrame:GetChildren()) do if v:IsA("Frame") then v:Destroy() end end

		local props = IntellisenseSystem.GetAllProperties(selectedObject.ClassName)
		for _, prop in ipairs(props) do 
			local success, val = pcall(function() return selectedObject[prop] end)
			if success and val ~= nil then 
				local row = Instance.new("Frame", InspectorScrollFrame)
				row.Size=UDim2.new(1,0,0,20)
				row.BackgroundTransparency=1

				local nameLabel = Instance.new("TextLabel", row)
				nameLabel.Size=UDim2.new(0.4,0,1,0)
				nameLabel.BackgroundTransparency=1
				nameLabel.Text=" "..prop
				nameLabel.TextColor3=Configuration.Colors.AccentBlue
				nameLabel.TextXAlignment=0
				nameLabel.Font=Configuration.Font
				nameLabel.TextSize=12

				local valueLabel = Instance.new("TextLabel", row)
				valueLabel.Size=UDim2.new(0.6,-5,1,0)
				valueLabel.Position=UDim2.new(0.4,0,0,0)
				valueLabel.BackgroundTransparency=1
				valueLabel.Text=tostring(val):gsub("\n", " ")
				valueLabel.TextColor3=Configuration.Colors.Text
				valueLabel.TextXAlignment=2
				valueLabel.Font=Configuration.Font
				valueLabel.TextSize=12
				valueLabel.TextTruncate=Enum.TextTruncate.AtEnd 
			end 
		end
		UpdateAugmentedReality(selectedObject) 
	else 
		if not overrideObject then 
			EditorState.LastInspectedObject = nil
			InspectorFrame.Visible = false
			PreviewWindow.Visible = false
			CleanupAugmentedReality() 
		end
	end 
end

local function UpdateSuggestionVisuals()
	if not SuggestionFrame then return end
	for i, btn in ipairs(SuggestionFrame:GetChildren()) do
		if btn:IsA("TextButton") then
			btn.BackgroundColor3 = (btn.LayoutOrder == EditorState.SelectedIndex) and Configuration.Colors.AccentBlue or Configuration.Colors.SuggestionBackground
		end
	end
	ScrollToSelection()
	UpdateObjectInspector()
end

local function AcceptSuggestion()
	if not EditorState.IsMenuActive or not EditorState.ScanResults[EditorState.SelectedIndex] then return end
	EditorState.IgnoreNextUpdate = true

	local item = EditorState.ScanResults[EditorState.SelectedIndex]
	local fullText = CodeInputBox.Text
	local cursor = CodeInputBox.CursorPosition
	local insertText = item.Name

	if item.Type == "Signature" then return end
	local startPos = cursor

	if EditorState.IsArgumentMode then
		local quote = EditorState.ArgumentQuote or (insertText:match(" ") and '"' or '')
		insertText = quote .. insertText .. quote
		while startPos > 0 do
			local char = fullText:sub(startPos-1, startPos-1)
			if char == '(' or char == ',' then break end
			startPos = startPos -1
		end
	else
		while startPos > 0 do
			local char = fullText:sub(startPos-1, startPos-1)
			if not char:match("[%w_]") then break end
			startPos = startPos - 1
		end

		local needsBrackets = not insertText:match("^[_%a][_%w]*$")
		if needsBrackets then
			local preChar = fullText:sub(startPos-1, startPos-1)
			if preChar == "." then startPos = startPos - 1 end
			insertText = '["' .. insertText .. '"]'
		end
		if item.Type == "Method" or item.Type == "Function" then insertText = insertText.."()" end
	end

	local before = fullText:sub(1, startPos-1)
	local after = fullText:sub(cursor)
	CodeInputBox.Text = before .. insertText .. after

	local newPos = #before + #insertText + 1
	if (item.Type == "Method" or item.Type == "Function") and not EditorState.IsArgumentMode then newPos = newPos - 1 end

	CodeInputBox.CursorPosition = newPos
	SuggestionFrame.Visible = false
	EditorState.IsMenuActive = false
	EditorState.IgnoreNextUpdate = false

	task.defer(function()
		if CodeInputBox and CodeInputBox.Parent then CodeInputBox:CaptureFocus() end
	end)
end

--// 8. INPUT HANDLING
UserInputService.InputBegan:Connect(function(input)
	if not (CodeInputBox and CodeInputBox.Parent and CodeInputBox:IsFocused()) then return end

	if input.KeyCode == Enum.KeyCode.Quote then
		local c = CodeInputBox.CursorPosition
		if CodeInputBox.Text:sub(c, c) == '"' then
			CodeInputBox.TextEditable = false
			task.defer(function()
				CodeInputBox.CursorPosition = c
				CodeInputBox.TextEditable = true
				CodeInputBox:CaptureFocus()
			end)
		else
			CodeInputBox.TextEditable = false
			task.defer(function()
				CodeInputBox.Text = CodeInputBox.Text:sub(1, c - 1) .. '""' .. CodeInputBox.Text:sub(c)
				CodeInputBox.CursorPosition = c
				CodeInputBox.TextEditable = true
				CodeInputBox:CaptureFocus()
			end)
		end
	end

	if EditorState.IsMenuActive then
		local key = input.KeyCode
		local shouldUpdate = false
		if key == Enum.KeyCode.Up then
			EditorState.SelectedIndex = math.max(1, EditorState.SelectedIndex - 1)
			shouldUpdate=true
		elseif key == Enum.KeyCode.Down then
			EditorState.SelectedIndex = math.min(#EditorState.ScanResults, EditorState.SelectedIndex + 1)
			shouldUpdate=true
		elseif key == Enum.KeyCode.Tab or key == Enum.KeyCode.Return then
			CodeInputBox.TextEditable = false
			AcceptSuggestion()
			RunService.RenderStepped:Wait()
			CodeInputBox.TextEditable = true
			CodeInputBox:CaptureFocus()
		end
		if shouldUpdate then
			CodeInputBox.TextEditable = false
			EditorState.IsNavigating = true
			UpdateSuggestionVisuals()
			RunService.RenderStepped:Wait()
			CodeInputBox.TextEditable = true
			CodeInputBox:CaptureFocus()
			EditorState.IsNavigating = false
		end
	end
end)

local function PositionSuggestWindow(preCursorText)
	local linesBefore = select(2, preCursorText:gsub("\n", "\n"))
	local lastLine = preCursorText:match("[^\n]*$") or ""
	local textSize = TextService:GetTextSize(lastLine, 14, Configuration.Font, Vector2.new(9999,9999))
	local absolutePos = MainFrame.AbsolutePosition
	local x = absolutePos.X + 35 + textSize.X - EditorScrollFrame.CanvasPosition.X + 10
	local y = absolutePos.Y + 30 + (linesBefore+1)*15 - EditorScrollFrame.CanvasPosition.Y + 5
	SuggestionFrame.Position = UDim2.fromOffset(x,y)
end

local function UpdateIntellisense() 
	if not (CodeInputBox and SuggestionFrame) then return end
	if EditorState.IgnoreNextUpdate or EditorState.IsNavigating then return end

	local text = CodeInputBox.Text
	if text:find("\t") then
		local c = CodeInputBox.CursorPosition
		CodeInputBox.Text = text:gsub("\t", "  ")
		CodeInputBox.CursorPosition = c + 1
		return
	end

	HighlightTextLabel.Text = SyntaxSystem.Highlight(text)
	local _,lineCount = text:gsub("\n","\n")
	local linesString=""
	for i=1,lineCount+1 do linesString=linesString..i.."\n" end
	LineNumbersLabel.Text=linesString

	local cursor = CodeInputBox.CursorPosition
	if cursor < 1 then
		SuggestionFrame.Visible=false
		EditorState.IsMenuActive=false
		UpdateObjectInspector(nil)
		return
	end

	local textBeforeCursor = text:sub(1, cursor-1)

	local context = IntellisenseSystem.GetPathContext(textBeforeCursor)
	local parentPath, separator, query = context:match("^(.-)([:%.])([%w_]*)$")

	if not parentPath and not separator then 
		parentPath = nil
		EditorState.CurrentParentPath = nil 
	elseif separator and (query == nil or query == "") then
		parentPath = context:sub(1, #context - 1)
		EditorState.CurrentParentPath = parentPath
		EditorState.CurrentSeparator = separator
	else
		EditorState.CurrentParentPath = parentPath
		EditorState.CurrentSeparator = separator or "."
	end

	EditorState.ParentObject = parentPath and IntellisenseSystem.ResolveLive(parentPath) or nil
	local results, q = IntellisenseSystem.Scan(textBeforeCursor, text)

	local sameList = (#results == #EditorState.ScanResults)
	if sameList then
		for i=1, #results do
			if results[i].Name ~= EditorState.ScanResults[i].Name then sameList=false break end
		end
	end

	if sameList then
		PositionSuggestWindow(textBeforeCursor)
		if not SuggestionFrame.Visible and #results > 0 then SuggestionFrame.Visible=true end
		UpdateObjectInspector()
		return
	end

	if #results == 0 then
		SuggestionFrame.Visible=false
		EditorState.IsMenuActive=false
		UpdateObjectInspector()
		return
	end

	local oldName = EditorState.ScanResults[EditorState.SelectedIndex] and EditorState.ScanResults[EditorState.SelectedIndex].Name
	local newIndex = 1
	if oldName then
		for i, item in ipairs(results) do
			if item.Name == oldName then newIndex = i break end
		end
	end

	EditorState.ScanResults = results
	EditorState.CurrentQuery = q
	EditorState.SelectedIndex = newIndex
	EditorState.IsMenuActive = true

	for _,v in pairs(SuggestionFrame:GetChildren()) do if v:IsA("TextButton") then v:Destroy() end end

	for i=1, #results do
		local data = results[i]
		local button = Instance.new("TextButton", SuggestionFrame)
		button.Size=UDim2.new(1,0,0,Configuration.ItemHeight)
		button.BackgroundColor3=(i==EditorState.SelectedIndex) and Configuration.Colors.AccentBlue or Configuration.Colors.SuggestionBackground
		button.TextColor3=Configuration.Colors.Text
		button.TextXAlignment=0
		button.Font=Configuration.Font
		button.TextSize=13
		button.ZIndex=21
		button.LayoutOrder=i

		local txt = "  " .. data.Name
		if data.Extra ~= "" and data.Extra ~= "Creatable" then txt = txt .. " ["..data.Extra.."]" end
		button.Text = txt

		local indicator = Instance.new("Frame", button)
		indicator.Size=UDim2.new(0,3,1,0)
		indicator.BorderSizePixel=0
		indicator.ZIndex=22

		if data.Type=="Child" or data.Type=="Instance" then indicator.BackgroundColor3=Color3.fromRGB(139, 233, 253)
		elseif data.Type=="Property" then indicator.BackgroundColor3=Color3.fromRGB(80, 250, 123)
		elseif data.Type=="Method" or data.Type=="Function" or data.Type=="Class" or data.Type=="Library" then indicator.BackgroundColor3=Color3.fromRGB(189, 147, 249)
		elseif data.Type=="Event" then indicator.BackgroundColor3=Color3.fromRGB(255, 121, 198)
		elseif data.Type=="Service" then indicator.BackgroundColor3=Color3.fromRGB(255, 184, 108)
		elseif data.Type=="EnumItem" then indicator.BackgroundColor3=Color3.fromRGB(241, 250, 140)
		elseif data.Type=="Signature" then indicator.BackgroundColor3=Color3.fromRGB(150,150,150)
		else indicator.BackgroundColor3=Color3.fromRGB(98, 114, 164) end

		button.MouseButton1Click:Connect(function()
			EditorState.SelectedIndex = i
			CodeInputBox:CaptureFocus()
			CodeInputBox.CursorPosition = cursor
			AcceptSuggestion()
		end)
	end

	PositionSuggestWindow(textBeforeCursor)
	SuggestionFrame.Size = UDim2.fromOffset(250, math.min(#results, 8) * Configuration.ItemHeight)
	SuggestionFrame.Visible = true
	ScrollToSelection()
	UpdateObjectInspector() 
end

task.spawn(function()
	while task.wait(0.3) do
		if EditorState.IsMenuActive and not EditorState.IsNavigating then pcall(UpdateIntellisense) end
	end
end)

CodeInputBox:GetPropertyChangedSignal("Text"):Connect(UpdateIntellisense)
CodeInputBox:GetPropertyChangedSignal("CursorPosition"):Connect(UpdateIntellisense)
task.spawn(UpdateIntellisense)

