local locale = { language = "en" }
local messages
local gameTerms = { }

function locale.SetLanguage(language)
	locale.language = language == "zh-CN" and "zh-CN" or "en"
	if locale.language == "zh-CN" and not messages then
		messages = require("Locales.zhCN")
	end
end

function locale.Text(text)
	if locale.language ~= "zh-CN" or type(text) ~= "string" then
		return text
	end
	if messages[text] then
		return messages[text]
	end
	local prefix, content = text:match("^(%^x%x%x%x%x%x%x)(.*)$")
	if not prefix then
		prefix, content = text:match("^(%^%d)(.*)$")
	end
	if prefix then
		return prefix .. (messages[content] or content)
	end
	return text
end

function locale.Label(text)
	return function() return locale.Text(text) end
end

-- These dictionaries only supply display names. The build and parser keep the
-- upstream English names, which are also used when a translation is missing.
function locale.Term(category, text)
	if locale.language ~= "zh-CN" or not text then
		return text
	end
	if not gameTerms[category] then
		local file = io.open("Locales/Game/" .. category .. ".json", "rb")
		if not file then
			gameTerms[category] = { }
		else
			local data = require("dkjson").decode(file:read("*a"))
			file:close()
			gameTerms[category] = data and data.entries or { }
		end
	end
	return gameTerms[category][text] or text
end

return locale
