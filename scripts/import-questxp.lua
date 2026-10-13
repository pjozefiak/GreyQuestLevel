-- Merge quest XP values out of saved Wowhead quest-listing pages into
-- QuestXP.lua, grouped by zone.
--
--   lua5.1 scripts/import-questxp.lua "wowhead-dump/Forever Silverpine Forest Quests.html"
--   lua5.1 scripts/import-questxp.lua wowhead-dump/*.html      -- re-import everything
--   lua5.1 scripts/import-questxp.lua --dry-run <file>         -- report, write nothing
--
-- Fully offline: it reads the files it is given and writes QuestXP.lua. It
-- never contacts Wowhead.
--
-- Wowhead renders those tables client-side from a `new Listview({... data:[...]})`
-- blob, so the values are already structured -- each record carries "id", "xp",
-- "name" and "level". That is what this reads, not the rendered table.
--
-- Entries are kept in zone groups, in the order the zones were first imported,
-- sorted by quest ID within each zone. The grouping is read back out of
-- QuestXP.lua on each run, so re-importing preserves it. Existing values are
-- never overwritten; a disagreement is reported instead.

---@diagnostic disable: undefined-global

local SCRIPT_DIR = (arg and arg[0] or ""):match("^(.*)[/\\]") or "."
local QUESTXP_FILE = SCRIPT_DIR .. "/../QuestXP.lua"

local ZONE_MARKER = "^%s*%-%-%s*(.+)%s+%(zone%s+(%d+)%)%s*$"
local ENTRY_LINE = "^%s*%[(%d+)%]%s*=%s*(%d+)%s*,%s*(.*)$"

local dryRun = false
local inputPaths = {}
for i = 1, #arg do
    if arg[i] == "--dry-run" then dryRun = true else inputPaths[#inputPaths + 1] = arg[i] end
end

if #inputPaths == 0 then
    io.write("usage: lua5.1 scripts/import-questxp.lua [--dry-run] <page.html> [more.html ...]\n")
    io.write("       lua5.1 scripts/import-questxp.lua wowhead-dump/*.html   -- re-import everything\n")
    os.exit(2)
end

-- ---------------------------------------------------------------------------
-- Read QuestXP.lua, keeping its zone grouping
-- ---------------------------------------------------------------------------
-- Parsed as text rather than executed, because the zone headers are comments
-- and would be lost by loading it. The result is checked against a real load
-- at the end, so a parsing slip cannot quietly drop entries.

local header = {}        -- preamble lines, reproduced verbatim
local groups = {}        -- ordered: { zone = id or nil, name = string, ids = {}, entries = {} }
local groupByZone = {}
local zoneOf = {}        -- quest id -> group, for cross-zone duplicate detection
local droppedLines = {}

-- Entries are held in a map and sorted at write time, so moving one between
-- groups is just two assignments.
local function newGroup(zone, name, unattributed)
    local g = { zone = zone, name = name, entries = {}, unattributed = unattributed }
    groups[#groups + 1] = g
    if zone then groupByZone[zone] = g end
    return g
end

local function sortedIDs(entries)
    local ids = {}
    for id in pairs(entries) do ids[#ids + 1] = id end
    table.sort(ids)
    return ids
end

do
    local f = io.open(QUESTXP_FILE, "r")
    if not f then
        io.write(("cannot read %s\n"):format(QUESTXP_FILE))
        os.exit(1)
    end

    local inTable, current = false, nil
    for line in f:lines() do
        if not inTable then
            if line:match("^GrayQuestLevelQuestXP%s*=") then
                inTable = true
            else
                header[#header + 1] = line
            end
        elseif line:match("^}") then
            inTable = false
        else
            local name, zone = line:match(ZONE_MARKER)
            local id, xp, trailing = line:match(ENTRY_LINE)
            if zone then
                current = groupByZone[tonumber(zone)] or newGroup(tonumber(zone), name)
            elseif id then
                -- Entries before any zone marker: hand-added, or written by a
                -- version of this script that did not group. Either way they
                -- can be adopted by a zone that turns out to list them.
                current = current or newGroup(nil, "Not attributed to a zone", true)
                id = tonumber(id)
                current.entries[id] = { xp = tonumber(xp), comment = trailing:match("^%-%-%s*(.*)$") }
                zoneOf[id] = current
            elseif line:match("%S") then
                droppedLines[#droppedLines + 1] = line
            end
        end
    end
    f:close()

    if #header == 0 then
        io.write(("cannot find the GrayQuestLevelQuestXP assignment in %s\n"):format(QUESTXP_FILE))
        os.exit(1)
    end
end

local existingCount = 0
for _ in pairs(zoneOf) do existingCount = existingCount + 1 end

-- ---------------------------------------------------------------------------
-- Read the saved pages
-- ---------------------------------------------------------------------------

-- Wowhead JSON-escapes names: \/ for slashes, \uXXXX for anything non-ASCII.
local function unescape(s)
    s = s:gsub("\\/", "/"):gsub('\\"', '"')
    s = s:gsub("\\u(%x%x%x%x)", function(hex)
        local code = tonumber(hex, 16)
        return code < 128 and string.char(code) or "?"
    end)
    return (s:gsub("[\r\n]", " "))
end

-- The data array has to be walked rather than pattern-matched. Records carry a
-- nested "envChange":{...} so brace counting is needed, and the page holds
-- other Listviews (comments, the viewer's own profile) with their own "id"
-- fields. An earlier version paired each "id" with the following "xp"; a stray
-- profile id between a quest's id and its xp silently replaced a real quest
-- with a bogus entry. So: find the quest Listview, isolate its array, split it
-- into records, and only then read fields.
local function sliceArray(text, startPos)
    local depth, inString, escaped = 0, false, false
    for i = startPos, #text do
        local c = text:sub(i, i)
        if inString then
            if escaped then escaped = false
            elseif c == "\\" then escaped = true
            elseif c == '"' then inString = false end
        elseif c == '"' then inString = true
        elseif c == "[" or c == "{" then depth = depth + 1
        elseif c == "]" or c == "}" then
            depth = depth - 1
            if depth == 0 then return text:sub(startPos, i) end
        end
    end
end

-- Takes the array including its brackets; the interior is split, so a record's
-- own `{` sits at depth 1 rather than 2.
local function splitRecords(array)
    local interior = array:sub(2, -2)
    local records, depth, inString, escaped, from = {}, 0, false, false, nil
    for i = 1, #interior do
        local c = interior:sub(i, i)
        if inString then
            if escaped then escaped = false
            elseif c == "\\" then escaped = true
            elseif c == '"' then inString = false end
        elseif c == '"' then inString = true
        elseif c == "{" then
            depth = depth + 1
            if depth == 1 then from = i end
        elseif c == "}" then
            if depth == 1 and from then records[#records + 1] = interior:sub(from, i) end
            depth = depth - 1
        elseif c == "[" then depth = depth + 1
        elseif c == "]" then depth = depth - 1
        end
    end
    return records
end

local function titleCase(slug)
    local words = (slug:gsub("%-", " "))
    return (words:gsub("(%a[%w']*)", function(w) return w:sub(1, 1):upper() .. w:sub(2) end))
end

-- Zone from the listview's own "quest givers in <zone>" link, falling back to
-- the page title. Not the filename, which the user is free to rename.
local function zoneFromHtml(html)
    local id, slug = html:match("zone=(%d+)/([a-z0-9%-]+)")
    if id then return tonumber(id), titleCase(slug) end
    local title = html:match("<title>%s*(.-)%s*</title>")
    if title then
        return nil, (title:gsub("^Forever%s+", ""):gsub("%s+Quests$", ""))
    end
end

-- Returns zone id, zone name and the records, or nil plus a reason.
local function readPage(path)
    local f = io.open(path, "r")
    if not f then return nil, "cannot read it" end
    local html = f:read("*a")
    f:close()

    local listviewPos = html:find("new Listview%(%{template: 'quest'")
    if not listviewPos then return nil, "no quest Listview - is it a quest *listing* page?" end

    local arrayPos = html:find("data:%s*%[", listviewPos)
    local array = arrayPos and sliceArray(html, (html:find("%[", arrayPos)))
    if not array then return nil, "found the quest Listview but could not read its data array" end

    -- Within an isolated record "level" cannot collide with "reqlevel": the
    -- pattern includes the opening quote, and reqlevel's quote precedes "req".
    local records, count = {}, 0
    for _, record in ipairs(splitRecords(array)) do
        local id = tonumber(record:match("\"id\":(%d+)"))
        local xp = tonumber(record:match("\"xp\":(%d+)"))
        local name = record:match("\"name\":\"(.-)\"")
        local level = tonumber(record:match("\"level\":(%-?%d+)"))
        if id and xp and name then
            count = count + 1
            records[id] = { xp = xp, name = unescape(name), level = level }
        end
    end
    if count == 0 then return nil, "no quest records found" end

    local zone, zoneName = zoneFromHtml(html)
    return zone, zoneName, records, count
end

-- ---------------------------------------------------------------------------
-- Merge, page by page
-- ---------------------------------------------------------------------------

local totalAdded, totalAdopted, totalAgreed = 0, 0, 0
local conflicts, elsewhere, zeroXP = {}, {}, {}

for _, path in ipairs(inputPaths) do
    local zone, zoneName, records, count = readPage(path)
    if not records then
        io.write(("%s\n  SKIPPED: %s\n"):format(path, zoneName or "unreadable"))
    else
        local group = (zone and groupByZone[zone]) or newGroup(zone, zoneName)
        -- A zone imported before its name was derivable keeps the better name.
        if zoneName and zoneName ~= "" then group.name = zoneName end

        local added, adopted = 0, 0
        for _, id in ipairs(sortedIDs(records)) do
            local rec = records[id]
            local owner = zoneOf[id]
            local label = ("%s (%s)"):format(rec.name, tostring(rec.level or "?"))

            if rec.xp == 0 then
                zeroXP[#zeroXP + 1] = ("[%d] %s"):format(id, rec.name)
            elseif owner == group then
                if owner.entries[id].xp == rec.xp then
                    totalAgreed = totalAgreed + 1
                    owner.entries[id].comment = label -- name and level now known
                else
                    conflicts[#conflicts + 1] = ("[%d] %s: file says %d, page says %d")
                        :format(id, rec.name, owner.entries[id].xp, rec.xp)
                end
            elseif owner and owner.unattributed then
                -- Ungrouped entry that this zone lists: file it under the zone,
                -- keeping the value already there.
                local kept = owner.entries[id]
                if kept.xp ~= rec.xp then
                    conflicts[#conflicts + 1] = ("[%d] %s: file says %d, page says %d")
                        :format(id, rec.name, kept.xp, rec.xp)
                end
                owner.entries[id] = nil
                group.entries[id] = { xp = kept.xp, comment = label }
                zoneOf[id] = group
                adopted = adopted + 1
            elseif owner then
                -- A real cross-zone duplicate: breadcrumbs appear in two lists.
                elsewhere[#elsewhere + 1] =
                    ("[%d] %s: already under %s"):format(id, rec.name, owner.name)
            else
                group.entries[id] = { xp = rec.xp, comment = label }
                zoneOf[id] = group
                added = added + 1
            end
        end

        totalAdded = totalAdded + added
        totalAdopted = totalAdopted + adopted
        io.write(("%s\n  %s: %d records, %d new%s\n"):format(
            path,
            group.name .. (zone and (" (zone %d)"):format(zone) or ""),
            count, added,
            adopted > 0 and (", %d moved in from ungrouped"):format(adopted) or ""))
    end
end

io.write(("%d entries in QuestXP.lua before, %d added, %d regrouped, %d already present and agreeing\n")
    :format(existingCount, totalAdded, totalAdopted, totalAgreed))

for _, c in ipairs(conflicts) do io.write(("  CONFLICT %s - keeping the file's value\n"):format(c)) end
for _, c in ipairs(elsewhere) do io.write(("  SKIPPED  %s\n"):format(c)) end
for _, c in ipairs(zeroXP) do io.write(("  SKIPPED  %s: page lists no XP\n"):format(c)) end
for _, l in ipairs(droppedLines) do io.write(("  DROPPED  unrecognised line: %s\n"):format(l)) end

if totalAdded == 0 and totalAdopted == 0 and #droppedLines == 0 then
    io.write("  nothing to write\n")
    os.exit(0)
end

if dryRun then
    io.write("  --dry-run: not written\n")
    os.exit(0)
end

-- ---------------------------------------------------------------------------
-- Write it back out, grouped
-- ---------------------------------------------------------------------------

local lines = {}
for _, l in ipairs(header) do lines[#lines + 1] = l end
while lines[#lines] and not lines[#lines]:match("%S") do lines[#lines] = nil end
lines[#lines + 1] = ""
lines[#lines + 1] = "GrayQuestLevelQuestXP = {"

local written, groupsWritten = 0, 0
for _, group in ipairs(groups) do
    local ids = sortedIDs(group.entries)
    -- A group can end up empty once its entries are adopted by a real zone.
    if #ids > 0 then
        groupsWritten = groupsWritten + 1
        if groupsWritten > 1 then lines[#lines + 1] = "" end
        lines[#lines + 1] = group.zone
            and ("    -- %s (zone %d)"):format(group.name, group.zone)
            or ("    -- %s"):format(group.name)
        for _, id in ipairs(ids) do
            local e = group.entries[id]
            lines[#lines + 1] = ("    [%d] = %d,%s")
                :format(id, e.xp, e.comment and ("  -- " .. e.comment) or "")
            written = written + 1
        end
    end
end

lines[#lines + 1] = "}"
lines[#lines + 1] = ""

local body = table.concat(lines, "\n")

-- Confirm the result is loadable and complete before replacing the file.
local chunk, err = loadstring(body, "QuestXP.lua")
if not chunk then
    io.write(("refusing to write: generated file does not parse (%s)\n"):format(tostring(err)))
    os.exit(1)
end
GrayQuestLevelQuestXP = nil
chunk()
local reloaded = 0
for _ in pairs(GrayQuestLevelQuestXP or {}) do reloaded = reloaded + 1 end
if reloaded ~= written then
    io.write(("refusing to write: generated %d entries but only %d survive a load\n")
        :format(written, reloaded))
    os.exit(1)
end

local out = assert(io.open(QUESTXP_FILE, "w"))
out:write(body)
out:close()
io.write(("  wrote %d entries across %d zone group(s)\n"):format(written, groupsWritten))
