class_name StrategyBar
extends TouchRegion
## Strategy-mode autopilot priorities (legacy #strategyControls): Collect, Attack, Evade, Exit.

signal command(name: String)

const COMMANDS := ["collect", "attack", "evade", "exit"]
var current := "collect"
var _down := -1


func _index_at(p: Vector2) -> int:
	return clampi(int(p.x / (size.x / COMMANDS.size())), 0, COMMANDS.size() - 1)


func _on_press(p: Vector2) -> void:
	_down = _index_at(p)
	queue_redraw()


func _on_release(p: Vector2) -> void:
	if _hit(p) and _index_at(p) == _down:
		current = COMMANDS[_down]
		command.emit(current)
	_down = -1
	queue_redraw()


func _draw() -> void:
	var w := size.x / COMMANDS.size()
	for i in COMMANDS.size():
		var r := Rect2(i * w + 2, 0, w - 4, size.y)
		var on: bool = COMMANDS[i] == current or i == _down
		Win95.bevel(self, r, "pressed" if on else "raised", Win95.LIGHT if on else Color(Win95.FACE, 0.9))
		var t: String = COMMANDS[i].capitalize()
		var tw := Win95.text_width(t, 15, true)
		Win95.text(self, r.get_center() + Vector2(-tw / 2, 5), t, 15, Win95.TEXT, true)
