-- Standalone, read-only Atlas viewer. It never uses the character PassiveSpec.
local locale = require("Modules.Localization")
local dkjson = require("dkjson")
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

function class:AtlasTab()
	self:ControlHost()
	self:Control()
	self.atlas = loadAtlas()
	self.tooltip = new("Tooltip"):Tooltip()
	self.marker = NewImageHandle()
	self.marker:Load("Assets/small_ring.png", "CLAMP")
	self:ResetView()
	self:Search("")
	self.controls.search = new("EditControl"):EditControl({"TOPLEFT", self, "TOPLEFT"},
		{ 12, 32, 200, 21 }, "", nil, nil, 128, function(text) self:Search(text) end, 14, false, true)
	self.controls.search.inactiveText = locale.Label("Search Atlas")
	self.controls.find = new("ButtonControl"):ButtonControl({"LEFT", self.controls.search, "RIGHT"},
		{ 5, 0, 83, 21 }, locale.Label("Find Next"), function() self:FindNext() end)
	self.controls.find.enabled = function() return #self.matches > 0 end
	self.controls.minus = new("ButtonControl"):ButtonControl({"LEFT", self.controls.find, "RIGHT"},
		{ 10, 0, 25, 21 }, "-", function() self:Zoom(1 / 1.35) end)
	self.controls.plus = new("ButtonControl"):ButtonControl({"LEFT", self.controls.minus, "RIGHT"},
		{ 4, 0, 25, 21 }, "+", function() self:Zoom(1.35) end)
	self.controls.reset = new("ButtonControl"):ButtonControl({"LEFT", self.controls.plus, "RIGHT"},
		{ 7, 0, 84, 21 }, locale.Label("Fit Atlas"), function() self:ResetView() end)
	return self
end

function class:ResetView()
	local b = self.atlas.bounds
	self.centerX, self.centerY = (b[1] + b[3]) / 2, (b[2] + b[4]) / 2
	self.zoom, self.dragging = 1, false
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
		tip:AddLine(13, "^xEAC37A" .. locale.Text("Atlas option") .. " " .. index)
		for _, stat in ipairs(option) do tip:AddLine(15, "^7" .. display(stat)) end
	end
	for _, reminder in ipairs(node.reminders) do tip:AddLine(13, "^8" .. display(reminder)) end
	if draft and not showOriginal and locale.language == "zh-CN" then
		tip:AddLine(12, "^xD1A85F" .. locale.Text("Preview translation · Hold Shift for English"))
	end
	return tip
end

function class:Draw(vp, events)
	local header = 62
	local w, h = vp.width, vp.height - header
	if w < 90 or h < 90 then return end
	self.x, self.y, self.width, self.height = vp.x, vp.y, vp.width, vp.height
	self:ProcessControlsInput(events, vp)
	local b = self.atlas.bounds
	self.baseScale = min(w / (b[3] - b[1] + 550), h / (b[4] - b[2] + 550))
	local cx, cy = GetCursorPos()
	local mx, my = cx - vp.x, cy - vp.y - header
	local overMap = inside(mx, my, w, h)
	for id, event in pairs(events) do
		if overMap and event.type == "KeyDown" and event.key == "LEFTBUTTON" then
			self.dragging, self.lastX, self.lastY = true, cx, cy
			events[id] = nil
		elseif overMap and event.type == "KeyUp" and (event.key == "WHEELUP" or event.key == "WHEELDOWN") then
			self:Zoom(event.key == "WHEELUP" and 1.25 or 0.8, mx - w / 2, my - h / 2)
			events[id] = nil
		end
	end
	local scale = self.baseScale * self.zoom
	if not IsKeyDown("LEFTBUTTON") then self.dragging = false end
	if self.dragging then
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
	SetDrawColor(0.31, 0.31, 0.33)
	for _, points in ipairs(self.atlas.edges) do
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
			local match = self.matchIds[node.id]
			if match then
				SetDrawColor(1, 0.78, 0.31, 0.9)
				DrawImage(self.marker, x - d, y - d, d * 2, d * 2)
			end
			SetDrawColor(1, 1, 1, (self.query == "" or match) and 1 or 0.57)
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
	local hint = self.query == "" and locale.Text("Drag to pan · Scroll to zoom · Hover for details") or
		string.format(locale.Text("Atlas matches: %d"), #self.matches)
	if vp.width >= 625 then locale.DrawRaw(vp.x + vp.width - 13, vp.y + 11, "RIGHT", 13, "VAR", "^8" .. hint) end
	self:DrawControls(vp)
	self.hoverNode = hover
	if hover then self:NodeTooltip(hover, vp.width):Draw(cx, cy, 5, 12, vp) end
end
