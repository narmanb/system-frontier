class_name SimWorld
extends RefCounted
## Gameplay simulation for one mission/sandbox, independent of rendering and UI.
##
## Ported from the effective legacy code (final overrides):
##   player flight  — block-1 `update` override (no Brake; inertia/counter-thrust only)
##   firing         — v7.2 `firePlayer`/`aiFire`, v7.2.3 `fireMissile`
##   projectiles    — v7.2.4 `updateBullets` (consumed on first hit, dropped-cargo protection)
##   beams          — v6.9 `updateBeams` + v7.2.3 `v723FireBeam`
##   NPC behaviour  — v7.2.3 `updateShips` (see NpcAI)
##   spawning       — v6.9 → v7.2.2 → v7.2.3 `spawnAI` chain, `v723EnsureSpecialEnemies`
##   pickups        — v7.2.2 `updateItems` (carriers), v7.2.4 drop protection
## World coordinates are fixed (2600×1800, wrapping) and never depend on viewport size.

signal message(text: String, duration: float)
signal sound(freq: float, duration: float, wave: String, volume: float)
signal finished(won: bool, reason: String)

const W := 2600.0
const H := 1800.0
const SHIP_DRAW_SIZE := 96.0
const DROP_PROTECTION := 2.5
const NPC_NAMES := ["Rook", "Moxie", "Byte", "Quasar", "Nibbles", "Vega", "Hex", "Sprocket"]
const ICON_TYPES := ["EXE", "DLL", "BMP", "WAV", "INI", "TXT", "ICO", "DAT", "FOLDER"]


class Bullet:
	var pos: Vector2
	var vel: Vector2
	var life: float
	var team: String
	var damage: float
	var color: Color
	var owner: SimShip
	var missile := false
	var target: SimShip = null


class Beam:
	var owner: SimShip
	var team: String
	var life: float
	var damage: float
	var width := 10.0
	var length := 980.0
	var color: Color
	var p1: Vector2
	var p2: Vector2


class Icon:
	var pos: Vector2
	var vel: Vector2
	var r := 22.0
	var value := 10.0
	var hp := 25.0
	var infected := false
	var spin := 0.0
	var kind := "EXE"
	var drift_timer := 2.0
	var carrier: SimShip = null
	var drop_protected_until := -1.0


class FuelCell:
	var pos: Vector2
	var r := 13.0
	var amount := 30.0
	var spin := 0.0


class Particle:
	var pos: Vector2
	var vel: Vector2
	var life: float
	var max_life: float
	var color: Color
	var size: float


var rng := RandomNumberGenerator.new()
var time := 0.0
var mode := "sandbox"           ## "sandbox" or "test"
var threat := 3                 ## directory difficulty
var player: SimShip
var ships: Array[SimShip] = []
var bullets: Array[Bullet] = []
var beams: Array[Beam] = []
var icons: Array[Icon] = []
var fuel_cells: Array[FuelCell] = []
var particles: Array[Particle] = []
var gate_pos := Vector2(W - 180, H - 160)
var gate_open := false
var over := false
var campaign := {"team": "Avengers", "difficulty": 1.0, "missiles": 5, "laserLevel": 1, "credits": 0, "warrant": 0, "relations": {}}
var telemetry := {"started": 0.0, "maxSpeed": 0.0, "timeTo90": -1.0, "shots": 0}
var infinite_test_resources := true
var message_timer := 0.0        ## legacy game.messageTimer: gates low-priority repeat messages
var _next_id := 1


# ------------------------------------------------------------------ setup

func setup(hull: Dictionary, p_mode := "sandbox", p_threat := 3, seed_value := -1) -> void:
	if seed_value >= 0:
		rng.seed = seed_value
	else:
		rng.randomize()
	mode = p_mode
	threat = p_threat
	var team: String = campaign["team"]
	var rel := {}
	var fac := DataStore.factions()
	for f in fac:
		rel[f] = float(fac[team]["bias"].get(f, 0))
	rel[team] = 100.0
	campaign["relations"] = rel
	player = make_player(hull)
	if mode == "test":
		_setup_test_range()
	else:
		var icon_count := 6
		for i in icon_count:
			spawn_icon()
		for i in 3 + threat:
			spawn_fuel()
		var base := maxi(1, ceili(threat * 0.72))
		var count := maxi(1, roundi(base * maxf(0.8, campaign["difficulty"])))
		for i in count:
			spawn_ai()
		ensure_special_enemies()
		msg("Entering SANDBOX://FLIGHT. Recover %d icons." % icons.size())
	sfx(330, 0.1)


## Mirrors startWave's player construction from v6Performance.
func make_player(hull: Dictionary) -> SimShip:
	var perf := ShipPerformance.compute(hull)
	var p := SimShip.new()
	p.id = _id()
	p.is_player = true
	p.name = "Operator"
	p.team = campaign["team"]
	p.pos = Vector2(W / 2, H / 2)
	p.a = -PI / 2
	p.r = 18
	p.hull_def = hull
	p.texture = load(hull.get("art", "res://assets/ships/red_falcon.png")) if hull.has("art") else null
	p.max_hull = perf.maxHull; p.hull = perf.maxHull
	p.max_fuel = perf.maxFuel; p.fuel = perf.maxFuel
	p.max_speed = perf.maxSpeed
	p.acceleration = perf.acceleration
	p.turn_rate = perf.turnRate
	p.fuel_burn = perf.fuelBurn
	p.coast_drag = perf.coastDrag
	p.fire_interval = perf.fireInterval
	p.weapon_damage = perf.damage
	p.weapon_cooling = perf.cooling
	p.heat_per_shot = perf.heatPerShot
	p.missile_damage = perf.missileDamage
	p.shield_hp = perf.shield; p.max_shield = perf.shield
	p.shield_recharge_factor = perf.shieldRechargeFactor
	p.cloak_chance = perf.cloak
	p.repair_rate = perf.repair
	p.pickup_radius = perf.pickupRadius
	p.salvage_mult = perf.salvageMult
	p.invuln = 4.0
	p.stats = perf.stats
	p.modules = perf.mods
	return p


func _setup_test_range() -> void:
	campaign["missiles"] = 999
	telemetry = {"started": time, "maxSpeed": 0.0, "timeTo90": -1.0, "shots": 0}
	var t1 := _make_npc("grunt", "Pirates", false, player.pos + Vector2(460, 0))
	t1.name = "STATIONARY TARGET"; t1.team = "Target"; t1.color = Color("#ffcf4a"); t1.hull = 9999; t1.max_hull = 9999
	t1.ai = "test"; t1.test_ai = "stationary"; t1.a = PI; t1.r = 28; t1.cd = 99
	var t2 := _make_npc("skirmisher", "Speed", false, player.pos + Vector2(-420, -180))
	t2.name = "MOVING TARGET"; t2.team = "Target"; t2.color = Color("#63ffb4"); t2.hull = 9999; t2.max_hull = 9999
	t2.ai = "test"; t2.test_ai = "mover"; t2.r = 25; t2.cd = 99
	ships.append(t1)
	ships.append(t2)
	msg("Factory test range active. Measure speed, turning, heat and fuel use.")


func _id() -> int:
	_next_id += 1
	return _next_id


# ------------------------------------------------------------------ helpers

func rnd(a: float, b: float) -> float:
	return a + rng.randf() * (b - a)


func pick(arr: Array) -> Variant:
	return arr[rng.randi() % arr.size()]


func msg(text: String, duration := 3.2) -> void:
	message_timer = duration
	message.emit(text, duration)


## Message that only shows when no other message is active (legacy `if(game.messageTimer<=0)msg(...)`).
func msg_if_idle(text: String, duration := 3.2) -> void:
	if message_timer <= 0:
		msg(text, duration)


func sfx(freq: float, dur := 0.07, wave := "square", vol := 0.035) -> void:
	sound.emit(freq, dur, wave, vol)


func wrap_pos(v: Vector2) -> Vector2:
	if v.x < 0: v.x += W
	if v.x > W: v.x -= W
	if v.y < 0: v.y += H
	if v.y > H: v.y -= H
	return v


## Shortest wrapped offset from `from` to `to` (rendering/radar only; AI uses raw distance like the legacy code).
static func wrapped_delta(from: Vector2, to: Vector2) -> Vector2:
	var d := to - from
	if d.x < -W / 2: d.x += W
	if d.x > W / 2: d.x -= W
	if d.y < -H / 2: d.y += H
	if d.y > H / 2: d.y -= H
	return d


func burst(at: Vector2, color: Color, n: int) -> void:
	for i in n:
		var ang := rnd(0, TAU)
		var sp := rnd(25, 170)
		var q := Particle.new()
		q.pos = at
		q.vel = Vector2(cos(ang), sin(ang)) * sp
		q.life = rnd(0.25, 0.9)
		q.max_life = q.life
		q.color = color
		q.size = rnd(1, 4)
		particles.append(q)


func far_spawn(min_distance := 650.0) -> Vector2:
	var p := Vector2.ZERO
	var tries := 0
	while true:
		p = Vector2(rnd(100, W - 100), rnd(100, H - 100))
		tries += 1
		if player == null or p.distance_to(player.pos) >= min_distance or tries >= 40:
			break
	return p


# ------------------------------------------------------------------ spawning

func spawn_icon() -> Icon:
	var o := Icon.new()
	o.kind = pick(ICON_TYPES)
	o.infected = rng.randf() < 0.14
	var spd := rnd(8, 18)
	var ang := rnd(0, TAU)
	o.pos = Vector2(rnd(180, W - 180), rnd(180, H - 180))
	o.r = 24.0 if o.kind == "FOLDER" else 22.0
	o.value = 10 + threat * 4
	o.spin = rnd(0, TAU)
	o.vel = Vector2(cos(ang), sin(ang)) * spd
	o.drift_timer = rnd(1.8, 4.2)
	icons.append(o)
	# Legacy also spawns orbiting icon defenders here (makeDefender) — Milestone 2.
	return o


func spawn_fuel() -> void:
	var f := FuelCell.new()
	f.pos = Vector2(rnd(100, W - 100), rnd(100, H - 100))
	f.spin = rnd(0, TAU)
	fuel_cells.append(f)


func _weighted(weights: Dictionary) -> String:
	var total := 0.0
	for k in weights:
		total += weights[k]
	var roll := rng.randf() * total
	for k in weights:
		roll -= weights[k]
		if roll <= 0:
			return k
	return weights.keys()[-1]


func _make_npc(arch: String, team: String, hostile: bool, at: Vector2) -> SimShip:
	var def: Dictionary = DataStore.npc_archetypes()["archetypes"][arch]
	var s := SimShip.new()
	s.id = _id()
	s.pos = at
	s.a = rnd(0, TAU)
	s.r = def.radius
	s.hull = def.hullBase + threat * 8 + (8 if hostile else 0)
	s.max_hull = s.hull
	s.team = team
	s.color = DataStore.faction_color(team)
	s.ai = def.ai if hostile else "collector"
	s.name = pick(NPC_NAMES)
	s.archetype = arch
	s.hull_def = {"gridSize": 48}
	s.texture = FactionPalette.npc_texture(arch, team)
	s.weapon_damage = def.damage + threat * 0.35
	s.weapon_cycle_factor = def.cycle
	s.ai_accel = def.accel + threat * 3
	s.ai_max_speed = def.maxSpeed + threat * 4
	s.ai_turn = def.turn
	s.beam_cooldown = rnd(0.8, 1.6)
	return s


## Effective spawnAI: v6.9 base → v7.2.2 relation aggression → v7.2.3 PrepareShip.
func spawn_ai() -> SimShip:
	var factions := []
	for f in DataStore.factions():
		if f != "Enforcers" and f != player.team:
			factions.append(f)
	var team: String = pick(factions)
	var rel: float = campaign["relations"].get(team, 0.0)
	var hostile := (rel < -25 and rng.randf() < 0.28 + threat * 0.05) or rng.randf() < 0.06 + threat * 0.055
	var at := far_spawn(720 - threat * 35)
	var weights: Dictionary = DataStore.npc_archetypes()["hostileWeights" if hostile else "collectorWeights"]
	var s := _make_npc(_weighted(weights), team, hostile, at)
	ships.append(s)
	if rel <= -25:
		NpcAI.make_aggressive(self, s)
	elif rel >= 25 and s.ai == "collector":
		s.aggro_to_player = false
	NpcAI.prepare(self, s)
	return s


## v723EnsureSpecialEnemies: skirmisher at threat ≥ 2, beam at ≥ 3 (normal/duel/black-hole, never test).
func ensure_special_enemies() -> void:
	if mode == "test":
		return
	if threat >= 2:
		_spawn_required("skirmisher")
	if threat >= 3:
		_spawn_required("beam")


func _spawn_required(arch: String) -> bool:
	for s in ships:
		if not s.dead and s.archetype == arch and NpcAI.COMBAT_AIS.has(s.ai):
			return true
	var replaced: SimShip = null
	for i in ships.size():
		var s := ships[i]
		if not s.dead and s.cargo_icon == null and s.ai == "hostile" and not (s.archetype in ["skirmisher", "beam"]):
			replaced = s
			ships.remove_at(i)
			break
	for tries in 500:
		var before := ships.size()
		var c := spawn_ai()
		if c.archetype == arch:
			c.ai = arch
			c.aggro_to_player = true
			c.cd = rnd(0.25, 0.7)
			NpcAI.prepare(self, c)
			return true
		ships.resize(before)
	if replaced:
		ships.append(replaced)
	return false


func spawn_enforcer() -> void:
	var def: Dictionary = DataStore.npc_archetypes()["archetypes"]["police"]
	var s := SimShip.new()
	s.id = _id()
	s.pos = player.pos + Vector2(400, 0)
	s.a = PI
	s.r = def.radius
	s.hull = def.hullBase + threat * 12
	s.max_hull = s.hull
	s.team = "Enforcers"
	s.color = DataStore.faction_color("Enforcers")
	s.ai = "enforcer"
	s.name = "INTERCEPT ENFORCER"
	s.archetype = "police"
	s.hull_def = {"gridSize": 48}
	s.texture = FactionPalette.npc_texture("police", "Enforcers")
	s.flash_police = true
	s.weapon_damage = def.damage
	s.weapon_cycle_factor = def.cycle
	s.ai_accel = def.accel
	s.ai_max_speed = def.maxSpeed
	s.ai_turn = def.turn
	ships.append(s)
	msg("INTERCEPT ENFORCER: Power down and submit to inspection.")


func crime(reason: String, points: int) -> void:
	campaign["warrant"] += points
	msg("%s. Warrant level %d." % [reason, campaign["warrant"]])
	if campaign["warrant"] >= 20:
		for s in ships:
			if s.team == "Enforcers" and not s.dead:
				return
		spawn_enforcer()


# ------------------------------------------------------------------ main step

## input: {turn: float -1..1, thrust: bool, fire: bool, missile: bool}
func step(dt: float, input: Dictionary) -> void:
	if over:
		return
	time += dt
	message_timer -= dt
	_update_player(dt, input)
	_update_bullets(dt)
	NpcAI.update_ships(self, dt)
	_update_items(dt)
	_update_beams(dt)
	_update_particles(dt)
	if mode != "test":
		_update_mission()
	_purge_dead()


func _update_player(dt: float, input: Dictionary) -> void:
	var p := player
	p.fire -= dt
	p.missile_cd -= dt
	p.thrusting = false
	p.weapon_heat = maxf(0.0, p.weapon_heat - p.weapon_cooling * dt)
	var turn := clampf(float(input.get("turn", 0.0)), -1.0, 1.0)
	p.a += p.turn_rate * dt * turn
	if input.get("thrust", false) and p.fuel > 0:
		p.vel += Vector2(cos(p.a), sin(p.a)) * p.acceleration * dt
		p.fuel -= dt * p.fuel_burn
		p.thrusting = true
	if input.get("fire", false):
		fire_player()
	if input.get("missile", false):
		fire_missile()
	var sp := p.vel.length()
	if sp > p.max_speed:
		p.vel *= p.max_speed / sp
	if not p.thrusting:
		p.vel *= pow(p.coast_drag, dt * 60.0)
	p.pos = wrap_pos(p.pos + p.vel * dt)
	p.fuel = maxf(0.0, p.fuel)
	p.invuln = maxf(0.0, p.invuln - dt)
	p.cloak = not p.thrusting and p.fire < -0.8 and p.cloak_chance > 0
	if p.max_shield > 0:
		p.shield_hp = minf(p.max_shield, p.shield_hp + dt * (2 + p.stats.reactor * 0.35) * p.shield_recharge_factor)
	if p.repair_rate > 0 and time - p.last_damage_at > 5.0:
		p.hull = minf(p.max_hull, p.hull + p.repair_rate * dt)
	if mode == "test":
		if infinite_test_resources:
			p.fuel = p.max_fuel
			campaign["missiles"] = 999
		var s := p.vel.length()
		telemetry.maxSpeed = maxf(telemetry.maxSpeed, s)
		if telemetry.timeTo90 < 0 and s >= p.max_speed * 0.9:
			telemetry.timeTo90 = time - telemetry.started
	if p.fuel <= 0:
		p.vel *= pow(0.5, dt)


func _bullet_color(owner: SimShip) -> Color:
	if owner == player:
		match owner.modules.get("primary", "pulse"):
			"heavy": return Color("#ffd06a")
			"rapid": return Color("#7dffb8")
		return Color("#75eaff")
	if owner.team == "Enforcers":
		return Color("#69bfff")
	return DataStore.faction_color(owner.team, Color("#ff6a5c"))


func fire_player() -> void:
	var p := player
	if p.fire > 0 or p.fuel <= 0 or p.weapon_heat >= 100:
		if p.weapon_heat >= 100:
			msg_if_idle("WEAPON OVERHEATED — allow the cooling system to recover.")
		return
	p.fire = p.fire_interval
	p.weapon_heat = minf(115.0, p.weapon_heat + p.heat_per_shot)
	var level: int = campaign["laserLevel"]
	var b := Bullet.new()
	b.pos = p.hardpoint_world("primary", SHIP_DRAW_SIZE)
	b.vel = Vector2(cos(p.a), sin(p.a)) * (480 + (level - 1) * 60) + p.vel
	b.life = 1.6
	b.team = p.team
	b.damage = p.weapon_damage + level * 2
	b.color = _bullet_color(p)
	b.owner = p
	bullets.append(b)
	telemetry.shots += 1
	var prim: String = p.modules.get("primary", "pulse")
	sfx(410.0 if prim == "heavy" else (820.0 if prim == "rapid" else 690.0), 0.035, "square", 0.02)


func fire_missile() -> void:
	var p := player
	if p.missile_cd > 0 or campaign["missiles"] <= 0:
		return
	p.missile_cd = 0.8
	if mode != "test":
		campaign["missiles"] -= 1
	var target: SimShip = null
	var best := INF
	for s in ships:
		if NpcAI.aggressive_to_player(self, s):
			var d := s.pos.distance_to(p.pos)
			if d < best:
				best = d
				target = s
	var b := Bullet.new()
	b.pos = p.hardpoint_world("secondary", SHIP_DRAW_SIZE)
	b.vel = Vector2(cos(p.a), sin(p.a)) * 240
	b.life = 4
	b.team = p.team
	b.damage = 45 * p.missile_damage
	b.color = Color("#ffb33f")
	b.owner = p
	b.missile = true
	b.target = target
	bullets.append(b)
	sfx(170, 0.12, "sawtooth", 0.03)


func ai_fire(s: SimShip, target: Vector2, kind := "laser") -> void:
	if s.cd > 0:
		return
	var scale: float = campaign["difficulty"]
	var cycle := clampf(s.weapon_cycle_factor, 0.5, 1.0)
	s.cd = (rnd(1.7, 2.5) if kind == "defender" else rnd(1.25, 2.05)) / cycle
	var ang := (target - s.pos).angle()
	var raw := 3.2 if kind == "defender" else (s.weapon_damage if s.weapon_damage > 0 else 4 + threat * 0.7)
	var b := Bullet.new()
	b.pos = s.pos
	b.vel = Vector2(cos(ang), sin(ang)) * 310
	b.life = 2.2
	b.team = s.team
	b.damage = raw * scale
	b.color = _bullet_color(s)
	b.owner = s
	bullets.append(b)


func fire_beam(s: SimShip, target: SimShip) -> void:
	var scale: float = campaign["difficulty"]
	var duration := 1.6 + rnd(0.15, 0.45)
	s.cd = 2.0 / clampf(s.weapon_cycle_factor, 0.5, 1.2)
	s.beam_state = "firing"
	s.beam_fire_time = duration
	s.beam_recover = 1.0
	var bm := Beam.new()
	bm.owner = s
	bm.team = s.team
	bm.life = duration
	bm.damage = (s.weapon_damage if s.weapon_damage > 0 else 6.5) * 3.25 * scale
	bm.color = DataStore.faction_color(s.team, Color("#ff5c78"))
	beams.append(bm)
	if target != player:
		NpcAI.retaliate(self, target, s, false)
	sfx(210, 0.08, "square", 0.04)


func damage_player(n: float) -> void:
	var p := player
	if p.invuln > 0 or over:
		return
	if p.cloak and rng.randf() < p.cloak_chance:
		msg("Cloaking field deflected incoming fire.")
		return
	var dmg := n
	if p.shield_hp > 0:
		var absorbed := minf(p.shield_hp, dmg * 0.85)
		p.shield_hp -= absorbed
		dmg -= absorbed
	p.hull -= dmg
	p.last_damage_at = time
	burst(p.pos, Color("#f66"), 5)
	sfx(95, 0.05, "sawtooth", 0.04)
	if p.hull <= 0:
		_end(false, "Your ship was destroyed.")


func damage_ship(s: SimShip, amount: float, attacker: SimShip) -> void:
	s.hull -= amount
	if s.hull <= 0 and not s.dead:
		destroy_ship(s, attacker)


## v7.2.4 → v7.2.2 → base destroyShip chain.
func destroy_ship(s: SimShip, killer: SimShip) -> void:
	var dropped: Icon = s.cargo_icon
	if dropped:
		dropped.carrier = null
		dropped.pos = s.pos
		dropped.vel = s.vel * 0.35 + Vector2(rnd(-20, 20), rnd(-20, 20))
		dropped.drift_timer = rnd(0.4, 1.1)
		s.cargo_icon = null
		if icons.has(dropped):
			dropped.drop_protected_until = time + DROP_PROTECTION
	s.dead = true
	burst(s.pos, s.color, 25)
	sfx(120, 0.18, "sawtooth", 0.05)
	if killer == player:
		campaign["credits"] += 8 + threat * 3
		if s.team == "Enforcers":
			crime("Attacked an Enforcer", 40)
		if campaign["relations"].has(s.team):
			campaign["relations"][s.team] -= 10


func _update_bullets(dt: float) -> void:
	for b in bullets:
		b.life -= dt
		if b.life <= 0:
			continue
		if b.missile:
			if b.target and not NpcAI.aggressive_to_player(self, b.target):
				b.target = null
			if b.target and not b.target.dead:
				var ang := (b.target.pos - b.pos).angle()
				var sp := b.vel.length() if b.vel.length() > 0 else 250.0
				b.vel += (Vector2(cos(ang), sin(ang)) * sp - b.vel) * dt * 1.25
		b.pos = wrap_pos(b.pos + b.vel * dt)
		if b.team != player.team and b.pos.distance_to(player.pos) < player.r + 4:
			damage_player(b.damage)
			b.life = 0
			continue
		var consumed := false
		for s in ships:
			if s.dead or s == b.owner or b.team == s.team or b.pos.distance_to(s.pos) >= s.r + 4:
				continue
			NpcAI.retaliate(self, s, b.owner, b.owner == player)
			b.life = 0
			consumed = true
			burst(b.pos, b.color, 5)
			damage_ship(s, b.damage, b.owner)
			break
		if consumed:
			continue
		if b.owner == player:
			for o in icons:
				if o.carrier or o.drop_protected_until > time:
					continue
				if b.pos.distance_to(o.pos) >= o.r:
					continue
				o.hp -= b.damage
				b.life = 0
				burst(o.pos, Color.WHITE, 4)
				if o.hp <= 0:
					icons.erase(o)
					crime("Destroyed a clean icon", 20)
					msg("ICON DESTROYED — LAW VIOLATION")
					sfx(110, 0.2)
				break
	bullets = bullets.filter(func(x: Bullet) -> bool: return x.life > 0)


static func dist_point_segment(p: Vector2, a: Vector2, b: Vector2) -> float:
	var d := b - a
	var len2 := d.length_squared()
	if len2 == 0:
		len2 = 1
	var t := clampf((p - a).dot(d) / len2, 0, 1)
	return p.distance_to(a + d * t)


func _update_beams(dt: float) -> void:
	for bm in beams:
		bm.life -= dt
		var o := bm.owner
		if o == null or o.dead:
			bm.life = 0
			continue
		bm.p1 = o.pos
		bm.p2 = o.pos + Vector2(cos(o.a), sin(o.a)) * bm.length
		if bm.team != player.team and dist_point_segment(player.pos, bm.p1, bm.p2) < bm.width + player.r * 0.45:
			damage_player(bm.damage * dt)
		for s in ships:
			if not s.dead and s != o and bm.team != s.team and dist_point_segment(s.pos, bm.p1, bm.p2) < bm.width + s.r * 0.45:
				damage_ship(s, bm.damage * dt, o)
	beams = beams.filter(func(x: Beam) -> bool: return x.life > 0)


func _update_items(dt: float) -> void:
	var p := player
	for i in range(icons.size() - 1, -1, -1):
		var o := icons[i]
		o.spin += dt * 0.45
		if o.carrier and not o.carrier.dead:
			o.pos = o.carrier.pos
			continue
		if o.carrier and o.carrier.dead:
			o.carrier = null
		o.drift_timer -= dt
		if o.drift_timer <= 0:
			var ang := o.vel.angle() + rnd(-1.2, 1.2)
			var spd := clampf(o.vel.length() + rnd(-3, 3), 7, 20)
			o.vel = Vector2(cos(ang), sin(ang)) * spd
			o.drift_timer = rnd(1.5, 3.5)
		o.pos += o.vel * dt
		if o.pos.x < 80 or o.pos.x > W - 80: o.vel.x *= -1
		if o.pos.y < 80 or o.pos.y > H - 80: o.vel.y *= -1
		o.pos = Vector2(clampf(o.pos.x, 70, W - 70), clampf(o.pos.y, 70, H - 70))
		if p.pos.distance_to(o.pos) < p.r + o.r + p.pickup_radius:
			icons.remove_at(i)
			if o.infected:
				p.vel += Vector2(rnd(-150, 150), rnd(-150, 150))
				p.a += PI
				msg("INFECTED %s captured — controls disrupted." % o.kind)
				sfx(90, 0.3, "sawtooth")
			else:
				var earned := roundi(o.value * p.salvage_mult)
				campaign["credits"] += earned
				msg("%s icon secured. +%d credits." % [o.kind, earned])
				sfx(880, 0.08)
			burst(o.pos, Color("#a0f") if o.infected else Color("#4ff"), 15)
	for i in range(fuel_cells.size() - 1, -1, -1):
		var f := fuel_cells[i]
		f.spin += dt
		if p.pos.distance_to(f.pos) < p.r + f.r + p.pickup_radius * 0.6:
			p.fuel = minf(p.max_fuel, p.fuel + f.amount)
			fuel_cells.remove_at(i)
			msg("Fuel cell recovered.")
			sfx(520, 0.07)


func _update_particles(dt: float) -> void:
	for q in particles:
		q.life -= dt
		q.pos += q.vel * dt
		q.vel *= 0.96
	particles = particles.filter(func(x: Particle) -> bool: return x.life > 0)


func _update_mission() -> void:
	if icons.is_empty() and not gate_open:
		gate_open = true
		msg("All icons recovered. Exit gate open.")
	if gate_open and player.pos.distance_to(gate_pos) < 55:
		_end(true, "Directory disinfected.")
	if player.fuel <= 0 and player.vel.length() < 2:
		msg_if_idle("Stranded. Fuel exhausted — collect a fuel cell or restart.")


func _end(won: bool, reason: String) -> void:
	if over:
		return
	over = true
	sfx(740.0 if won else 90.0, 0.25 if won else 0.5, "square" if won else "sawtooth", 0.04)
	finished.emit(won, reason)


func _purge_dead() -> void:
	ships = ships.filter(func(s: SimShip) -> bool: return not s.dead)
