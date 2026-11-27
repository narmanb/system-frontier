class_name MissionController
extends RefCounted
## Directory objectives and mission-only world objects. Port of the effective legacy code:
##   base updateMission (normal / race / duel / boss / black hole), v7.2.3 duel gate rule,
##   v6.4 special missions (rescue, repair, courier, scan, defrag), ambient programs,
##   discoveries (cache / lost file / vendor / quarantine) and dragonEncounter.
## Choices that legacy showed in a modal are raised as `dialog` requests on the world and
## resolved with `resolve_dialog(kind, choice)`; the world is blocked meanwhile.

const SPECIAL := ["rescue", "repair", "courier", "scan", "defrag"]
const PROGRAM_NAMES := ["CALC.EXE", "MABEL.DLL", "CLIPPY-7", "BYTE NURSE", "PORTER.EXE", "PIXEL PETE", "ARCHIVIST", "PATCH.GRL", "MUSICDRV", "OLD TIMER"]
const PROGRAM_LINES := ["The directory feels different since the infection arrived.", "I remember when this sector had proper toolbars.",
	"Watch the floating caches. Some of them still contain fabrication parts.", "The Enforcers are asking too many questions again.",
	"Black holes and duel locks are older than this infection.", "I heard the Ship Factory can use recovered alloy now."]


class Program:
	var pos: Vector2
	var vel := Vector2.ZERO
	var r := 16.0
	var name := ""
	var role := ""
	var line := ""
	var objective := false
	var greeted := false
	var rescued := false
	var follow := false
	var status := ""
	var phase := 0.0


class MissionNode:
	var pos: Vector2
	var kind := "repair"     ## repair | scan | defrag
	var index := 0
	var progress := 0.0
	var complete := false
	var phase := 0.0


class Discovery:
	var pos: Vector2
	var r := 24.0
	var kind := "cache"      ## cache | lost | vendor | quarantine
	var spin := 0.0
	var triggered := false


var w: SimWorld
var type := "normal"
var dir: Dictionary = {}
var programs: Array[Program] = []
var nodes: Array[MissionNode] = []
var discoveries: Array[Discovery] = []
var total := 0
var done := 0
var next := 0                        ## defrag
var courier: Program = null
var courier_picked := false
var courier_delivered := false
var destination := Vector2.ZERO
var race_checkpoints: Array = []     ## [Vector2], radius 45
var race_next := 0
var race_time := 0.0
var race_active := false
var black_hole = null                ## Vector2 or null, r 58
var wave_salvage := {"alloy": 0, "circuitry": 0, "data": 0}
# --- EXPERIMENTAL: Recycle Bin endless survival
var wave := 0
var wave_state := ""                 ## "fighting" | "intermission"
var intermission := 0.0
var score := 0
var _kills_seen := 0
var _icons_seen := 0
const INTERMISSION := 8.0


func _init(world: SimWorld, directory: Dictionary) -> void:
	w = world
	dir = directory
	type = str(directory.get("type", "normal"))


func is_special() -> bool:
	return SPECIAL.has(type)


func rnd(a: float, b: float) -> float:
	return w.rnd(a, b)


## v64RandomPosition: away from the player, other objects and the gate.
func random_position(min_from_player := 340.0, others: Array = []) -> Vector2:
	var p := Vector2.ZERO
	for tries in 80:
		p = Vector2(rnd(150, SimWorld.W - 150), rnd(150, SimWorld.H - 150))
		var ok := p.distance_to(w.player.pos) >= min_from_player and p.distance_to(w.gate_pos) >= 160
		for o in others:
			if p.distance_to(o) < 210:
				ok = false
		if ok:
			break
	return p


func _program(role: String, objective: bool, at = null) -> Program:
	var pr := Program.new()
	var used := []
	for o in programs:
		used.append(o.pos)
	pr.pos = at if at != null else random_position(280, used)
	pr.name = w.pick(PROGRAM_NAMES)
	pr.line = w.pick(PROGRAM_LINES)
	pr.role = role
	pr.objective = objective
	pr.phase = rnd(0, TAU)
	return pr


## Called by SimWorld after the base spawn (legacy v6.4 startWave layer).
func start() -> void:
	if type == "endless":
		wave_state = "intermission"   # short "get ready" before wave 1
		intermission = 4.0
		w.msg("RECYCLE BIN — hostile programs are coming to empty it. Get ready.", 4.0)
		return
	if type == "race":
		race_checkpoints = []
		for i in 5:
			race_checkpoints.append(Vector2(350 + i * 430, SimWorld.H - 350 if i % 2 == 1 else 350))
		race_active = true
		w.icons.clear()
	for i in (0 if type == "boss" else 1 + int(int(dir.get("difficulty", 1)) > 2)):
		programs.append(_program(w.pick(["Resident", "Technician", "Archivist", "Shopkeeper"]), false))
	var used := []
	for i in 1 + int(int(dir.get("difficulty", 1)) >= 3):
		var d := Discovery.new()
		d.pos = random_position(420, used)
		used.append(d.pos)
		d.kind = w.pick(["cache", "lost", "vendor", "quarantine"])
		d.spin = rnd(0, TAU)
		discoveries.append(d)
	if is_special():
		_reduce_combat()
		match type:
			"rescue":
				total = 3
				var u := []
				for i in total:
					var pr := _program("Stranded Program", true, random_position(380, u))
					u.append(pr.pos)
					pr.status = "stranded"
					programs.append(pr)
			"repair", "scan":
				total = 3 if type == "repair" else 4
				var u := []
				for i in total:
					var n := MissionNode.new()
					n.pos = random_position(360 if type == "repair" else 330, u)
					u.append(n.pos)
					n.kind = type
					n.index = i
					n.phase = rnd(0, TAU)
					nodes.append(n)
			"courier":
				var start_pos := Vector2(clampf(w.player.pos.x + 180, 120, SimWorld.W - 120), clampf(w.player.pos.y + 80, 120, SimWorld.H - 120))
				courier = _program("Courier", true, start_pos)
				courier.status = "waiting"
				programs.append(courier)
				destination = w.gate_pos + Vector2(-90, -40)
			"defrag":
				total = 5
				var u := []
				for i in total:
					var n := MissionNode.new()
					n.pos = random_position(300, u)
					u.append(n.pos)
					n.kind = "defrag"
					n.index = i
					n.phase = rnd(0, TAU)
					nodes.append(n)
	w.msg(intro())


## v64ReduceSpecialCombat: no icons, one friendly collector, fewer hazards, gate closed.
func _reduce_combat() -> void:
	w.icons.clear()
	var keep: Array[SimShip] = []
	for s in w.ships:
		if s.ai == "collector":
			keep.append(s)
			break
	for s in keep:
		s.ai = "collector"
		s.team = w.player.team
		s.color = Color("#66ddff")
	w.ships = keep
	var k := clampi(int(dir.get("difficulty", 1)) / 2, 0, w.hazards.size())
	w.hazards = w.hazards.slice(0, k)
	w.gate_open = false


func intro() -> String:
	match type:
		"rescue": return "Civilian programs detected. Release all three quarantine locks."
		"repair": return "Damaged directory nodes detected. Hold close to perform repairs."
		"courier": return "Courier signal located. Link with it and guide it to the terminal."
		"scan": return "Hidden infection signatures detected. Resolve all scanner contacts."
		"defrag": return "Fragmented path detected. Touch memory blocks in numerical order."
		"duel": return "Duel lock engaged. Destroy every hostile duelist."
		"blackhole": return "Recover %d icons to expose the dragon black hole." % w.icons.size()
		"race": return "Directory race active. Clear every checkpoint first."
		"boss": return "Inner Demon stronghold entered."
	return "Recover %d clean icons." % w.icons.size()


func objective_text() -> String:
	match type:
		"endless":
			if wave_state == "intermission":
				if wave == 0:
					return "READY %ds" % ceili(intermission)
				return "W%d NEXT %ds" % [wave, ceili(intermission)]
			return "W%d · %d LEFT" % [wave, _endless_remaining()]
		"rescue": return "%d/%d" % [done, total]
		"repair": return "%d/%d" % [done, total]
		"scan": return "%d/%d" % [done, total]
		"defrag": return "%d/%d" % [next, total]
		"courier": return "DELIVERED" if courier_delivered else ("LINKED" if courier_picked else "FIND")
		"race": return "%d/%d" % [race_next, race_checkpoints.size()] if race_active else "DONE"
		"duel": return "%d left" % _duel_remaining()
		"boss": return "ACTIVE" if _boss_alive() else "DEFEATED"
		"blackhole":
			if black_hole != null:
				return "ENTER"
	return ""


# ------------------------------------------------------------------ Recycle Bin (experimental)

func _endless_remaining() -> int:
	var n := 0
	for s in w.ships:
		if not s.dead and NpcAI.aggressive_to_player(w, s):
			n += 1
	return n


func _next_wave() -> void:
	wave += 1
	wave_state = "fighting"
	w.threat = mini(6, 1 + wave / 2)
	var count := mini(14, 1 + wave)
	for i in count:
		w.spawn_ai()
	if wave >= 3:
		w._spawn_required("skirmisher")
	if wave >= 5:
		w._spawn_required("beam")
	if wave % 5 == 0:
		w.spawn_purge_daemon(wave / 5)
	if wave % 2 == 0 and w.hazards.size() < 6:
		w.spawn_hazard()
	for i in 2:   # bonus files to recover for score
		var o := w.spawn_icon()
		o.value = 10 + wave * 5
	for s in w.ships:
		NpcAI.prepare(w, s)
		s.aggro_to_player = true
	w.msg("WAVE %d — %d hostile programs are trying to empty the Recycle Bin." % [wave, _endless_remaining()])
	w.sfx(260, 0.2, "sawtooth", 0.04)


func _update_endless(dt: float) -> void:
	var p := w.player
	# score: kills scale with the wave, recovered files with their value
	if w.player_kills > _kills_seen:
		score += (w.player_kills - _kills_seen) * 25 * wave
		_kills_seen = w.player_kills
	if w.icons_collected > _icons_seen:
		score += (w.icons_collected - _icons_seen) * (20 + wave * 10)
		_icons_seen = w.icons_collected
	if wave_state == "fighting":
		if _endless_remaining() == 0:
			wave_state = "intermission"
			intermission = INTERMISSION
			var bonus := 100 * wave
			score += bonus
			p.hull = minf(p.max_hull, p.hull + p.max_hull * 0.25)
			w.campaign["missiles"] = int(w.campaign["missiles"]) + 2
			for i in 2:
				w.spawn_fuel()
			w.msg("WAVE %d CLEARED  +%d. Hull patched, +2 missiles. Ambulance open (✚ / A). Next wave in %ds." % [wave, bonus, int(INTERMISSION)], 4.0)
			w.sfx(820, 0.15)
	else:
		intermission -= dt
		if intermission <= 0:
			_next_wave()
	if p.fuel <= 0 and p.vel.length() < 2:
		w.msg_if_idle("Stranded. Press A or the ✚ button for the ambulance.")


## Point the strategy autopilot ("collect") should head for when no icons remain.
func objective_point():
	match type:
		"rescue":
			for pr in programs:
				if pr.objective and not pr.rescued:
					return pr.pos
		"repair", "scan":
			for n in nodes:
				if not n.complete:
					return n.pos
		"defrag":
			if next < nodes.size():
				return nodes[next].pos
		"courier":
			return destination if courier_picked else courier.pos
		"race":
			if race_active and race_next < race_checkpoints.size():
				return race_checkpoints[race_next]
	if black_hole != null:
		return black_hole
	return null


func _duel_remaining() -> int:
	var n := 0
	for s in w.ships:
		if not s.dead and s.team != w.player.team and (NpcAI.COMBAT_AIS.has(s.ai) or NpcAI.faction_war(s, w.player)):
			n += 1
	return n


func _boss_alive() -> bool:
	for s in w.ships:
		if s.boss and not s.dead:
			return true
	return false


func _open_gate(text: String) -> void:
	if w.gate_open:
		return
	w.gate_open = true
	w.msg(text)
	w.sfx(820, 0.13)


## Per-frame objective logic (legacy updateMission chain).
func update(dt: float) -> void:
	if type == "endless":
		_update_endless(dt)
		return
	var p := w.player
	_update_discoveries(dt)
	_update_programs(dt)
	if is_special():
		_update_special(dt)
		if w.gate_open and p.pos.distance_to(w.gate_pos) < 55:
			w.end_mission(true, "Directory objective completed.")
	else:
		if race_active:
			race_time += dt
			if race_next < race_checkpoints.size() and p.pos.distance_to(race_checkpoints[race_next]) < 45:
				race_next += 1
				w.sfx(720, 0.08)
				w.msg("Checkpoint %d/%d" % [race_next, race_checkpoints.size()])
			if race_next >= race_checkpoints.size():
				w.campaign["credits"] += 80
				w.gate_open = true
				race_active = false
				w.msg("FIRST PLACE — icon cache awarded. Exit gate open.")
		elif type == "duel":
			w.gate_open = _duel_remaining() == 0
		elif type == "boss":
			if not _boss_alive():
				w.gate_open = true
		elif w.icons.is_empty() and not w.gate_open and black_hole == null:
			if type == "blackhole":
				black_hole = Vector2(SimWorld.W * 0.72, SimWorld.H * 0.35)
				w.msg("Dragon black hole opened. Enter it to claim a Noble Program.")
			else:
				w.gate_open = true
				w.msg("All icons recovered. Exit gate open.")
		if black_hole != null and p.pos.distance_to(black_hole) < 58 + 10:
			black_hole = null
			w.request_dialog("dragon", {"cost": 30 + int(dir.get("difficulty", 1)) * 10})
		if w.gate_open and p.pos.distance_to(w.gate_pos) < 55:
			w.end_mission(true, "The Inner Demon has been purged." if type == "boss" else "Directory disinfected.")
	if p.fuel <= 0 and p.vel.length() < 2:
		w.msg_if_idle("Stranded. Press A or the ✚ button for the ambulance.")


func _update_special(dt: float) -> void:
	var p := w.player
	match type:
		"rescue":
			for pr in programs:
				if pr.objective and not pr.rescued and p.pos.distance_to(pr.pos) < 58:
					pr.rescued = true
					pr.follow = true
					pr.status = "rescued"
					done += 1
					w.sfx(760, 0.1)
					w.msg("%s released — %d/%d programs rescued." % [pr.name, done, total])
			if done >= total:
				_open_gate("All stranded programs rescued. Exit gate open.")
		"repair":
			for n in nodes:
				if n.complete:
					continue
				if p.pos.distance_to(n.pos) < 72:
					n.progress += dt
					if n.progress >= 2:
						n.complete = true
						n.progress = 2
						done += 1
						w.sfx(680, 0.13)
						w.msg("Directory node %d/%d repaired." % [done, total])
				else:
					n.progress = maxf(0, n.progress - dt * 0.28)
			if done >= total:
				_open_gate("Directory structure stabilized. Exit gate open.")
		"courier":
			if not courier_picked and p.pos.distance_to(courier.pos) < 70:
				courier_picked = true
				courier.follow = true
				courier.status = "linked"
				w.msg("%s: Link established. Guide me to the destination terminal." % courier.name)
				w.sfx(720, 0.1)
			if courier_picked and not courier_delivered and p.pos.distance_to(destination) < 85 and courier.pos.distance_to(destination) < 140:
				courier_delivered = true
				courier.follow = false
				courier.pos = destination
				courier.status = "delivered"
				_open_gate("Courier delivered safely. Exit gate open.")
		"scan":
			for n in nodes:
				if n.complete:
					continue
				if p.pos.distance_to(n.pos) < 105:
					n.progress += dt
					if n.progress >= 1.4:
						n.complete = true
						done += 1
						w.sfx(890, 0.08)
						w.msg("Infection signature %d/%d resolved." % [done, total])
				else:
					n.progress = maxf(0, n.progress - dt * 0.5)
			if done >= total:
				_open_gate("All infection signatures resolved. Exit gate open.")
		"defrag":
			if next < nodes.size() and p.pos.distance_to(nodes[next].pos) < 64:
				nodes[next].complete = true
				next += 1
				w.sfx(620 + next * 55, 0.07)
				w.msg("Memory fragment %d/%d locked into position." % [next, total])
			if next >= total:
				_open_gate("Directory path defragmented. Exit gate open.")


func _update_programs(dt: float) -> void:
	var p := w.player
	var followers := 0
	for pr in programs:
		pr.phase += dt
		if pr.follow:
			var slot := (programs.find(pr) % 3) - 1
			var target := p.pos - Vector2(cos(p.a), sin(p.a)) * 90 + Vector2(cos(p.a + PI / 2), sin(p.a + PI / 2)) * slot * 42
			var ang := (target - pr.pos).angle()
			var dd := pr.pos.distance_to(target)
			pr.vel += (Vector2(cos(ang), sin(ang)) * minf(150, dd * 1.5) - pr.vel) * dt * 2.5
			pr.pos = w.wrap_pos(pr.pos + pr.vel * dt)
			followers += 1
		elif not pr.objective:
			pr.pos += Vector2(cos(pr.phase * 0.35), sin(pr.phase * 0.31)) * 3 * dt
		if not pr.objective and not pr.greeted and p.pos.distance_to(pr.pos) < 125:
			pr.greeted = true
			w.msg("%s: %s" % [pr.name, pr.line], 2.6)


func _update_discoveries(dt: float) -> void:
	for o in discoveries:
		o.spin += dt
		if not o.triggered and w.player.pos.distance_to(o.pos) < o.r + w.player.pickup_radius * 0.7:
			_trigger(o)
	discoveries = discoveries.filter(func(o: Discovery) -> bool: return not o.triggered)


func _add_salvage(bundle: Dictionary) -> void:
	if w.campaign.has("salvage"):
		Campaign.add_salvage(w.campaign, bundle)
	for k in ["alloy", "circuitry", "data"]:
		wave_salvage[k] += int(bundle.get(k, 0))


func _trigger(o: Discovery) -> void:
	o.triggered = true
	w.campaign["discoveries"] = int(w.campaign.get("discoveries", 0)) + 1
	var diff := int(dir.get("difficulty", 1))
	match o.kind:
		"cache", "lost":
			var r := {"credits": 18 + diff * 5, w.pick(["alloy", "circuitry"]): 1} if o.kind == "cache" else {"credits": 12, "data": 1}
			w.campaign["credits"] += int(r.get("credits", 0))
			_add_salvage(r)
			w.msg(("Fabrication cache opened: %s." if o.kind == "cache" else "Lost file restored: %s.") % Campaign.reward_text(r))
			w.sfx(940, 0.11)
		"vendor":
			w.request_dialog("vendor", {})
		"quarantine":
			w.request_dialog("quarantine", {})


## Applies a dialog choice. Returns false if the choice is not affordable (dialog stays open).
func resolve_dialog(kind: String, choice: String, payload: Dictionary) -> bool:
	var c := w.campaign
	var p := w.player
	match kind:
		"dragon":
			match choice:
				"bomb":
					var cost: int = payload.get("cost", 40)
					if c["credits"] < cost:
						w.sfx(110, 0.1)
						return false
					c["credits"] -= cost
					c["noble"] = mini(4, int(c.get("noble", 0)) + 1)
					w.gate_open = true
					w.msg("Noble Program recovered. Exit gate open.")
				"fight":
					# Legacy used the removed v5 `laser` stat here (NaN in v6); weaponPower is its v6 successor.
					p.hull = maxf(20, p.hull - maxf(10, 50 - float(p.stats.get("weaponPower", 5)) * 4))
					c["noble"] = mini(4, int(c.get("noble", 0)) + 1)
					w.gate_open = true
					w.msg("Dragon defeated in simulation. Noble Program recovered.")
				_:
					w.gate_open = true
					w.msg("Black hole escaped. Exit gate open.")
		"vendor":
			match choice:
				"repair":
					if c["credits"] < 25:
						w.sfx(110, 0.1)
						return false
					c["credits"] -= 25
					p.hull = minf(p.max_hull, p.hull + 55)
					w.msg("Temporary hull patch installed.")
				"trade":
					if int(c["salvage"].get("data", 0)) < 1:
						w.sfx(110, 0.1)
						return false
					c["salvage"]["data"] -= 1
					c["salvage"]["circuitry"] += 2
					w.msg("One data core traded for two circuitry bundles.")
		"quarantine":
			if choice == "purge":
				p.fuel = maxf(0, p.fuel - 18)
				_add_salvage({"data": 1, "circuitry": 1})
				c["credits"] += 10
				w.msg("Cache purged. Fuel spent; fabrication data recovered.")
	return true
