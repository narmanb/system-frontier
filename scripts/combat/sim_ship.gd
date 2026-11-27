class_name SimShip
extends RefCounted
## One flying ship (player or NPC). Plain data; behaviour lives in SimWorld / NpcAI.
## Field names follow the legacy entity fields (camelCase → snake_case) for traceability.

var id := 0
var name := ""
var team := ""
var is_player := false
var pos := Vector2.ZERO
var vel := Vector2.ZERO
var a := 0.0            ## heading, radians; 0 = +x, sprite art points "up" (a = -PI/2)
var r := 18.0           ## collision radius
var hull := 100.0
var max_hull := 100.0
var dead := false
var thrusting := false
var color := Color.WHITE

# ---- ship definition (art + mounts)
var hull_def: Dictionary = {}   ## starter hull / custom ship data (gridSize, thrusters, hardpoints)
var texture: Texture2D
var archetype := ""             ## NPC archetype id (grunt, skirmisher, beam, hunter, raider, police)
var draw_size := 96.0

# ---- player flight/weapon state
var max_speed := 200.0
var acceleration := 100.0
var turn_rate := 2.5
var fuel := 100.0
var max_fuel := 100.0
var fuel_burn := 1.0
var coast_drag := 0.9993
var fire := 0.0
var fire_interval := 0.25
var weapon_damage := 5.0
var weapon_cooling := 10.0
var weapon_heat := 0.0
var heat_per_shot := 14.0
var missile_cd := 0.0
var missile_damage := 1.0
var shield_hp := 0.0
var max_shield := 0.0
var shield_recharge_factor := 1.0
var cloak_chance := 0.0
var cloak := false
var repair_rate := 0.0
var pickup_radius := 27.0
var salvage_mult := 1.0
var last_damage_at := -1000.0
var invuln := 0.0
var stats: Dictionary = {}
var modules: Dictionary = {}

# ---- NPC state
var ai := ""
var cd := 0.0
var ai_accel := 90.0
var ai_max_speed := 160.0
var ai_turn := 2.5
var weapon_cycle_factor := 1.0
var aggro_to_player := false
var player_provoked := false
var retaliation_target: SimShip = null
var retaliation_timer := 0.0
var evasion_seed := 0.0
var roam_target = null          ## Vector2 or null
var roam_timer := 0.0
var cargo_icon = null           ## SimWorld.Icon or null
var carry_target = null
var carry_timer := 0.0
var flash_police := false
# skirmisher
var skirmish_phase := ""
var skirmish_timer := 0.0
var attack_side := 0
var burst_remaining := 0
# beam
var beam_state := "idle"
var beam_cooldown := 0.0
var beam_charge := 0.0
var beam_charge_start := 1.5
var beam_fire_time := 0.0
var beam_recover := 0.0
var beam_target: SimShip = null
# test range
var test_ai := ""


func speed() -> float:
	return vel.length()


func grid_size() -> int:
	return int(hull_def.get("gridSize", 48))


func mount(kind: String, id: String) -> Dictionary:
	var list: Array = ShipPerformance.normalize_thrusters(hull_def.get("thrusters"), grid_size()) if kind == "thruster" \
		else ShipPerformance.normalize_hardpoints(hull_def.get("hardpoints"), grid_size())
	for m in list:
		if m["id"] == id:
			return m
	return list[0]


func hardpoint_world(id: String, size := 96.0) -> Vector2:
	return ShipPerformance.mount_world(pos, a, mount("hardpoint", id), grid_size(), size, int(hull_def.get("rotation", 0)))
