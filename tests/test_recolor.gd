extends TestCase
## NPC faction recolor vs. legacy v69→v724 pipeline (tests/fixtures/recolor.json).


func test_recolor_matches_legacy_pixels() -> void:
	var fx := fixture("recolor.json")
	var defs: Dictionary = DataStore.npc_archetypes()["archetypes"]
	for c in fx["cases"]:
		var arch: String = c["archetype"]
		var img: Image = (load(defs[arch]["art"]) as Texture2D).get_image()
		img.convert(Image.FORMAT_RGBA8)
		var out := FactionPalette.recolor_grid(FactionPalette.image_to_grid(img), c["team"], arch, bool(defs[arch]["recolor"]))
		var exp: Array = c["grid"]
		var bad := 0
		var first := ""
		for i in exp.size():
			var e: String = "" if exp[i] == null else str(exp[i]).to_lower()
			if out[i] != e:
				bad += 1
				if first == "":
					first = "px %d: %s != %s" % [i, out[i], e]
		check(bad == 0, "%s/%s: %d mismatched pixels (%s)" % [arch, c["team"], bad, first])


func test_assets_present_and_48px() -> void:
	for id in DataStore.starter_hulls()["order"]:
		var t: Texture2D = load(DataStore.starter_hull(id)["art"])
		check(t != null and t.get_width() == 48 and t.get_height() == 48, "starter %s art is 48x48" % id)
	for id in DataStore.npc_archetypes()["archetypes"]:
		var t: Texture2D = load(DataStore.npc_archetypes()["archetypes"][id]["art"])
		check(t != null and t.get_width() == 48, "npc %s art is 48x48" % id)
