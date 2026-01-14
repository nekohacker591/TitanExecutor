--// 0. CLEANUP
if _G.Titan_Connection then 
    pcall(function() _G.Titan_Connection:Disconnect() end)
    _G.Titan_Connection = nil
end

--// 1. SERVICES
local CoreGui = game:GetService("CoreGui")
local UserInputService = game:GetService("UserInputService")
local TextService = game:GetService("TextService")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")
local Players = game:GetService("Players")
local Camera = Workspace.CurrentCamera

if not RunService:IsRunning() then return end

if CoreGui:FindFirstChild("Titan_V44") then CoreGui.Titan_V44:Destroy() end

--// 2. FORWARD DECLARATIONS
local Screen, Main, Input, Suggest, Inspector, PrevWin
local InsScroll, PScroll, High, Lines, Scroll
local State = {
    Results={}, Query="", Index=1, Active=false, IgnoreUpdate=false, 
    ParentObj=nil, ARClone=nil, ARConn=nil, LastInspected=nil, 
    Scale=1, Mode="Static", PartMap={}, ArgMode=false, ArgQuote="",
    Navigating=false, SymbolTable = {}
}

--// 3. CONFIG
local Config = {
    Colors = {
        Main    = Color3.fromRGB(30, 30, 30),
        Editor  = Color3.fromRGB(20, 20, 20),
        Bar     = Color3.fromRGB(45, 45, 45),
        Text    = Color3.fromRGB(240, 240, 240),
        Accent  = Color3.fromRGB(0, 120, 215),
        Suggest = Color3.fromRGB(40, 40, 40),
        Inspector = Color3.fromRGB(25, 25, 25),
        
        Syntax = {
            Kw = "#FF79C6", Num = "#BD93F9", Str = "#F1FA8C", 
            Com = "#6272A4", Blt = "#8BE9FD", Mtd = "#50FA7B",
            Var = "#FFFFFF" -- NEW: Color for local variables
        }
    },
    Font = Enum.Font.Code,
    ItemHeight = 20
}

--// 4. SYNTAX ENGINE
local Syntax = {}
function Syntax.Highlight(text)
    text = text:gsub("&", "&amp;"):gsub("<", "&lt;"):gsub(">", "&gt;")
    local rep = {}; local id = 0
    local function mask(t, c) id=id+1; local k="\0"..id.."\0"; rep[k]=string.format('<font color="%s">%s</font>',c,t); return k end

    text = text:gsub("(%-%-.+)", function(m) return mask(m, Config.Colors.Syntax.Com) end)
    text = text:gsub('(".-")', function(m) return mask(m, Config.Colors.Syntax.Str) end)
    text = text:gsub("('.-')", function(m) return mask(m, Config.Colors.Syntax.Str) end)

    local kws = {["local"]=1,["function"]=1,["if"]=1,["then"]=1,["else"]=1,["end"]=1,["return"]=1,["while"]=1,["do"]=1,["for"]=1,["in"]=1,["true"]=1,["false"]=1,["nil"]=1}
    local blts = {["game"]=1,["workspace"]=1,["script"]=1,["task"]=1,["math"]=1,["table"]=1,["string"]=1,["coroutine"]=1,["print"]=1,["warn"]=1,["error"]=1,["wait"]=1,["Enum"]=1,["Instance"]=1,["CFrame"]=1,["Vector3"]=1,["Vector2"]=1,["Color3"]=1,["UDim2"]=1,["UDim"]=1,["Ray"]=1,["TweenInfo"]=1,["tick"]=1,["pcall"]=1,["typeof"]=1,["require"]=1}

    text = text:gsub("(%a[%w_]*)", function(w)
        if kws[w] then return mask(w, Config.Colors.Syntax.Kw) end
        if blts[w] then return mask(w, Config.Colors.Syntax.Blt) end
        return w
    end)
    
    --// NEW: Pass for coloring local variable declarations
    text = text:gsub("local%s+([%a_][%w_]*)", function(full, var) return full:gsub(var, mask(var, Config.Colors.Syntax.Var)) end)

    return text:gsub("%z%d+%z", function(k) return rep[k] or k end)
end

--// 5. INTELLISENSE ENGINE (FINAL JUDGMENT EDITION)
local Intel = {}

Intel.Libs = {task=true, math=true, table=true, string=true, coroutine=true, debug=true, os=true, utf8=true, bit32=true}
Intel.GlobalFuncs = {["assert"]=true, ["collectgarbage"]=true, ["error"]=true, ["getfenv"]=true, ["getmetatable"]=true, ["ipairs"]=true, ["loadstring"]=true, ["next"]=true, ["pairs"]=true, ["pcall"]=true, ["print"]=true, ["rawequal"]=true, ["rawget"]=true, ["rawset"]=true, ["require"]=true, ["select"]=true, ["setfenv"]=true, ["setmetatable"]=true, ["tonumber"]=true, ["tostring"]=true, ["type"]=true, ["unpack"]=true, ["xpcall"]=true, ["_G"]=true, ["_VERSION"]=true, ["spawn"]=true, ["delay"]=true, ["wait"]=true, ["tick"]=true, ["time"]=true, ["typeof"]=true, ["settings"]=true, ["UserSettings"]=true, ["elapsedTime"]=true, ["stats"]=true, ["plugin"]=true, ["warn"]=true}
Intel.Constructors = {"Vector3", "Vector2", "CFrame", "Color3", "UDim2", "UDim", "Ray", "Rect", "Region3", "Region3int16", "NumberRange", "NumberSequence", "ColorSequence", "ColorSequenceKeypoint", "PhysicalProperties", "RaycastParams", "OverlapParams", "TweenInfo", "Axes", "Faces", "Enum", "_G", "shared", "BrickColor", "Vector3int16", "PathWaypoint"}
Intel.Services = {"Players","ReplicatedStorage","ServerScriptService","ServerStorage","ReplicatedFirst","Lighting","SoundService","TweenService","RunService","UserInputService","ContextActionService","MarketplaceService","TeleportService","HttpService","StarterGui","StarterPack","StarterPlayer","Teams","Chat","TextService","CollectionService","ContentProvider","Debris","GamePassService","LogService","PhysicsService","ScriptContext","TestService", "BadgeService", "InsertService", "PathfindingService"}
Intel.CreatableInstances = {"Part", "Model", "Folder", "Script", "LocalScript", "ModuleScript", "ScreenGui", "Frame", "TextLabel", "TextButton", "TextBox", "ImageLabel", "ImageButton", "ScrollingFrame", "UICorner", "UIListLayout", "UIGridLayout", "UIPadding", "UIAspectRatioConstraint", "UIScale", "UIStroke", "Humanoid", "Animation", "Sound", "Attachment", "Configuration", "RemoteEvent", "RemoteFunction", "BindableEvent", "BindableFunction", "BoolValue", "StringValue", "IntValue", "NumberValue", "ObjectValue", "Vector3Value", "CFrameValue", "Color3Value", "BrickColorValue", "Tool", "HopperBin", "WeldConstraint", "NoCollisionConstraint", "Motor6D", "AlignPosition", "AlignOrientation", "Beam", "BillboardGui", "BodyGyro", "BodyPosition", "BodyVelocity", "Camera", "ClickDetector", "ColorCorrectionEffect", "CylinderHandleAdornment", "Decal", "Explosion", "Fire", "ForceField", "HingeConstraint", "Light", "ParticleEmitter", "ProximityPrompt", "SelectionBox", "Smoke", "Sparkles", "SpotLight", "SurfaceGui", "SurfaceLight", "Texture", "Trail", "Tween", "VelocityMotor", "VideoFrame"}
Intel.ClassMembers = {
    DataModel = { Inherits = "Instance", Properties = {"Workspace", "Players", "Lighting", "ReplicatedFirst", "ReplicatedStorage", "ServerScriptService", "ServerStorage", "StarterGui", "StarterPack", "StarterPlayer", "Teams", "SoundService"} },
    Workspace = { Inherits = "Model", Properties = {"CurrentCamera", "Gravity"} },
    task = { Methods = {"wait", "spawn", "defer", "delay", "cancel"} },
    math = { Properties = {"pi", "huge"}, Methods = {"abs", "acos", "asin", "atan", "ceil", "cos", "deg", "exp", "floor", "fmod", "rad", "log", "log10", "max", "min", "pow", "sin", "sqrt", "tan", "clamp", "sign", "round"} },
    string = { Methods = {"byte", "char", "find", "format", "gmatch", "gsub", "len", "lower", "match", "rep", "reverse", "sub", "upper", "split"} },
    table = { Methods = {"insert", "remove", "sort", "concat", "create", "find", "getn", "maxn", "pack", "unpack", "move", "clear"} },
    coroutine = { Properties = {"running", "status"}, Methods = {"create", "resume", "yield", "wrap", "close", "isyieldable"} },
    os = { Methods = {"clock", "date", "difftime", "time"} },
    debug = { Methods = {"traceback", "info", "getmetatable", "getupvalue", "setupvalue"} },
    CFrameConstructor = { Properties = {"identity"}, Methods = {"new", "Angles", "fromEulerAnglesXYZ", "fromEulerAnglesYXZ", "fromAxisAngle"} },
    CFrame = { Properties = {"Position", "X", "Y", "Z", "LookVector", "RightVector", "UpVector"}, Methods = {"Lerp", "ToObjectSpace", "ToWorldSpace", "Inverse", "PointToWorldSpace", "VectorToWorldSpace"} },
    Vector3Constructor = { Properties = {"xAxis", "yAxis", "zAxis", "zero", "one"}, Methods = {"new", "fromAxis", "fromNormalId"} },
    Vector3 = { Properties = {"X", "Y", "Z", "Unit", "Magnitude"}, Methods = {"Lerp", "Dot", "Cross", "isClose"} },
    Color3Constructor = { Methods = {"new", "fromRGB", "fromHSV", "fromHex"} },
    Color3 = { Properties = {"r", "g", "b"}, Methods = {"Lerp", "ToHSV"} },
    UDim2Constructor = { Methods = {"new"} },
    UDim2 = { Properties = {"ScaleX", "ScaleY", "OffsetX", "OffsetY"}, Methods = {"Lerp"} },
    RBXScriptSignal = { Methods = {"Connect", "Wait", "Once"} },
    InstanceConstructor = { Methods = {"new", "IsA", "FindFirstChildWhichIsA", "WaitForChildWhichIsA"} },
    Instance = { Properties = {"Name", "Parent", "ClassName", "Archivable", "RobloxLocked"}, Methods = {"GetService", "FindFirstChild", "WaitForChild", "GetChildren", "GetDescendants", "IsA", "Clone", "Destroy", "ClearAllChildren", "FindFirstAncestor", "GetAttribute", "SetAttribute"}, Events = {"ChildAdded", "ChildRemoved", "DescendantAdded", "DescendantRemoving", "AttributeChanged", "AncestryChanged"} },
    BasePart = { Inherits = "Instance", Properties = {"Anchored", "CFrame", "Position", "Size", "Color", "Material", "Transparency", "CanCollide", "Locked", "Velocity", "Mass", "CanTouch", "CanQuery", "CastShadow"}, Methods = {"GetTouchingParts", "CanSetNetworkOwnership", "SetNetworkOwner"}, Events = {"Touched", "TouchEnded"} },
    Part = { Inherits = "BasePart", Properties = {"Shape"} },
    Model = { Inherits = "Instance", Properties = {"PrimaryPart"}, Methods = {"GetBoundingBox", "MoveTo", "ScaleTo", "GetPivot", "PivotTo"} },
    Players = { Inherits = "Instance", Properties = {"LocalPlayer", "MaxPlayers", "NumPlayers"}, Methods = {"GetPlayerByUserId", "GetPlayers", "PlayerFromCharacter"}, Events = {"PlayerAdded", "PlayerRemoving"} },
    Player = { Inherits = "Instance", Properties = {"Character", "UserId", "DisplayName", "AccountAge"}, Events = {"Chatted", "CharacterAdded", "CharacterRemoving"} },
    Humanoid = { Inherits = "Instance", Properties = {"Health", "MaxHealth", "WalkSpeed", "JumpPower", "MoveDirection", "Sit"}, Methods = {"TakeDamage", "MoveTo", "ApplyDescription", "GetState"}, Events = {"Died", "HealthChanged", "Running", "StateChanged"} },
    Tool = { Inherits = "Instance", Properties = {"Enabled", "RequiresHandle"}, Events = {"Activated", "Deactivated", "Equipped", "Unequipped"} },
    RemoteEvent = { Inherits = "Instance", Methods = {"FireServer", "FireClient", "FireAllClients"}, Events = {"OnServerEvent", "OnClientEvent"} },
    TweenService = { Inherits = "Instance", Methods = {"Create"} },
    RunService = { Inherits = "Instance", Methods = {"IsStudio", "IsServer", "IsClient"}, Events = {"RenderStepped", "Heartbeat", "Stepped"} },
    UserInputService = { Inherits = "Instance", Properties = {"MouseBehavior", "MouseIconEnabled"}, Methods = {"GetMouseLocation", "IsKeyDown"}, Events = {"InputBegan", "InputEnded", "InputChanged", "TouchTap"} },
    Sound = { Inherits = "Instance", Properties = {"SoundId", "Volume", "Pitch", "TimePosition", "IsPlaying", "Looped"}, Methods = {"Play", "Pause", "Stop"}, Events = {"Ended", "Paused", "Played", "Resumed"} },
    ParticleEmitter = { Inherits = "Instance", Properties = {"Enabled", "Rate", "Lifetime", "Speed", "SpreadAngle", "Color", "Size"}, Methods = {"Emit"} },
    GuiBase2d = { Inherits = "Instance", Properties = {"AbsolutePosition", "AbsoluteSize", "AbsoluteRotation"} },
    GuiObject = { Inherits = "GuiBase2d", Properties = {"Size", "Position", "AnchorPoint", "BackgroundColor3", "Visible", "ZIndex", "Rotation"} },
    Frame = { Inherits = "GuiObject" },
    TextLabel = { Inherits = "GuiObject", Properties = {"Text", "TextColor3", "Font", "TextSize", "TextWrapped", "TextXAlignment", "TextYAlignment"} },
    TextButton = { Inherits = "TextLabel", Events = {"MouseButton1Click", "MouseButton1Down", "MouseButton1Up", "Activated"} }
}

function Intel.GetPathContext(text)
    local len = #text; local i = len; local depth = 0; local inQuote = nil
    while i > 0 do
        local c = text:sub(i, i)
        if inQuote then if c == inQuote and text:sub(i-1, i-1) ~= "\\" then inQuote = nil end
        elseif c == '"' or c == "'" then inQuote = c
        elseif c == "]" or c == ")" or c == "}" then depth = depth + 1
        elseif c == "[" or c == "(" or c == "{" then depth = depth - 1
        elseif depth == 0 and c:match("[^%w_%.%:]") then return text:sub(i+1) end
        i = i - 1
    end
    return text
end

function Intel.TokenizePath(path)
    local tokens = {}; local i = 1; local len = #path
    while i <= len do
        local c = path:sub(i,i)
        if c == "." or c == ":" then i = i + 1
        elseif c == "[" then local endBracket = path:find("]", i, true); if not endBracket then break end; local content = path:sub(i+1, endBracket-1); local inner = content:match("^[\"'](.+)[\"']$"); table.insert(tokens, inner or content); i = endBracket + 1
        else local nextSep = path:find("[%.%:%[]", i); local segment = nextSep and path:sub(i, nextSep-1) or path:sub(i); table.insert(tokens, segment); i = nextSep or (len + 1) end
    end
    return tokens
end

function Intel.ParseLocals(fullText)
    local locals = {}
    for name in fullText:gmatch("function%s+([%a_][%w_.:]*)") do name = name:match("([^.:]+)$") or name; locals[name] = { Type = "Function", ClassName = "Function" } end
    for name, expr in fullText:gmatch("local%s+([%a_][%w_]*)%s*=%s*(.+)") do
        expr = expr:match("^%s*(.-)%s*$"); local info = { Type = "Variable", ClassName = "any" }
        --// NEW: DYNAMIC TYPE INFERENCE FOR METHOD RETURNS
        local path, method = expr:match("^(.-)[:%.]([%w_]+)%s*%([^)]*)$")
        if path and method then
            local parentObj = Intel.Resolve(path, true)
            if typeof(parentObj) == "Instance" then info.Type = "Instance"; info.ClassName = parentObj.ClassName
            elseif type(parentObj) == "table" and parentObj.ClassName then info.Type = "Instance"; info.ClassName = parentObj.ClassName end
        else
            local obj = Intel.Resolve(expr, true)
            if type(obj) == "userdata" then info.Type = "Instance"; info.ClassName = obj.ClassName
            elseif type(obj) == "string" and (Intel.Libs[obj] or Intel.ClassMembers[obj.."Constructor"]) then info.Type = "Library"; info.ClassName = obj
            elseif expr:match('^".-"$') or expr:match("^'.'-$") then info.Type = "String"; info.ClassName = "string"
            elseif tonumber(expr) then info.Type = "Number"; info.ClassName = "number"
            elseif expr:match('^function%s*%(') then info.Type = "Function"; info.ClassName = "Function"
            elseif expr:match('^Instance%.new%s*%("%s*([%w_]+)%s*"%)') then info.Type = "Instance"; info.ClassName = expr:match('^Instance%.new%s*%("%s*([%w_]+)%s*"%)') end
        end
        locals[name] = info
    end
    return locals
end

function Intel.Resolve(path, isParsing)
    if not path or path == "" then return nil end
    local tokens = Intel.TokenizePath(path); if #tokens == 0 then return nil end
    local start = tokens[1]
    
    if not isParsing and State.SymbolTable[start] then
        local info = State.SymbolTable[start]; if #tokens == 1 then return info end
        local parentObj = Intel.Resolve(table.concat(tokens, ".", 1, #tokens-1))
        if parentObj and typeof(parentObj) == "Instance" then
            local child = parentObj:FindFirstChild(tokens[#tokens])
            if child then return child end
        end
        return info
    end

    local root = nil;
    if start == "game" then root = game
    elseif start == "workspace" then root = workspace
    elseif start == "script" then root = script
    elseif start == "Enum" then root = Enum
    elseif Intel.Libs[start] then return start
    elseif start == "Instance" then return Instance
    elseif Intel.ClassMembers[start.."Constructor"] then return start
    else pcall(function() root = _G[start] or game:GetService(start) end) end
    if not root then return nil end
    
    local o = root
    for k = 2, #tokens do
        local key = tokens[k]; if key ~= "" then
            local success, new_o = pcall(function() return o[key] end)
            if not success and typeof(o) == "Instance" then o = o:FindFirstChild(key) else o = new_o end
            if not o then return nil end
        end
    end
    return o
end

function Intel.Scan(txt, fullText)
    State.ArgMode = false; State.ArgQuote = ""; State.SymbolTable = Intel.ParseLocals(fullText)
    local funcName, quote, argQuery = txt:match("[:%.]([%w_]+)%s*%([%s*]*([\"'])([^\"']*)$")
    if not funcName then funcName, quote, argQuery = txt:match("([%w_]+)%s*%([%s*]*([\"'])([^\"']*)$") end
    if funcName and quote then
        local res = {}; funcName = funcName:lower()
        if funcName == "getservice" or funcName == "findfirstchild" or funcName == "waitforchild" then
            local target, list
            if funcName == "getservice" then target = "Service"; list = Intel.Services
            else
                target = "Child"; local methodStart = txt:find(":"..funcName, 1, true) or txt:find("%."..funcName, 1, true)
                if methodStart then
                    local objPath = Intel.GetPathContext(txt:sub(1, methodStart-1))
                    if objPath then local obj = Intel.Resolve(objPath); if obj then pcall(function() list = obj:GetChildren() end) end end
                end
            end
            if list then for _, item in ipairs(list) do local name = (type(item) == "string") and item or item.Name; if name:lower():find(argQuery:lower(), 1, true) then table.insert(res, {N=name, T=target, W=1, X=(type(item)=="string") and "Service" or item.ClassName}) end end end
        elseif funcName == "new" and txt:match("Instance%.new%s*%($") then for _, className in ipairs(Intel.CreatableInstances) do if className:lower():find(argQuery:lower(), 1, true) then table.insert(res, {N=className, T="Class", W=1, X="Creatable"}) end end end
        table.sort(res, function(a,b) return a.N < b.N end)
        if #res > 0 then State.ArgMode = true; State.ArgQuote = quote; return res, argQuery, nil end
    end
    local context = Intel.GetPathContext(txt) or ""; local parentPath, separator, query = context:match("^(.-)([:%.])([%w_]*)$")
    if not parentPath then query = context; parentPath = ""; separator = "" end
    if parentPath == "" and query == "" and not txt:match("=%s*$") then return {}, "", nil end
    local res = {}; local seen = {}
    local function add(n, t, extra, w) if not seen[n] and n:lower():find(query:lower(), 1, true) then table.insert(res, {N=n, T=t, X=extra or "", W=w or 2}); seen[n]=true end end
    local parentObj = nil 
    if parentPath == "" then
        for name, info in pairs(State.SymbolTable) do add(name, info.Type, info.ClassName, 2) end
        local roots = {"game","workspace","script", "Enum", "Instance"}; for k,_ in pairs(Intel.Libs) do table.insert(roots, k) end; for k,_ in pairs(Intel.GlobalFuncs) do table.insert(roots, k) end; for _,v in ipairs(Intel.Constructors) do table.insert(roots, v) end
        for _,v in ipairs(roots) do if Intel.GlobalFuncs[v] then add(v, "Function", "", 3) elseif Intel.Libs[v] or v == "Instance" or Intel.ClassMembers[v.."Constructor"] then add(v, "Class", "", 2) else add(v, "Global", "", 1) end end
    else
        parentObj = Intel.Resolve(parentPath)
        if parentObj then
            local className
            if parentPath == "game" then className = "DataModel"
            elseif parentPath == "workspace" then className = "Workspace"
            elseif type(parentObj) == "table" and parentObj.ClassName then className = parentObj.ClassName
            elseif type(parentObj) == "string" and (Intel.ClassMembers[parentObj] or Intel.ClassMembers[parentObj.."Constructor"]) then className = parentObj .. (Intel.ClassMembers[parentObj.."Constructor"] and "Constructor" or "")
            elseif typeof(parentObj) == "Instance" then className = parentObj.ClassName
            elseif typeof(parentObj) == "RBXScriptSignal" then className = "RBXScriptSignal" end
            
            while className do
                local members = Intel.ClassMembers[className]
                if members then
                    if separator == "." then for _,p in ipairs(members.Properties or {}) do add(p, "Property", className, 2) end; for _,e in ipairs(members.Events or {}) do add(e, "Event", className, 4) end; for _,m in ipairs(members.Methods or {}) do add(m, "Method", className, 3) end
                    elseif separator == ":" then for _,m in ipairs(members.Methods or {}) do add(m, "Method", className, 3) end end
                end
                className = members and members.Inherits
            end
            if separator == "." and typeof(parentObj) == "Instance" then pcall(function() for _,c in ipairs(parentObj:GetChildren()) do add(c.Name, "Child", c.ClassName, 1) end end) end
        end
    end
    table.sort(res, function(a,b) if a.W == b.W then return a.N < b.N else return a.W < b.W end end)
    return res, query, parentObj
end

--// 6. UI, EVENT HANDLING, ETC
Screen = Instance.new("ScreenGui"); Screen.Name = "Titan_V44"; Screen.ResetOnSpawn = false; Screen.ZIndexBehavior = Enum.ZIndexBehavior.Sibling; pcall(function() Screen.Parent = CoreGui end); if not Screen.Parent then Screen.Parent = Players.LocalPlayer:WaitForChild("PlayerGui") end
Main = Instance.new("Frame", Screen); Main.Name = "Main"; Main.Size = UDim2.fromOffset(600, 400); Main.Position = UDim2.fromScale(0.5,0.5); Main.AnchorPoint = Vector2.new(0.5,0.5); Main.BackgroundColor3 = Config.Colors.Main; Main.Active = true; Main.Draggable = true; Instance.new("UICorner", Main).CornerRadius = UDim.new(0,6)
local Top = Instance.new("Frame", Main); Top.Size=UDim2.new(1,0,0,30); Top.BackgroundColor3=Config.Colors.Bar; Top.BorderSizePixel=0; local Title = Instance.new("TextLabel", Top); Title.Text=" TITAN IDE"; Title.Size=UDim2.new(1,-80,1,0); Title.BackgroundTransparency=1; Title.TextColor3=Config.Colors.Text; Title.TextXAlignment=0; Title.Font=Enum.Font.GothamBold; Title.TextSize=12; local Close = Instance.new("TextButton", Top); Close.Text="X"; Close.Size=UDim2.new(0,30,1,0); Close.Position=UDim2.new(1,-30,0,0); Close.BackgroundTransparency=1; Close.TextColor3=Color3.new(1,0.3,0.3); Close.Font=Enum.Font.GothamBold; Close.MouseButton1Click:Connect(function() Screen:Destroy() end)
local EditArea = Instance.new("Frame", Main); EditArea.Size=UDim2.new(1,0,1,-65); EditArea.Position=UDim2.new(0,0,0,30); EditArea.BackgroundColor3=Config.Colors.Editor; Lines = Instance.new("TextLabel", EditArea); Lines.Size=UDim2.new(0,35,1,0); Lines.BackgroundColor3=Config.Colors.Bar; Lines.TextColor3=Color3.new(0.5,0.5,0.5); Lines.TextYAlignment=0; Lines.Font=Config.Font; Lines.TextSize=14; Lines.Text="1"; Scroll = Instance.new("ScrollingFrame", EditArea); Scroll.Size=UDim2.new(1,-35,1,0); Scroll.Position=UDim2.new(0,35,0,0); Scroll.BackgroundTransparency=1; Scroll.BorderSizePixel=0; Scroll.CanvasSize=UDim2.new(0,0,0,0); Scroll.AutomaticCanvasSize=Enum.AutomaticSize.XY; High = Instance.new("TextLabel", Scroll); High.Size=UDim2.new(1,0,1,0); High.BackgroundTransparency=1; High.TextXAlignment=0; High.TextYAlignment=0; High.Font=Config.Font; High.TextSize=14; High.RichText=true; High.Text=""; High.ZIndex=2; Input = Instance.new("TextBox", Scroll); Input.Size=UDim2.new(1,0,1,0); Input.BackgroundTransparency=1; Input.TextXAlignment=0; Input.TextYAlignment=0; Input.Font=Config.Font; Input.TextSize=14; Input.MultiLine=true; Input.ClearTextOnFocus=false; Input.TextTransparency=0.5; Input.TextColor3=Config.Colors.Text; Input.Text=""; Input.ZIndex=3; Input.AutomaticSize=Enum.AutomaticSize.XY
Suggest = Instance.new("ScrollingFrame", Screen); Suggest.Name = "SuggestBox"; Suggest.Size = UDim2.fromOffset(250, 200); Suggest.BackgroundColor3 = Config.Colors.Suggest; Suggest.BorderColor3 = Config.Colors.Accent; Suggest.BorderSizePixel = 1; Suggest.Visible = false; Suggest.ZIndex = 20; Suggest.CanvasSize = UDim2.new(0,0,0,0); Suggest.AutomaticCanvasSize = Enum.AutomaticSize.Y; Suggest.ScrollBarThickness = 4; Instance.new("UIListLayout", Suggest)
local Exec = Instance.new("TextButton", Main); Exec.Text="EXECUTE"; Exec.Size=UDim2.new(0,100,0,25); Exec.Position=UDim2.new(1,-110,1,-30); Exec.BackgroundColor3=Config.Colors.Accent; Exec.TextColor3=Color3.new(1,1,1); Exec.Font=Enum.Font.GothamBold; Exec.TextSize=12; Instance.new("UICorner", Exec).CornerRadius=UDim.new(0,4); Exec.MouseButton1Click:Connect(function() local f,e=loadstring(Input.Text); if f then task.spawn(f) else warn(e) end end)
Inspector = Instance.new("Frame", Screen); Inspector.Name = "Inspector"; Inspector.Size = UDim2.fromOffset(220, 300); Inspector.Position = UDim2.new(0.7, 0, 0.5, -150); Inspector.BackgroundColor3 = Config.Colors.Inspector; Inspector.BorderColor3 = Config.Colors.Bar; Inspector.BorderSizePixel = 1; Inspector.Visible = false; Inspector.Active = true; Inspector.Draggable = true; local InsTop = Instance.new("Frame", Inspector); InsTop.Size=UDim2.new(1,0,0,25); InsTop.BackgroundColor3=Config.Colors.Bar; local InsTitle = Instance.new("TextLabel", InsTop); InsTitle.Text=" INSPECTOR"; InsTitle.Size=UDim2.new(1,-25,1,0); InsTitle.BackgroundTransparency=1; InsTitle.TextColor3=Config.Colors.Text; InsTitle.Font=Enum.Font.GothamBold; InsTitle.TextSize=12; local InsClose = Instance.new("TextButton", InsTop); InsClose.Text="X"; InsClose.Size=UDim2.new(0,25,1,0); InsClose.Position=UDim2.new(1,-25,0,0); InsClose.BackgroundTransparency=1; InsClose.TextColor3=Color3.new(1,0.3,0.3); InsClose.MouseButton1Click:Connect(function() Inspector.Visible=false; State.ARClone=nil; end); InsScroll = Instance.new("ScrollingFrame", Inspector); InsScroll.Size = UDim2.new(1,0,1,-25); InsScroll.Position = UDim2.new(0,0,0,25); InsScroll.BackgroundTransparency = 1; InsScroll.BorderSizePixel = 0; InsScroll.ScrollBarThickness = 4; InsScroll.AutomaticCanvasSize = Enum.AutomaticSize.Y; Instance.new("UIListLayout", InsScroll)
PrevWin = Instance.new("Frame", Screen); PrevWin.Name = "Preview"; PrevWin.Size = UDim2.fromOffset(200, 240); PrevWin.Position = UDim2.new(0.9, 0, 0.5, -150); PrevWin.BackgroundColor3 = Color3.new(0,0,0); PrevWin.BackgroundTransparency = 0.5; PrevWin.BorderColor3 = Config.Colors.Accent; PrevWin.BorderSizePixel = 1; PrevWin.Visible = false; PrevWin.Active = true; PrevWin.Draggable = true; local PrevTitle = Instance.new("TextLabel", PrevWin); PrevTitle.Text=" PREVIEW (DRAG)"; PrevTitle.Size=UDim2.new(1,-25,0,20); PrevTitle.BackgroundColor3=Config.Colors.Accent; PrevTitle.TextColor3=Color3.new(1,1,1); PrevTitle.Font=Enum.Font.GothamBold; PrevTitle.TextSize=10; local PrevClose = Instance.new("TextButton", PrevWin); PrevClose.Text="X"; PrevClose.Size=UDim2.new(0,25,0,20); PrevClose.Position=UDim2.new(1,-25,0,0); PrevClose.BackgroundColor3=Config.Colors.Accent; PrevClose.TextColor3=Color3.new(1,1,1); PrevClose.MouseButton1Click:Connect(function() PrevWin.Visible=false end); local ControlFrame = Instance.new("Frame", PrevWin); ControlFrame.Size = UDim2.new(1,0,0,30); ControlFrame.Position = UDim2.new(0,0,1,-30); ControlFrame.BackgroundColor3 = Config.Colors.Bar; ControlFrame.BorderSizePixel = 0; local ScaleLabel = Instance.new("TextLabel", ControlFrame); ScaleLabel.Text="Scale:"; ScaleLabel.Size=UDim2.new(0,40,1,0); ScaleLabel.BackgroundTransparency=1; ScaleLabel.TextColor3=Config.Colors.Text; ScaleLabel.Font=Config.Font; ScaleLabel.TextSize=12; local ScaleSlider = Instance.new("TextButton", ControlFrame); ScaleSlider.Text=""; ScaleSlider.Size=UDim2.new(0,80,0,4); ScaleSlider.Position=UDim2.new(0,45,0.5,-2); ScaleSlider.BackgroundColor3=Color3.new(0.3,0.3,0.3); local ScaleFill = Instance.new("Frame", ScaleSlider); ScaleFill.Size=UDim2.new(0.5,0,1,0); ScaleFill.BackgroundColor3=Config.Colors.Accent; ScaleFill.BorderSizePixel=0; local ModeBtn = Instance.new("TextButton", ControlFrame); ModeBtn.Text="Static"; ModeBtn.Size=UDim2.new(0,60,0,20); ModeBtn.Position=UDim2.new(1,-65,0.5,-10); ModeBtn.BackgroundColor3=Config.Colors.Editor; ModeBtn.TextColor3=Config.Colors.Text; ModeBtn.Font=Config.Font; ModeBtn.TextSize=12; Instance.new("UICorner", ModeBtn).CornerRadius=UDim.new(0,4); ModeBtn.MouseButton1Click:Connect(function() if State.Mode == "Static" then State.Mode = "Live"; ModeBtn.Text = "Live"; ModeBtn.TextColor3 = Color3.new(0,1,0) else State.Mode = "Static"; ModeBtn.Text = "Static"; ModeBtn.TextColor3 = Config.Colors.Text end end); local DraggingSlider = false; ScaleSlider.MouseButton1Down:Connect(function() DraggingSlider = true end); UserInputService.InputEnded:Connect(function(input) if input.UserInputType == Enum.UserInputType.MouseButton1 then DraggingSlider = false end end); UserInputService.InputChanged:Connect(function(input) if DraggingSlider and input.UserInputType == Enum.UserInputType.MouseMovement then local relX = math.clamp((input.Position.X - ScaleSlider.AbsolutePosition.X) / ScaleSlider.AbsoluteSize.X, 0, 1); ScaleFill.Size = UDim2.new(relX, 0, 1, 0); State.Scale = 0.5 + (relX * 1.5) end end)
local function ScrollToSelection() local itemH = Config.ItemHeight; local currentY = (State.Index - 1) * itemH; if currentY >= Suggest.CanvasPosition.Y + Suggest.AbsoluteSize.Y then Suggest.CanvasPosition = Vector2.new(0, currentY - Suggest.AbsoluteSize.Y + itemH) elseif currentY < Suggest.CanvasPosition.Y then Suggest.CanvasPosition = Vector2.new(0, currentY) end end
local function CleanupAR() if State.ARClone then State.ARClone:Destroy(); State.ARClone = nil end; if State.ARConn then State.ARConn:Disconnect(); State.ARConn = nil end; State.PartMap = {} end
local function MapHierarchy(real, clone) if real:IsA("BasePart") and clone:IsA("BasePart") then State.PartMap[real] = clone; clone.Anchored = true; clone.CanCollide = false; clone.CanTouch = false; clone.CanQuery = false end; local rChildren = real:GetChildren(); local cChildren = clone:GetChildren(); for i = 1, #rChildren do if cChildren[i] then MapHierarchy(rChildren[i], cChildren[i]) end end end
local function UpdateAR(obj) if not obj then return end; CleanupAR(); local clone = nil; local wasArch = obj.Archivable; obj.Archivable = true; pcall(function() clone = obj:Clone() end); obj.Archivable = wasArch; if clone then State.ARClone = clone; if clone:IsA("GuiObject") or clone:IsA("ScreenGui") then local holder = Instance.new("Part", Workspace); holder.Transparency=1; holder.Anchored=true; holder.CanCollide=false; holder.Size=Vector3.new(1,1,1); local bb = Instance.new("BillboardGui", holder); bb.Size=UDim2.fromScale(5, 5); bb.AlwaysOnTop=true; if clone:IsA("ScreenGui") then for _,c in ipairs(clone:GetChildren()) do c.Parent=bb end; clone:Destroy() else clone.Parent=bb; clone.Position=UDim2.fromScale(0.5,0.5); clone.AnchorPoint=Vector2.new(0.5,0.5) end; State.ARClone = holder; State.ARConn = RunService.RenderStepped:Connect(function() if not (PrevWin and PrevWin.Visible) then return end; local center = PrevWin.AbsolutePosition + Vector2.new(PrevWin.AbsoluteSize.X/2, -100); local ray = Camera:ScreenPointToRay(center.X, center.Y); holder.CFrame = CFrame.new(ray.Origin + ray.Direction * (10 / State.Scale)) end) elseif clone:IsA("BasePart") or clone:IsA("Model") or clone:IsA("Tool") or clone:IsA("Accessory") then clone.Parent = Workspace; State.PartMap = {}; MapHierarchy(obj, clone); for _, d in ipairs(clone:GetDescendants()) do if d:IsA("LuaSourceContainer") then d:Destroy() end end; if clone:IsA("Model") then local cf, size = clone:GetBoundingBox(); local maxDim = math.max(size.X, size.Y, size.Z); if maxDim > 0 then clone:ScaleTo(5 / maxDim) end end; local angle = 0; State.ARConn = RunService.RenderStepped:Connect(function(dt) if not (PrevWin and PrevWin.Visible) then return end; local center = PrevWin.AbsolutePosition + Vector2.new(PrevWin.AbsoluteSize.X/2, 100); local ray = Camera:ScreenPointToRay(center.X, center.Y); local depth = 10 / State.Scale; local targetPos = ray.Origin + ray.Direction * depth; if State.Mode == "Live" then local realPivot = (obj:IsA("Model") and obj:GetPivot()) or (obj:IsA("BasePart") and obj.CFrame) or CFrame.new(); local offset = CFrame.new(targetPos) * realPivot:Inverse(); for rp, cp in pairs(State.PartMap) do if rp and rp.Parent then cp.CFrame = offset * rp.CFrame; cp.Transparency = rp.Transparency; cp.Color = rp.Color end end else angle = angle + dt * 0.5; local rot = CFrame.fromEulerAnglesYXZ(0, angle, 0); if clone:IsA("Model") then clone:PivotTo(CFrame.new(targetPos) * rot) elseif clone:IsA("BasePart") then clone.CFrame = CFrame.new(targetPos) * rot end end end) end end end
local function UpdateInspector(overrideObj) if not (Inspector and InsScroll) then return end; local obj = overrideObj; if not obj and not State.ArgMode then local item = State.Results[State.Index]; if item and item.T == "Child" and State.ParentObj and typeof(State.ParentObj) == "Instance" then pcall(function() obj = State.ParentObj:FindFirstChild(item.N) end) end end; if obj then if State.LastInspected == obj then return end; State.LastInspected = obj; Inspector.Visible = true; PrevWin.Visible = true; local title = Inspector:FindFirstChild("Frame") and Inspector.Frame:FindFirstChild("TextLabel"); if title then title.Text = " " .. obj.Name .. " ["..obj.ClassName.."]" end; for _,v in pairs(InsScroll:GetChildren()) do if v:IsA("Frame") then v:Destroy() end end; local props = {"Name", "ClassName", "Parent", "Archivable", "Size", "Position", "CFrame", "Color", "Transparency", "Reflectance", "Material", "Text", "Value", "Enabled"}; for _, prop in ipairs(props) do local success, val = pcall(function() return obj[prop] end); if success and val ~= nil then local row = Instance.new("Frame", InsScroll); row.Size=UDim2.new(1,0,0,20); row.BackgroundTransparency=1; local n = Instance.new("TextLabel", row); n.Size=UDim2.new(0.4,0,1,0); n.BackgroundTransparency=1; n.Text=" "..prop; n.TextColor3=Config.Colors.Accent; n.TextXAlignment=0; n.Font=Config.Font; n.TextSize=12; local v = Instance.new("TextLabel", row); v.Size=UDim2.new(0.6,-5,1,0); v.Position=UDim2.new(0.4,0,0,0); v.BackgroundTransparency=1; v.Text=tostring(val):gsub("\n", " "); v.TextColor3=Config.Colors.Text; v.TextXAlignment=2; v.Font=Config.Font; v.TextSize=12; v.TextTruncate=Enum.TextTruncate.AtEnd end end; UpdateAR(obj) end end
local function UpdateVisuals() if not Suggest then return end; for i, btn in ipairs(Suggest:GetChildren()) do if btn:IsA("TextButton") then btn.BackgroundColor3 = (btn.LayoutOrder == State.Index) and Config.Colors.Accent or Config.Colors.Suggest end end; ScrollToSelection(); UpdateInspector() end
local function Accept() if not State.Active or not State.Results[State.Index] then return end; State.IgnoreUpdate = true; local item = State.Results[State.Index]; local full = Input.Text; local cur = Input.CursorPosition; local ins = item.N; local startPos = cur; if State.ArgMode then while startPos > 0 do local char = full:sub(startPos-1, startPos-1); if char == '"' or char == "'" then break end; startPos = startPos - 1 end else while startPos > 0 do local char = full:sub(startPos-1, startPos-1); if not char:match("[%w_]") then break end; startPos = startPos - 1 end; local needsBrackets = not ins:match("^[_%a][_%w]*$"); if needsBrackets then local preChar = full:sub(startPos-1, startPos-1); if preChar == "." then startPos = startPos - 1 end; ins = '["' .. ins .. '"]' end; if item.T == "Method" or item.T == "Function" then ins = ins.."()" end end; local before = full:sub(1, startPos-1); local after = full:sub(cur); Input.Text = before .. ins .. after; local newPos = #before + #ins + 1; if (item.T == "Method" or item.T == "Function") and not State.ArgMode then newPos = newPos - 1 end; Input.CursorPosition = newPos; Suggest.Visible = false; State.Active = false; State.IgnoreUpdate = false; task.defer(function() if Input and Input.Parent then Input:CaptureFocus() end end) end
UserInputService.InputBegan:Connect(function(input)
    if not (Input and Input.Parent and Input:IsFocused()) then return end
    if input.KeyCode == Enum.KeyCode.Quote then
        local c = Input.CursorPosition
        if Input.Text:sub(c, c) == '"' then
            Input.TextEditable = false; task.defer(function() Input.CursorPosition = c; Input.TextEditable = true; Input:CaptureFocus() end)
        else
            Input.TextEditable = false; task.defer(function() Input.Text = Input.Text:sub(1, c - 1) .. '""' .. Input.Text:sub(c); Input.CursorPosition = c; Input.TextEditable = true; Input:CaptureFocus() end)
        end
    end
    if State.Active then
        local key = input.KeyCode; local update = false
        if key == Enum.KeyCode.Up then State.Index = math.max(1, State.Index - 1); update=true
        elseif key == Enum.KeyCode.Down then State.Index = math.min(#State.Results, State.Index + 1); update=true
        elseif key == Enum.KeyCode.Tab or key == Enum.KeyCode.Return then Input.TextEditable = false; Accept(); RunService.RenderStepped:Wait(); Input.TextEditable = true; Input:CaptureFocus() end
        if update then Input.TextEditable = false; State.Navigating = true; UpdateVisuals(); RunService.RenderStepped:Wait(); Input.TextEditable = true; Input:CaptureFocus(); State.Navigating = false end
    end
end)
local function PositionSuggestWindow(pre) local linesBefore = select(2, pre:gsub("\n", "\n")); local lastLine = pre:match("[^\n]*$") or ""; local vec = TextService:GetTextSize(lastLine, 14, Config.Font, Vector2.new(9999,9999)); local abs = Main.AbsolutePosition; local x = abs.X + 35 + vec.X - Scroll.CanvasPosition.X + 10; local y = abs.Y + 30 + (linesBefore+1)*15 - Scroll.CanvasPosition.Y + 5; Suggest.Position = UDim2.fromOffset(x,y) end
local function Update() if not (Input and Suggest) then return end; if State.IgnoreUpdate or State.Navigating then return end; local text = Input.Text; if text:find("\t") then local c = Input.CursorPosition; Input.Text = text:gsub("\t", "  "); Input.CursorPosition = c + 1; return end; High.Text = Syntax.Highlight(text); local _,lc = text:gsub("\n","\n"); local l=""; for i=1,lc+1 do l=l..i.."\n" end; Lines.Text=l; local cur = Input.CursorPosition; if cur < 1 then Suggest.Visible=false; State.Active=false; return end; local pre = text:sub(1, cur-1); local res, q, parentObj = Intel.Scan(pre, text); local sameList = (#res == #State.Results); if sameList then for i=1, #res do if res[i].N ~= State.Results[i].N then sameList=false; break end end end; if sameList then PositionSuggestWindow(pre); if not Suggest.Visible and #res > 0 then Suggest.Visible=true end; return end; if #res == 0 then Suggest.Visible=false; State.Active=false; return end; local oldName = State.Results[State.Index] and State.Results[State.Index].N; local newIndex = 1; if oldName then for i, item in ipairs(res) do if item.N == oldName then newIndex = i; break end end end; State.Results = res; State.Query = q; State.ParentObj = parentObj; State.Index = newIndex; State.Active = true; for _,v in pairs(Suggest:GetChildren()) do if v:IsA("TextButton") then v:Destroy() end end; for i=1, #res do local d = res[i]; local b = Instance.new("TextButton", Suggest); b.Size=UDim2.new(1,0,0,Config.ItemHeight); b.BackgroundColor3=(i==State.Index) and Config.Colors.Accent or Config.Colors.Suggest; b.TextColor3=Config.Colors.Text; b.TextXAlignment=0; b.Font=Config.Font; b.TextSize=13; b.ZIndex=21; b.LayoutOrder=i; local txt = "  " .. d.N; if d.X ~= "" and d.X ~= "Creatable" then txt = txt .. " ["..d.X.."]" end; b.Text = txt; local f = Instance.new("Frame", b); f.Size=UDim2.new(0,3,1,0); f.BorderSizePixel=0; f.ZIndex=22; if d.T=="Child" or d.T=="Instance" then f.BackgroundColor3=Color3.fromRGB(139, 233, 253) elseif d.T=="Property" then f.BackgroundColor3=Color3.fromRGB(80, 250, 123) elseif d.T=="Method" or d.T=="Function" or d.T=="Class" or d.T=="Library" then f.BackgroundColor3=Color3.fromRGB(189, 147, 249) elseif d.T=="Event" then f.BackgroundColor3=Color3.fromRGB(255, 121, 198) elseif d.T=="Service" then f.BackgroundColor3=Color3.fromRGB(255, 184, 108) elseif d.T=="EnumItem" then f.BackgroundColor3=Color3.fromRGB(241, 250, 140) else f.BackgroundColor3=Color3.fromRGB(98, 114, 164) end; b.MouseButton1Click:Connect(function() State.Index = i; Input:CaptureFocus(); Input.CursorPosition = cur; Accept() end) end; PositionSuggestWindow(pre); Suggest.Size = UDim2.fromOffset(250, math.min(#res, 8) * Config.ItemHeight); Suggest.Visible = true; ScrollToSelection(); UpdateInspector() end
task.spawn(function() while task.wait(0.3) do if State.Active and not State.Navigating then pcall(Update) end end end)
Input:GetPropertyChangedSignal("Text"):Connect(Update)
Input:GetPropertyChangedSignal("CursorPosition"):Connect(Update)
task.spawn(Update)
