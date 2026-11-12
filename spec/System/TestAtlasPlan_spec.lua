describe("3.30 Atlas allocation and totals", function()
	local AtlasPlan = require("Modules.AtlasPlan")
	local locale = require("Modules.Localization")

	local function atlasTab()
		newBuild()
		build.controls.modeAtlas:Click()
		runCallback("OnFrame")
		assert(not launch.promptMsg, launch.promptMsg)
		return assert(build.atlasTab)
	end

	local function allocatePath(plan, goal)
		local queue, back, i = { plan.atlas.starts[1] }, { }, 1
		back[queue[1]] = 0
		while queue[i] and not back[goal] do
			local id = queue[i]
			for _, nextId in ipairs(plan.atlas.links[id]) do
				if back[nextId] == nil then
					back[nextId] = id
					queue[#queue + 1] = nextId
				end
			end
			i = i + 1
		end
		local path, id = { }, goal
		while assert(back[id]) ~= 0 do
			path[#path + 1] = id
			id = back[id]
		end
		for i = #path, 1, -1 do
			id = path[i]
			assert(plan:Allocate(id, plan.atlas.byId[id].optionIds[1]))
		end
	end

	it("uses 150 official points, disallows disconnected nodes and preserves legal refunds", function()
		local planner = atlasTab().plan
		assert(planner.atlas.totalPoints == 150)
		assert(not planner:Allocate(29045))
		assert(not planner:Allocate(2461))
		assert(planner:Allocate(55117))
		assert(planner:Allocate(2461))
		assert(not planner:Refund(55117))
		assert(planner:Refund(2461))
		assert(planner:Refund(55117) and planner.used == 0)
		local atLimit
		repeat
			for _, node in ipairs(planner.atlas.nodes) do
				if planner.selected[node.id] == nil and planner:CanAllocate(node.id) then
					assert(planner:Allocate(node.id, node.optionIds[1]))
				end
			end
			atLimit = planner.used == planner.atlas.totalPoints
		until atLimit
		assert(planner.used == 150)
		for _, node in ipairs(planner.atlas.nodes) do
			if planner.selected[node.id] == nil and node.kind ~= "mastery" and node.kind ~= "start" then
				local ok, reason = planner:Allocate(node.id, node.optionIds[1])
				assert(not ok and reason == "Atlas point limit reached." and planner.used == 150)
				break
			end
		end
		local restored = AtlasPlan.new(planner.atlas)
		restored:Load(planner:Save())
		assert(restored.used == 150)
		for id, option in pairs(planner.selected) do assert(restored.selected[id] == option) end
	end)

	it("merges compatible values and keeps conditions, relative chance and special effects apart", function()
		local atlas = {
			version = "3.30", totalPoints = 150, edgeEnds = { {1, 2}, {1, 3}, {1, 4} },
			nodes = {
				{ id = 1, kind = "start", optionIds = { } },
				{ id = 2, kind = "normal", optionIds = { }, stats = {
					"2% increased Maps found in your Maps",
					"Your Maps have +25% Surpassing Chance to contain a Rogue Exile",
					"10% more Pack Size in your Maps",
					"Expeditions in your Maps have +1 Remnants",
				} },
				{ id = 3, kind = "normal", optionIds = { }, stats = {
					"3% increased Maps found in your Maps",
					"Your Maps have +50% Surpassing Chance to contain a Rogue Exile",
					"Your Maps have 50% increased chance to contain a Rogue Exile",
					"Expeditions in your Maps have +2 Remnants",
				} },
				{ id = 4, kind = "normal", optionIds = { }, stats = {
					"5% increased Maps found in your Maps per Explicit Modifier",
					"10% less Pack Size in your Maps",
					"Your Maps have 4% chance to contain a Rogue Exile",
				} },
			},
		}
		local planner = AtlasPlan.new(atlas)
		assert(planner:Allocate(2) and planner:Allocate(3) and planner:Allocate(4))
		local totals, details = planner:Summary()
		local values = { }
		for _, row in ipairs(totals) do values[row.key] = row.value end
		assert(values["percent:% increased/reduced maps found in your maps"] == 5)
		assert(values["percent:your maps have % surpassing chance to contain a rogue exile"] == 75)
		assert(values["percent:your maps have % increased/reduced chance to contain a rogue exile"] == 50)
		assert(values["percent:your maps have % chance to contain a rogue exile"] == 4)
		assert(values["percent:% increased/reduced maps found in your maps per explicit modifier"] == 5)
		assert(values["flat:expeditions in your maps have +# remnants"] == 3)
		assert(#totals == 6 and #details == 2)
	end)

	it("counts exactly one option, shows it in Chinese, and saves it independently of the build", function()
		local tab = atlasTab()
		local planner = tab.plan
		local playerDps = build.calcsTab.mainOutput.TotalDPS
		local node = planner.atlas.byId[19729]
		allocatePath(planner, node.id)
		local points = planner.used
		assert(not planner:Allocate(node.id, 999999))
		assert(tab:SetNode(node.id, node.optionIds[2]))
		assert(planner.used == points and build.modFlag)
		local totals, details = planner:Summary()
		local found
		for _, row in ipairs(details) do
			if row.node == node.name then found = row end
		end
		assert(found and #found.chosen == 1 and found.chosen[1] == "Unstable Breaches")
		local prior = locale.language
		locale.SetLanguage("zh-CN")
		local summary = table.concat(tab:SummaryLines(390), "\n")
		assert(summary:find("独立效果", 1, true) and summary:find("不稳定裂隙", 1, true))
		locale.SetLanguage(prior)
		local saved = build:SaveDB("code")
		assert(saved:find("<AtlasPlan", 1, true))
		assert(build.calcsTab.mainOutput.TotalDPS == playerDps)
		loadBuildFromXML(saved)
		assert(build.atlasTab.plan.selected[node.id] == node.optionIds[2])
		assert(build.atlasTab.plan.used == points)
		assert(build.calcsTab.mainOutput.TotalDPS == playerDps)
	end)

	it("allocates and refunds a connected node from mouse input without panning", function()
		local tab = atlasTab()
		local node = tab.atlas.byId[55117]
		tab.centerX, tab.centerY, tab.zoom = node.x, node.y, 5
		local vp = { x = 312, y = 32, width = 1200, height = 950 }
		tab:Draw(vp, { })
		local cursor = GetCursorPos
		GetCursorPos = function()
			return vp.x + (vp.width - tab.summaryWidth) / 2, vp.y + 83 + (vp.height - 83) / 2
		end
		local ok, err = pcall(function()
			tab:Draw(vp, { { type = "KeyDown", key = "LEFTBUTTON" }, { type = "KeyUp", key = "LEFTBUTTON" } })
			assert(tab.plan.selected[node.id] == 0 and tab.plan.used == 1)
			tab:Draw(vp, { { type = "KeyUp", key = "RIGHTBUTTON" } })
			assert(tab.plan.selected[node.id] == nil and tab.plan.used == 0)
		end)
		GetCursorPos = cursor
		assert(ok, err)
	end)
end)
