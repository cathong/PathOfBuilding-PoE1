-- Atlas allocations are independent of player stats and character passive points.
local plan = { }
plan.__index = plan

function plan.new(atlas)
	if not atlas.byId then
		atlas.byId, atlas.links, atlas.starts = { }, { }, { }
		for _, node in ipairs(atlas.nodes) do
			atlas.byId[node.id], atlas.links[node.id] = node, { }
			if node.kind == "start" then atlas.starts[#atlas.starts + 1] = node.id end
		end
		for _, edge in ipairs(atlas.edgeEnds) do
			local a, b = edge[1], edge[2]
			table.insert(atlas.links[a], b)
			table.insert(atlas.links[b], a)
		end
		for _, links in pairs(atlas.links) do table.sort(links) end
	end
	return setmetatable({ atlas = atlas, selected = { }, used = 0, revision = 0 }, plan)
end

function plan:Active(id)
	return self.selected[id] ~= nil or self.atlas.byId[id].kind == "start"
end

local function allocatable(node)
	return node and node.kind ~= "start" and node.kind ~= "mastery"
end

function plan:CanAllocate(id)
	if not allocatable(self.atlas.byId[id]) then return false, "Atlas node cannot be allocated." end
	if self.selected[id] ~= nil then return true end
	if self.used >= self.atlas.totalPoints then return false, "Atlas point limit reached." end
	for _, other in ipairs(self.atlas.links[id]) do
		if self:Active(other) then return true end
	end
	return false, "Allocate a connected Atlas node first."
end

local function validOption(node, value)
	if #node.optionIds == 0 then return value == 0 end
	for _, optionId in ipairs(node.optionIds) do
		if value == optionId then return true end
	end
	return false
end

function plan:Allocate(id, option)
	local ok, reason = self:CanAllocate(id)
	if not ok then return false, reason end
	option = option or 0
	if not validOption(self.atlas.byId[id], option) then return false, "Choose one Atlas option." end
	if self.selected[id] == nil then self.used = self.used + 1 end
	if self.selected[id] ~= option then
		self.selected[id] = option
		self.revision = self.revision + 1
	end
	return true
end

local function reachable(atlas, selected, skip, limit)
	local queue, seen, kept, count = { }, { }, { }, 0
	for _, root in ipairs(atlas.starts) do
		queue[#queue + 1] = root
		seen[root] = true
	end
	local index = 1
	while queue[index] do
		for _, id in ipairs(atlas.links[queue[index]]) do
			if id ~= skip and selected[id] ~= nil and not seen[id] and count < limit then
				queue[#queue + 1] = id
				seen[id] = true
				kept[id] = selected[id]
				count = count + 1
			end
		end
		index = index + 1
	end
	return kept, count
end

function plan:Refund(id)
	if self.selected[id] == nil then return false end
	local _, count = reachable(self.atlas, self.selected, id, self.atlas.totalPoints)
	if count ~= self.used - 1 then return false, "Refund dependent Atlas nodes first." end
	self.selected[id] = nil
	self.used = self.used - 1
	self.revision = self.revision + 1
	return true
end

function plan:Load(xml)
	if xml.attrib.version ~= self.atlas.version then return end
	local selected = { }
	for _, child in ipairs(xml) do
		if child.elem == "Node" then
			local id, option = tonumber(child.attrib.id), tonumber(child.attrib.option) or 0
			local node = self.atlas.byId[id]
			if allocatable(node) and validOption(node, option) then selected[id] = option end
		end
	end
	self.selected, self.used = reachable(self.atlas, selected, nil, self.atlas.totalPoints)
	self.revision = self.revision + 1
end

function plan:Save()
	local xml = { elem = "AtlasPlan", attrib = { version = self.atlas.version } }
	for id, option in pairsSortByKey(self.selected) do
		xml[#xml + 1] = { elem = "Node", attrib = { id = tostring(id), option = option ~= 0 and tostring(option) or nil } }
	end
	return xml
end

local function normalized(s)
	return s:lower():gsub("%[([^%]]+)%]", "%1")
end

-- Group a single additive coefficient, leaving the full subject and conditions
-- in the grouping key. Thresholds/caps, alternatives and multipliers stay literal.
local function additive(text)
	local prefix, number, tail = text:match("^(.-)(%d+%.?%d*)(%%.*)$")
	if number and not prefix:match("%d%-$") then
		local suffix = normalized(tail)
		if suffix:find(" up to ", 1, true) or suffix:find(" maximum ", 1, true) or suffix:find(" minimum ", 1, true) then return end
		local inc = suffix:match("^%% increased (.+)$")
		local red = suffix:match("^%% reduced (.+)$")
		local value = tonumber(number)
		if inc or red then
			return "percent", normalized(prefix) .. "% increased/reduced " .. (inc or red), red and -value or value, number
		end
		if suffix:match("^%% chance ") or suffix:match("^%% surpassing chance ") or suffix:match("^%% additional chance ") then
			-- A leading '+' and no '+' both express an absolute chance modifier;
			-- other chance categories keep their own suffix.
			return "percent", normalized(prefix):gsub("%+$", "") .. suffix, value, number
		end
	end

	local before, count, after = text:match("^(.-)(%d+) (additional .+)$")
	if count and not before:find("%%") and not before:lower():find("up to ", 1, true)
		and not after:lower():find(" maximum ", 1, true) and not after:lower():find(" per ", 1, true) then
		return "flat", normalized(before .. "# " .. after), tonumber(count), count
	end
	before, after = text:match("^(.-)an? (additional .+)$")
	if before and not before:find("%%") and not after:lower():find(" per ", 1, true) then
		return "flat", normalized(before .. "# " .. after), 1
	end
	before, count, after = text:match("^(.-)%+(%d+) (.+)$")
	if count and not before:find("%%") and not after:find("%%") and not after:lower():find(" per ", 1, true) then
		return "flat", normalized(before .. "+# " .. after), tonumber(count), count
	end
end

local function optionFor(node, effect)
	for index, id in ipairs(node.optionIds) do
		if id == effect then return node.options[index] end
	end
end

-- Some options supply the noun for an unfinished stat description. Keep
-- the chosen subject attached so different targets can never be combined.
local function optionQualifier(text)
	local lower = text:lower()
	return lower:match(" certain ") or lower:match(" of type$") or lower:match(" always$")
		or lower:match(" to be$") or lower:match(" from$")
end

function plan:Summary()
	local grouped, totals, details = { }, { }, { }
	local function insert(text, node, chosen)
		local kind, key, value, number = additive(text)
		if kind then
			key = kind .. ":" .. key .. (chosen and " [" .. table.concat(chosen, " / ") .. "]" or "")
			local row = grouped[key]
			if not row then
				row = { kind = kind, key = key, value = 0, sources = 0, chosen = chosen }
				grouped[key] = row
				totals[#totals + 1] = row
			end
			row.value, row.sources = row.value + value, row.sources + 1
			local example = { text = text, number = number }
			if value >= 0 then row.positive = row.positive or example else row.negative = row.negative or example end
		else
			details[#details + 1] = { text = text, node = node.name, chosen = chosen }
		end
	end
	for id, choice in pairsSortByKey(self.selected) do
		local node = self.atlas.byId[id]
		local option = optionFor(node, choice)
		local hasQualifier = false
		for _, text in ipairs(node.stats) do
			if text ~= "Select a type of content to have additional chance to spawn" then
				local qualifier = option and optionQualifier(text) and option or nil
				insert(text, node, qualifier)
				hasQualifier = hasQualifier or qualifier ~= nil
			end
		end
		if option and not hasQualifier then
			for _, text in ipairs(option) do insert(text, node) end
		end
	end
	table.sort(totals, function(a, b)
		if a.sources ~= b.sources then return a.sources > b.sources end
		return a.key < b.key
	end)
	return totals, details
end

return plan
