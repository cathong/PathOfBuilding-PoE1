-- Atlas planner. It never uses the character PassiveSpec.
local locale = require("Modules.Localization")
local dkjson = require("dkjson")
local AtlasPlan = require("Modules.AtlasPlan")
local min, max, sqrt = math.min, math.max, math.sqrt
local shared

local function loadJSON(path)
	local file = assert(io.open(path, "rb"))
	local raw = file:read("*a")
	file:close()
	return assert(dkjson.decode(raw))
end

local function loadAtlas()
	if not shared then
		local prefix = "Data/Atlas/3_30/"
		local atlas = loadJSON(prefix .. "tree.json")
		atlas.text = loadJSON("Locales/Atlas/3_30.json")
		atlas.draft = { }
		for _, entry in ipairs(atlas.text.drafts) do atlas.draft[entry] = true end
		for _, sheet in pairs(atlas.sheets) do
			sheet.handle = NewImageHandle()
			sheet.handle:Load(prefix .. sheet.file, "CLAMP")
		end
		shared = atlas
	end
	return shared
end

local function translated(atlas, english)
	if locale.language == "zh-CN" then
		return atlas.text.entries[english] or locale.Text(english)
	end
	return english
end

local function inside(x, y, w, h)
	return x >= 0 and x < w and y >= 0 and y < h
end

local function line(x1, y1, x2, y2, width)
	local dx, dy = x2 - x1, y2 - y1
	local len = sqrt(dx * dx + dy * dy)
	if len > 0 then
		local nx, ny = -dy * width / len, dx * width / len
		DrawImageQuad(nil, x1 + nx, y1 + ny, x2 + nx, y2 + ny, x2 - nx, y2 - ny, x1 - nx, y1 - ny)
	end
end

local function sprite(atlas, key, x, y, diameter)
	local icon = atlas.icons[key]
	if not icon then return false end
	local sheet = atlas.sheets[icon[1]]
	local u, v, w, h = icon[2], icon[3], icon[4], icon[5]
	local scale = diameter / max(w, h)
	DrawImage(sheet.handle, x - w * scale / 2, y - h * scale / 2, w * scale, h * scale,
		u / sheet.width, v / sheet.height, (u + w) / sheet.width, (v + h) / sheet.height)
	return true
end

local size = { start = 240, normal = 62, notable = 92, keystone = 137, mastery = 134, wormhole = 144 }
local frame = { normal = "frameNormal", notable = "frameNotable", keystone = "frameKeystone", wormhole = "frameWormhole" }
local class = newClass("AtlasTab", "ControlHost", "Control")

function class:AtlasTab(build)
	self:ControlHost()
	self:Control()
	self.atlas = loadAtlas()
	self.build = build
	self.plan = AtlasPlan.new(self.atlas)
	self.showTotals = true
	self.tooltip = new("Tooltip"):Tooltip()
	self.marker = NewImageHandle()
	self.marker:Load("Assets/small_ring.png", "CLAMP")
	self:ResetView()
	self:Search("")
	self.controls.search = new("EditControl"):EditControl({"TOPLEFT", self, "TOPLEFT"},
		{ 12, 32, 200, 21 }, "", nil, nil, 128, function(text) self:Search(text) end, 14, false, true)
	self.controls.search.inactiveText = locale.Label("Search Atlas")
	self.controls.search.width = function() return max(85, min(200, (self.width or 720) - 375)) end
	self.controls.find = new("ButtonControl"):ButtonControl({"LEFT", self.controls.search, "RIGHT"},
		{ 5, 0, 83, 21 }, locale.Label("Find Next"), function() self:FindNext() end)
	self.controls.find.enabled = function() return #self.matches > 0 end
	self.controls.minus = new("ButtonControl"):ButtonControl({"LEFT", self.controls.find, "RIGHT"},
		{ 10, 0, 25, 21 }, "-", function() self:Zoom(1 / 1.35) end)
	self.controls.plus = new("ButtonControl"):ButtonControl({"LEFT", self.controls.minus, "RIGHT"},
		{ 4, 0, 25, 21 }, "+", function() self:Zoom(1.35) end)
	self.controls.reset = new("ButtonControl"):ButtonControl({"LEFT", self.controls.plus, "RIGHT"},
		{ 7, 0, 84, 21 }, locale.Label("Fit Atlas"), function() self:ResetView() end)
	self.controls.totals = new("ButtonControl"):ButtonControl({"TOPRIGHT", self, "TOPRIGHT"},
		{ -12, 32, 105, 21 }, locale.Label("Atlas Totals"), function() self.showTotals = not self.showTotals end)
	self.controls.totals.locked = function() return self.showTotals end
	self.controls.totals.shown = function() return self.width and self.width >= 470 end
	self.controls.summaryScroll = new("ScrollBarControl"):ScrollBarControl({"TOPRIGHT", self, "TOPRIGHT"},
		{ -5, 116, 14, 0 }, 72, "VERTICAL", true)
	self.controls.summaryScroll.height = function() return max(1, (self.height or 120) - 121) end
	self.controls.summaryScroll.shown = function() return (self.summaryWidth or 0) > 0 and self.controls.summaryScroll.enabled end
	return self
end

function class:ResetView()
	local b = self.atlas.bounds
	self.centerX, self.centerY = (b[1] + b[3]) / 2, (b[2] + b[4]) / 2
	self.zoom, self.dragging, self.pressed = 1, false, false
end

function class:Search(text)
	self.query = text:match("^%s*(.-)%s*$"):lower()
	self.matches, self.matchIds, self.matchIndex = { }, { }, 0
	if self.query == "" then return end
	local function matches(value)
		return value:lower():find(self.query, 1, true)
			or (self.atlas.text.entries[value] or ""):lower():find(self.query, 1, true)
	end
	for _, node in ipairs(self.atlas.nodes) do
		local match = matches(node.name)
		for _, list in ipairs({ node.stats, node.reminders }) do
			for _, value in ipairs(list) do match = match or matches(value) end
		end
		for _, option in ipairs(node.options) do
			for _, value in ipairs(option) do match = match or matches(value) end
		end
		if match then
			self.matches[#self.matches + 1] = node
			self.matchIds[node.id] = true
		end
	end
end

function class:FindNext()
	if #self.matches == 0 then return end
	self.matchIndex = self.matchIndex % #self.matches + 1
	local node = self.matches[self.matchIndex]
	self.centerX, self.centerY = node.x, node.y
	self.zoom = max(self.zoom, 3.25)
end

function class:Zoom(multiplier, x, y)
	local nextZoom = max(1, min(14, self.zoom * multiplier))
	if x and self.baseScale then
		local offset = (1 / self.zoom - 1 / nextZoom) / self.baseScale
		self.centerX = self.centerX + x * offset
		self.centerY = self.centerY + y * offset
	end
	self.zoom = nextZoom
end

function class:SetNode(id, option)
	local before = self.plan.revision
	local ok, reason = self.plan:Allocate(id, option)
	self.status = not ok and reason or nil
	if self.plan.revision ~= before then self.build.modFlag = true end
	return ok
end

function class:ClickNode(node, button)
	self.status = nil
	if button == "RIGHTBUTTON" then
		local ok, reason = self.plan:Refund(node.id)
		if ok then self.build.modFlag = true else self.status = reason end
		return
	end
	if self.plan.selected[node.id] ~= nil and #node.options == 0 then return end
	local ok, reason = self.plan:CanAllocate(node.id)
	if not ok then self.status = reason return end
	if #node.options == 0 then self:SetNode(node.id) return end
	local labels, controls = { }, { }
	local index = 1
	for i, list in ipairs(node.options) do
		local translatedList = { }
		for _, stat in ipairs(list) do translatedList[#translatedList + 1] = translated(self.atlas, stat) end
		labels[i] = i .. ". " .. table.concat(translatedList, " / ")
		if self.plan.selected[node.id] == node.optionIds[i] then index = i end
	end
	local width = min(645, main.screenW - 40)
	controls.options = new("DropDownControl"):DropDownControl({"TOPLEFT", nil, "TOPLEFT"}, { 12, 35, width - 24, 23 }, labels)
	controls.options:SetSel(index, true)
	controls.options.tooltipFunc = function(tip, _, _, value)
		tip:Clear()
		tip.maxWidth = min(520, width - 20)
		if value then tip:AddLine(15, value) end
	end
	controls.apply = new("ButtonControl"):ButtonControl(nil, { -100, 79, 90, 22 }, locale.Label("Apply"), function()
		self:SetNode(node.id, node.optionIds[controls.options.selIndex])
		main:ClosePopup()
	end)
	controls.cancel = new("ButtonControl"):ButtonControl(nil, { 10, 79, 90, 22 }, locale.Label("Cancel"), function() main:ClosePopup() end)
	main:OpenPopup(width, 110, translated(self.atlas, node.name), controls, "apply", "options", "cancel")
end

local function amount(value)
	return string.format("%.8f", math.abs(value)):gsub("0+$", ""):gsub("%.$", "")
end

local function withTotal(text, number, value, kind)
	if not number then return end
	local matches = 0
	local result = text:gsub(kind == "percent" and "(%d+%.?%d*)(%%)" or "(%d+%.?%d*)()", function(n, suffix)
		if tonumber(n) == tonumber(number) then
			matches = matches + 1
			return value .. (type(suffix) == "string" and suffix or "")
		end
		return n .. (type(suffix) == "string" and suffix or "")
	end)
	if matches == 1 then return result end
end

function class:SummaryLines(width)
	local original = locale.language == "zh-CN" and IsKeyDown("SHIFT")
	local key = table.concat({ self.plan.revision, width, locale.language, tostring(original) }, ":")
	if self.summaryKey == key then return self.summaryLines end
	local lines = { }
	local function add(text, color)
		for _, lineText in ipairs(locale.WrapCjk(color .. text, width, function(value)
			return locale.WidthRaw(14, "VAR", value)
		end)) do
			lines[#lines + 1] = lineText
		end
	end
	local function display(text) return original and text or translated(self.atlas, text) end
	local function qualifier(chosen)
		if not chosen then return "" end
		local list = { }
		for _, value in ipairs(chosen) do list[#list + 1] = display(value) end
		return " — " .. table.concat(list, " / ")
	end
	local totals, details = self.plan:Summary()
	if self.plan.used == 0 then
		add(locale.Text("Allocate Atlas nodes to see their modifiers."), "^8")
	end
	if #totals > 0 then
		add(locale.Text("Combined numeric modifiers"), "^xEAC37A")
		for _, row in ipairs(totals) do
			local example = (row.value < 0 and row.negative or row.positive) or row.negative
			local text = display(example.text)
			local suffix = row.sources > 1 and ("  ^8×" .. row.sources) or ""
			if row.sources > 1 then
				local total = amount(row.value)
				local updated = withTotal(text, example.number, total, row.kind)
				if updated then
					text = updated
				else
					local n = (row.value < 0 and "-" or "+") .. total .. (row.kind == "percent" and "%" or "")
					text = string.format(locale.Text("Atlas total %s · Example: %s"), n, text)
				end
			end
			add(text .. qualifier(row.chosen) .. suffix, "^7")
		end
	end
	if #details > 0 then
		if #totals > 0 then lines[#lines + 1] = "" end
		add(locale.Text("Separate effects"), "^xEAC37A")
		for _, row in ipairs(details) do
			add(display(row.node) .. " · " .. display(row.text) .. qualifier(row.chosen), "^7")
		end
	end
	self.summaryKey, self.summaryLines = key, lines
	return lines
end

function class:DrawSummary(x, y, w, h)
	if w <= 0 then return end
	SetDrawColor(0.11, 0.12, 0.15)
	DrawImage(nil, x, y, w, h)
	SetDrawColor(0.29, 0.28, 0.27)
	DrawImage(nil, x, y, 1, h)
	locale.DrawRaw(x + 12, y + 8, "LEFT", 16, "VAR", "^xEAC37A" .. locale.Text("Atlas Totals"))
	local lines = self:SummaryLines(w - 36)
	local scroll = self.controls.summaryScroll
	local rowHeight = 18
	local height = h - 38
	scroll:SetContentDimension(#lines * rowHeight, height)
	SetViewport(x + 12, y + 33, w - 34, height)
	local start = math.floor(scroll.offset / rowHeight) + 1
	for i = start, min(#lines, start + math.ceil(height / rowHeight)) do
		locale.DrawRaw(0, (i - 1) * rowHeight - scroll.offset, "LEFT", 14, "VAR", lines[i])
	end
	SetViewport()
end

function class:NodeTooltip(node, width)
	local tip = self.tooltip
	tip:Clear()
	tip.maxWidth = min(510, width - 12)
	local showOriginal = locale.language == "zh-CN" and IsKeyDown("SHIFT")
	local draft = false
	local function display(text)
		draft = draft or self.atlas.draft[text]
		return showOriginal and text or translated(self.atlas, text)
	end
	tip:AddLine(18, "^xEAC37A" .. display(node.name))
	if not showOriginal and locale.language == "zh-CN" and translated(self.atlas, node.name) ~= node.name then
		tip:AddLine(12, "^8" .. node.name)
	end
	for _, stat in ipairs(node.stats) do tip:AddLine(15, "^7" .. display(stat)) end
	for index, option in ipairs(node.options) do
		tip:AddSeparator(4)
		local selected = self.plan.selected[node.id] == node.optionIds[index]
		tip:AddLine(13, (selected and "^xA8D687" or "^xEAC37A") .. locale.Text("Atlas option") .. " " .. index
			.. (selected and (" · " .. locale.Text("Selected")) or ""))
		for _, stat in ipairs(option) do tip:AddLine(15, "^7" .. display(stat)) end
	end
	for _, reminder in ipairs(node.reminders) do tip:AddLine(13, "^8" .. display(reminder)) end
	if draft and not showOriginal and locale.language == "zh-CN" then
		tip:AddLine(12, "^xD1A85F" .. locale.Text("Preview translation · Hold Shift for English"))
	end
	return tip
end

function class:Draw(vp, events)
	local header = 83
	local h = vp.height - header
	if vp.width < 90 or h < 90 then return end
	self.x, self.y, self.width, self.height = vp.x, vp.y, vp.width, vp.height
	self.summaryWidth = self.showTotals and vp.width >= 470 and min(430, max(218, math.floor(vp.width * 0.35))) or 0
	local w = vp.width - self.summaryWidth
	self:ProcessControlsInput(events, vp)
	local b = self.atlas.bounds
	self.baseScale = min(w / (b[3] - b[1] + 550), h / (b[4] - b[2] + 550))
	local cx, cy = GetCursorPos()
	local mx, my = cx - vp.x, cy - vp.y - header
	local overMap = inside(mx, my, w, h)
	local overSummary = self.summaryWidth > 0 and inside(mx - w, my, self.summaryWidth, h)
	local click
	for id, event in pairsSortByKey(events) do
		if overMap and event.type == "KeyDown" and event.key == "LEFTBUTTON" then
			self.pressed, self.dragging, self.lastX, self.lastY = true, false, cx, cy
			events[id] = nil
		elseif event.type == "KeyUp" and event.key == "LEFTBUTTON" and self.pressed then
			if overMap and not self.dragging and math.abs(self.lastX - cx) <= 4 and math.abs(self.lastY - cy) <= 4 then
				click = event.key
			end
			self.pressed, self.dragging = false, false
			events[id] = nil
		elseif overMap and event.type == "KeyUp" and event.key == "RIGHTBUTTON" then
			click = event.key
			events[id] = nil
		elseif event.type == "KeyUp" and (event.key == "WHEELUP" or event.key == "WHEELDOWN") then
			local up = event.key == "WHEELUP"
			if overMap then
				self:Zoom(up and 1.25 or 0.8, mx - w / 2, my - h / 2)
				events[id] = nil
			elseif overSummary then
				self.controls.summaryScroll:Scroll(up and -1 or 1)
				events[id] = nil
			end
		end
	end
	local scale = self.baseScale * self.zoom
	if not IsKeyDown("LEFTBUTTON") then self.pressed, self.dragging = false, false end
	if self.pressed and (self.dragging or math.abs(self.lastX - cx) > 4 or math.abs(self.lastY - cy) > 4) then
		self.dragging = true
		self.centerX = self.centerX + (self.lastX - cx) / scale
		self.centerY = self.centerY + (self.lastY - cy) / scale
		self.lastX, self.lastY = cx, cy
	end
	self.centerX = max(b[1], min(b[3], self.centerX))
	self.centerY = max(b[2], min(b[4], self.centerY))
	local ox, oy = w / 2 - self.centerX * scale, h / 2 - self.centerY * scale

	SetViewport(vp.x, vp.y + header, w, h)
	SetDrawColor(0.07, 0.083, 0.10)
	DrawImage(nil, 0, 0, w, h)
	for edgeIndex, points in ipairs(self.atlas.edges) do
		local ends = self.atlas.edgeEnds[edgeIndex]
		if self.plan:Active(ends[1]) and self.plan:Active(ends[2]) then
			SetDrawColor(0.92, 0.69, 0.31)
		else
			SetDrawColor(0.31, 0.31, 0.33)
		end
		for i = 1, #points - 2, 2 do
			local x1, y1 = points[i] * scale + ox, points[i + 1] * scale + oy
			local x2, y2 = points[i + 2] * scale + ox, points[i + 3] * scale + oy
			if max(x1, x2) >= 0 and min(x1, x2) <= w and max(y1, y2) >= 0 and min(y1, y2) <= h then
				line(x1, y1, x2, y2, max(0.42, min(1.5, 4 * scale)))
			end
		end
	end
	local hover, hoverDist
	for _, node in ipairs(self.atlas.nodes) do
		local x, y = node.x * scale + ox, node.y * scale + oy
		if x >= -28 and x <= w + 28 and y >= -28 and y <= h + 28 then
			local d = max(3, size[node.kind] * scale)
			local match, active = self.matchIds[node.id], self.plan:Active(node.id)
			if match or (active and node.kind ~= "start") then
				if active then SetDrawColor(1, 0.76, 0.34, 0.96) else SetDrawColor(0.56, 0.8, 1, 0.84) end
				DrawImage(self.marker, x - d, y - d, d * 2, d * 2)
			end
			SetDrawColor(1, 1, 1, (active or self.query == "" or match) and 1 or 0.57)
			if not sprite(self.atlas, node.icon, x, y, d) then
				SetDrawColor(match and 1 or 0.62, match and 0.75 or 0.55, 0.42)
				DrawImage(self.marker, x - d / 2, y - d / 2, d, d)
			end
			if frame[node.kind] and d >= 5 then sprite(self.atlas, frame[node.kind], x, y, d * 1.42) end
			if overMap and not self.dragging then
				local dist = (mx - x) ^ 2 + (my - y) ^ 2
				if dist <= max(5, d / 2 + 2) ^ 2 and (not hoverDist or dist < hoverDist) then
					hover, hoverDist = node, dist
				end
			end
		end
	end
	SetViewport()

	SetDrawColor(0.11, 0.12, 0.15)
	DrawImage(nil, vp.x, vp.y, vp.width, header)
	SetDrawColor(0.27, 0.27, 0.29)
	DrawImage(nil, vp.x, vp.y + header - 1, vp.width, 1)
	locale.DrawRaw(vp.x + 12, vp.y + 7, "LEFT", 18, "VAR", "^xEAC37A" .. locale.Text("Atlas Passive Tree") .. "  ^7" .. self.atlas.version)
	if click and hover then self:ClickNode(hover, click) end
	local points = string.format(locale.Text("Atlas points: %d / %d used · %d left"),
		self.plan.used, self.atlas.totalPoints, self.atlas.totalPoints - self.plan.used)
	locale.DrawRaw(vp.x + vp.width - 12, vp.y + 10, "RIGHT", 14, "VAR", "^xEAC37A" .. points)
	local hint = self.status and locale.Text(self.status) or
		(self.query == "" and locale.Text("Click to allocate · Right-click to refund · Drag or scroll to move") or
			string.format(locale.Text("Atlas matches: %d"), #self.matches))
	locale.DrawRaw(vp.x + 12, vp.y + 60, "LEFT", 13, "VAR", (self.status and "^xEAC37A" or "^8") .. hint)
	self:DrawSummary(vp.x + w, vp.y + header, self.summaryWidth, h)
	self:DrawControls(vp)
	self.hoverNode = hover
	if hover and not click then self:NodeTooltip(hover, vp.width):Draw(cx, cy, 5, 12, vp) end
end
