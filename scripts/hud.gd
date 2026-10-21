class_name HUD
extends CanvasLayer
## Player frame, target frame, cast bar, action bar, error text and a controls panel.

const GOLD := Color(0.78, 0.66, 0.38)
const PANEL_BG := Color(0.05, 0.05, 0.07, 0.82)

var player: Player

var _root: Control
var _player_bar: ProgressBar
var _target_frame: Panel
var _target_name: Label
var _target_bar: ProgressBar
var _target_hp: Label
var _cast_panel: Panel
var _cast_bar: ProgressBar
var _cast_fill: StyleBoxFlat
var _cast_label: Label
var _cast_fade := 0.0
var _action_bar: Panel
var _slots: Array = []
var _icon: SpellIcon
var _key_label: Label
var _error: Label
var _error_time := 0.0
var _help: Label
var _t := 0.0


class SpellIcon:
	extends Control
	var lit := false

	func _draw() -> void:
		var r := Rect2(Vector2.ZERO, size)
		draw_rect(r, Color(0.07, 0.05, 0.15))
		draw_rect(r.grow(-4), Color(0.17, 0.11, 0.33))
		var pts := PackedVector2Array()
		for p in [Vector2(0.6, 0.06), Vector2(0.24, 0.55), Vector2(0.47, 0.55), Vector2(0.34, 0.95),
				Vector2(0.8, 0.4), Vector2(0.56, 0.4), Vector2(0.74, 0.06)]:
			pts.append(p * size)
		draw_colored_polygon(pts, Color(0.75, 0.82, 1.0))
		if lit:
			draw_rect(r, Color(1.0, 0.85, 0.35), false, 3.0)


func setup(p: Player) -> void:
	player = p
	player.target_changed.connect(_on_target_changed)
	player.channel_started.connect(_on_channel_started)
	player.channel_stopped.connect(_on_channel_stopped)
	player.error_message.connect(show_error)
	_on_target_changed(player.target)


func _ready() -> void:
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_root)

	# Player frame
	var pf := _panel(Vector2(16, 16), Vector2(240, 66))
	var pname := _label("Hooded One", 16, Color(0.95, 0.92, 0.85))
	pname.position = Vector2(12, 6)
	pf.add_child(pname)
	_player_bar = _bar(Color(0.15, 0.7, 0.2), Vector2(216, 20))
	_player_bar.position = Vector2(12, 32)
	_player_bar.value = 1.0
	pf.add_child(_player_bar)
	var php := _label("100%", 13, Color.WHITE)
	php.position = Vector2(12, 33)
	php.size = Vector2(216, 18)
	php.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	pf.add_child(php)

	# Target frame
	_target_frame = _panel(Vector2(272, 16), Vector2(240, 66))
	_target_name = _label("", 16, Color(1.0, 0.35, 0.3))
	_target_name.position = Vector2(12, 6)
	_target_frame.add_child(_target_name)
	_target_bar = _bar(Color(0.15, 0.7, 0.2), Vector2(216, 20))
	_target_bar.position = Vector2(12, 32)
	_target_frame.add_child(_target_bar)
	_target_hp = _label("", 13, Color.WHITE)
	_target_hp.position = Vector2(12, 33)
	_target_hp.size = Vector2(216, 18)
	_target_hp.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_target_frame.add_child(_target_hp)
	_target_frame.visible = false

	# Cast bar
	_cast_panel = _panel(Vector2.ZERO, Vector2(330, 34))
	_cast_bar = _bar(Color(0.45, 0.5, 1.0), Vector2(314, 22))
	_cast_bar.position = Vector2(8, 6)
	_cast_bar.value = 1.0
	_cast_fill = _cast_bar.get_theme_stylebox("fill") as StyleBoxFlat
	_cast_panel.add_child(_cast_bar)
	_cast_label = _label("", 14, Color.WHITE)
	_cast_label.position = Vector2(8, 7)
	_cast_label.size = Vector2(314, 20)
	_cast_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_cast_panel.add_child(_cast_label)
	_cast_panel.visible = false

	# Action bar: six slots, Force Lightning on 1.
	_action_bar = _panel(Vector2.ZERO, Vector2(6 * 58 + 10, 68))
	for i in 6:
		var slot := Panel.new()
		slot.mouse_filter = Control.MOUSE_FILTER_IGNORE
		slot.position = Vector2(8 + i * 58, 8)
		slot.size = Vector2(52, 52)
		slot.add_theme_stylebox_override("panel", _style(Color(0.1, 0.1, 0.12, 0.9), Color(0.3, 0.28, 0.22), 2))
		_action_bar.add_child(slot)
		if i == 0:
			_icon = SpellIcon.new()
			_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
			_icon.position = Vector2(2, 2)
			_icon.size = Vector2(48, 48)
			slot.add_child(_icon)
		var key := _label(str(i + 1), 13, Color(0.85, 0.85, 0.85) if i == 0 else Color(0.4, 0.4, 0.4))
		key.position = Vector2(5, 2)
		slot.add_child(key)
		if i == 0:
			_key_label = key
		_slots.append(slot)

	# Red error text, like "Out of range."
	_error = _label("", 22, Color(1.0, 0.22, 0.18))
	_error.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_error.size = Vector2(600, 30)
	_root.add_child(_error)

	# Controls (F1 toggles)
	_help = _label("", 13, Color(0.9, 0.88, 0.8))
	_help.text = "W/S  forward / back\nA/D  turn (strafe with right mouse)\nQ/E  strafe\nLeft drag  look around\nRight drag  steer\nBoth mouse buttons  run\nWheel  zoom\nTab or click  target\n1  Force Lightning (moving cancels)\nEsc  cancel cast / clear target\nNum Lock  autorun\nF1  hide this help"
	_help.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_root.add_child(_help)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("toggle_help"):
		_help.visible = not _help.visible


func _process(delta: float) -> void:
	_t += delta
	var vp := _root.get_viewport_rect().size
	_action_bar.position = Vector2((vp.x - _action_bar.size.x) / 2.0, vp.y - _action_bar.size.y - 14)
	_cast_panel.position = Vector2((vp.x - _cast_panel.size.x) / 2.0, vp.y - 150)
	_error.position = Vector2((vp.x - _error.size.x) / 2.0, 110)
	_help.position = Vector2(vp.x - _help.size.x - 16, 16)

	if player == null:
		return

	# Target frame
	var tgt = player.target
	if is_instance_valid(tgt):
		_target_frame.visible = true
		_target_name.text = tgt.display_name
		_target_bar.value = tgt.hp / tgt.max_hp
		_target_hp.text = "%d / %d" % [int(ceil(tgt.hp)), int(tgt.max_hp)]
	else:
		_target_frame.visible = false

	# Action button: red key when it can't be cast, gold border while channeling.
	var usable := is_instance_valid(tgt) and player.target_in_range()
	_key_label.add_theme_color_override("font_color", Color(0.9, 0.9, 0.9) if usable else Color(1.0, 0.2, 0.15))
	_icon.modulate = Color.WHITE if usable else Color(0.55, 0.55, 0.6)
	if _icon.lit != player.channeling:
		_icon.lit = player.channeling
		_icon.queue_redraw()

	# Cast bar
	if player.channeling:
		_cast_panel.visible = true
		_cast_panel.modulate.a = 1.0
		_cast_bar.value = 1.0
		var pulse := 0.5 + 0.5 * sin(_t * 12.0)
		_cast_fill.bg_color = Color(0.35, 0.42, 1.0).lerp(Color(0.7, 0.78, 1.0), pulse * 0.6)
		_cast_label.text = "%s   %.1fs" % [player.SPELL_NAME, player.channel_time]
	elif _cast_fade > 0.0:
		_cast_fade -= delta
		_cast_panel.modulate.a = clampf(_cast_fade / 0.5, 0.0, 1.0)
		if _cast_fade <= 0.0:
			_cast_panel.visible = false

	# Error text fades out.
	if _error_time > 0.0:
		_error_time -= delta
		_error.modulate.a = clampf(_error_time / 0.6, 0.0, 1.0)


func show_error(text: String) -> void:
	_error.text = text
	_error_time = 1.8
	_error.modulate.a = 1.0


func _on_target_changed(_t2: Node3D) -> void:
	pass   # the frame updates every frame in _process


func _on_channel_started() -> void:
	_cast_fade = 0.0
	_cast_panel.visible = true


func _on_channel_stopped(reason: String) -> void:
	_cast_fill.bg_color = Color(0.8, 0.15, 0.1)
	_cast_label.text = reason
	_cast_fade = 0.9
	_cast_panel.visible = true


# ---------------------------------------------------------------- builders

func _style(bg: Color, border: Color, width := 2) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = border
	sb.set_border_width_all(width)
	sb.set_corner_radius_all(4)
	return sb


func _panel(pos: Vector2, size: Vector2) -> Panel:
	var p := Panel.new()
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.position = pos
	p.size = size
	p.add_theme_stylebox_override("panel", _style(PANEL_BG, GOLD, 2))
	_root.add_child(p)
	return p


func _bar(fill: Color, size: Vector2) -> ProgressBar:
	var b := ProgressBar.new()
	b.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.show_percentage = false
	b.min_value = 0.0
	b.max_value = 1.0
	b.step = 0.0001
	b.size = size
	b.custom_minimum_size = size
	var f := StyleBoxFlat.new()
	f.bg_color = fill
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0.02, 0.02, 0.03)
	b.add_theme_stylebox_override("fill", f)
	b.add_theme_stylebox_override("background", bg)
	return b


func _label(text: String, font_size: int, color: Color) -> Label:
	var l := Label.new()
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.text = text
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_outline_color", Color.BLACK)
	l.add_theme_constant_override("outline_size", 4)
	return l
