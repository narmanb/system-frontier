class_name TouchRegion
extends Control
## Base for small in-flight HUD widgets that must react to a *second* finger (e.g. tapping
## the radar while holding thrust). Godot only emulates mouse events for the first touch, so
## these widgets read InputEventScreenTouch/Drag directly, and real mouse events on desktop.
## Subclasses override _on_press/_on_drag/_on_release with local coordinates.

var _touch_index := -1
var _mouse_down := false


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE  # input handled in _input below


func _local(screen_pos: Vector2) -> Vector2:
	return get_global_transform_with_canvas().affine_inverse() * screen_pos


func _input(event: InputEvent) -> void:
	if not is_visible_in_tree():
		return
	if event is InputEventScreenTouch:
		if event.pressed and _touch_index == -1 and _hit(_local(event.position)):
			_touch_index = event.index
			_on_press(_local(event.position))
			get_viewport().set_input_as_handled()
		elif not event.pressed and event.index == _touch_index:
			_touch_index = -1
			_on_release(_local(event.position))
			get_viewport().set_input_as_handled()
	elif event is InputEventScreenDrag and event.index == _touch_index:
		_on_drag(_local(event.position))
		get_viewport().set_input_as_handled()
	elif event is InputEventMouseButton and event.device != InputEvent.DEVICE_ID_EMULATION and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed and _hit(_local(event.position)):
			_mouse_down = true
			_on_press(_local(event.position))
			get_viewport().set_input_as_handled()
		elif not event.pressed and _mouse_down:
			_mouse_down = false
			_on_release(_local(event.position))
			get_viewport().set_input_as_handled()
	elif event is InputEventMouseMotion and _mouse_down and event.device != InputEvent.DEVICE_ID_EMULATION:
		_on_drag(_local(event.position))


func cancel() -> void:
	_touch_index = -1
	_mouse_down = false


func _hit(p: Vector2) -> bool:
	return Rect2(Vector2.ZERO, size).has_point(p)


func _on_press(_p: Vector2) -> void: pass
func _on_drag(_p: Vector2) -> void: pass
func _on_release(_p: Vector2) -> void: pass
