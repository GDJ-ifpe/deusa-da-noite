extends CharacterBody2D

@export var speed := 300.0
@export var gravity := 980.0
@export var jump_velocity := -350.0

func _physics_process(_delta: float) -> void:
	# Aplica gravidade se não estiver no chão
	if not is_on_floor():
		velocity.y += gravity * _delta

	# Movimento horizontal (setas ou A/D)
	velocity.x = 0
	if Input.is_action_pressed("ui_right"):
		velocity.x += 1
	if Input.is_action_pressed("ui_left"):
		velocity.x -= 1

	if velocity.x != 0:
		velocity.x = sign(velocity.x) * speed

		# Vira o placeholder para o lado onde está andando (inverte escala X)
		$ColorRect.scale.x = abs($ColorRect.scale.x) * (1 if velocity.x > 0 else -1)

	# Pulo (espaço, W ou seta para cima), apenas se estiver no chão
	if is_on_floor() and Input.is_action_just_pressed("ui_accept"):
		velocity.y = jump_velocity

	move_and_slide()
