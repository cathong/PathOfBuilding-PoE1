local atlas = require("Locales.CJK.glyphs")
local utf8 = require("lua-utf8")
local nativeDraw, nativeWidth, nativeCursor = DrawString, DrawStringWidth, DrawStringCursorIndex
local textures = { }

-- Keep the native font for Latin text and use the same glyph advances for
-- measuring, drawing, and positioning the caret in mixed-language strings.
local function runs(line, height, font)
	local result, width, start, search = { }, 0, 1, 1
	local function add(first, last, glyph)
		if first <= last then
			local text = line:sub(first, last)
			local advance = glyph and math.ceil(glyph[10] * height) or nativeWidth(height, font, text)
			result[#result + 1] = { first = first, text = text, glyph = glyph, advance = advance }
			width = width + advance
		end
	end
	while true do
		local first, last = line:find("[\194-\244][\128-\191]+", search)
		if not first then break end
		local valid, codepoint = pcall(utf8.codepoint, line:sub(first, last))
		local glyph = valid and atlas.glyphs[codepoint]
		if glyph then
			add(start, first - 1)
			add(first, last, glyph)
			start = last + 1
		end
		search = last + 1
	end
	add(start, #line)
	return result, width
end

local function lastColor(text)
	local color
	for at in text:gmatch("()%^[x%d]") do
		color = text:match("^%^x%x%x%x%x%x%x", at) or text:match("^%^%d", at) or color
	end
	return color
end

function DrawStringWidth(height, font, text)
	if type(text) ~= "string" or not text:find("[\194-\244]") then
		return nativeWidth(height, font, text)
	end
	local width = 0
	for line in (text .. "\n"):gmatch("([^\n]*)\n") do
		local _, lineWidth = runs(line, height, font)
		width = math.max(width, lineWidth)
	end
	return width
end

function DrawString(x, y, align, height, font, text)
	if type(text) ~= "string" or not text:find("[\194-\244]") then
		return nativeDraw(x, y, align, height, font, text)
	end
	local r, g, b, a = GetDrawColor()
	local screenWidth = GetVirtualScreenSize()
	local color
	for line in (text .. "\n"):gmatch("([^\n]*)\n") do
		local parts, width = runs(line, height, font)
		local left = x
		if align == "CENTER" then
			left = math.floor((screenWidth - width) / 2 + x)
		elseif align == "RIGHT" then
			left = math.floor(screenWidth - width - x)
		elseif align == "CENTER_X" then
			left = math.floor(x - width / 2)
		elseif align == "RIGHT_X" then
			left = math.floor(x - width)
		end
		left = math.floor(left + 0.5)
		for _, part in ipairs(parts) do
			local glyph = part.glyph
			if color then SetDrawColor(color) end
			if glyph then
				local page, u0, v0, u1, v1, dx, dy, w, h = unpack(glyph)
				if not textures[page] then
					textures[page] = NewImageHandle()
					textures[page]:Load(atlas.pages[page], "CLAMP")
				end
				DrawImage(textures[page], left + dx * height, math.floor(y) + dy * height,
					w * height, h * height, u0, v0, u1, v1)
			else
				nativeDraw(left, y, "LEFT", height, font, part.text)
				color = lastColor(part.text) or color
			end
			left = left + part.advance
		end
		y = y + height
	end
	SetDrawColor(r, g, b, a)
end

function DrawStringCursorIndex(height, font, text, x, y)
	if type(text) ~= "string" or not text:find("[\194-\244]") or height <= 0 then
		return nativeCursor(height, font, text, x, y)
	end
	local offset = 0
	local row = math.max(0, math.floor(y / height))
	for line in (text .. "\n"):gmatch("([^\n]*)\n") do
		if row == 0 then
			local parts = runs(line, height, font)
			for _, part in ipairs(parts) do
				if x < part.advance then
				local index = part.glyph and (x < part.advance / 2 and 1 or #part.text + 1)
						or nativeCursor(height, font, part.text, x, 0)
					return offset + part.first - 1 + index
				end
				x = x - part.advance
			end
			return offset + #line + 1
		end
		offset = offset + #line + 1
		row = row - 1
	end
	return #text + 1
end

return true
