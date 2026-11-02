extends CharacterBody2D
## Personagem protagonista - base jogável.
## Cobre: andar, pulo com altura variável, gravidade, coyote time,
## jump buffer, estados de animação (idle/walk/jump/fall/interact),
## interação com objetos e ganchos para dash / pulo duplo / tempo parado.

# ============================================================
# CONFIGURAÇÕES AJUSTÁVEIS (Inspector)
# ============================================================
@export_group("Movimento")
@export var speed: float = 200.0
@export var acceleration: float = 1500.0
@export var friction: float = 2200.0
@export var jump_velocity: float = -420.0
@export var jump_release_multiplier: float = 0.4
@export var max_fall_speed: float = 1000.0

@export_group("Timers (segundos)")
@export var coyote_time: float = 0.12
@export var jump_buffer_time: float = 0.10
@export var interact_duration: float = 0.30

@export_group("Interação")
@export var interaction_radius: float = 32.0

@export_group("Vida")
@export var max_hp: int = 5
var hp: int

# ============================================================
# AÇÕES (mapeadas no Input Map)
# ============================================================
const ACTION_LEFT     := "ui_left"
const ACTION_RIGHT    := "ui_right"
const ACTION_DOWN     := "ui_down"
const ACTION_JUMP     := "ui_accept"
# Mesma tecla para interagir (contexto: no chão + perto de interagível).
# Se quiser tecla separada, troque para "interact" e mapeie no Input Map.
const ACTION_INTERACT := "interagir"

# ============================================================
# ESTADOS
# ============================================================
enum State { IDLE, RUNNING, JUMPING, FALLING, INTERACTING }
var state: State = State.IDLE

# ============================================================
# NÓS
# ============================================================
@onready var sprite: AnimatedSprite2D         = get_node_or_null("AnimatedSprite2D")
@onready var placeholder: ColorRect           = get_node_or_null("ColorRect")
@onready var collision: CollisionShape2D      = get_node_or_null("CollisionShape2D")
@onready var interaction_area: Area2D         = get_node_or_null("InteractionArea")

# ============================================================
# ESTADO INTERNO
# ============================================================
var facing_right: bool = true
var _coyote_timer: float = 0.0
var _jump_buffer_timer: float = 0.0
var _was_on_floor: bool = false
var _is_interacting: bool = false
var _nearby_interactables: Array = []

# ============================================================
# GANCHOS PARA FEATURES FUTURAS (dash / pulo duplo / tempo parado)
# ============================================================
var can_double_jump: bool = false
var extra_jumps_left: int = 0
var can_dash: bool = false
var is_dashing: bool = false
var time_stopped: bool = false

# ============================================================
# SINAIS
# ============================================================
signal player_died
signal player_hit(hp_restante: int)
signal interacted(target: Node)

# ============================================================
# CICLO DE VIDA
# ============================================================
func _ready() -> void:
	hp = max_hp
	_setup_placeholder()
	_setup_interaction_area()

func _setup_placeholder() -> void:
	var has_frames := false
	if sprite and sprite.sprite_frames:
		has_frames = sprite.sprite_frames.get_animation_names().size() > 0
	if placeholder:
		placeholder.visible = not has_frames
	if sprite:
		sprite.visible = has_frames

func _setup_interaction_area() -> void:
	if not interaction_area:
		return
	var cs := interaction_area.get_node_or_null("CollisionShape2D") as CollisionShape2D
	if cs == null:
		cs = CollisionShape2D.new()
		cs.name = "CollisionShape2D"
		interaction_area.add_child(cs)
	if cs.shape == null:
		var circle := CircleShape2D.new()
		circle.radius = interaction_radius
		cs.shape = circle
	interaction_area.area_entered.connect(_on_interaction_entered)
	interaction_area.area_exited.connect(_on_interaction_exited)
	interaction_area.body_entered.connect(_on_interaction_entered)
	interaction_area.body_exited.connect(_on_interaction_exited)

# ============================================================
# LOOP FÍSICO
# ============================================================
func _physics_process(delta: float) -> void:
	if time_stopped:
		return

	_update_timers(delta)
	_apply_gravity(delta)
	_handle_coyote_time()
	_handle_action_input()
	_handle_horizontal_input(delta)

	move_and_slide()
	_clamp_fall_speed()
	_update_animation_state()
	_was_on_floor = is_on_floor()

# ============================================================
# TIMERS
# ============================================================
func _update_timers(delta: float) -> void:
	if _coyote_timer > 0.0:
		_coyote_timer -= delta
	if _jump_buffer_timer > 0.0:
		_jump_buffer_timer -= delta

# ============================================================
# GRAVIDADE
# ============================================================
func _apply_gravity(delta: float) -> void:
	if not is_on_floor() and not is_dashing:
		velocity += get_gravity() * delta

func _clamp_fall_speed() -> void:
	if velocity.y > max_fall_speed:
		velocity.y = max_fall_speed

# ============================================================
# COYOTE TIME
# ============================================================
func _handle_coyote_time() -> void:
	if _was_on_floor and not is_on_floor():
		_coyote_timer = coyote_time

# ============================================================
# AÇÃO (pulo ou interação - context-sensitive com ui_accept)
# ============================================================
func _handle_action_input() -> void:
	if not Input.is_action_just_pressed(ACTION_JUMP):
		return

	# Contexto: no chão + perto de interagível -> interage.
	if is_on_floor() and not _nearby_interactables.is_empty():
		_try_interact()
		return

	# Caso contrário, comportamento de pulo com buffer + altura variável.
	_jump_buffer_timer = jump_buffer_time
	_try_jump()

	# Soltar cedo = pulo mais curto.
	if Input.is_action_just_released(ACTION_JUMP) and velocity.y < 0.0:
		velocity.y *= jump_release_multiplier

func _try_jump() -> void:
	if _jump_buffer_timer <= 0.0:
		return
	var pode_pular := is_on_floor() or _coyote_timer > 0.0
	if not pode_pular and can_double_jump and extra_jumps_left > 0:
		pode_pular = true
		extra_jumps_left -= 1
	if pode_pular:
		velocity.y = jump_velocity
		_jump_buffer_timer = 0.0
		_coyote_timer = 0.0
		state = State.JUMPING

# ============================================================
# MOVIMENTO HORIZONTAL
# ============================================================
func _handle_horizontal_input(delta: float) -> void:
	if _is_interacting:
		velocity.x = move_toward(velocity.x, 0.0, friction * delta)
		return

	var direction := Input.get_axis(ACTION_LEFT, ACTION_RIGHT)
	if direction != 0.0:
		velocity.x = move_toward(velocity.x, direction * speed, acceleration * delta)
		if direction > 0.0:
			facing_right = true
			if sprite: sprite.flip_h = false
			if placeholder: placeholder.scale.x = abs(placeholder.scale.x)
		else:
			facing_right = false
			if sprite: sprite.flip_h = true
			if placeholder: placeholder.scale.x = -abs(placeholder.scale.x)
	else:
		velocity.x = move_toward(velocity.x, 0.0, friction * delta)

# ============================================================
# INTERAÇÃO
# ============================================================
func _try_interact() -> void:
	if _is_interacting:
		return
	var target = _pick_closest_interactable()
	if target == null:
		return
	_is_interacting = true
	_play_anim("interact")
	if target.has_method("interact"):
		target.interact(self)
	emit_signal("interacted", target)
	await get_tree().create_timer(interact_duration).timeout
	_is_interacting = false

func _pick_closest_interactable():
	var best = null
	var best_dist := INF
	for obj in _nearby_interactables:
		if not is_instance_valid(obj):
			continue
		var d: float = global_position.distance_squared_to(obj.global_position)
		if d < best_dist:
			best_dist = d
			best = obj
	return best

func _on_interaction_entered(node: Node) -> void:
	if node.is_in_group("interactable") and not _nearby_interactables.has(node):
		_nearby_interactables.append(node)

func _on_interaction_exited(node: Node) -> void:
	_nearby_interactables.erase(node)

# ============================================================
# ANIMAÇÃO
# ============================================================
func _update_animation_state() -> void:
	if _is_interacting:
		state = State.INTERACTING
		return

	if not is_on_floor():
		state = State.JUMPING if velocity.y < 0.0 else State.FALLING
		return

	state = State.RUNNING if abs(velocity.x) > 5.0 else State.IDLE

func _process(_delta: float) -> void:
	match state:
		State.IDLE:        _play_anim("idle")
		State.RUNNING:     _play_anim("walk")
		State.JUMPING:     _play_anim("jump")
		State.FALLING:     _play_anim("fall" if _has_anim("fall") else "jump")
		State.INTERACTING: _play_anim("interact")

func _play_anim(nome: String) -> void:
	if sprite == null or sprite.sprite_frames == null:
		return
	if not _has_anim(nome):
		return
	if sprite.animation != nome:
		sprite.play(nome)

func _has_anim(nome: String) -> bool:
	if sprite == null or sprite.sprite_frames == null:
		return false
	return sprite.sprite_frames.has_animation(nome)

# ============================================================
# DANO / MORTE (ganchos)
# ============================================================
func receber_dano(quantidade: int) -> void:
	if hp <= 0:
		return
	hp -= quantidade
	hp = max(hp, 0)
	emit_signal("player_hit", hp)
	if hp <= 0:
		_morrer()

func _morrer() -> void:
	emit_signal("player_died")
	state = State.IDLE
