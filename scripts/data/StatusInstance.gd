class_name StatusInstance
extends RefCounted
## A live status sitting on a component or a mech during combat (as opposed
## to StatusEffectData, which is the "this card applies X" declaration on a
## card). Combat Rules / Statuses & Links define what each status does.

var status: String
var stacks: int

func _init(p_status: String = "", p_stacks: int = 0) -> void:
	status = p_status
	stacks = p_stacks

func clone() -> StatusInstance:
	return StatusInstance.new(status, stacks)
