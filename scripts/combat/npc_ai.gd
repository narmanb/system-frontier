class_name NpcAI
extends RefCounted
## Native port of the effective NPC behaviour: legacy v7.2.3 `updateShips` (which fully
## replaces the v6.9/v7.2.1/v7.2.2 versions) plus v7.2.4 `v724Retaliate`.
## Faction warfare: Pirates and Predators attack every other faction; valid retaliation
## targets take priority; skirmisher/beam archetypes have dedicated state machines.

const COMBAT_AIS := ["hostile", "skirmisher", "beam", "enforcer", "boss"]
const NON_CONVERTIBLE := ["carrier", "defender", "escort", "boss", "enforcer"]


static func norm_angle(a: float) -> float:
	return atan2(sin(a), cos(a))


static func faction_war(attacker: SimShip, target: SimShip) -> bool:
	if attacker == null or target == null or attacker == target or attacker.dead or target.dead or attacker.team == target.team:
		return false
	if attacker.team == "Pirates" or attacker.team == "Predators":
		return target.team != attacker.team
	return false


static func aggressive_to_player(w: SimWorld, s: SimShip) -> bool:
	if s == null or s.dead or w.player == null or s.team == w.player.team:
		return false
	return s.aggro_to_player or faction_war(s, w.player) or COMBAT_AIS.has(s.ai)


static func combat_ai_for(s: SimShip) -> String:
	if s.team == "Enforcers" or s.archetype == "police":
		return "enforcer"
	if s.archetype == "skirmisher":
		return "skirmisher"
	if s.archetype == "beam":
		return "beam"
	return "hostile"


## v722MakeAggressive (spawn-time, hostile relations).
static func make_aggressive(w: SimWorld, s: SimShip) -> void:
	if s == null or s.dead or s.team == w.player.team:
		return
	s.aggro_to_player = true
	s.ai = combat_ai_for(s)
	s.cd = minf(s.cd, 0.22)
	s.evasion_seed = w.rnd(0, TAU)


## v723PrepareShip (called at spawn and every update).
static func prepare(w: SimWorld, s: SimShip) -> void:
	if s.team == "Pirates" or s.team == "Predators":
		if not (s.ai in ["boss", "defender", "escort", "enforcer", "test"]):
			s.ai = combat_ai_for(s)
		if w.player and s.team != w.player.team:
			s.aggro_to_player = true


## v724Retaliate.
static func retaliate(w: SimWorld, victim: SimShip, attacker: SimShip, from_player: bool) -> void:
	if victim == null or attacker == null or victim.dead or attacker.dead or victim.team == attacker.team:
		return
	if victim.ai == "test":
		return
	victim.retaliation_target = attacker
	victim.retaliation_timer = 12.0
	if attacker == w.player or from_player:
		victim.aggro_to_player = true
	if not NON_CONVERTIBLE.has(victim.ai):
		victim.ai = victim.archetype if victim.archetype in ["skirmisher", "beam"] else "hostile"
	victim.cd = minf(victim.cd, 0.20)
	if from_player and not victim.player_provoked:
		victim.player_provoked = true
		if w.campaign["relations"].has(victim.team):
			w.campaign["relations"][victim.team] -= 6
		w.msg_if_idle("%s is returning fire." % victim.name, 2.2)


static func valid_retaliation(w: SimWorld, s: SimShip) -> bool:
	var t := s.retaliation_target
	return t != null and not t.dead and t != s and t.team != s.team and (t == w.player or w.ships.has(t))


static func target_score(w: SimWorld, s: SimShip, t: SimShip) -> float:
	var score := s.pos.distance_to(t.pos)
	if t == s.retaliation_target:
		score -= 1000
	if s.team == "Pirates":
		if t.cargo_icon:
			score -= 330
		if t != w.player and t.max_hull > 0:
			score -= (1 - t.hull / t.max_hull) * 110
	if s.team == "Predators":
		var ratio := clampf(t.hull / t.max_hull, 0, 1) if t.max_hull > 0 else 1.0
		score -= (1 - ratio) * 430
		if t.cargo_icon:
			score -= 130
	return score


static func choose_target(w: SimWorld, s: SimShip) -> SimShip:
	if valid_retaliation(w, s):
		return s.retaliation_target
	var candidates: Array[SimShip] = []
	if w.player and not w.player.dead:
		if faction_war(s, w.player) or s.aggro_to_player or COMBAT_AIS.has(s.ai):
			candidates.append(w.player)
	if s.team == "Pirates" or s.team == "Predators":
		for other in w.ships:
			if faction_war(s, other):
				candidates.append(other)
	if candidates.is_empty():
		return null
	var rng_limit := 980.0 if s.team == "Predators" else (880.0 if s.team == "Pirates" else 1200.0)
	var best: SimShip = null
	var best_score := INF
	for t in candidates:
		var d := s.pos.distance_to(t.pos)
		if d > rng_limit and t != s.retaliation_target and t != w.player:
			continue
		var sc := target_score(w, s, t)
		if sc < best_score:
			best = t
			best_score = sc
	return best


static func steer_toward(s: SimShip, target: Vector2, dt: float, power := 0.9) -> void:
	var desired := (target - s.pos).angle()
	var diff := norm_angle(desired - s.a)
	var turn := s.ai_turn if s.ai_turn > 0 else 2.5
	s.a += clampf(diff, -turn * dt, turn * dt)
	var accel := s.ai_accel if s.ai_accel > 0 else 90.0
	s.vel += Vector2(cos(s.a), sin(s.a)) * power * accel * dt
	s.thrusting = power > 0.08


static func away_from(s: SimShip, threat: Vector2) -> Vector2:
	return s.pos + (s.pos - threat)


static func avoid(s: SimShip, target_pos: Vector2, target_r: float, dt: float, weight: float) -> void:
	var d_vec := s.pos - target_pos
	var d := d_vec.length()
	if d == 0:
		d = 1
	var desired := s.r + target_r + 34
	if d < desired:
		var push := (1 - d / desired) * weight
		s.vel += (d_vec / d) * s.ai_accel * dt * 0.68 * push


static func roam_target(w: SimWorld, s: SimShip) -> Vector2:
	if s.roam_target == null or s.roam_timer <= 0 or s.pos.distance_to(s.roam_target) < 48:
		s.roam_timer = w.rnd(1.8, 3.8)
		s.roam_target = Vector2(clampf(s.pos.x + w.rnd(-330, 330), 80, SimWorld.W - 80), clampf(s.pos.y + w.rnd(-250, 250), 80, SimWorld.H - 80))
	return s.roam_target


static func nearest_icon(w: SimWorld, s: SimShip, allow_infected: bool) -> SimWorld.Icon:
	var best: SimWorld.Icon = null
	var bd := INF
	for o in w.icons:
		if o.carrier or (o.infected and not allow_infected):
			continue
		var d := s.pos.distance_to(o.pos)
		if d < bd:
			bd = d
			best = o
	return best


static func pickup_icon(s: SimShip, o: SimWorld.Icon) -> bool:
	if s.cargo_icon or o.carrier or o.infected:
		return false
	s.cargo_icon = o
	s.ai = "carrier"
	o.carrier = s
	o.vel = Vector2.ZERO
	s.roam_timer = 0
	return true


static func carrier_roam(w: SimWorld, s: SimShip, dt: float) -> void:
	if s.carry_target == null or s.carry_timer <= 0 or s.pos.distance_to(s.carry_target) < 55:
		s.carry_timer = w.rnd(1.8, 3.8)
		s.carry_target = Vector2(clampf(s.pos.x + w.rnd(-360, 360), 90, SimWorld.W - 90), clampf(s.pos.y + w.rnd(-270, 270), 90, SimWorld.H - 90))
	s.carry_timer -= dt
	steer_toward(s, s.carry_target, dt, 0.38)
	if s.pos.distance_to(w.player.pos) < 210:
		steer_toward(s, away_from(s, w.player.pos), dt, 0.72)


static func generic_combat(w: SimWorld, s: SimShip, dt: float, target: SimShip) -> void:
	if target == null:
		steer_toward(s, roam_target(w, s), dt, 0.25)
		return
	var d := s.pos.distance_to(target.pos)
	var lead := minf(0.36, d / 1200.0)
	var pred := target.pos + target.vel * lead
	if d > 215:
		steer_toward(s, pred, dt, 0.58)
	else:
		steer_toward(s, away_from(s, target.pos), dt, 0.40)
	if d < 380:
		w.ai_fire(s, pred)


static func skirmisher_step(w: SimWorld, s: SimShip, dt: float) -> void:
	var target := choose_target(w, s)
	if target == null:
		steer_toward(s, roam_target(w, s), dt, 0.36)
		return
	if s.skirmish_phase == "":
		s.skirmish_phase = "approach"
	s.skirmish_timer -= dt
	if s.attack_side == 0:
		s.attack_side = -1 if w.rng.randf() < 0.5 else 1
	var hp := clampf(s.hull / s.max_hull, 0, 1) if s.max_hull > 0 else 1.0
	var d := s.pos.distance_to(target.pos)
	var to_target := (target.pos - s.pos).angle()
	if hp < 0.30 and s.skirmish_phase != "retreat":
		s.skirmish_phase = "retreat"
		s.skirmish_timer = 1.5 + w.rnd(0.2, 0.6)
		s.attack_side *= -1
	match s.skirmish_phase:
		"retreat":
			var ang := to_target + PI + s.attack_side * 0.48
			steer_toward(s, s.pos + Vector2(cos(ang), sin(ang)) * 430, dt, 1.0)
			if s.skirmish_timer <= 0:
				s.skirmish_phase = "reposition"
				s.skirmish_timer = 1.0 + w.rnd(0.25, 0.7)
			return
		"break":
			var ang := to_target + PI + s.attack_side * 0.78
			steer_toward(s, s.pos + Vector2(cos(ang), sin(ang)) * 390, dt, 0.96)
			if s.skirmish_timer <= 0 or d > 520:
				s.skirmish_phase = "reposition"
				s.skirmish_timer = 0.85 + w.rnd(0.25, 0.65)
				if w.rng.randf() < 0.58:
					s.attack_side *= -1
			return
		"reposition":
			var flank := (s.pos - target.pos).angle() + s.attack_side * 1.25
			var point := target.pos + Vector2(cos(flank), sin(flank)) * 330
			steer_toward(s, point, dt, 0.84)
			if s.skirmish_timer <= 0 or s.pos.distance_to(point) < 85:
				s.skirmish_phase = "approach"
				s.skirmish_timer = 1.5
			return
		"attack":
			var pred := target.pos + target.vel * 0.20
			steer_toward(s, pred, dt, 0.46)
			if s.burst_remaining > 0 and s.cd <= 0:
				w.ai_fire(s, pred)
				s.burst_remaining -= 1
				if s.burst_remaining > 0:
					s.cd = 0.10
				else:
					s.cd = 0.72 + w.rnd(0.12, 0.35)
					s.skirmish_phase = "break"
					s.skirmish_timer = 1.0 + w.rnd(0.2, 0.55)
			if s.skirmish_timer <= 0 and s.skirmish_phase == "attack":
				s.skirmish_phase = "break"
				s.skirmish_timer = 0.8
			return
	# approach
	var heading := target.vel.angle() if target.vel.length() > 12 else target.a
	var approach := heading + PI + s.attack_side * 0.92
	var point := target.pos + Vector2(cos(approach), sin(approach)) * 285
	steer_toward(s, point, dt, 0.94 if d > 470 else 0.72)
	var aim_diff := absf(norm_angle(to_target - s.a))
	if d < 430 and d > 175 and aim_diff < 0.72:
		s.skirmish_phase = "attack"
		s.skirmish_timer = 0.9
		s.burst_remaining = 3 if w.rng.randf() < 0.32 else 2
		s.cd = minf(s.cd, 0.06)
	elif d < 165:
		s.skirmish_phase = "break"
		s.skirmish_timer = 0.8


static func beam_step(w: SimWorld, s: SimShip, dt: float) -> void:
	var target := choose_target(w, s)
	s.beam_cooldown -= dt
	if target == null:
		if s.beam_state == "charging":
			s.beam_state = "idle"
		steer_toward(s, roam_target(w, s), dt, 0.28)
		return
	match s.beam_state:
		"firing":
			s.beam_fire_time -= dt
			s.vel *= pow(0.86, dt * 60)
			if s.beam_fire_time <= 0:
				s.beam_state = "recover"
			return
		"recover":
			s.beam_recover -= dt
			s.vel *= pow(0.95, dt * 60)
			if s.beam_recover <= 0:
				s.beam_state = "idle"
				s.beam_cooldown = maxf(s.beam_cooldown, 0.8)
			return
		"charging":
			var bt := s.beam_target
			if bt == null or bt.dead or bt.team == s.team or s.pos.distance_to(bt.pos) > 720:
				s.beam_state = "idle"
				s.beam_cooldown = 0.7
				return
			s.vel *= pow(0.82, dt * 60)
			var lock_diff := norm_angle((bt.pos - s.pos).angle() - s.a)
			s.a += clampf(lock_diff, -0.65, 0.65) * s.ai_turn * dt * 0.48
			s.beam_charge -= dt
			if s.beam_charge <= 0:
				w.fire_beam(s, bt)
				s.beam_cooldown = 3.0 + w.rnd(0.3, 0.8)
			return
	var d := s.pos.distance_to(target.pos)
	if d > 560:
		steer_toward(s, target.pos, dt, 0.55)
		return
	if d < 245:
		steer_toward(s, away_from(s, target.pos), dt, 0.66)
	s.vel *= pow(0.82, dt * 60)
	var diff := norm_angle((target.pos - s.pos).angle() - s.a)
	s.a += clampf(diff, -1, 1) * s.ai_turn * dt * 0.62
	if s.beam_cooldown <= 0 and absf(diff) < 0.58:
		s.beam_state = "charging"
		s.beam_charge = 1.25 + w.rnd(0.12, 0.30)
		s.beam_charge_start = s.beam_charge
		s.beam_target = target


static func update_ships(w: SimWorld, dt: float) -> void:
	var p := w.player
	for s in w.ships:
		if s.dead:
			continue
		s.cd -= dt
		s.thrusting = false
		s.roam_timer -= dt
		if s.retaliation_timer > 0 or s.retaliation_target:
			s.retaliation_timer -= dt
			if s.retaliation_timer <= 0 or not valid_retaliation(w, s):
				s.retaliation_target = null
				s.retaliation_timer = 0
		prepare(w, s)

		if s.ai == "test":
			if s.test_ai == "mover":
				s.vel = Vector2(cos(w.time * 0.7) * 105, sin(w.time * 0.9) * 75)
				s.a = s.vel.angle()
				s.pos = w.wrap_pos(s.pos + s.vel * dt)
			continue

		if s.ai == "defender":
			if s.guard_icon == null or not w.icons.has(s.guard_icon):
				s.ai = "escort"
				s.team = p.team
				s.color = Color("#62ffbd")
				w.msg("Icon defender joined your escort.")
				continue
			s.orbit_angle += s.orbit_speed * dt
			s.pos = s.guard_icon.pos + Vector2(cos(s.orbit_angle), sin(s.orbit_angle)) * s.orbit_r
			s.a = s.orbit_angle + PI * 0.5
			if s.pos.distance_to(p.pos) < 245 and p.team != s.team:
				w.ai_fire(s, p.pos, "defender")
			continue

		if s.ai == "collector" and s.cargo_icon == null:
			var o := nearest_icon(w, s, false)
			if o and s.pos.distance_to(o.pos) < s.r + o.r + 34:
				if pickup_icon(s, o):
					# Port addition: tell the player why an icon vanished (D-036).
					w.msg_if_idle("%s (%s) grabbed an icon — destroy the carrier to drop it." % [s.name, s.team], 3.0)

		match s.ai:
			"escort":
				var best: SimShip = null
				var bd := INF
				for x in w.ships:
					if x != s and not x.dead and (faction_war(x, s) or aggressive_to_player(w, x)):
						var dd := s.pos.distance_to(x.pos)
						if dd < bd:
							bd = dd
							best = x
				if best:
					steer_toward(s, best.pos, dt, 0.62)
					if bd < 320:
						w.ai_fire(s, best.pos)
				else:
					steer_toward(s, p.pos, dt, 0.38)
				avoid(s, p.pos, p.r, dt, 0.55)
			"collector":
				if s.pos.distance_to(p.pos) < 170:
					steer_toward(s, away_from(s, p.pos), dt, 0.88)
				else:
					var ic := nearest_icon(w, s, true)
					if ic:
						steer_toward(s, ic.pos, dt, 0.30 if s.pos.distance_to(ic.pos) < ic.r + 44 else 0.44)
					else:
						steer_toward(s, roam_target(w, s), dt, 0.30)
			"carrier":
				carrier_roam(w, s, dt)
				if valid_retaliation(w, s):
					generic_combat(w, s, dt, s.retaliation_target)
			"skirmisher":
				skirmisher_step(w, s, dt)
			"beam":
				beam_step(w, s, dt)
			"enforcer":
				steer_toward(s, p.pos, dt, 0.64)
				if s.pos.distance_to(p.pos) < 410:
					w.ai_fire(s, p.pos)
				s.flash_police = true
			"hostile":
				generic_combat(w, s, dt, choose_target(w, s))
			"boss":
				var ang := (p.pos - s.pos).angle() + sin(w.time / 0.9) * 0.5
				s.a = ang
				s.vel += Vector2(cos(ang), sin(ang)) * 35 * dt
				s.thrusting = true
				if s.pos.distance_to(p.pos) < 650:
					w.ai_fire(s, p.pos, "boss")
				if w.rng.randf() < dt * 0.4:
					var h := SimWorld.Hazard.new()
					h.pos = s.pos + Vector2(w.rnd(-120, 120), w.rnd(-120, 120))
					h.r = 18
					h.type = "virus"
					h.hp = 25
					w.hazards.append(h)

		for other in w.ships:
			if other != s and not other.dead:
				avoid(s, other.pos, other.r, dt, 0.55 if s.ai == "skirmisher" else 0.20)
		avoid(s, p.pos, p.r, dt, 0.9 if s.ai == "collector" else 0.24)
		var drag := 0.992 if s.ai == "collector" else (0.989 if s.ai == "carrier" else 0.985)
		s.vel *= pow(drag, dt * 60)
		var sp := s.vel.length()
		var cap := 145.0 if s.boss else s.ai_max_speed
		if sp > cap:
			s.vel *= cap / sp
		s.pos = w.wrap_pos(s.pos + s.vel * dt)

		for o in w.icons:
			if o.carrier:
				continue
			var d := s.pos.distance_to(o.pos)
			var mn := o.r + s.r * 0.88
			if d < mn and d > 0:
				var ang := (s.pos - o.pos).angle()
				s.pos += Vector2(cos(ang), sin(ang)) * (mn - d)
				s.vel += Vector2(cos(ang), sin(ang)) * 10
				break
		if s.cargo_icon:
			s.cargo_icon.pos = s.pos
		if s.pos.distance_to(p.pos) < s.r + p.r:
			w.damage_player(12.0 if s.boss else (2.25 if s.ai == "collector" else 3.5))
			var ang := (s.pos - p.pos).angle()
			s.pos += Vector2(cos(ang), sin(ang)) * 18
			s.vel += Vector2(cos(ang), sin(ang)) * 32
