-- Gray Quest Level
-- Line 1: the lowest quest level that is still green, and where quests turn gray.
-- Line 2: how many more XP gains of the last size it takes to reach the next level.
-- Works on Retail-API clients (incl. WoW Forever beta), where GetQuestGreenRange
-- no longer exists.

local ADDON_NAME = ...

GrayQuestLevelDB = GrayQuestLevelDB or {}

-- ---------------------------------------------------------------------------
-- Safe reads
-- ---------------------------------------------------------------------------

-- Reads a number from an API that may be absent, may throw, or (on this client)
-- may hand back a secret value that throws when compared. Everything that
-- touches the value happens inside pcall.
local function SafeNumber(fn, unit)
    if type(fn) ~= "function" then return nil end
    local ok, value = pcall(fn, unit)
    if not ok then return nil end
    local ok2, usable = pcall(function()
        return type(value) == "number" and value == value -- NaN check
    end)
    if ok2 and usable then return value end
end

local function PlayerLevel()
    return SafeNumber(UnitEffectiveLevel, "player")
        or SafeNumber(UnitLevel, "player")
        or 1
end

-- ---------------------------------------------------------------------------
-- Quest level math
-- ---------------------------------------------------------------------------

-- How many levels below you a quest can be and still be green.
-- Looked up by name each time: globals are resolved lazily, and a plain
-- table + ipairs would stop at the first nil candidate.
local RANGE_FUNCS = { "UnitQuestTrivialLevelRange", "GetQuestGreenRange" }

local function GetGreenRange()
    for i = 1, #RANGE_FUNCS do
        local range = SafeNumber(_G[RANGE_FUNCS[i]], "player")
        if range then return range end
    end
end

-- Two colour tables can be the same colour without being the same table, so
-- fall back to comparing the components. Wrapped by the caller's pcall.
local function ColorsMatch(a, b)
    if a == b then return true end
    if type(a) ~= "table" or type(b) ~= "table" then return false end
    -- Both must actually carry components. Without this check a client that
    -- hands back bare tables makes every level "match" (nil == nil), and the
    -- scan reports your own level as gray.
    if type(a.r) ~= "number" or type(b.r) ~= "number" then return false end
    return a.r == b.r and a.g == b.g and a.b == b.b
end

-- Ask the game's own quest-colour function which levels are gray. This is the
-- function the quest log itself colours entries with, so whatever it says is
-- by definition what you see in the log -- no arithmetic, nothing to get out
-- of step with the client.
-- Returns the highest gray level, or 0 if the function works but nothing is
-- gray yet, or nil if this client has no usable colour API.
local function ScanForGray(level)
    if type(GetQuestDifficultyColor) ~= "function"
        or type(QuestDifficultyColors) ~= "table"
        or not QuestDifficultyColors.trivial then
        return nil
    end
    local worked = false
    for q = level, 1, -1 do
        local ok, color = pcall(GetQuestDifficultyColor, q)
        if ok and color ~= nil then
            worked = true
            local ok2, isTrivial = pcall(ColorsMatch, color, QuestDifficultyColors.trivial)
            if ok2 and isTrivial then
                return q -- highest gray level
            end
        end
    end
    if worked then return 0 end -- nothing is gray at this level yet
end

-- The three ways of working out the boundary, kept side by side so they can be
-- compared -- on the Forever beta they do not always agree.
--
--   table  : the published vanilla gray-level table (default)
--   range  : playerLevel - UnitQuestTrivialLevelRange("player")
--   colors : walk GetQuestDifficultyColor down until it reports trivial
--
-- `table` is the default as of v1.5, because both client-API sources are
-- demonstrably wrong here: UnitQuestTrivialLevelRange returns a flat 5 on this
-- build (Retail's non-scaling value) when vanilla scales it with level. The
-- level-8 reading that validated `range` in v1.4 did so by coincidence --
-- floor(8/10) is 0, so the missing term happened not to matter at that level.
--
-- Measured at level 20: `range` said gray 15, `colors` said gray 14, and the
-- quest log showed a level-14 quest ("The Dead Fields", wowhead quest=437)
-- still green, turning gray at 21. That is gray 13, i.e.
-- 20 - floor(20/10) - 5 -- the table, and neither API.
local function RangeGray(level)
    local range = GetGreenRange()
    if range then return level - range end
end

-- Vanilla's gray-level table: the highest level that is trivial to a player of
-- `level`. Quests and mobs share it. Returns 0 when nothing is gray yet.
--
-- The 6-39 band is confirmed against this client at levels 8 and 20. The 40+
-- bands are the published vanilla formulas and are NOT yet verified here --
-- the bands are not continuous at 60 (59 gives 47, 60 gives 51), which is how
-- the tables are written, not a transcription slip. If the display disagrees
-- with your quest log at those levels, `/gql debug` prints every source and
-- `/gql calibrate <n>` applies an offset.
local function TableGray(level)
    if level <= 5 then
        return 0 -- nothing is trivial this early
    elseif level <= 39 then
        return level - math.floor(level / 10) - 5
    elseif level <= 59 then
        return level - math.floor(level / 5) - 1
    else
        return level - 9
    end
end

-- Order used by `auto`, and as the fallback when the preferred source has
-- nothing to say: most trustworthy on this client first.
local SOURCE_ORDER = { "table", "range", "colors" }

local function Compute()
    local level = PlayerLevel()
    local pref = GrayQuestLevelDB.source or "auto"

    local byTable = TableGray(level)
    local byRange = RangeGray(level)
    local byColors = ScanForGray(level)

    -- 0 is a real answer ("nothing gray yet") and is truthy in Lua, so a
    -- present-but-zero source is still picked over a later one.
    local candidates = { table = byTable, range = byRange, colors = byColors }

    local highestGray, source = candidates[pref], pref
    if highestGray == nil then
        for i = 1, #SOURCE_ORDER do
            local name = SOURCE_ORDER[i]
            if candidates[name] ~= nil then
                highestGray, source = candidates[name], name
                break
            end
        end
    end

    if highestGray == nil then return level, nil, nil, "none", byTable, byRange, byColors end

    highestGray = highestGray + (tonumber(GrayQuestLevelDB.offset) or 0)
    return level, math.max(1, highestGray + 1), highestGray, source, byTable, byRange, byColors
end

-- ---------------------------------------------------------------------------
-- XP tracking
-- ---------------------------------------------------------------------------
-- The WeakAura this replaces read a "last mob XP" value that its own trigger
-- filled in from the combat XP chat message. Parsing that message is a bad bet
-- on this client (Retail API, restricted combat log, localised strings), so
-- instead we watch the XP bar itself: every PLAYER_XP_UPDATE, the difference
-- from the previous reading IS the amount just gained, whatever caused it.

local lastXP, lastMax   -- previous reading of the bar
local lastGain          -- size of the most recent gain
local pendingLevelUp    -- set when we level, so the next delta isn't nonsense

local function IsMaxLevel()
    local maxLevel = SafeNumber(GetMaxPlayerLevel) or SafeNumber(GetMaxLevelForPlayerExpansion)
    if maxLevel and PlayerLevel() >= maxLevel then return true end
    local max = SafeNumber(UnitXPMax, "player")
    return max ~= nil and max <= 0
end

local function XPDisabled()
    if type(IsXPUserDisabled) ~= "function" then return false end
    local ok, disabled = pcall(IsXPUserDisabled)
    return ok and disabled == true
end

-- Records the current bar position, and returns the gain since last time.
local function SampleXP()
    local xp = SafeNumber(UnitXP, "player")
    local max = SafeNumber(UnitXPMax, "player")
    if not xp or not max then return nil end

    local gain
    if lastXP and lastMax then
        if pendingLevelUp or xp < lastXP then
            -- Crossed a level: finish the old bar, then add the new bar's XP.
            -- Only meaningful for a single level; a multi-level gain is
            -- undercounted, which is fine for an estimate.
            gain = (lastMax - lastXP) + xp
        else
            gain = xp - lastXP
        end
    end

    pendingLevelUp = nil
    lastXP, lastMax = xp, max

    if gain and gain > 0 then
        lastGain = gain
        if GrayQuestLevelDB then GrayQuestLevelDB.lastGain = gain end
    end
    return gain
end

-- Returns: killsNeeded, xpRemaining, gainSize — or nil plus a reason string.
local function ComputeKills()
    if XPDisabled() then return nil, "xp off" end
    if IsMaxLevel() then return nil, "max level" end

    local xp = SafeNumber(UnitXP, "player")
    local max = SafeNumber(UnitXPMax, "player")
    if not xp or not max or max <= 0 then return nil, "no xp data" end

    local remaining = max - xp
    local gain = lastGain or (GrayQuestLevelDB and GrayQuestLevelDB.lastGain)
    if not gain or gain <= 0 then return nil, "waiting", remaining end

    return math.ceil(remaining / gain), remaining, gain
end

-- ---------------------------------------------------------------------------
-- On-screen display
-- ---------------------------------------------------------------------------

local frame = CreateFrame("Frame", "GrayQuestLevelFrame", UIParent)
frame:SetSize(170, 40)
frame:SetFrameStrata("MEDIUM")
frame:SetClampedToScreen(true)
frame:SetMovable(true)
frame:EnableMouse(true)
frame:RegisterForDrag("LeftButton")

local bg = frame:CreateTexture(nil, "BACKGROUND")
bg:SetAllPoints()
bg:SetColorTexture(0, 0, 0, 0.45)

local questText = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
questText:SetPoint("TOP", frame, "TOP", 0, -4)

local killText = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
killText:SetPoint("TOP", questText, "BOTTOM", 0, -2)

local function ApplyPosition()
    frame:ClearAllPoints()
    local p = GrayQuestLevelDB.pos
    if p then
        frame:SetPoint(p[1], UIParent, p[2], p[3], p[4])
    else
        frame:SetPoint("TOP", UIParent, "TOP", 0, -120)
    end
end

frame:SetScript("OnDragStart", function(self)
    if not GrayQuestLevelDB.locked then self:StartMoving() end
end)
frame:SetScript("OnDragStop", function(self)
    self:StopMovingOrSizing()
    local point, _, relPoint, x, y = self:GetPoint()
    GrayQuestLevelDB.pos = { point, relPoint, x, y }
end)

frame:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
    GameTooltip:AddLine("Gray Quest Level")
    GameTooltip:AddLine("Quests at the green number or above give normal XP.", 1, 1, 1, true)
    GameTooltip:AddLine("Quests at the gray number or below are gray.", 1, 1, 1, true)
    local kills, remaining, gain = ComputeKills()
    if kills and gain then
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine(("Last XP gain: %d  |  %d XP to go"):format(gain, remaining), 1, 1, 1)
    end
    GameTooltip:AddLine("Drag to move  |  /gql lock", 0.6, 0.6, 0.6)
    GameTooltip:Show()
end)
frame:SetScript("OnLeave", function() GameTooltip:Hide() end)

local function Update()
    -- Line 1: quest levels
    local ok, _, lowestGreen, highestGray = pcall(Compute)
    if not ok or not lowestGreen then
        questText:SetText("|cffff5555Gray level: unavailable|r")
    elseif highestGray < 1 then
        questText:SetText("|cff40c040Green: all|r  |cff808080-|r  |cff9d9d9dno gray yet|r")
    else
        questText:SetText(("|cff40c040Green %d+|r  |cff808080-|r  |cff9d9d9dGray %d-|r")
            :format(lowestGreen, highestGray))
    end

    -- Line 2: kills to level. When `kills` is nil the second return is the
    -- reason string rather than an XP amount.
    local ok2, kills, reason = pcall(ComputeKills)
    if not ok2 then
        killText:SetText("|cff808080Kills to level: ?|r")
    elseif kills then
        killText:SetText(("Kills to level: |cffffd100%d|r"):format(kills))
    else
        if reason == "max level" then
            killText:SetText("|cff808080Max level|r")
        elseif reason == "xp off" then
            killText:SetText("|cff808080XP gain off|r")
        else
            killText:SetText("|cff808080Kills to level: ?|r")
        end
    end

    frame:SetWidth(math.max(140,
        math.max(questText:GetStringWidth(), killText:GetStringWidth()) + 20))
end

-- ---------------------------------------------------------------------------
-- Events
-- ---------------------------------------------------------------------------

local function SafeRegister(event)
    pcall(frame.RegisterEvent, frame, event) -- unknown events throw on this client
end

SafeRegister("PLAYER_ENTERING_WORLD")
SafeRegister("PLAYER_LEVEL_UP")
SafeRegister("PLAYER_LEVEL_CHANGED")
SafeRegister("UNIT_LEVEL")
SafeRegister("PLAYER_XP_UPDATE")
SafeRegister("DISABLE_XP_GAIN")
SafeRegister("ENABLE_XP_GAIN")

frame:SetScript("OnEvent", function(_, event, arg1)
    if event == "PLAYER_ENTERING_WORLD" then
        ApplyPosition()
        SampleXP() -- establish the baseline; no gain recorded from this one
        Update()
    elseif event == "PLAYER_XP_UPDATE" then
        SampleXP()
        Update()
    elseif event == "PLAYER_LEVEL_UP" or event == "PLAYER_LEVEL_CHANGED" then
        pendingLevelUp = true
        C_Timer.After(0.5, function() SampleXP(); Update() end)
    elseif event == "UNIT_LEVEL" then
        if arg1 == "player" then C_Timer.After(0.5, Update) end
    else
        Update()
    end
end)

-- Belt and braces: the level events above are only as reliable as this build's
-- event list, and an event that doesn't exist here fails to register silently
-- (SafeRegister swallows the throw). A cheap poll means the quest levels follow
-- your character within a couple of seconds no matter which events survived.
local sinceCheck, lastSeenLevel = 0, nil
frame:SetScript("OnUpdate", function(_, elapsed)
    sinceCheck = sinceCheck + (elapsed or 0)
    if sinceCheck < 2 then return end
    sinceCheck = 0
    local level = PlayerLevel()
    if level ~= lastSeenLevel then
        lastSeenLevel = level
        Update()
    end
end)

-- ---------------------------------------------------------------------------
-- Slash commands
-- ---------------------------------------------------------------------------

SLASH_GRAYQUESTLEVEL1 = "/gql"
SlashCmdList.GRAYQUESTLEVEL = function(msg)
    msg = (msg or ""):lower():match("^%s*(.-)%s*$")
    local cmd, rest = msg:match("^(%S+)%s*(.*)$")

    if cmd == "lock" then
        GrayQuestLevelDB.locked = not GrayQuestLevelDB.locked
        print("|cff40c040Gray Quest Level|r: " .. (GrayQuestLevelDB.locked and "locked" or "unlocked"))
    elseif cmd == "reset" then
        GrayQuestLevelDB.pos = nil
        ApplyPosition()
    elseif cmd == "hide" then
        frame:Hide()
    elseif cmd == "show" then
        frame:Show(); Update()
    elseif cmd == "calibrate" then
        -- "the highest gray level I can actually see in my log is N"
        local observed = tonumber(rest)
        if rest == "off" or rest == "reset" then
            GrayQuestLevelDB.offset = 0
            Update()
            print("|cff40c040Gray Quest Level|r: offset cleared.")
        elseif not observed then
            print("|cff40c040Gray Quest Level|r: usage /gql calibrate <highest gray level you see>,"
                .. " or /gql calibrate off")
        else
            GrayQuestLevelDB.offset = 0
            local _, _, computed, source = Compute()
            if not computed then
                print("|cff40c040Gray Quest Level|r: nothing to calibrate against on this client.")
            elseif source == "colors" and computed ~= observed then
                -- Don't paper over this. The colour API is what the quest log
                -- colours with, so a disagreement is a real finding, not
                -- something to hide behind a fudge factor.
                print(("|cff40c040Gray Quest Level|r: the game's own colour API says gray %d, you see gray %d.")
                    :format(computed, observed))
                print("  That shouldn't happen - please report it. Offset NOT applied.")
            elseif source == "colors" then
                print("|cff40c040Gray Quest Level|r: already matches your quest log, nothing to correct.")
            else
                GrayQuestLevelDB.offset = observed - computed
                Update()
                print(("|cff40c040Gray Quest Level|r: %s calibrated, offset %+d.")
                    :format(tostring(source), GrayQuestLevelDB.offset))
            end
        end
    elseif cmd == "source" then
        if rest == "auto" or rest == "table" or rest == "range" or rest == "colors" then
            GrayQuestLevelDB.source = rest
            Update()
            local _, lowestGreen, highestGray = Compute()
            print(("|cff40c040Gray Quest Level|r: source %s -> green %s+, gray %s-")
                :format(rest, tostring(lowestGreen), tostring(highestGray)))
        else
            print("|cff40c040Gray Quest Level|r: usage /gql source auto | table | range | colors")
            print(("  currently: %s"):format(tostring(GrayQuestLevelDB.source or "auto")))
        end
    elseif cmd == "debug" then
        local level = PlayerLevel()
        print(("|cff40c040Gray Quest Level|r debug - player level %d"):format(level))
        print(("  UnitLevel: %s | UnitEffectiveLevel: %s"):format(
            tostring(SafeNumber(UnitLevel, "player")),
            tostring(SafeNumber(UnitEffectiveLevel, "player"))))
        for i = 1, #RANGE_FUNCS do
            local name = RANGE_FUNCS[i]
            print(("  %s: %s"):format(name,
                type(_G[name]) ~= "function" and "absent" or tostring(SafeNumber(_G[name], "player"))))
        end
        print(("  GetQuestDifficultyColor: %s"):format(
            type(GetQuestDifficultyColor) == "function" and "present" or "absent"))
        local _, lowestGreen, highestGray, source, byTable, byRange, byColors = Compute()
        print(("  table says gray %s (green %s+)"):format(
            tostring(byTable), byTable and tostring(byTable + 1) or "?"))
        print(("  range says gray %s (green %s+)"):format(
            tostring(byRange), byRange and tostring(byRange + 1) or "?"))
        print(("  colors say gray %s (green %s+)"):format(
            tostring(byColors), byColors and tostring(byColors + 1) or "?"))
        if (byRange and byRange ~= byTable) or (byColors and byColors ~= byTable) then
            print("  |cffff8800they DISAGREE - whichever matches your quest log is the right one|r")
            print("  |cffff8800switch with /gql source table | range | colors|r")
        end
        print(("  offset: %d | preference: %s"):format(
            tonumber(GrayQuestLevelDB.offset) or 0, tostring(GrayQuestLevelDB.source or "auto")))
        print(("  using %s -> green %s+, gray %s-"):format(
            tostring(source), tostring(lowestGreen), tostring(highestGray)))
    elseif cmd == "xp" then
        local n = tonumber(rest)
        if n and n > 0 then
            lastGain = n
            GrayQuestLevelDB.lastGain = n
            Update()
            print(("|cff40c040Gray Quest Level|r: using %d XP per kill until the next XP gain."):format(n))
        else
            print("|cff40c040Gray Quest Level|r: usage /gql xp <number>")
        end
    else
        local level, lowestGreen, highestGray = Compute()
        if lowestGreen and highestGray >= 1 then
            print(("|cff40c040Gray Quest Level|r: you are %d, green down to %d, gray at %d and below.")
                :format(level, lowestGreen, highestGray))
        elseif lowestGreen then
            print(("|cff40c040Gray Quest Level|r: you are %d, nothing is gray yet."):format(level))
        else
            print("|cff40c040Gray Quest Level|r: couldn't read the quest range on this client.")
        end

        local kills, remaining, gain = ComputeKills()
        if kills then
            print(("  %d XP to go, last gain %d, about %d kills."):format(remaining, gain, kills))
        elseif remaining == "max level" then
            print("  At max level.")
        elseif remaining == "xp off" then
            print("  XP gain is turned off for this character.")
        elseif remaining == "no xp data" then
            print("  This client won't hand over the XP values.")
        else
            print("  No XP gain seen yet this session - kill something, or use /gql xp <number>.")
        end
        print("  /gql lock | reset | hide | show | xp <n> | calibrate <n> | source <s> | debug")
    end
end
