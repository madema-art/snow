class_name SnowTitle
extends CanvasLayer
## Launch presentation: the game fades up out of the boot-splash colour onto the
## summit and the SNOW wordmark rests over the view for a moment, then leaves.
## Shown once per launch only (never on restart), gone the instant the rider
## pushes off or the pause menu opens. It is not a HUD: nothing is ever drawn
## during a descent.
const NAVY := Color(0.027, 0.047, 0.086)   # same as the boot splash background
const FADE_IN := 0.9
const HOLD := 2.6
const FADE_OUT := 1.2
var run: SnowRun
var veil: ColorRect
var mark: Label
var rule: ColorRect
var age := 0.0
var done := false

func _ready() -> void:
	layer = 8
	process_mode = Node.PROCESS_MODE_ALWAYS
	veil = ColorRect.new()
	veil.color = NAVY
	veil.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	veil.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(veil)
	mark = Label.new()
	mark.text = "S N O W"
	mark.add_theme_font_size_override("font_size", 300)
	mark.add_theme_color_override("font_color", Color(0.96, 0.98, 1.0))
	mark.add_theme_color_override("font_shadow_color", Color(0.0, 0.03, 0.08, 0.55))
	mark.add_theme_constant_override("shadow_offset_y", 6)
	mark.add_theme_constant_override("shadow_outline_size", 24)
	mark.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	mark.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	mark.offset_top = 260
	mark.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(mark)
	rule = ColorRect.new()
	rule.color = Color("ff7a2a")
	rule.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	rule.offset_left = -330
	rule.offset_right = 330
	rule.offset_top = 690
	rule.offset_bottom = 698
	rule.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(rule)
	mark.modulate.a = 0.0
	rule.modulate.a = 0.0

func dismiss() -> void:
	done = true
	visible = false

func _process(delta: float) -> void:
	if done:
		return
	age += delta
	# Leave at once when the player acts.
	if run != null and (run.state != "ready" or get_tree().paused) and age < FADE_IN + HOLD:
		age = FADE_IN + HOLD
	veil.color.a = 1.0 - smoothstep(0.0, FADE_IN, age)
	var shown := smoothstep(FADE_IN * 0.5, FADE_IN * 1.4, age) * (1.0 - smoothstep(FADE_IN + HOLD, FADE_IN + HOLD + FADE_OUT, age))
	mark.modulate.a = shown
	rule.modulate.a = shown
	if age >= FADE_IN + HOLD + FADE_OUT:
		dismiss()
