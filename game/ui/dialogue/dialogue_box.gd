extends CanvasLayer

@export var pause_game := true
@export var typing_speed := 0.03
@export var skip_key: int = KEY_X
@export var close_key: int = KEY_ESCAPE
@export var name_font_size := 24
@export var text_font_size := 20
@export var box_color: Color = Color(0.15, 0.15, 0.2, 0.9)
@export var portrait_color: Color = Color(0.4, 0.8, 1.0, 1)
@export var skip_hint_color: Color = Color(0.7, 0.7, 0.7, 1)

var dialogue_data: Dictionary
var current_lines: Array = []
var current_line_index := 0
var current_text := ""
var target_text := ""
var timer := 0.0
var is_typing := false
var is_skippable := false

@onready var panel: Control = $Panel
@onready var background: ColorRect = $Panel/Background
@onready var portrait: ColorRect = $Panel/Portrait
@onready var name_label: Label = $Panel/NameLabel
@onready var text_label: Label = $Panel/TextLabel
@onready var skip_hint: Label = $Panel/SkipHint

func _ready() -> void:
	panel.visible = false
	set_process_input(true)
	add_to_group("dialogue_box")
	process_mode = Node.PROCESS_MODE_ALWAYS
	
	# Aplica cores exportadas
	background.color = box_color
	portrait.color = portrait_color
	skip_hint.modulate = skip_hint_color
	
	# Aplica tamanhos de fonte exportados
	name_label.add_theme_font_size_override("fonts", name_font_size)
	text_label.add_theme_font_size_override("fonts", text_font_size)
	
	load_dialogue_data("res://ui/dialogue/dialogue_data.json")

func load_dialogue_data(path: String) -> void:
	var file = FileAccess.open(path, FileAccess.READ)
	if not file:
		push_error("Não foi possível abrir: " + path)
		return
	var json_text = file.get_as_text()
	file.close()
	var result = JSON.parse_string(json_text)
	if typeof(result) != TYPE_DICTIONARY:
		push_error("Erro ao parsear JSON: dado não é um dicionário")
		return
	dialogue_data = result

func show_dialogue(dialogue_id: String, skip: bool = true) -> void:
	if not dialogue_data:
		push_error("Dados de diálogo não carregados")
		return
	
	var dialogues = dialogue_data["dialogues"]
	if not dialogues:
		push_error("JSON não tem 'dialogues'")
		return
	
	current_line_index = 0
	is_skippable = skip
	var found := false
	for d in dialogues:
		if d["id"] == dialogue_id:
			current_lines = d["lines"]
			found = true
			break
	
	if not found:
		push_error("Diálogo não encontrado: " + dialogue_id)
		return
	
	for d in dialogues:
		if d["id"] == dialogue_id and d.has("pause_game"):
			pause_game = bool(d["pause_game"])
			break
	
	panel.visible = true
	if pause_game:
		get_tree().paused = true
	_show_line()

func _show_line() -> void:
	if current_line_index >= current_lines.size():
		end_dialogue()
		return
	
	var line: Dictionary = current_lines[current_line_index]
	name_label.text = str(line["character"])
	target_text = str(line["text"])
	current_text = ""
	is_typing = true
	timer = 0.0
	text_label.text = ""
	
	if line.has("portrait"):
		portrait.visible = true
	else:
		portrait.visible = false
	
	skip_hint.visible = is_skippable

func _process(_delta: float) -> void:
	if not panel.visible or not is_typing:
		return
	
	timer += _delta
	if timer >= typing_speed:
		timer = 0.0
		if current_text.length() < target_text.length():
			current_text = target_text.substr(0, current_text.length() + 1)
			text_label.text = current_text
		else:
			is_typing = false

func _input(event: InputEvent) -> void:
	if not panel.visible:
		return
	
	# Fecha o diálogo com ESC (força o fechamento)
	if event is InputEventKey and event.pressed and event.keycode == close_key:
		end_dialogue()
		return
	
	# Avança com clique do mouse
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		_advance()
	
	# Avança com tecla (padrão X)
	if event is InputEventKey and event.pressed and event.keycode == skip_key:
		_advance()

func _advance() -> void:
	if is_typing and is_skippable:
		is_typing = false
		text_label.text = target_text
		current_text = target_text
	elif not is_typing:
		next_line()

func next_line() -> void:
	current_line_index += 1
	_show_line()

func end_dialogue() -> void:
	panel.visible = false
	current_lines = []
	current_line_index = 0
	text_label.text = ""
	if pause_game:
		get_tree().paused = false
