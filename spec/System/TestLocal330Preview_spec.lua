describe("Local 3.30 public preview", function()
	local function recalc()
		runCallback("OnFrame")
		build.calcsTab:BuildOutput()
		return build.calcsTab.mainOutput, build.calcsTab.mainEnv
	end

	local function unique(name)
		return new("Item"):Item(assert(main.uniqueDB.byTitle[name:lower()], name).raw)
	end

	local function equip(item)
		build.itemsTab.displayItem = item
		build.itemsTab:AddDisplayItem()
	end

	it("uses the published endpoints for Winter Orb and Flame Link", function()
		local function stats(id, level)
			return calcLib.buildSkillInstanceStats({ level = level, quality = 20 }, data.skills[id])
		end
		local first, last = stats("WinterOrb", 1), stats("WinterOrb", 20)
		assert(first.spell_minimum_base_cold_damage == 40 and first.spell_maximum_base_cold_damage == 59)
		assert(last.spell_minimum_base_cold_damage == 307 and last.spell_maximum_base_cold_damage == 460)
		for level, row in pairs(data.skills.WinterOrb.levels) do
			assert(row.damageEffectiveness == 0.7 and stats("WinterOrb", level).base_number_of_projectiles == 2)
		end
		first, last = stats("FlameLink", 1), stats("FlameLink", 20)
		assert(first.flame_link_minimum_fire_damage == 36 and first.flame_link_maximum_fire_damage == 54)
		assert(last.flame_link_minimum_fire_damage == 219 and last.flame_link_maximum_fire_damage == 329)
		assert(last["flame_link_added_fire_damage_from_life_%"] == 3)
	end)

	it("calculates Radiation as a non-hit spell DoT and preserves the 20/20 preview after import", function()
		newBuild()
		build.skillsTab:PasteSocketGroup("Fireball of Radiation 1/0  1")
		build.configTab.input.customMods = "+10 to Level of all Fire Spell Skill Gems"
		build.configTab:BuildModList()
		local _, env = recalc()
		local active = env.player.mainSkill
		assert(active.activeEffect.level == 20 and active.activeEffect.quality == 20)
		assert(not active.skillFlags.hit and active.skillData.dotIsSpell)
		assert(math.abs(active.skillData.FireDot - 3493.6) < 1e-6)
		assert(active.skillData.radius == 15)
		loadBuildFromXML(build:SaveDB("code"))
		local gem = build.skillsTab.socketGroupList[1].gemList[1]
		assert(gem.level == 20 and gem.quality == 20 and gem.reqInt == 155)
	end)

	it("loads Arcane Link as a party link with published mana cost and lightning bonuses", function()
		newBuild()
		build.skillsTab:PasteSocketGroup("Arcane Link 20/20  1")
		build.partyTab.enableExportBuffs = true
		local _, env = recalc()
		local active = env.player.mainSkill
		local effect = active.activeEffect
		assert(active.skillTypes[SkillType.Link] and not active.skillTypes[SkillType.Totemable])
		assert(effect.grantedEffectLevel.cost.ManaPerMinute == 3920)
		local link = assert(build.partyTab.buffExports.Link["Arcane Link"])
		local found, manaScaled = { }, 0
		for _, mod in ipairs(link.modList) do
			local percent = mod[2]
			if percent and percent.type == "PercentStat" then
				assert(mod.value == 3 and percent.stat == "Mana" and percent.actor == "parent")
				manaScaled = manaScaled + 1
			else
				found[mod.name] = mod.value
			end
		end
		assert(found.LightningMin == 222 and found.LightningMax == 333 and manaScaled == 2)
	end)

	it("uses 3.30 Warden Barkskin values at the selected stack count", function()
		newBuild()
		build.spec:SelectClass(2) -- Ranger
		build.spec:SelectAscendClass(1) -- Warden
		build.spec:AllocNode(assert(build.spec.nodes[4849])) -- Mother's Teachings
		build.configTab.input.barkskinStacks = 5
		build.configTab:BuildModList()
		build.buildFlag = true
		local _, env = recalc()
		local cfg = env.player.mainSkill.skillCfg
		assert(env.player.modDB:Sum("BASE", cfg, "PhysicalDamageTakenFromAttacks") == -375)
		assert(math.abs(env.player.modDB:More(cfg, "EvadeChance") - 1.30) < 1e-6)
	end)

	it("applies Acuity's new life recovery restrictions without stopping energy shield recoup", function()
		newBuild()
		build.configTab.input.customMods = "30% of Damage taken Recouped as Life\n20% of Physical Damage taken Recouped as Life\n10% of Damage taken Recouped as Energy Shield\nRegenerate 100 Life per second"
		build.configTab:BuildModList()
		local before = recalc()
		assert(before.LifeRecoup > 0 and before.PhysicalLifeRecoup > 0 and before.LifeRegen > 0)
		equip(unique("Atziri's Acuity"))
		local after, env = recalc()
		assert(after.LifeRecoup == 0 and after.PhysicalLifeRecoup == 0 and after.LifeRegen == 0)
		assert(after.EnergyShieldRecoup == before.EnergyShieldRecoup)
		assert(env.player.modDB:Flag(nil, "NoLifeRecoup"))
	end)

	it("applies the Artillery Quiver implicit only to attack totems", function()
		newBuild()
		build.skillsTab:PasteSocketGroup("Holy Flame Totem 20/0  1")
		equip(new("Item"):Item("Rarity: NORMAL\nShort Bow"))
		local item = new("Item"):Item("Rarity: RARE\nPreview Quiver\nArtillery Quiver\nImplicits: 1\n" .. data.itemBases["Artillery Quiver"].implicit)
		equip(item)
		assert(recalc().ActiveTotemLimit == 1)
		newBuild()
		build.skillsTab:PasteSocketGroup("Siege Ballista 20/0  1")
		equip(new("Item"):Item("Rarity: NORMAL\nShort Bow"))
		local withoutQuiver = recalc().ActiveTotemLimit
		equip(new("Item"):Item(item.raw))
		assert(recalc().ActiveTotemLimit == withoutQuiver + 1)
	end)

	it("restricts each Doedre ailment variant to cursed enemies", function()
		newBuild()
		local amulet = unique("Doedre's Tongue")
		for variant, ailment in ipairs({ "Ignite", "Shock", "Freeze" }) do
			amulet.variant = variant + 1
			amulet:BuildAndParseRaw()
			local parsed
			for _, mod in ipairs(amulet.modList) do
				if mod.name == "PhysicalCan" .. ailment then
					parsed = mod
					break
				end
			end
			assert(parsed and parsed[1].type == "ActorCondition")
			assert(parsed[1].actor == "enemy" and parsed[1].var == "Cursed")
		end
	end)

	it("keeps Doryani's four roll groups and Femurs' distinct optional mods", function()
		newBuild()
		local belt = unique("Doryani's Invitation")
		assert(belt.selectedVersion == 2)
		for group = 1, 4 do
			assert(#belt:GetVariantGroupOptions(group, false) == 4 and belt.variantGroupSelections[group])
		end
		belt.selectedVersion = 1
		belt:BuildAndParseRaw()
		assert(#belt:GetVariantGroupOptions(1, false) == 8 and #belt:GetVariantGroupOptions(4, false) == 0)
		local staff = unique("Femurs of the Saints")
		assert(staff.selectedVersion == 9)
		local seen = { }
		for group = 1, 4 do
			local variant = staff.variantGroupSelections[group]
			assert(variant and not seen[variant])
			seen[variant] = true
		end
		staff.selectedVersion = 5
		staff:BuildAndParseRaw()
		assert(#staff:GetVariantGroupOptions(1, false) == 0)
	end)

	it("scales only the flask base chosen on Doryani's Invitation", function()
		newBuild()
		local function armour()
			return recalc().Armour
		end
		equip(new("Item"):Item("Rarity: NORMAL\nGranite Flask"))
		local slot = build.itemsTab.slots["Flask 1"]
		slot.active = true
		build.itemsTab.activeItemSet[slot.slotName].active = true
		local baseline = armour()
		assert(baseline == 1500)
		local belt = unique("Doryani's Invitation")
		belt.variantGroupSelections[2] = 14 -- Fire resistance rather than flat armour
		belt:BuildAndParseRaw()
		equip(belt)
		assert(armour() == 2250)
		belt.variantGroupSelections[4] = 22 -- Ruby instead of Granite
		belt:BuildAndParseRaw()
		build.buildFlag = true
		assert(armour() == baseline)
	end)
end)
