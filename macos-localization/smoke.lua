-- Run from a temporary copy of the candidate's Resources/src directory.
-- Requires the LuaJIT revision used by the project's Dockerfile, plus lua-utf8.
local filenames = arg
arg = {} -- Do not let Main treat the smoke inputs as launch arguments.
dofile("HeadlessWrapper.lua")
assert(not launch.promptMsg, launch.promptMsg)
assert(launch.devMode, "The generic upstream updater must stay disabled")
local locale = require("Modules.Localization")
locale.SetLanguage("en")
newBuild()
assert(not launch.promptMsg, launch.promptMsg)
build.skillsTab:PasteSocketGroup("Fireball 20/0  1\nAdded Cold Damage 20/0  1")
build.skillsTab.socketGroupList[1].includeInFullDPS = true
build.viewMode = "SKILLS"
runCallback("OnFrame")
local output = build.calcsTab.mainOutput
local total, full = output.TotalDPS, output.FullDPS
assert(total > 0 and full > 0)
local xml = build:SaveDB("code")
assert(xml and xml:find("Fireball", 1, true))

locale.SetLanguage("zh-CN")
assert(build.controls.modeTree:GetProperty("label") == locale.Text("Tree"))
assert(locale.Text("Tree") ~= "Tree")
assert(locale.Text("^7Tree") == "^7" .. locale.Text("Tree"))
assert(locale.Text("Untranslated UI field") == "Untranslated UI field")
assert(locale.Term("gems", "Nonexistent test term") == "Nonexistent test term")

assert(locale.Display("^7Total Life: ^xFFAA005,286") == "^7总生命： ^xFFAA005,286")
assert(locale.Display("^7Are you ^xADAA47Shocked?") == "^7你处于感电状态吗？")
assert(locale.Display("Skill Hit Damage") == "技能击中伤害")
assert(locale.Display("+65 to maximum Life") == "+65 最大生命")
assert(locale.Display("+(30-35) to maximum Life") == "+(30-35) 最大生命")
assert(locale.Display("Adds (5-8) to (10-15) Fire Damage") == "附加 (5-8) 至 (10-15) 火焰伤害")
assert(locale.Display("12% increased Cast Speed") == "施法速度提高 12%")
assert(locale.Display("Untranslated item of unknown origin") == "Untranslated item of unknown origin")
local stats = io.open("Locales/Game/stats.json", "rb")
if stats then
    stats:close()
    assert(locale.Display("30% increased Damage") == "伤害提高 30%")
    assert(locale.Display("Aegis Aurora, Champion Kite Shield") == "幻芒圣盾，斗士鸢盾")
    assert(locale.Display("Seething Divine Life Flask of Entropy"):find("不朽生命药剂", 1, true))
    assert(locale.Display("4x Storm Burst:") == "4 × 裂风雷球：")
end
local treeNames = io.open("Locales/Game/tree_names.json", "rb")
if treeNames then
    treeNames:close()
    local function tooltipText(tooltip)
        local lines = {}
        for _, line in ipairs(tooltip.lines) do
            if line.text then lines[#lines + 1] = locale.Display(line.text) end
        end
        return table.concat(lines, "\n")
    end
    local function expect(tooltip, ...)
        local text = tooltipText(tooltip)
        for _, value in ipairs({...}) do
            assert(text:find(value, 1, true), "Missing localized tooltip text: " .. value)
        end
    end
    local tree = dofile("TreeData/3_29/tree.lua")
    for id, node in pairs(tree.nodes) do
        if node.name == "Ancestral Bond" then
            local tooltip = new("Tooltip"):Tooltip()
            build.treeTab.viewer:AddNodeTooltip(tooltip, build.spec.nodes[id], build, true)
            expect(tooltip, "先祖魂约", "召唤图腾数量上限 +1")
            break
        end
    end
    local function checkGem(name, ...)
        for _, gem in pairs(build.data.gems) do
            local effect = gem.grantedEffect
            if gem.name == name and not effect.legacy then
                local tooltip = new("Tooltip"):Tooltip()
                require("Classes.GemTooltip").AddGemTooltip(tooltip, build,
                    { gemData = gem, grantedEffect = effect, level = 20, quality = 20 })
                expect(tooltip, ...)
                return
            end
        end
        error("Missing test gem " .. name)
    end
    if build.spec.treeVersion == "3_29" then
        local node = assert(build.spec.nodes[37504], "Missing 3.29 Intuition node")
        local tooltip = new("Tooltip"):Tooltip()
        build.treeTab.viewer:AddNodeTooltip(tooltip, node, build)
        expect(tooltip, "直觉感知", "法术伤害压制率 +8%", "闪避值提高 15%",
            "生命上限提高 5%", "阻挡 40%", "分配此天赋点后的属性变化", "+8% 法术伤害压制几率", "每点")
        assert(not tooltipText(tooltip):find("per point", 1, true))
    end
    checkGem("Storm Burst", "裂风雷球", "范围半径 +0.4 米", "192 - 288")
    checkGem("Poisonous Concoction of Bouncing", "弹跃之毒爆灵药", "连锁次数 +2", "暴击率 +6%")
    checkGem("Spell Totem", "法术图腾", "代你施放该法术的图腾", "图腾持续 8 秒")
    for _, raw in ipairs(build.data.uniques.body) do
        if raw:match("^Lightning Coil\n") then
            local tooltip = new("Tooltip"):Tooltip()
            build.itemsTab:AddItemTooltip(tooltip, new("Item"):Item(raw, "UNIQUE"))
            expect(tooltip, "雷语", "闪电抗性 -60%", "有 50% 转为闪电伤害")
            break
        end
    end
    print("PASS actual passive, gem and item tooltip text")
end
local function sidebarValue(label)
    for _, row in ipairs(build.controls.statBox.list) do
        if row[1] and StripEscapes(row[1]):find(label, 1, true) then return row[2] end
    end
end
-- Run the normal frame callback, without requesting a recalculation.
runCallback("OnFrame")
local lifeText = assert(sidebarValue("总生命"), "The sidebar was not localized")
locale.SetLanguage("en")
runCallback("OnFrame")
assert(sidebarValue("Total Life") == lifeText, "The sidebar did not restore English or changed the value")
locale.SetLanguage("zh-CN")
runCallback("OnFrame")
assert(sidebarValue("总生命") == lifeText, "The sidebar did not refresh after changing back to Chinese")
print("PASS sidebar labels refresh with unchanged values")
local widths = locale.WrapCjk("^7图腾数量上限", 9, function(text)
    return #(text:gsub("%^7", ""))
end)
assert(#widths == 2 and widths[1] == "^7图腾数" and widths[2] == "^7量上限")
local dictionaries = { gems = "Fireball", items = "Vaal Regalia",
    passives = "Resolute Technique", uniques = "Mageblood" }
for category, sample in pairs(dictionaries) do
    local file = io.open("Locales/Game/" .. category .. ".json", "rb")
    if file then
        file:close()
        assert(locale.Term(category, sample) ~= sample, "Cannot resolve terms for " .. category)
    end
end
local atlas = require("Locales.CJK.glyphs")
local utf8 = require("lua-utf8")
for _, point in utf8.next, locale.Text("Tree") do
    assert(point < 128 or atlas.glyphs[point], "Missing a Chinese glyph")
end
for _, mode in ipairs({"IMPORT", "TREE", "SKILLS", "ITEMS", "CALCS", "CONFIG", "NOTES", "PARTY", "COMPARE"}) do
    build.viewMode = mode
    runCallback("OnFrame")
    assert(not launch.promptMsg, mode .. " " .. tostring(launch.promptMsg))
end
build.viewMode = "SKILLS"
build.buildFlag = true
runCallback("OnFrame")
output = build.calcsTab.mainOutput
assert(output.TotalDPS == total and output.FullDPS == full, "Localization changed the calculation")
assert(build:SaveDB("code") == xml, "Localization changed the exported build")
locale.SetLanguage("en")
assert(build.controls.modeTree:GetProperty("label") == "Tree")
print("PASS Chinese/English switch, 9 views, game term fallback, glyph atlas, equal DPS and export")

for _, filename in ipairs(filenames) do
    local file = assert(io.open(filename, "rb"))
    local content = file:read("*a")
    file:close()
    loadBuildFromXML(content, "Smoke Test")
    assert(not launch.promptMsg, tostring(launch.promptMsg) .. " " .. filename)
    assert(build.calcsTab.mainOutput and build.calcsTab.mainOutput.Life,
        "Could not calculate " .. filename)
    local previous = build:SaveDB("code")
    local values = {}
    for _, key in ipairs({"FullDPS", "TotalDPS", "Life", "EnergyShield", "Mana", "PhysicalMaximumHitTaken"}) do
        values[key] = build.calcsTab.mainOutput[key]
    end
    locale.SetLanguage("zh-CN")
    build.buildFlag = true
    runCallback("OnFrame")
    assert(not launch.promptMsg, launch.promptMsg)
    for key, value in pairs(values) do
        assert(build.calcsTab.mainOutput[key] == value, key .. " changed after switching language")
    end
    assert(build:SaveDB("code") == previous, "Build export changed after switching language")
    locale.SetLanguage("en")
    print("PASS open and bilingual parity " .. filename:match("[^/]+$"))
end
