extends TestCase
## Faction warfare, targeting, spawning and projectile rules (behavioural regressions
## derived from legacy v7.2.3/v7.2.4 code; see docs/PARITY_MATRIX.md).


func _world(threat := 3, seed_value := 7) -> SimWorld:
	var w := SimWorld.new()
	w.setup(DataStore.starter_hull("redFalcon"), "sandbox", threat, seed_value)
	return w


func _ship(w: SimWorld, arch: String, team: String, at: Vector2, ai := "") -> SimShip:
	var s := w._make_npc(arch, team, true, at)
	if ai != "":
		s.ai = ai
	w.ships.append(s)
	return s


func test_special_archetypes_spawn_by_threat() -> void:
	for seed_value in range(1, 21):
		var w := _world(3, seed_value)
		var has := {"skirmisher": false, "beam": false}
		for s in w.ships:
			if s.archetype in has and NpcAI.COMBAT_AIS.has(s.ai):
				has[s.archetype] = true
		check(has["skirmisher"] and has["beam"], "seed %d threat 3 has skirmisher+beam" % seed_value)
	var t := SimWorld.new()
	t.setup(DataStore.starter_hull("redFalcon"), "test", 3, 1)
	for s in t.ships:
		check(s.ai == "test", "test range spawns only targets")


func test_faction_war_rules() -> void:
	var w := _world(1, 3)
	w.ships.clear()
	var pirate := _ship(w, "grunt", "Pirates", Vector2(100, 100))
	var pred := _ship(w, "grunt", "Predators", Vector2(200, 100))
	var knight := _ship(w, "grunt", "Knights", Vector2(300, 100))
	var pirate2 := _ship(w, "grunt", "Pirates", Vector2(400, 100))
	check(NpcAI.faction_war(pirate, knight), "Pirates attack Knights")
	check(NpcAI.faction_war(pred, pirate), "Predators attack Pirates")
	check(not NpcAI.faction_war(pirate, pirate2), "Pirates do not attack Pirates")
	check(not NpcAI.faction_war(knight, pirate), "Knights do not start faction war")
	check(NpcAI.faction_war(pirate, w.player), "Pirates hostile to Avengers player")


func test_retaliation_priority_and_invalidation() -> void:
	var w := _world(1, 3)
	w.ships.clear()
	var pirate := _ship(w, "grunt", "Pirates", Vector2(1300, 1000))
	var near_knight := _ship(w, "grunt", "Knights", Vector2(1300, 1060))
	var far_speed := _ship(w, "grunt", "Speed", Vector2(1300, 1700))
	NpcAI.retaliate(w, pirate, far_speed, false)
	check(NpcAI.choose_target(w, pirate) == far_speed, "valid retaliation target beats nearer targets")
	far_speed.dead = true
	check(NpcAI.choose_target(w, pirate) != far_speed, "dead retaliation target is invalidated")
	check(NpcAI.choose_target(w, pirate) in [near_knight, w.player], "falls back to faction-war/player target")


func test_player_attack_provokes_neutral() -> void:
	var w := _world(1, 3)
	w.ships.clear()
	var collector := _ship(w, "grunt", "Speed", w.player.pos + Vector2(200, 0), "collector")
	collector.aggro_to_player = false
	var rel_before: float = w.campaign["relations"]["Speed"]
	NpcAI.retaliate(w, collector, w.player, true)
	check(collector.aggro_to_player and collector.ai == "hostile", "neutral turns hostile on player fire")
	near(w.campaign["relations"]["Speed"], rel_before - 6, 1e-9, "relation penalty applied once")
	NpcAI.retaliate(w, collector, w.player, true)
	near(w.campaign["relations"]["Speed"], rel_before - 6, 1e-9, "no double penalty")


func test_projectile_consumed_on_first_hit() -> void:
	var w := _world(1, 3)
	w.ships.clear()
	w.icons.clear()
	var at := w.player.pos + Vector2(300, 0)
	var a := _ship(w, "grunt", "Knights", at)
	var b := _ship(w, "grunt", "Knights", at + Vector2(1, 0))
	var bl := SimWorld.Bullet.new()
	bl.pos = at - Vector2(2, 0); bl.vel = Vector2.ZERO; bl.life = 1; bl.team = w.player.team
	bl.damage = 5; bl.owner = w.player; bl.color = Color.WHITE
	w.bullets.append(bl)
	var ha := a.hull
	var hb := b.hull
	w._update_bullets(1.0 / 60)
	var hits := int(a.hull < ha) + int(b.hull < hb)
	check(hits == 1, "exactly one ship damaged by one projectile (got %d)" % hits)
	check(w.bullets.is_empty(), "projectile removed after hit")


func test_dropped_cargo_protected() -> void:
	var w := _world(1, 3)
	w.ships.clear()
	w.icons.clear()
	var carrier := _ship(w, "grunt", "Speed", w.player.pos + Vector2(400, 0), "collector")
	var icon := w.spawn_icon()
	icon.infected = false
	icon.pos = carrier.pos
	check(NpcAI.pickup_icon(carrier, icon), "collector picks up icon")
	check(carrier.ai == "carrier", "collector becomes carrier")
	w.destroy_ship(carrier, w.player)
	check(icon.carrier == null and w.icons.has(icon), "cargo dropped back into the world")
	check(icon.drop_protected_until > w.time + 2.4, "2.5 s drop protection")
	var bl := SimWorld.Bullet.new()
	bl.pos = icon.pos; bl.vel = Vector2.ZERO; bl.life = 1; bl.team = w.player.team
	bl.damage = 50; bl.owner = w.player; bl.color = Color.WHITE
	w.bullets.append(bl)
	w._update_bullets(1.0 / 60)
	check(w.icons.has(icon) and icon.hp == 25, "protected icon not damaged")
	check(int(w.campaign["warrant"]) == 0, "no crime for protected icon")


func test_icon_destruction_spawns_enforcer() -> void:
	var w := _world(1, 3)
	w.ships.clear()
	w.crime("Destroyed a clean icon", 20)
	var enf := w.ships.filter(func(s): return s.team == "Enforcers")
	check(enf.size() == 1 and enf[0].ai == "enforcer", "warrant 20 spawns one Enforcer")
	w.crime("Again", 20)
	check(w.ships.filter(func(s): return s.team == "Enforcers").size() == 1, "no duplicate Enforcer")


func test_long_simulation_is_stable() -> void:
	var w := _world(5, 11)
	var dt := 1.0 / 60
	for i in 60 * 45:
		w.step(dt, {"turn": sin(i * 0.01), "thrust": i % 200 < 120, "fire": i % 3 == 0, "missile": i % 400 == 0})
		if w.over:
			break
	for s in w.ships:
		check(is_finite(s.pos.x) and is_finite(s.pos.y) and is_finite(s.vel.x), "ship state finite")
		check(s.pos.x >= 0 and s.pos.x <= SimWorld.W and s.pos.y >= 0 and s.pos.y <= SimWorld.H, "ship within wrapped world")
		check(s.vel.length() <= s.ai_max_speed + 1e-3, "ship obeys speed cap")
	check(is_finite(w.player.pos.x), "player state finite")
