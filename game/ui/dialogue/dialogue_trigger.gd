extends Area2D

@export var dialogue_id: String = ""
@export var trigger_once: bool = true

var triggered := false

func _ready() -> void:
	body_entered.connect(_on_body_entered)

func _on_body_entered(body: Node) -> void:
	if triggered and trigger_once:
		return
	if body.is_in_group("player") or body.name == "Player":
		var dialogue_box = get_tree().get_first_node_in_group("dialogue_box")
		if dialogue_box:
			dialogue_box.show_dialogue(dialogue_id, true)
			triggered = true
