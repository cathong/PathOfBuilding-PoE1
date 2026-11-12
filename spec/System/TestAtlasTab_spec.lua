describe("3.30 Atlas viewer", function()
	local locale = require("Modules.Localization")

	it("opens after Compare, displays the Atlas, and leaves build XML unchanged", function()
		newBuild()
		build.skillsTab:PasteSocketGroup("Fireball 20/0  1")
		runCallback("OnFrame")
		local saved = build:SaveDB("code")
		local spec, output = build.spec, build.calcsTab.mainOutput.TotalDPS
		local button = build.controls.modeAtlas
		assert(button.anchor.control == build.controls.modeCompare or button:GetPos() > build.controls.modeCompare:GetPos())
		button:Click()
		runCallback("OnFrame")
		assert(not launch.promptMsg, launch.promptMsg)
		local viewer = assert(build.atlasTab)
		assert(build.viewMode == "ATLAS" and viewer.atlas.version == "3.30")
		assert(#viewer.atlas.nodes == 1116 and #viewer.atlas.edges == 1050)
		assert(build.spec == spec and build.calcsTab.mainOutput.TotalDPS == output)
		assert(build:SaveDB("code") == saved)
		build.controls.modeCompare:Click()
		runCallback("OnFrame")
		assert(build.viewMode == "COMPARE" and not launch.promptMsg)
	end)

	it("searches both languages, positions the map and shows localized effects", function()
		local original = locale.language
		locale.SetLanguage("zh-CN")
		newBuild()
		assert(build.controls.modeAtlas:GetProperty("label") == "异界天赋")
		build.controls.modeAtlas:Click()
		runCallback("OnFrame")
		local viewer = assert(build.atlasTab)
		viewer:Search("Thorough Exploration")
		assert(#viewer.matches == 1)
		viewer:Search("全面探险")
		assert(#viewer.matches == 1)
		viewer:FindNext()
		local node = viewer.matches[1]
		assert(node.id == 63753 and viewer.centerX == node.x and viewer.centerY == node.y)
		assert(viewer.zoom > 1)
		local tooltip = viewer:NodeTooltip(node, 730)
		local text = ""
		for _, line in ipairs(tooltip.lines) do text = text .. (line.text or "") end
		assert(text:find("全面探险", 1, true))
		assert(text:find("50", 1, true) and text:find("鬼灵", 1, true))
		viewer:Search("异界异象出现几率")
		assert(#viewer.matches > 0)
		viewer:ResetView()
		assert(viewer.zoom == 1)
		locale.SetLanguage(original)
	end)

	it("has Chinese names, effects, reminders and options for all nodes", function()
		newBuild()
		build.controls.modeAtlas:Click()
		runCallback("OnFrame")
		local atlas = assert(build.atlasTab).atlas
		local function translated(text)
			assert(text == "Atlas Start" or atlas.text.entries[text], text)
		end
		local withOptions = 0
		for _, node in ipairs(atlas.nodes) do
			translated(node.name)
			for _, stat in ipairs(node.stats) do translated(stat) end
			for _, stat in ipairs(node.reminders) do translated(stat) end
			if #node.options > 0 then withOptions = withOptions + 1 end
			for _, option in ipairs(node.options) do
				for _, stat in ipairs(option) do translated(stat) end
			end
		end
		assert(withOptions == 31)
	end)
end)
