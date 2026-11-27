extends TestCase
## SaveService: versioned atomic writes, backup fallback, resets, legacy import.

const ROOT := "user://test_saves/"


func _fresh() -> void:
	SaveService.root = ROOT
	SaveService.reset("all")


func _done() -> void:
	SaveService.reset("all")
	SaveService.root = "user://"


func test_campaign_roundtrip_and_backup() -> void:
	_fresh()
	check(not SaveService.has_campaign(), "starts empty")
	var c := Campaign.create({"pilot": "Ace"})
	c["credits"] = 42
	check(SaveService.save_campaign(c), "save ok")
	var l: Dictionary = SaveService.load_campaign()
	check(l["pilot"] == "Ace" and l["credits"] == 42, "roundtrip")
	c["credits"] = 99
	SaveService.save_campaign(c)
	# corrupt the main file: loader must fall back to the previous save (.bak)
	var f := FileAccess.open(ROOT + "campaign.json", FileAccess.WRITE)
	f.store_string("{not json")
	f.close()
	var b: Dictionary = SaveService.load_campaign()
	check(b != null and b["credits"] == 42, "falls back to backup")
	_done()


func test_reset_kinds_are_independent() -> void:
	_fresh()
	SaveService.save_campaign(Campaign.create({}))
	SaveService.save_custom_ships([{"id": "custom_1", "name": "X", "stats": {}, "grid": []}])
	SaveService.reset("factory")
	check(SaveService.has_campaign() and SaveService.custom_ships().is_empty(), "factory reset keeps campaign")
	SaveService.save_custom_ships([{"id": "custom_1", "name": "X", "stats": {}}])
	SaveService.reset("campaign")
	check(not SaveService.has_campaign() and SaveService.custom_ships().size() == 1, "campaign reset keeps ships")
	_done()


func test_legacy_import() -> void:
	_fresh()
	var legacy := {"pilot": "Old", "team": "Knights", "credits": 7, "ship": {"id": "lance"}, "dirs": [{"id": 0, "name": "WINDOWS", "type": "normal"}]}
	check(SaveService.import_legacy(JSON.stringify(legacy)) == "campaign", "campaign detected")
	check(SaveService.load_campaign()["pilot"] == "Old", "campaign imported")
	check(SaveService.import_legacy(JSON.stringify([{"name": "Bird", "stats": {"brake": 3}, "grid": [null, "#ffffff"]}])) == "ships", "ships detected")
	var ships := SaveService.custom_ships()
	check(ships.size() == 1 and ships[0]["stats"]["inertia"] == 3, "ship migrated")
	check(SaveService.import_legacy("nonsense") == "", "rejects junk")
	_done()
