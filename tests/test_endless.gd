extends TestCase
## EXPERIMENTAL Recycle Bin endless mode: waves, scoring, daemon, records.

const DT := 1.0 / 60


func _world(seed_value := 3) -> SimWorld:
	var w := track(SimWorld.new())
	w.setup_endless(DataStore.starter_hull("redFalcon"), seed_value)
	w.player.invuln = 99999
	w.mission.intermission = 0   # skip the get-ready countdown
	w.step(DT, {})
	return w


func _clear_wave(w: SimWorld) -> void:
	for s in w.ships.duplicate():
		if NpcAI.aggressive_to_player(w, s):
			w.destroy_ship(s, w.player)
	w._purge_dead()
	w.step(DT, {})


func test_get_ready_countdown() -> void:
	var w := track(SimWorld.new())
	w.setup_endless(DataStore.starter_hull("redFalcon"), 1)
	check(w.mission.wave == 0 and w.ships.is_empty(), "no enemies during the countdown")
	check(w.mission.objective_text().begins_with("READY"), "countdown chip")
	for i in int(4.2 / DT):
		w.step(DT, {})
	check(w.mission.wave == 1, "wave 1 starts after the countdown")


func test_first_wave_all_hostile() -> void:
	var w := _world()
	check(w.mission.wave == 1 and w.mission.wave_state == "fighting", "starts on wave 1")
	var hostile := w.ships.filter(func(s): return NpcAI.aggressive_to_player(w, s))
	check(hostile.size() >= 2, "wave 1 has 2+ hostiles (got %d)" % hostile.size())
	check(not w.gate_open, "no exit gate in the Recycle Bin")


func test_wave_cycle_and_scoring() -> void:
	var w := _world()
	var hp := w.player.max_hull
	w.player.hull = hp * 0.5
	var missiles: int = w.campaign["missiles"]
	_clear_wave(w)
	var m := w.mission
	check(m.wave_state == "intermission", "cleared wave -> intermission")
	check(m.score >= 2 * 25 + 100, "kills and wave bonus scored (score %d)" % m.score)
	check(w.player.hull > hp * 0.5 and int(w.campaign["missiles"]) == missiles + 2, "intermission repairs and restocks")
	var before := w.ships.size()
	for i in int((MissionController.INTERMISSION + 0.5) / DT):
		w.step(DT, {})
	check(m.wave == 2 and m.wave_state == "fighting", "next wave starts after the intermission")
	check(w.ships.size() > before, "wave 2 spawns more ships")


func test_daemon_every_fifth_wave() -> void:
	var w := _world(9)
	for i in 4:
		_clear_wave(w)
		w.mission.intermission = 0
		w.step(DT, {})
	check(w.mission.wave == 5, "reached wave 5 (at %d)" % w.mission.wave)
	var daemon := w.ships.filter(func(s): return s.boss)
	check(daemon.size() == 1 and daemon[0].name.begins_with("PURGE DAEMON"), "Purge Daemon guards wave 5")
	check(w.ships.any(func(s): return s.archetype == "beam"), "beam ships from wave 5")
	w.destroy_ship(daemon[0], w.player)
	check(not w.gate_open, "daemon kill does not open a gate")


func test_records() -> void:
	SaveService.root = "user://test_records/"
	SaveService.reset("all")
	var r1 := SaveService.record_endless(500, 3)
	check(r1["new_best"] and r1["best_score"] == 500 and r1["runs"] == 1, "first run is a best")
	var r2 := SaveService.record_endless(200, 5)
	check(not r2["new_best"] and r2["best_score"] == 500 and r2["best_wave"] == 5 and r2["runs"] == 2, "best kept, best wave updated")
	SaveService.reset("all")
	SaveService.root = "user://"
