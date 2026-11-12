-- Official 3.30 gem preview (forum thread 4013898). Only 20/20 is public.
-- Local IDs keep these records distinct from the eventual client export.
return function(skills, mod, skill, gems)
	local function register(id, name, tags, grantedEffect)
		local gemTags = { intelligence = true, grants_active_skill = true }
		for _, tag in ipairs(tags) do
			gemTags[tag[1]] = true
		end
		local tagNames = { }
		for index, tag in ipairs(tags) do
			tagNames[index] = tag[2]
		end
		grantedEffect.name = name
		grantedEffect.baseTypeName = name
		grantedEffect.color = 3
		grantedEffect.previewLevel = 20
		grantedEffect.previewQuality = 20
		grantedEffect.levels[20].levelRequirement = 70
		skills[id] = grantedEffect

		local gemId = "LocalPreview/3.30/" .. id
		gems[gemId] = {
			name = name, baseTypeName = name, gameId = gemId, variantId = id, grantedEffectId = id,
			tags = gemTags, tagString = table.concat(tagNames, ", "),
			reqStr = 0, reqDex = 0, reqInt = 100, naturalMaxLevel = 20,
		}
	end

	local link = { type = "GlobalEffect", effectType = "Link" }
	local parentMana = { type = "PercentStat", stat = "Mana", percent = 1, actor = "parent" }
	register("Local330ArcaneLink", "Arcane Link", {
		{ "spell", "Spell" }, { "duration", "Duration" }, { "link", "Link" },
		{ "lightning", "Lightning" }, { "arcane", "Arcane" },
	}, {
		description = "Links to an allied player, adding lightning damage based on your maximum mana.",
		previewNote = "Linked target gains 222 to 333 added lightning damage and 3% of your maximum mana as added lightning damage.",
		skillTypes = { [SkillType.Spell] = true, [SkillType.Buff] = true, [SkillType.Duration] = true,
			[SkillType.Link] = true, [SkillType.Lightning] = true, [SkillType.Arcane] = true },
		statDescriptionScope = "buff_skill_stat_descriptions",
		castTime = 0.5,
		statMap = {
			local330_arcane_link_min = { mod("LightningMin", "BASE", nil, 0, 0, link) },
			local330_arcane_link_max = { mod("LightningMax", "BASE", nil, 0, 0, link) },
			local330_arcane_link_mana = {
				mod("LightningMin", "BASE", nil, 0, 0, link, parentMana),
				mod("LightningMax", "BASE", nil, 0, 0, link, parentMana),
			},
		},
		baseFlags = { spell = true, duration = true },
		stats = { "local330_arcane_link_min", "local330_arcane_link_max", "local330_arcane_link_mana",
			"base_skill_effect_duration", "skill_cost_over_time_is_not_removed_with_skill", "display_link_stuff" },
		notMinionStat = { "base_skill_effect_duration" },
		levels = { [20] = { 222, 333, 3, 11400, cost = { ManaPerMinute = 3920 } } },
	})

	register("Local330FireballOfRadiation", "Fireball of Radiation", {
		{ "projectile", "Projectile" }, { "spell", "Spell" }, { "area", "AoE" },
		{ "duration", "Duration" }, { "fire", "Fire" },
	}, {
		description = "Fires a projectile that applies a fire damage over time debuff to nearby enemies.",
		previewNote = "70% less Projectile Speed",
		skillTypes = { [SkillType.Spell] = true, [SkillType.Projectile] = true, [SkillType.Area] = true,
			[SkillType.Duration] = true, [SkillType.Fire] = true, [SkillType.DamageOverTime] = true },
		statDescriptionScope = "skill_stat_descriptions",
		castTime = 0.75,
		previewNoHit = true,
		baseFlags = { spell = true, projectile = true, area = true, duration = true },
		baseMods = { skill("radius", 15), mod("ProjectileSpeed", "MORE", -70) },
		stats = { "base_fire_damage_to_deal_per_minute", "base_skill_effect_duration",
			"spell_damage_modifiers_apply_to_skill_dot" },
		levels = { [20] = { 209616, 1000, cost = { Mana = 20 } } },
	})
end
