local locale = { language = "en" }
local messages, displayEntries, numberTemplates, flaskBases
local gameTerms = { }
local displayCache, cacheSize = { }, 0
local marker = "\1"

function locale.SetLanguage(language)
	locale.language = language == "zh-CN" and "zh-CN" or "en"
	if locale.language == "zh-CN" and not messages then
		messages = require("Locales.zhCN")
	end
end

local function leadingColours(text)
	local last = 1
	while true do
		local part = text:sub(last)
		local colour = part:match("^(%^x%x%x%x%x%x%x)") or part:match("^(%^%d)")
		if not colour then
			return text:sub(1, last - 1), part
		end
		last = last + #colour
	end
end

function locale.Text(text)
	if locale.language ~= "zh-CN" or type(text) ~= "string" then
		return text
	end
	if messages[text] then
		return messages[text]
	end
	local prefix, content = leadingColours(text)
	return prefix .. (messages[content] or content)
end

function locale.Label(text)
	return function() return locale.Text(text) end
end

local function dictionary(category)
	if not gameTerms[category] then
		local file = io.open("Locales/Game/" .. category .. ".json", "rb")
		local data
		if file then
			data = require("dkjson").decode(file:read("*a"))
			file:close()
		end
		gameTerms[category] = type(data) == "table" and type(data.entries) == "table" and data.entries or { }
	end
	return gameTerms[category]
end

-- Display names are independent of parser keys, item text and save data.
function locale.Term(category, text)
	if locale.language ~= "zh-CN" or type(text) ~= "string" then
		return text
	end
	return dictionary(category)[text] or text
end

function locale.PassiveName(id, name)
	if locale.language ~= "zh-CN" or type(name) ~= "string" then return name end
	return dictionary("tree_names")[tostring(id) .. "\t" .. name:match("^%s*(.-)%s*$")] or locale.Term("passives", name)
end

-- Retain the source argument order so translations can reorder numbered values.
local function placeholders(text, hash)
	local order = { }
	local shaped = text:gsub("{(%d+)}", function(index)
		order[#order + 1] = tonumber(index) + 1
		return marker
	end)
	if hash and #order == 0 then
		shaped = text:gsub("#", function()
			order[#order + 1] = #order + 1
			return marker
		end)
	end
	return shaped, order
end

local function numericShape(text)
	local args = { }
	local parts = { }
	local cursor = 1
	while true do
		local start = text:find("[%d(]", cursor)
		if not start then
			parts[#parts + 1] = text:sub(cursor)
			return table.concat(parts), args
		end
		parts[#parts + 1] = text:sub(cursor, start - 1)
		local rest = text:sub(start)
		local num = rest:match("^(%(%-?%d+%.?%d*%-%-?%d+%.?%d*%))")
			or rest:match("^(%d[%d,]*%d%.%d+)")
			or rest:match("^(%d+%.%d+)")
			or rest:match("^(%d[%d,]*%d)")
			or rest:match("^(%d)")
		if num then
			args[#args + 1] = num
			parts[#parts + 1] = marker
			cursor = start + #num
		else
			parts[#parts + 1] = "("
			cursor = start + 1
		end
	end
end

local function insertTemplate(source, target, allowHash, preferred, supplemental)
	local sourceShape, from = placeholders(source, allowHash)
	local targetShape, to = placeholders(target, allowHash)
	if #from == 0 or #to == 0 then
		return
	end
	local available, consumed = { }, { }
	for _, n in ipairs(from) do available[n] = true end
	for _, n in ipairs(to) do
		if not available[n] then return end
		consumed[n] = true
	end
	for _, n in ipairs(from) do
		if not consumed[n] then return end
	end
	-- Fixed numbers in a template (e.g. 3.29) must never become variable.
	if sourceShape:find("%d") or sourceShape:find("{", 1, true) or targetShape:find("{", 1, true) then
		return
	end
	local priority = preferred and 4 or supplemental and 1 or source:find("{%d+}") and 3 or 2
	sourceShape = sourceShape:lower()
	local old = numberTemplates[sourceShape]
	if not old or priority > old.priority then
		numberTemplates[sourceShape] = { from = from, to = to, text = targetShape, priority = priority }
	elseif priority == old.priority and (old.text ~= targetShape or table.concat(old.from, ",") ~= table.concat(from, ",")
		or table.concat(old.to, ",") ~= table.concat(to, ",")) then
		old.ambiguous = true
	end
end

local function loadDisplayEntries()
	displayEntries, numberTemplates, flaskBases = { }, { }, { }
	for name in pairs(dictionary("items")) do
		if name:match(" Flask$") then flaskBases[#flaskBases + 1] = name end
	end
	table.sort(flaskBases, function(a, b)
		if #a == #b then return a < b end
		return #a > #b
	end)
	-- Read narrower dictionaries first to keep UI wording and name distinctions.
	for _, category in ipairs({"tree_effects", "gem_descriptions", "ui", "gems", "passives", "items", "uniques", "monsters", "tags", "stats", "game_stats_extra"}) do
		local supplemental = category == "game_stats_extra"
		local statTemplates = category == "stats" or supplemental
		for en, zh in pairs(dictionary(category)) do
			if type(zh) == "string" and zh:find("[\224-\239]") then
				if en:find("{%d+}") or (statTemplates and en:find("#", 1, true)) then
					insertTemplate(en, zh, statTemplates, false, supplemental)
				else
					displayEntries[en] = displayEntries[en] or zh
				end
			end
		end
	end
	for en, zh in pairs(messages) do
		if en:find("{%d+}") then
			insertTemplate(en, zh, false, true)
		end
	end
end

local function translate(content)
	local exact = messages[content] or displayEntries[content]
	if exact then return exact end
	if content:find("%d") and not content:find("%^") then
		local shaped, numbers = numericShape(content)
		local rule = numberTemplates[shaped:lower()]
		if rule and not rule.ambiguous and #numbers == #rule.from then
			local values = { }
			for i, n in ipairs(rule.from) do
				if values[n] and values[n] ~= numbers[i] then return end
				values[n] = numbers[i]
			end
			local index = 0
			return (rule.text:gsub(marker, function()
				index = index + 1
				return values[rule.to[index]]
			end))
		end
	end
end

local function withoutColours(text)
	return (text:gsub("%^x%x%x%x%x%x%x", ""):gsub("%^%d", ""))
end

local function translateFlask(text)
	if not text:find("Flask", 1, true) then return end
	for _, base in ipairs(flaskBases) do
		local first, last = text:find(base, 1, true)
		if first then
			local prefix = text:sub(1, first - 1)
			local suffix = text:sub(last + 1)
			if (prefix == "" or prefix:sub(-1) == " ") and (suffix == "" or suffix:match("^ of ")) then
				prefix = prefix:gsub("%s+$", "")
				suffix = suffix:gsub("^%s+", "")
				local tags = dictionary("tags")
				local zhPrefix = prefix == "" and "" or (tags[prefix] or prefix) .. " "
				local zhSuffix = suffix == "" and "" or " · " .. (tags[suffix] or suffix)
				return zhPrefix .. dictionary("items")[base] .. zhSuffix
			end
		end
	end
end

local function translateJoined(text)
	-- A tooltip summary can combine a count with the original skill name.
	local count, name, colon = text:match("^(%d+)x (.-)(:?)$")
	local gem = name and (dictionary("gems")[name] or dictionary("monsters")[name])
	if gem then
		return count .. " × " .. gem .. (colon == ":" and "：" or "")
	end
	if not text:find(", ", 1, true) then return end
	local parts, changed = { }, false
	local cursor = 1
	while cursor <= #text do
		local split = text:find(", ", cursor, true)
		local segment = text:sub(cursor, split and split - 1 or -1)
		local translated = translate(segment)
		parts[#parts + 1] = translated or segment
		changed = changed or translated ~= nil
		if not split then break end
		cursor = split + 2
	end
	if changed then return table.concat(parts, "，") end
end

local function displayLine(text)
	local prefix, body = leadingColours(text)
	local arrow, tail = body:match("^(<%- )(.*)$")
	if not arrow then
		arrow, tail = body:match("^(%-> )(.*)$")
	end
	if arrow then return prefix .. arrow .. locale.Display(tail) end
	local clean = body:gsub("%[[^%[%]|]+|([^%[%]]+)%]", "%1")
	local translated = translate(clean) or translate(clean:match("^%s*(.-)%s*$"))
	if not translated and body:find("%^") then
		translated = translate(withoutColours(body))
	end
	if not translated then
		local name = clean:match("^Allocates (.+)$")
		local passive = name and dictionary("passives")[name]
		if passive then translated = locale.Text("Allocates ") .. passive end
	end
	if not translated then
		local label, value = clean:match("^(Added Small Passive Skills.-:) (.+)$")
		local known = label and messages[label]
		if known then
			local stat = translate(value)
			if stat then translated = known .. stat end
		end
	end
	if not translated then translated = translateFlask(body) or translateJoined(body) end
	if translated then
		return prefix .. translated
	end
	-- Panel values are often assembled from a label, colon and preformatted
	-- value. Preserve the value, including its colour and unit.
	local label, colonColour, value = body:match("^(.-)(%^x%x%x%x%x%x%x):(.*)$")
	if not label then label, colonColour, value = body:match("^(.-)(%^%d):(.*)$") end
	if not label then label, value = body:match("^([^:]+):(.*)$") end
	if label then
		local known = messages[label .. ":"] or messages[label] or translate(label .. ":") or translate(label)
		if known then
			known = known:gsub(":$", "")
			-- A fullwidth colon is multiple bytes in Lua patterns.
			known = known:gsub("：$", "")
			return prefix .. known .. (colonColour or "") .. "：" .. value
		end
	end
	-- Modifier hints are appended to many item lines. Translate each side
	-- separately when the wording and the hint's boundaries are unambiguous.
	local mod, suffix = body:match("^(.-)(%s+%^8.+)$")
	if mod then
		local suffixSpace, hint = suffix:match("^(%s+)(.+)$")
		return prefix .. (translate(mod) or mod) .. suffixSpace .. locale.Text(hint)
	end
	return text
end

function locale.Display(text)
	if locale.language ~= "zh-CN" or type(text) ~= "string" or not text:find("[A-Za-z]") then
		return text
	end
	local cached = displayCache[text]
	if cached then return cached end
	if not displayEntries then loadDisplayEntries() end
	local result = messages[text] or displayEntries[text]
	if not result then
		if text:find("\n", 1, true) then
			result = text:gsub("[^\n]+", displayLine)
		else
			result = displayLine(text)
		end
	end
	if #text <= 4096 then
		if cacheSize >= 8192 then displayCache, cacheSize = { }, 0 end
		displayCache[text] = result
		cacheSize = cacheSize + 1
	end
	return result
end

-- Keep editable text, identifiers and user names literal, while still using
-- the CJK font when available.
function locale.DrawRaw(...)
	return (locale.drawRaw or DrawString)(...)
end

function locale.WidthRaw(...)
	return (locale.widthRaw or DrawStringWidth)(...)
end

-- Fit CJK tooltips without depending on spaces between words or breaking UTF-8.
function locale.WrapCjk(text, width, measure)
	local lines, line, colour, cursor = { }, "", "", 1
	while cursor <= #text do
		local remaining = text:sub(cursor)
		local code = remaining:match("^(%^x%x%x%x%x%x%x)") or remaining:match("^(%^%d)")
		if code then
			colour = code
			line = line .. code
			cursor = cursor + #code
		else
			local token = remaining:match("^[\194-\244][\128-\191]+")
				or remaining:match("^[A-Za-z0-9%.%%/]+") or remaining:sub(1, 1)
			if measure(line) > 0 and measure(line .. token) > width then
				lines[#lines + 1] = line
				line = colour
			end
			if token ~= " " or measure(line) > 0 then line = line .. token end
			cursor = cursor + #token
		end
	end
	lines[#lines + 1] = line
	return lines
end

return locale
