--[[
Riddler Assistant - modular starter
UI: dark purple, two separate draggable panels (AI Riddler + Code Redeemer)
Knowledge can be updated later via import JSON file.
This starter does not monitor Roblox chat or read hidden game state.
Only redeem codes when you explicitly test/authorize it; current Redeem is a safe placeholder.
]]

local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local player = Players.LocalPlayer

local PREFIX = "RiddlerAssistant"
local DATA_FILE = PREFIX .. "_knowledge.json"
local SETTINGS_FILE = PREFIX .. "_settings.json"

local defaults = {
    knowledge = {
        brainrots = {},
        mutations = {},
        traits = {},
        riddles = {},
        codes = {},
        trivia = {},
        notes = {}
    },
    settings = {
        testMode = true,
        autoCopy = false,
        autoRedeem = false,
        listen = false,
        autoType = false,
        manual = true,
        spamRedeem = false,
        speed = "Normal",
        model = "Local matcher"
    }
}

local function safeDecode(s)
    local ok, result = pcall(function() return HttpService:JSONDecode(s) end)
    if ok and type(result) == "table" then return result end
    return nil
end

local function readLocal(path)
    if type(readfile) ~= "function" or type(isfile) ~= "function" then return nil end
    local ok, result = pcall(function()
        if isfile(path) then return readfile(path) end
    end)
    if ok and type(result) == "string" then return safeDecode(result) end
    return nil
end

local function writeLocal(path, data)
    if type(writefile) ~= "function" then return false end
    local ok = pcall(function() writefile(path, HttpService:JSONEncode(data)) end)
    return ok
end

local saved = readLocal(DATA_FILE)
local knowledge = (saved and saved.knowledge) or defaults.knowledge
local settingsSaved = readLocal(SETTINGS_FILE)
local settings = settingsSaved or defaults.settings

local function saveKnowledge()
    return writeLocal(DATA_FILE, {knowledge = knowledge, updatedAt = os.date("!%Y-%m-%dT%H:%M:%SZ")})
end
local function saveSettings()
    return writeLocal(SETTINGS_FILE, settings)
end

local function trim(s)
    return (tostring(s or ""):gsub("^%s+", ""):gsub("%s+$", ""))
end

local function tokenize(s)
    local out = {}
    for word in string.lower(tostring(s or "")):gmatch("[%w']+") do
        if #word > 2 then out[word] = true end
    end
    return out
end

local function scoreText(query, candidate)
    local q, c = tokenize(query), tokenize(candidate)
    local score, count = 0, 0
    for word in pairs(q) do
        count = count + 1
        if c[word] then score = score + 1 end
    end
    if count == 0 then return 0 end
    return score / count
end

local function flatten(v)
    if type(v) == "string" or type(v) == "number" then return tostring(v) end
    if type(v) ~= "table" then return "" end
    local parts = {}
    for k, x in pairs(v) do
        if type(x) ~= "table" then
            table.insert(parts, tostring(k) .. " " .. tostring(x))
        end
    end
    return table.concat(parts, " ")
end

local function searchKnowledge(query)
    local best, bestScore = nil, 0
    local buckets = {"brainrots", "mutations", "traits", "riddles", "codes", "trivia", "notes"}
    for _, bucket in ipairs(buckets) do
        local rows = knowledge[bucket]
        if type(rows) == "table" then
            for _, row in ipairs(rows) do
                if type(row) == "table" then
                    local candidate = flatten(row)
                    local score = scoreText(query, candidate)
                    if bucket == "riddles" and type(row.question) == "string" then
                        score = math.max(score, scoreText(query, row.question) * 1.2)
                    end
                    if score > bestScore then
                        bestScore = score
                        best = {bucket = bucket, row = row, score = score}
                    end
                end
            end
        end
    end
    return best, bestScore
end

local function answerQuery(query)
    local hit, score = searchKnowledge(query)
    if not hit or score < 0.22 then
        return "I don't have a reliable match yet. Add a confirmed fact or riddle to the knowledge file.", false
    end
    local row = hit.row
    if hit.bucket == "riddles" then
        return tostring(row.answer or row.response or "A matching riddle entry has no answer saved."), true
    end
    return tostring(row.answer or row.name or row.title or row.description or flatten(row)), true
end

local function addKnowledge(payload)
    if type(payload) ~= "table" then return false, "JSON must contain an object." end
    local incoming = payload.knowledge or payload
    local valid = {brainrots=true, mutations=true, traits=true, riddles=true, codes=true, trivia=true, notes=true}
    local added = 0
    for bucket, allowed in pairs(valid) do
        if allowed and type(incoming[bucket]) == "table" then
            knowledge[bucket] = knowledge[bucket] or {}
            for _, row in ipairs(incoming[bucket]) do
                if type(row) == "table" then
                    table.insert(knowledge[bucket], row)
                    added = added + 1
                end
            end
        end
    end
    local ok = saveKnowledge()
    return true, ("Imported %d entries%s"):format(added, ok and " and saved." or ". Saving isn't supported in this executor; export/keep the JSON file.")
end

-- UI helpers
local function make(class, props, parent)
    local obj = Instance.new(class)
    for k, v in pairs(props or {}) do obj[k] = v end
    obj.Parent = parent
    return obj
end

local purple = Color3.fromRGB(133, 77, 183)
local dark = Color3.fromRGB(20, 15, 27)
local panel = Color3.fromRGB(31, 23, 41)
local input = Color3.fromRGB(17, 13, 23)
local muted = Color3.fromRGB(181, 164, 195)
local white = Color3.fromRGB(245, 239, 250)

local gui = make("ScreenGui", {Name="RiddlerAssistantUI", ResetOnSpawn=false, ZIndexBehavior=Enum.ZIndexBehavior.Sibling}, player:WaitForChild("PlayerGui"))

local function round(obj, radius)
    make("UICorner", {CornerRadius=UDim.new(0, radius or 7)}, obj)
end
local function stroke(obj, color, thickness)
    make("UIStroke", {Color=color or Color3.fromRGB(81, 60, 99), Thickness=thickness or 1, Transparency=0.1}, obj)
end
local function label(parent, text, size, pos, fontSize, color, bold)
    return make("TextLabel", {BackgroundTransparency=1, Text=text, Size=size, Position=pos, Font=bold and Enum.Font.GothamBold or Enum.Font.Gotham, TextSize=fontSize or 12, TextColor3=color or white, TextXAlignment=Enum.TextXAlignment.Left, TextYAlignment=Enum.TextYAlignment.Center, TextWrapped=true}, parent)
end
local function button(parent, text, size, pos, callback, filled)
    local b = make("TextButton", {Text=text, Size=size, Position=pos, BackgroundColor3=filled and purple or Color3.fromRGB(48, 35, 61), TextColor3=white, Font=Enum.Font.GothamBold, TextSize=11, AutoButtonColor=true}, parent)
    round(b, 6); stroke(b, Color3.fromRGB(87, 62, 108))
    b.Activated:Connect(callback)
    return b
end
local function textBox(parent, placeholder, size, pos, multi)
    local t = make("TextBox", {Text="", PlaceholderText=placeholder, ClearTextOnFocus=false, MultiLine=multi or false, TextWrapped=true, TextXAlignment=Enum.TextXAlignment.Left, TextYAlignment=Enum.TextYAlignment.Top, Size=size, Position=pos, BackgroundColor3=input, TextColor3=white, PlaceholderColor3=muted, Font=Enum.Font.Gotham, TextSize=12}, parent)
    round(t, 6); stroke(t)
    return t
end
local function toggle(parent, text, pos, default, callback)
    local b = button(parent, (default and "●" or "○") .. "  " .. text, UDim2.new(0, 128, 0, 25), pos, function()
        default = not default
        b.Text = (default and "●" or "○") .. "  " .. text
        callback(default)
    end, false)
    return b
end
local function draggable(frame, handle)
    local dragging, dragInput, startPos, framePos = false, nil, nil, nil
    handle.InputBegan:Connect(function(i)
        if i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch then
            dragging = true; startPos = i.Position; framePos = frame.Position
            i.Changed:Connect(function() if i.UserInputState == Enum.UserInputState.End then dragging = false end end)
        end
    end)
    handle.InputChanged:Connect(function(i)
        if i.UserInputType == Enum.UserInputType.MouseMovement or i.UserInputType == Enum.UserInputType.Touch then dragInput = i end
    end)
    UserInputService.InputChanged:Connect(function(i)
        if dragging and (i == dragInput or i.UserInputType == Enum.UserInputType.MouseMovement) then
            local delta = i.Position - startPos
            frame.Position = UDim2.new(framePos.X.Scale, framePos.X.Offset + delta.X, framePos.Y.Scale, framePos.Y.Offset + delta.Y)
        end
    end)
end

local main = make("Frame", {Name="RiddlerPanel", Size=UDim2.new(0, 300, 0, 420), Position=UDim2.new(0.18,0,0.2,0), BackgroundColor3=dark}, gui)
round(main, 9); stroke(main, Color3.fromRGB(99, 68, 124), 1.3)
local header = make("Frame", {Size=UDim2.new(1,0,0,36), BackgroundColor3=panel}, main); round(header, 9)
label(header, "✦  AI RIDDLER", UDim2.new(1,-75,1,0), UDim2.new(0,12,0,0), 14, white, true)
local closeMain = button(header, "×", UDim2.new(0,28,0,26), UDim2.new(1,-33,0,5), function() main.Visible = false end, false)
draggable(main, header)

label(main, "QUESTION", UDim2.new(1,-24,0,18), UDim2.new(0,12,0,42), 10, muted, true)
local question = textBox(main, "Enter a riddle or clue...", UDim2.new(1,-24,0,74), UDim2.new(0,12,0,62), true)
label(main, "ANSWER", UDim2.new(1,-24,0,18), UDim2.new(0,12,0,144), 10, muted, true)
local answer = textBox(main, "Answer will appear here...", UDim2.new(1,-24,0,66), UDim2.new(0,12,0,164), true)
local status = label(main, "Ready • local knowledge matcher", UDim2.new(1,-24,0,28), UDim2.new(0,12,0,233), 10, muted, false)
button(main, "ASK / SOLVE", UDim2.new(0,112,0,30), UDim2.new(0,12,0,264), function()
    local result, found = answerQuery(question.Text)
    answer.Text = result
    status.Text = found and "Match found in saved knowledge." or "No confident match; add more data."
end, true)
button(main, "COPY", UDim2.new(0,64,0,30), UDim2.new(0,130,0,264), function()
    if type(setclipboard) == "function" then pcall(setclipboard, answer.Text) end
    status.Text = "Copy requested (if supported by executor)."
end, false)
button(main, "CLEAR", UDim2.new(0,64,0,30), UDim2.new(0,200,0,264), function()
    question.Text = ""; answer.Text = ""; status.Text = "Cleared."
end, false)
button(main, "TEST", UDim2.new(0,64,0,28), UDim2.new(0,12,0,302), function()
    question.Text = "I am at the Coral Cove beach. What beach did I mention?"
    local result, found = answerQuery(question.Text)
    answer.Text = result
    status.Text = found and "Test passed: memory match found." or "Test needs a saved clue in the knowledge file."
end, false)
button(main, "IMPORT KNOWLEDGE", UDim2.new(0,172,0,28), UDim2.new(0,82,0,302), function()
    importFrame.Visible = not importFrame.Visible
end, false)
button(main, "CODE REDEEMER  ›", UDim2.new(1,-24,0,34), UDim2.new(0,12,0,342), function()
    redeemer.Visible = not redeemer.Visible
end, true)
label(main, "Knowledge is imported from JSON; no automatic chat monitoring.", UDim2.new(1,-24,0,24), UDim2.new(0,12,0,382), 9, muted, false)

-- Import modal
local importFrame = make("Frame", {Name="KnowledgeImporter", Size=UDim2.new(0,340,0,320), Position=UDim2.new(0.5,-170,0.5,-160), BackgroundColor3=dark, Visible=false, ZIndex=10}, gui)
round(importFrame, 9); stroke(importFrame, purple, 1.3)
local importHeader = make("Frame", {Size=UDim2.new(1,0,0,36), BackgroundColor3=panel, ZIndex=11}, importFrame); round(importHeader, 9)
label(importHeader, "IMPORT KNOWLEDGE JSON", UDim2.new(1,-45,1,0), UDim2.new(0,10,0,0), 12, white, true).ZIndex = 12
button(importHeader, "×", UDim2.new(0,26,0,25), UDim2.new(1,-31,0,5), function() importFrame.Visible=false end, false).ZIndex=12
local importBox = textBox(importFrame, 'Paste JSON: {"riddles":[{"question":"...","answer":"..."}]}', UDim2.new(1,-20,0,205), UDim2.new(0,10,0,44), true); importBox.ZIndex=12
local importStatus = label(importFrame, "Supported buckets: brainrots, mutations, traits, riddles, codes, trivia, notes", UDim2.new(1,-20,0,30), UDim2.new(0,10,0,252), 9, muted, false); importStatus.ZIndex=12
button(importFrame, "IMPORT + SAVE", UDim2.new(0,145,0,28), UDim2.new(0,10,0,285), function()
    local payload = safeDecode(importBox.Text)
    local ok, msg = addKnowledge(payload)
    importStatus.Text = msg
end, true).ZIndex=12
button(importFrame, "EXPORT JSON", UDim2.new(0,120,0,28), UDim2.new(0,165,0,285), function()
    local encoded = HttpService:JSONEncode({knowledge=knowledge})
    if type(setclipboard) == "function" then pcall(setclipboard, encoded) end
    importStatus.Text = "Export copied if clipboard is supported."
end, false).ZIndex=12

-- Separate code redeemer panel. Redeem is intentionally a placeholder until user supplies a legitimate code endpoint/workflow.
local redeemer = make("Frame", {Name="CodeRedeemerPanel", Size=UDim2.new(0,300,0,390), Position=UDim2.new(0.56,0,0.2,0), BackgroundColor3=dark, Visible=false}, gui)
round(redeemer, 9); stroke(redeemer, Color3.fromRGB(99, 68, 124), 1.3)
local rhead = make("Frame", {Size=UDim2.new(1,0,0,36), BackgroundColor3=panel}, redeemer); round(rhead, 9)
label(rhead, "✦  CODE REDEEMER", UDim2.new(1,-40,1,0), UDim2.new(0,12,0,0), 13, white, true)
button(rhead, "×", UDim2.new(0,26,0,26), UDim2.new(1,-31,0,5), function() redeemer.Visible=false end, false)
draggable(redeemer, rhead)
label(redeemer, "CODE", UDim2.new(1,-24,0,18), UDim2.new(0,12,0,44), 10, muted, true)
local codeBox = textBox(redeemer, "Enter code...", UDim2.new(1,-24,0,40), UDim2.new(0,12,0,64), false)
label(redeemer, "STATUS / RESULT", UDim2.new(1,-24,0,18), UDim2.new(0,12,0,112), 10, muted, true)
local codeStatus = textBox(redeemer, "Result will appear here...", UDim2.new(1,-24,0,56), UDim2.new(0,12,0,132), true)
button(redeemer, "COPY", UDim2.new(0,72,0,28), UDim2.new(0,12,0,196), function()
    if type(setclipboard) == "function" then pcall(setclipboard, codeBox.Text) end
    codeStatus.Text = "Copy requested (if supported)."
end, false)
button(redeemer, "CLEAR", UDim2.new(0,72,0,28), UDim2.new(0,92,0,196), function() codeBox.Text=""; codeStatus.Text="" end, false)
button(redeemer, "TEST", UDim2.new(0,72,0,28), UDim2.new(0,172,0,196), function()
    codeStatus.Text = "Test mode: code '" .. codeBox.Text .. "' was not redeemed."
end, true)
toggle(redeemer, "Listen", UDim2.new(0,12,0,236), settings.listen, function(v) settings.listen=v; saveSettings() end)
toggle(redeemer, "Auto Type", UDim2.new(0,154,0,236), settings.autoType, function(v) settings.autoType=v; saveSettings() end)
toggle(redeemer, "Manual Mode", UDim2.new(0,12,0,266), settings.manual, function(v) settings.manual=v; saveSettings() end)
toggle(redeemer, "Spam Redeem", UDim2.new(0,154,0,266), settings.spamRedeem, function(v) settings.spamRedeem=v; saveSettings() end)
label(redeemer, "Speed", UDim2.new(0,60,0,25), UDim2.new(0,12,0,305), 11, muted, true)
local speedButton = button(redeemer, settings.speed or "Normal", UDim2.new(0,120,0,25), UDim2.new(0,78,0,305), function()
    settings.speed = settings.speed == "Slow" and "Normal" or (settings.speed == "Normal" and "Fast" or "Slow")
    speedButton.Text = settings.speed; saveSettings()
end, false)
button(redeemer, "REDEEM", UDim2.new(1,-24,0,32), UDim2.new(0,12,0,342), function()
    codeStatus.Text = "Safe placeholder: no game redemption was performed. Connect a legitimate, documented redeem workflow to enable this."
end, true)

-- Keep core settings persisted.
toggle(main, "Test Mode", UDim2.new(0,154,0,302), settings.testMode, function(v) settings.testMode=v; saveSettings() end)

-- Add a simple sample knowledge entry so the Test button explains the feature without claiming game truth.
if #knowledge.notes == 0 then
    table.insert(knowledge.notes, {title="Sample memory", description="This is a sample only. Import verified clues and answers to use the solver."})
end
saveSettings()
