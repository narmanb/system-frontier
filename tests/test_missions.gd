extends TestCase
## Every mission family driven through its objective (legacy v6.4 / base rules).

const DT := 1.0 / 60


func _world(type: String, diff := 2, seed_value := 5) -> SimWorld:
	var c := Campaign.create({"team": "Avengers"})
	c["noble"] = 4
	var d := {"id": 0, "name": "TEST", "type": type, "difficulty": diff, "icons": 0 if type in MissionController.SPECIAL else 4, "theme": "system"}
	var w := track(SimWorld.new())
	w.setup_directory(c, d, seed_value)
	w.player.invuln = 9999
	return w


func _run(w: SimWorld, seconds: float) -> void:
	for i in int(seconds / DT):
		w.step(DT, {})


func _fly_to(w: SimWorld, p: Vector2, hold := 0.0) -> void:
	w.player.pos = p
	w.player.vel = Vector2.ZERO
	_run(w, maxf(DT * 2, hold))


func _clear_combat(w: SimWorld) -> void:
	w.ships.clear()
	w.hazards.clear()
	w.bullets.clear()


func test_special_missions_reduce_combat() -> void:
	for t in MissionController.SPECIAL:
		var w := _world(t, 3)
		check(w.icons.is_empty(), "%s: no icons" % t)
		check(w.ships.size() <= 1, "%s: at most one ship" % t)
		for s in w.ships:
			check(s.team == w.player.team, "%s: remaining ship friendly" % t)
		check(not w.gate_open, "%s: gate closed" % t)


func test_rescue() -> void:
	var w := _world("rescue")
	_clear_combat(w)
	for pr in w.mission.programs.duplicate():
		if pr.objective:
			_fly_to(w, pr.pos)
	check(w.mission.done == 3 and w.gate_open, "all rescued opens gate")
	_fly_to(w, w.gate_pos)
	check(w.over, "gate ends mission")


func test_repair_needs_hold_time() -> void:
	var w := _world("repair")
	_clear_combat(w)
	_fly_to(w, w.mission.nodes[0].pos, 1.0)
	check(w.mission.done == 0, "not repaired after 1 s")
	_run(w, 1.2)
	check(w.mission.done == 1, "repaired after 2 s")
	for n in w.mission.nodes:
		_fly_to(w, n.pos, 2.2)
	check(w.gate_open, "all nodes repaired")


func test_scan() -> void:
	var w := _world("scan")
	_clear_combat(w)
	for n in w.mission.nodes:
		_fly_to(w, n.pos, 1.6)
	check(w.mission.done == 4 and w.gate_open, "four signatures resolved")


func test_defrag_in_order() -> void:
	var w := _world("defrag")
	_clear_combat(w)
	_fly_to(w, w.mission.nodes[2].pos)
	check(w.mission.next == 0, "out-of-order fragment ignored")
	for n in w.mission.nodes:
		_fly_to(w, n.pos)
	check(w.mission.next == 5 and w.gate_open, "all fragments in order")


func test_courier() -> void:
	var w := _world("courier")
	_clear_combat(w)
	_fly_to(w, w.mission.courier.pos)
	check(w.mission.courier_picked, "linked")
	w.player.pos = w.mission.destination
	w.mission.courier.pos = w.mission.destination + Vector2(40, 0)
	_run(w, 0.1)
	check(w.mission.courier_delivered and w.gate_open, "delivered")


func test_race() -> void:
	var w := _world("race")
	_clear_combat(w)
	var credits: int = w.campaign["credits"]
	for cp in w.mission.race_checkpoints:
		_fly_to(w, cp)
	check(w.gate_open and w.campaign["credits"] == credits + 80, "race finished, +80 credits")


func test_duel_gate_follows_hostiles() -> void:
	var w := _world("duel", 2)
	_run(w, DT * 2)
	check(not w.gate_open, "duel locked while hostiles live")
	var hostiles := w.ships.filter(func(s): return s.team != w.player.team and NpcAI.COMBAT_AIS.has(s.ai))
	check(hostiles.size() >= 4, "duel spawns 2+threat hostiles (got %d)" % hostiles.size())
	for s in w.ships:
		w.destroy_ship(s, w.player)
	w._purge_dead()
	_run(w, DT * 2)
	check(w.gate_open, "gate opens when duelists are gone")


func test_boss() -> void:
	var w := _world("boss", 4)
	var boss := w.ships.filter(func(s): return s.boss)
	check(boss.size() == 1 and boss[0].hull == 600, "Inner Demon present")
	check(w.hazards.size() >= 4, "boss directory has threat hazards")
	w.destroy_ship(boss[0], w.player)
	w._purge_dead()
	_run(w, DT * 2)
	check(w.gate_open, "boss death opens gate")


func test_black_hole_dragon() -> void:
	var w := _world("blackhole", 2)
	_clear_combat(w)
	w.icons.clear()
	_run(w, DT * 2)
	check(w.mission.black_hole != null and not w.gate_open, "black hole appears after icons")
	var asked := []
	w.dialog.connect(func(k, p): asked.append([k, p]))
	_fly_to(w, w.mission.black_hole)
	check(asked.size() == 1 and asked[0][0] == "dragon" and w.blocked, "dragon encounter dialog")
	w.campaign["credits"] = 0
	check(not w.resolve_dialog("dragon", "bomb", asked[0][1]), "logic bomb needs credits")
	check(w.resolve_dialog("dragon", "fight", asked[0][1]), "fight resolves")
	check(w.campaign["noble"] == 4 and w.gate_open and not w.blocked, "noble capped at 4, gate open")
	check(is_finite(w.player.hull) and w.player.hull >= 20, "fight leaves finite hull (legacy NaN fixed)")


func test_defender_becomes_escort() -> void:
	var w := track(SimWorld.new())
	w.setup(DataStore.starter_hull("redFalcon"), "sandbox", 5, 3)
	var def := w.ships.filter(func(s): return s.ai == "defender")
	if def.is_empty():
		return  # random; covered by other seeds
	var d: SimShip = def[0]
	w.icons.erase(d.guard_icon)
	NpcAI.update_ships(w, DT)
	check(d.ai == "escort" and d.team == w.player.team, "defender joins escort when icon is gone")


func test_ambulance_and_strategy() -> void:
	var w := _world("normal", 1)
	w.campaign["credits"] = 500
	w.player.fuel = 10
	check(w.buy_ambulance("fuel") and w.player.fuel == w.player.max_fuel, "refuel")
	var m: int = w.campaign["missiles"]
	check(w.buy_ambulance("missiles") and w.campaign["missiles"] == m + 3, "missiles")
	check(not w.buy_ambulance("warrant"), "nothing to clear")
	w.campaign["credits"] = 0
	check(not w.buy_ambulance("laser"), "cannot afford")
	var s := _world("normal", 1)
	_clear_combat(s)
	s.campaign["mode"] = "strategy"
	s.strategy = "collect"
	var target: Vector2 = s.icons[0].pos
	for ic in s.icons:
		if ic.pos.distance_to(s.player.pos) < target.distance_to(s.player.pos):
			target = ic.pos
	var d0 := s.player.pos.distance_to(target)
	_run(s, 3.0)
	check(s.player.pos.distance_to(target) < d0 or s.icons_collected > 0, "autopilot heads for nearest icon")
