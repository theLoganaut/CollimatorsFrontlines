class_name CombatScene
extends Control
## The whole combat screen (Combat Slice §5-6), built from Logan's UI
## sketch layout (UI & Screens). Wires CombatManager's signals to the UI
## pieces, resolves card drops (CardUI hands over the release point; the
## crosshair's position picks the target), and paces the enemy turn: each
## enemy attack traces a crosshair over the player's mech for ~2s, locks on,
## fires, and lets the HP animations play before the next one.
##
## Before the first turn, every passive is revealed: the Bastion's first,
## then each Warden's in turn. Each passive's card rises out of its part to
## the middle of the screen, holds, then shrinks into a badge on that mech's
## panel (above the player's health bar, below an enemy's). Passives are
## always in play; they never go in the hand. A click skips the reveal.
##
## During a run (RunState), the fight uses the run's Bastion, carried over
## from the last fight, and the chosen map node's Wardens. Winning goes on
## to the reward screen; losing, or Eject in settings, ejects the pilot
## (debrief, then the War Room). With no run active
## (Main.tscn, dev tools) it's a standalone Bastion vs 3 Wardens with Restart.
##
## Every run fight is recorded (FightRecord, saved by Replays when it ends).
## With `replay_record` set, the screen plays a recorded fight back instead:
## the same mechs and seed, the player's commands fed in one by one at a
## watchable pace (the speed buttons and fast-forward still work), no input
## but hovering, and the end screen goes back to `replay_return`.

const SIDE_MARGIN := 16.0
## The enemy row starts below the speed/settings buttons plus this much.
const ENEMY_TOP_CLEARANCE := 16.0
## The outer enemies sit lower than the middle one by this share of an
## enemy panel's height (a shallow V, as if they're flanking).
const ENEMY_SIDE_DROP := 0.15
## Fraction of the player mech image that hangs off the bottom edge.
const PLAYER_IMAGE_OFFSCREEN := 0.05
## How much of the hand shows above the bottom edge (the rest runs off it).
const HAND_VISIBLE_HEIGHT := 133.0
const HAND_GAP_MARGIN := 6.0 # space between the player mech image and the nearest card
const COLUMN_GAP := 20.0 # between the enemy row and the log / description box / turn panel
const DESCRIPTION_MAX_SIZE := Vector2(420, 360)
const SPEED_GAP := 10.0 # between the speed buttons and the settings button
const ENEMY_TURN_START_DELAY := 0.4
const ENEMY_AFTER_HIT_DELAY := 0.7
## Gap between the hits of a multi-hit card (scaled by game speed): see
## hit_gap(). A volley card (rule "volley": rockets, shot, mortars) fires
## its hits VOLLEY_GAP apart, all but at once.
const HIT_INTERVAL := 0.45
const MIN_HIT_INTERVAL := 0.1
const VOLLEY_GAP := 0.04
## Opening passive reveal (all scaled by game speed).
const REVEAL_START_DELAY := 0.5
const REVEAL_IN := 0.4
const REVEAL_HOLD := 1.1
const REVEAL_OUT := 0.35
const REVEAL_AFTER := 0.2
const REVEAL_SCALE := 1.5
const REVEAL_CARD_GAP := 28.0
const REVEAL_CENTER_Y := 0.42 # share of screen height
const REVEAL_DIM := 0.55 # backdrop alpha; the mech being revealed stays lit
const REVEAL_Z := 240

var combat: CombatManager
## A recorded fight to play back (set before changing to this scene; the
## Pilot Log does), and where to go once it's over.
static var replay_record: Dictionary = {}
static var replay_return: String = SceneRouter.PILOT_LOG
## Pause before each replayed command (scaled by game speed).
const REPLAY_STEP := 0.55
var _replaying: bool = false
var _replay_driving: bool = false # the replay itself is playing a command
var _replay_hit: Dictionary = {} # the part a replayed attack is aimed at
var _replay_bar: HBoxContainer = null
## This fight's recording (FightRecord), {} when not recording.
var _record: Dictionary = {}
var _seed: int = 0
var _background: Dictionary = {}
var player_mech: MechData
var enemy_mechs: Array[MechData] = []
var enemy_labels: Dictionary = {} # MechData -> String

var player_panel: PlayerMechPanel
var enemy_panels: Array[EnemyPanel] = []
var hand_tray: HandTray
var description_box: DescriptionBox
var turn_panel: TurnPanel
var settings_button: SettingsButton
var combat_log: CombatLog
## Opens / closes the log (closed by default; L does the same).
var log_button: Button
var end_screen: EndScreen
var play_field: PlayField
var player_reticle: TargetingReticle
var enemy_reticle: TargetingReticle
var speed_controls: SpeedControls
var turn_plate: TurnPlate
## Opens the location map over the fight (a run fight only), left of the speed buttons.
var map_button: MapButton
var settings_menu: SettingsMenu
var hit_fx: HitFx

var _generation: int = 0 # bumped on restart so a running enemy-turn coroutine stops
var _targeted_grid: ChassisGridUI = null
var _acting_panel: EnemyPanel = null
var _reveal_running: bool = false
var _reveal_nodes: Array[Node] = [] # cards/captions on screen during the reveal
var _reveal_dim: ColorRect = null
var _picker: PanelContainer = null # Reroute's status choice
## While aiming an attack: the enemy whose health bar shows what it would
## take, and whose grid marks the part it would destroy.
var _preview_panel: EnemyPanel = null
## The screen's edges pulse red while the card in hand would overheat (Logan, 2026-10-02).
var _overheat_glow: ColorRect = null
var _glow: float = 0.0 # 0..1, eased toward on/off
var _glow_on: bool = false
var _glow_t: float = 0.0
const GLOW_SHADER := """
shader_type canvas_item;
uniform float strength = 0.0;
void fragment() {
	vec2 uv = UV * 2.0 - 1.0;
	float edge = smoothstep(0.8, 1.45, length(uv));
	COLOR = vec4(0.85, 0.08, 0.04, edge * 0.7 * strength);
}
"""

## Keyboard play: a number key picks the Nth card in the fan; an attack
## then aims at an enemy part (Tab / Shift+Tab cycle, Enter / Space or the
## same number fires, Esc cancels). Plays go through _handle_card_drop, so
## the rules are the mouse's.
var _aim_card: CardData = null
var _aim_ui: CardUI = null
var _aim_target: ComponentData = null
## Gamepad: a self card picked with LB / RB, waiting for A (an attack card
## picked that way aims, like its number key). See Gamepad.
var _pad_card: CardData = null
var _pad_ui: CardUI = null

## A play that would overheat into a possible defeat needs a second press
## within CONFIRM_MS (the card's key, or "end_turn").
const CONFIRM_MS := 4000
var _confirm_key: String = ""
var _confirm_until: int = 0

## Fast-forward: the enemy turn runs FAST_FORWARD times faster while Shift
## or Space is held, or all the time once F toggles it on.
const FAST_FORWARD := 4.0
var _ff_on: bool = false

func _exit_tree() -> void:
	Engine.time_scale = GameSettings.speed # fast-forward never outlives the fight
	PlaytestReport.current_fight = Callable()
	if Gamepad.handler == self:
		Gamepad.handler = null

## The fight so far, as a record (a mid-run playtest report carries it).
func _record_so_far() -> Dictionary:
	if _record.is_empty() or combat == null:
		return {}
	var rec := _record.duplicate(true)
	FightRecord.finish(rec, combat, "in progress")
	return rec

func _ready() -> void:
	UIState.drop_handler = _handle_card_drop
	PlaytestReport.current_fight = _record_so_far
	Gamepad.handler = self
	get_viewport().size_changed.connect(_layout)
	GameSettings.changed.connect(_apply_settings)
	_start_new_combat()

func _start_new_combat() -> void:
	_generation += 1
	UIState.reset()
	for child in get_children():
		child.queue_free()
	player_panel = null # _layout() no-ops until the new UI is built
	enemy_panels.clear()
	enemy_labels.clear()
	_targeted_grid = null
	_acting_panel = null
	_reveal_running = false
	_reveal_nodes.clear()
	_reveal_dim = null
	_record = {}
	_replay_bar = null
	_replaying = not replay_record.is_empty()

	var recorded := FightRecord.mechs(replay_record) if _replaying else {}
	if _replaying and recorded.is_empty():
		_replaying = false
		replay_record = {}
		SceneRouter.go(replay_return)
		return
	if _replaying:
		player_mech = recorded["player"]
		enemy_mechs = recorded["enemies"]
	elif _in_run():
		RunState.run.prepare_player_for_fight() # full carry-over: HP and destroyed parts stay
		player_mech = RunState.run.player_mech
		enemy_mechs = RunState.run.encounter_enemies()
	else:
		player_mech = GameData.fresh_bastion()
		enemy_mechs = [GameData.fresh_scrap_warden(), GameData.fresh_scrap_warden(), GameData.fresh_scrap_warden()]
	# Names from the mech files; repeats get numbered ("Scrap Warden 2").
	var counts := {}
	for m in enemy_mechs:
		counts[m.name] = int(counts.get(m.name, 0)) + 1
	var seen := {}
	for m in enemy_mechs:
		seen[m.name] = int(seen.get(m.name, 0)) + 1
		enemy_labels[m] = m.name if counts[m.name] == 1 else "%s %d" % [m.name, seen[m.name]]

	_seed = int(replay_record["seed"]) if _replaying else randi() % 1000000000
	combat = CombatManager.new(player_mech, enemy_mechs, _seed)
	combat.auto_resolve_enemy_turn = false
	combat.component_damaged.connect(_on_component_damaged)
	combat.component_destroyed.connect(_on_component_destroyed)
	combat.card_played.connect(_on_card_played)
	combat.overheated.connect(_on_overheated)
	combat.turn_changed.connect(_on_turn_changed)
	combat.enemy_turn_started.connect(_on_enemy_turn_started)
	combat.enemy_action.connect(_on_enemy_action)
	combat.hit_landed.connect(_on_hit_landed)
	combat.passive_triggered.connect(_on_passive_triggered)
	combat.hit_missed.connect(_on_hit_missed)
	combat.hand_changed.connect(_on_hand_changed)
	combat.primed_changed.connect(_refresh_primed)
	combat.boss_phase_changed.connect(_on_boss_phase)
	combat.ai_note.connect(func(_m: MechData, text: String): combat_log.log_line(text, CombatLog.CAT_ENEMY))
	if not UIState.intent_hover_changed.is_connected(_on_intent_hover):
		UIState.intent_hover_changed.connect(_on_intent_hover)
	if not UIState.status_hover_changed.is_connected(_on_status_hover):
		UIState.status_hover_changed.connect(_on_status_hover)
	if not UIState.hovered_card_changed.is_connected(_on_card_hover):
		UIState.hovered_card_changed.connect(_on_card_hover)
		UIState.hover_changed.connect(_on_part_hover)
	combat.enemy_set_aside.connect(_on_enemy_set_aside)
	combat.mech_vented.connect(_on_mech_vented)
	combat.chance_failed.connect(_on_chance_failed)
	combat.enemy_retreated.connect(_on_enemy_retreated)
	combat.game_over.connect(_on_game_over)
	_trail_fight()

	call_deferred("_build_ui_and_start")

## The fight's beats in the crash trail (CrashLog): who, the seed, cards
## played, turns, parts lost, the result.
func _trail_fight() -> void:
	CrashLog.crumb("%s: %s vs %s, seed %d" % ["replay" if _replaying else "fight", player_mech.name,
		", ".join(enemy_mechs.map(func(m): return enemy_labels.get(m, m.name))), _seed])
	combat.card_played.connect(func(mech: MechData, card: CardData): CrashLog.crumb("%s plays %s" % [mech.name, card.name]))
	combat.turn_changed.connect(func(phase, turn_number: int): CrashLog.crumb("turn %d: %s" % [turn_number, CombatManager.Phase.keys()[phase]]))
	combat.component_destroyed.connect(func(mech: MechData, component: ComponentData): CrashLog.crumb("%s loses %s" % [mech.name, component.name]))
	combat.mech_vented.connect(func(mech: MechData, amount: int): CrashLog.crumb("%s vents %d" % [mech.name, amount]))
	combat.game_over.connect(func(result): CrashLog.crumb("fight over: %s" % CombatManager.Result.keys()[result]))

func _build_ui_and_start() -> void:
	play_field = PlayField.new()
	add_child(play_field)
	var bg := _pick_background()
	_background = bg
	play_field.set_background(bg)
	Audio.music("boss" if enemy_mechs.any(func(m): return m.tier == "boss") else "combat")
	Audio.ambience("rain" if bg.get("weather", "") == "rain" else (Audio.location_ambience(RunState.run.location) if _in_run() else ""))

	settings_button = SettingsButton.new()
	add_child(settings_button)
	speed_controls = SpeedControls.new()
	add_child(speed_controls)
	if _in_run():
		map_button = MapButton.new()
		add_child(map_button)
		map_button.pressed.connect(func(): LocationMapScreen.peek(self))
	turn_plate = TurnPlate.new()
	add_child(turn_plate)
	turn_plate.resized.connect(func(): _place_turn_plate())

	for i in range(enemy_mechs.size()):
		var panel := EnemyPanel.new()
		add_child(panel)
		panel.setup(enemy_mechs[i], enemy_labels[enemy_mechs[i]])
		enemy_panels.append(panel)

	player_panel = PlayerMechPanel.new()
	add_child(player_panel)
	player_panel.setup(player_mech)

	combat_log = CombatLog.new()
	add_child(combat_log)
	log_button = GlassPanel.button("Log", 12)
	log_button.custom_minimum_size = Vector2(64, 26)
	log_button.size = log_button.custom_minimum_size
	log_button.tooltip_text = "Show or hide the combat log (%s)." % GameSettings.key_label("log")
	log_button.pressed.connect(_toggle_log)
	add_child(log_button)

	description_box = DescriptionBox.new()
	add_child(description_box)

	turn_panel = TurnPanel.new()
	add_child(turn_panel)
	turn_panel.end_turn_pressed.connect(_on_end_turn_pressed)

	hand_tray = HandTray.new()
	add_child(hand_tray)

	enemy_reticle = TargetingReticle.new()
	add_child(enemy_reticle)
	player_reticle = TargetingReticle.new()
	add_child(player_reticle)

	hit_fx = HitFx.new()
	add_child(hit_fx)

	_overheat_glow = ColorRect.new()
	_overheat_glow.set_anchors_preset(Control.PRESET_FULL_RECT)
	_overheat_glow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_overheat_glow.z_index = 140
	var glow_mat := ShaderMaterial.new()
	glow_mat.shader = Shader.new()
	glow_mat.shader.code = GLOW_SHADER
	_overheat_glow.material = glow_mat
	_overheat_glow.visible = false
	add_child(_overheat_glow)
	player_panel.overheat_warning.connect(func(on: bool): _glow_on = on)
	HoloHint.keep_clear = [player_panel.heat_rect] # a card's hint never covers the heat readout

	end_screen = EndScreen.new()
	end_screen.z_index = 300
	end_screen.action_pressed.connect(_on_end_action)
	add_child(end_screen)

	settings_menu = SettingsMenu.new()
	settings_menu.z_index = 400
	settings_menu.restart_requested.connect(_on_restart_pressed)
	add_child(settings_menu)
	if _replaying:
		settings_menu.set_restart_action("Leave replay")
	elif _in_run():
		settings_menu.set_restart_action("Eject (ends the mission)", "Click again to eject")
	settings_button.pressed.connect(settings_menu.open)

	player_panel.combat = combat

	_layout()
	_apply_settings()
	hand_tray.setup(player_mech, combat)

	var names: Array[String] = []
	for m in enemy_mechs:
		names.append(enemy_labels[m] if m.title == "" else "%s (%s)" % [enemy_labels[m], m.title])
	combat_log.log_line("Contact: %s." % ", ".join(names), CombatLog.CAT_TURN)
	if _replaying:
		_build_replay_bar()
	_run_passive_reveal(_generation) # then combat.start_combat()

## Positions everything for the current screen shape. The logical screen is
## at least BASE_SIZE (1152×720) and grows in one direction to match the
## display's aspect ratio (stretch aspect "expand"), so nothing is letterboxed.
## Top middle, level with the speed and settings buttons (same height).
func _place_turn_plate() -> void:
	if turn_plate == null:
		return
	var screen := get_viewport_rect().size
	turn_plate.position = Vector2(round((screen.x - turn_plate.size.x) / 2.0), SIDE_MARGIN)

func _layout() -> void:
	if player_panel == null:
		return
	var screen: Vector2 = get_viewport_rect().size
	size = screen
	play_field.size = screen

	settings_button.position = Vector2(screen.x - SettingsButton.BUTTON_SIZE.x - SIDE_MARGIN, SIDE_MARGIN)
	speed_controls.position = Vector2(settings_button.position.x - SPEED_GAP - speed_controls.size.x, SIDE_MARGIN)
	if map_button != null:
		map_button.position = Vector2(speed_controls.position.x - SPEED_GAP - MapButton.BUTTON_SIZE.x, SIDE_MARGIN)
	_place_turn_plate()
	hit_fx.size = screen
	settings_menu.size = screen
	end_screen.size = screen
	if _reveal_dim != null:
		_reveal_dim.size = screen

	# Enemies: on a background, each stands with its feet on the floor where
	# the background says. Otherwise: below the top-right buttons, image
	# centers at 1/4, 2/4, 3/4 of the screen width, the outer ones dropped
	# lower than the middle (by a share of the smallest panel's height).
	var n := enemy_panels.size()
	var feet := play_field.feet_points(n)
	if feet.size() == n:
		for i in range(n):
			enemy_panels[i].position = feet[i] - enemy_panels[i].feet_offset()
	else:
		var row_y: float = SIDE_MARGIN + SettingsButton.BUTTON_SIZE.y + ENEMY_TOP_CLEARANCE
		var smallest_h: float = INF
		for panel in enemy_panels:
			smallest_h = minf(smallest_h, panel.panel_size.y)
		var side_drop: float = smallest_h * ENEMY_SIDE_DROP
		var half_span: float = maxf(float(n - 1) / 2.0, 1.0)
		for i in range(n):
			var from_center: float = float(i) - float(n - 1) / 2.0
			var image_center_x: float = screen.x * float(i + 1) / float(n + 1)
			var y: float = row_y + side_drop * absf(from_center) / half_span
			enemy_panels[i].position = Vector2(image_center_x - enemy_panels[i].image_center_offset().x, y)
	var enemy_bottom: float = 0.0
	for panel in enemy_panels:
		enemy_bottom = maxf(enemy_bottom, panel.position.y + panel.panel_size.y)

	# Player: image centered, a little of it running off the bottom edge.
	var image_bottom: float = screen.y + PlayerMechPanel.IMAGE_SIZE.y * PLAYER_IMAGE_OFFSCREEN
	player_panel.position = Vector2(
		screen.x / 2.0 - PlayerMechPanel.IMAGE_X - PlayerMechPanel.IMAGE_SIZE.x / 2.0,
		image_bottom - PlayerMechPanel.PANEL_SIZE.y)
	var player_right: float = player_panel.position.x + PlayerMechPanel.PANEL_SIZE.x
	var image_left: float = player_panel.position.x + PlayerMechPanel.IMAGE_X

	# Hand: cards hugging the player mech image on both sides, running off
	# the bottom. The left group tucks under the heat box (which sits above
	# the cards' top edge), so both sides start the same distance from the image.
	var hand_y: float = screen.y - HAND_VISIBLE_HEIGHT
	hand_tray.position = Vector2(0, hand_y)
	hand_tray.size = Vector2(screen.x, HAND_VISIBLE_HEIGHT)
	hand_tray.left_gap = screen.x / 2.0 - image_left + HAND_GAP_MARGIN
	hand_tray.right_gap = player_right - screen.x / 2.0 + HAND_GAP_MARGIN
	hand_tray.relayout()

	# Side column, between the enemy row and the hand: log on the left;
	# description box and turn panel to the right of the player mech.
	var column_top: float = enemy_bottom + COLUMN_GAP
	var column_h: float = minf(hand_y - COLUMN_GAP / 2.0 - column_top, DESCRIPTION_MAX_SIZE.y)
	log_button.position = Vector2(SIDE_MARGIN, column_top)
	combat_log.position = Vector2(SIDE_MARGIN, column_top + log_button.size.y + 6.0)
	turn_panel.position = Vector2(screen.x - TurnPanel.PANEL_SIZE.x - SIDE_MARGIN, column_top)
	var desc_x: float = player_right + SIDE_MARGIN
	var desc_w: float = minf(turn_panel.position.x - SIDE_MARGIN - desc_x, DESCRIPTION_MAX_SIZE.x)
	description_box.position = Vector2(desc_x, column_top)
	description_box.set_box_size(Vector2(desc_w, column_h))

## This fight's background (data/backgrounds.json): one of the run
## location's for the fight's tier (its strongest enemy), picked per fight.
## {} = none (no run, or none drawn for this location and tier yet).
func _pick_background() -> Dictionary:
	if _replaying:
		return replay_record.get("background", {})
	if not _in_run():
		return {}
	var tier := "regular"
	for m in enemy_mechs:
		if m.tier == "boss":
			tier = "boss"
		elif m.tier == "elite" and tier != "boss":
			tier = "elite"
	var options := GameData.backgrounds_for(RunState.run.location.get("id", ""), tier)
	if options.is_empty():
		return {}
	return options[absi(hash([RunState.run.seed_value, RunState.run.current_node_id])) % options.size()]

# ---------- opening passive reveal ----------

func _run_passive_reveal(gen: int) -> void:
	_reveal_running = true
	UIState.input_locked = true
	turn_panel.set_enabled(false)
	turn_plate.set_label("Deploying")
	if _in_run() and not RunState.run.current_node().is_empty():
		turn_plate.set_encounter(int(RunState.run.current_node()["row"]) + 1, RunState.run.encounter_count())
	_reveal_dim = ColorRect.new()
	_reveal_dim.color = Color(0, 0, 0, REVEAL_DIM)
	_reveal_dim.size = get_viewport_rect().size
	_reveal_dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_reveal_dim.z_index = REVEAL_Z
	_reveal_dim.modulate.a = 0.0
	add_child(_reveal_dim)
	_reveal_dim.create_tween().tween_property(_reveal_dim, "modulate:a", 1.0, REVEAL_START_DELAY)
	await get_tree().create_timer(REVEAL_START_DELAY, false).timeout
	var groups: Array = [{"mech": player_mech, "row": player_panel.passive_row, "grid": player_panel.grid, "panel": null, "node": player_panel}]
	for panel in enemy_panels:
		groups.append({"mech": panel.mech, "row": panel.passive_row, "grid": panel.grid, "panel": panel, "node": panel})
	for g in groups:
		if not _reveal_active(gen):
			return
		var comps: Array[ComponentData] = []
		for c in g["mech"].passive_components():
			if not c.destroyed: # a part lost earlier in the run: its badge just shows greyed
				comps.append(c)
		if not comps.is_empty():
			await _reveal_group(gen, g, comps)
	if _reveal_active(gen):
		_end_passive_reveal()

func _reveal_active(gen: int) -> bool:
	return gen == _generation and _reveal_running

## One mech's passives: out of their parts to the middle, hold, then into
## that mech's badge row.
func _reveal_group(gen: int, g: Dictionary, comps: Array[ComponentData]) -> void:
	var panel: EnemyPanel = g["panel"]
	var grid: ChassisGridUI = g["grid"]
	var row: PassiveRow = g["row"]
	var lit: Control = g["node"]
	lit.z_index = REVEAL_Z + 1 # above the dim backdrop
	grid.spotlight = true
	if panel != null:
		panel.set_acting(true)
	var screen: Vector2 = get_viewport_rect().size
	var center := Vector2(screen.x / 2.0, screen.y * REVEAL_CENTER_Y)
	var n := comps.size()
	var slot_w: float = CardUI.BASE_SIZE.x * REVEAL_SCALE + REVEAL_CARD_GAP

	var cards: Array[CardUI] = []
	for i in range(n):
		var card := CardUI.new()
		card.z_index = REVEAL_Z + 10
		add_child(card)
		card.show_passive(comps[i])
		_reveal_nodes.append(card)
		cards.append(card)
		card.global_position = grid.component_center_global(comps[i]) - CardUI.BASE_SIZE / 2.0
		card.scale = Vector2(0.15, 0.15)
		card.modulate.a = 0.0
		var to: Vector2 = center + Vector2((float(i) - float(n - 1) / 2.0) * slot_w, 0.0) - CardUI.BASE_SIZE / 2.0
		var tw := card.create_tween().set_parallel(true)
		tw.tween_property(card, "global_position", to, REVEAL_IN).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
		tw.tween_property(card, "scale", Vector2(REVEAL_SCALE, REVEAL_SCALE), REVEAL_IN).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
		tw.tween_property(card, "modulate:a", 1.0, REVEAL_IN * 0.6)
		grid.flash(comps[i])

	# The caption goes under where the cards actually came to rest (measured,
	# scale included), once they're there.
	await get_tree().create_timer(REVEAL_IN, false).timeout
	if not _reveal_active(gen):
		return
	var span := cards[0].get_global_rect()
	for c in cards:
		span = span.merge(c.get_global_rect())
	var caption := _reveal_caption("%s · passive%s" % [_label_for(g["mech"]), "s" if n > 1 else ""], span.get_center().x, span.end.y + 14.0)
	caption.create_tween().tween_property(caption, "modulate:a", 1.0, 0.15)

	await get_tree().create_timer(REVEAL_HOLD, false).timeout
	if not _reveal_active(gen):
		return
	for i in range(n):
		var icon := row.icon_for(comps[i])
		var dest: Vector2 = icon.get_global_rect().get_center() - CardUI.BASE_SIZE / 2.0
		var tw := cards[i].create_tween().set_parallel(true)
		tw.tween_property(cards[i], "global_position", dest, REVEAL_OUT).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_CUBIC)
		tw.tween_property(cards[i], "scale", Vector2(0.12, 0.12), REVEAL_OUT).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_CUBIC)
		tw.tween_property(cards[i], "modulate:a", 0.3, REVEAL_OUT).set_ease(Tween.EASE_IN)
	caption.create_tween().tween_property(caption, "modulate:a", 0.0, REVEAL_OUT)

	await get_tree().create_timer(REVEAL_OUT, false).timeout
	if not _reveal_active(gen):
		return
	for i in range(n):
		row.icon_for(comps[i]).pop_in()
		_reveal_nodes.erase(cards[i])
		cards[i].queue_free()
	_reveal_nodes.erase(caption)
	caption.queue_free()
	lit.z_index = 0
	grid.spotlight = false
	if panel != null:
		panel.set_acting(false)
	await get_tree().create_timer(REVEAL_AFTER, false).timeout

## The reveal's caption: a holo glass plate under the cards (Logan,
## 2026-10-02: above them, as bare text, it was hard to read) naming whose
## passives these are, with "Click to skip" under it.
func _reveal_caption(text: String, center_x: float, top: float) -> Control:
	const W := 380.0
	var plate := PanelContainer.new()
	plate.add_theme_stylebox_override("panel", GlassPanel.panel_style(GlassPanel.HOLO, 10.0))
	plate.draw.connect(func(): GlassPanel.draw_frame(plate, Rect2(Vector2.ZERO, plate.size), 0.9, GlassPanel.HOLO, 8.0))
	plate.custom_minimum_size = Vector2(W, 0)
	plate.mouse_filter = Control.MOUSE_FILTER_IGNORE
	plate.z_index = REVEAL_Z + 12 # over the cards, should they ever reach it
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 2)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	plate.add_child(box)
	var title := UIKit.label(text.to_upper(), 16, Color("eefcfa"))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(title)
	var skip := UIKit.label("Click to skip", 11, Color("8fd8d0"))
	skip.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(skip)
	plate.modulate.a = 0.0
	add_child(plate)
	plate.global_position = Vector2(center_x - W / 2.0, top) # global, like the cards
	_reveal_nodes.append(plate)
	return plate

## Finishes the reveal (or skips the rest of it) and starts the fight.
func _end_passive_reveal() -> void:
	if not _reveal_running:
		return
	_reveal_running = false
	for node in _reveal_nodes:
		if is_instance_valid(node):
			node.queue_free()
	_reveal_nodes.clear()
	if _reveal_dim != null:
		var dim := _reveal_dim
		_reveal_dim = null
		dim.create_tween().tween_property(dim, "modulate:a", 0.0, 0.25).finished.connect(dim.queue_free)
	player_panel.z_index = 0
	player_panel.passive_row.reveal_all()
	player_panel.grid.spotlight = false
	for panel in enemy_panels:
		panel.z_index = 0
		panel.passive_row.reveal_all()
		panel.grid.spotlight = false
		panel.set_acting(false)
	UIState.input_locked = false
	if hit_fx != null: # parts lost in earlier fights are still smoking
		for c in player_mech.components:
			if c.destroyed:
				hit_fx.smolder(player_panel.grid.component_center_global(c))
	if _in_run():
		var labels := enemy_mechs.map(func(m): return enemy_labels[m])
		_record = FightRecord.begin(player_mech, enemy_mechs, _seed, labels, _background)
		_record["location"] = RunState.run.location.get("name", "")
		_record["kind"] = RunState.run.current_node().get("kind", "")
	combat.start_combat() # -> turn_changed: Turn 1, End Turn enabled
	if _replaying:
		FightRecord.apply_opening(replay_record, player_mech, enemy_mechs)
		_refresh_all_panels()
		_replay_drive(_generation)
		return
	Tutorial.reached("combat", {"player": player_panel, "hand": hand_tray, "heat": player_panel._heat_box,
		"intents": enemy_panels[0]._intent_row if not enemy_panels.is_empty() else null,
		"enemy": enemy_panels[0] if not enemy_panels.is_empty() else null, "end_turn": turn_panel,
		"keep_clear": [turn_panel, settings_button, speed_controls, map_button, log_button]}) # never over a button
	if _in_run():
		for line in RunState.run.apply_fight_start_effects(player_mech, enemy_mechs):
			combat_log.log_line(line)
		_refresh_all_panels()
		if not _record.is_empty():
			FightRecord.set_opening(_record, player_mech, enemy_mechs)
	for m in enemy_mechs:
		if m.tier == "boss" and m.lines.has("intro"):
			combat_log.log_line("%s: \"%s\"" % [m.title if m.title != "" else m.name, m.lines["intro"]], CombatLog.CAT_ENEMY)
			show_banner("%s  ·  %s" % [m.title.to_upper(), m.name.to_upper()] if m.title != "" else m.name.to_upper(), m.lines["intro"], Palette.HARDPOINT)

## Hotkeys: E ends the turn, V vents (same rules as the buttons); 1–9 play
## the cards in the fan (attacks aim first: Tab cycles, Enter / Space
## fires); F toggles fast-forwarding enemy turns; L shows / hides the log.
## Every letter key is rebindable (GameSettings.KEY_ACTIONS); 1–9 aren't.
func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey) or not event.pressed or event.echo or combat == null or _reveal_running:
		return
	if GameSettings.is_key(event, "fast_forward"):
		get_viewport().set_input_as_handled()
		_ff_on = not _ff_on
		if hit_fx != null:
			hit_fx.float_text(player_panel.image_global_rect().get_center(), "Enemy turns: %s" % ("fast" if _ff_on else "normal"), Palette.TEXT_MUTED, 16)
		return
	if GameSettings.is_key(event, "log"):
		get_viewport().set_input_as_handled()
		_toggle_log()
		return
	if map_button != null and GameSettings.is_key(event, "map"):
		get_viewport().set_input_as_handled()
		LocationMapScreen.peek(self)
		return
	if _replaying or UIState.input_locked or UIState.dragging_card != null or not combat.is_player_turn():
		return
	var k: int = event.keycode
	if (k >= KEY_1 and k <= KEY_9) or (k >= KEY_KP_1 and k <= KEY_KP_9):
		get_viewport().set_input_as_handled()
		_hotkey_card(k - KEY_1 if k <= KEY_9 else k - KEY_KP_1)
		return
	if GameSettings.is_key(event, "next_target"):
		if _aim_card != null:
			get_viewport().set_input_as_handled()
			_cycle_target(-1 if event.shift_pressed else 1)
	elif GameSettings.is_key(event, "fire") or k == KEY_SPACE:
		if _aim_card != null:
			get_viewport().set_input_as_handled()
			_fire_aimed()
	elif GameSettings.is_key(event, "end_turn"):
		get_viewport().set_input_as_handled()
		_on_end_turn_pressed()

## A click (anywhere but the speed/settings buttons) or Space/Enter skips
## the reveal. Esc while aiming cancels the aim (before the settings menu
## sees it).
func _input(event: InputEvent) -> void:
	if _aim_card != null and event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ESCAPE:
		get_viewport().set_input_as_handled()
		_cancel_aim()
		return
	if not _reveal_running:
		return
	var skip := false
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var p: Vector2 = event.position
		skip = not settings_button.get_global_rect().has_point(p) and not speed_controls.get_global_rect().has_point(p) \
			and not (map_button != null and map_button.get_global_rect().has_point(p))
	elif event is InputEventKey and event.pressed and not event.echo:
		skip = event.keycode in [KEY_SPACE, KEY_ENTER, KEY_KP_ENTER]
	if skip:
		get_viewport().set_input_as_handled()
		_end_passive_reveal()

# ---------- keyboard play ----------

## Number key `i` (0-based): a self card plays at once; an attack aims.
func _hotkey_card(i: int) -> void:
	var cards := hand_tray.ordered_cards()
	if i < 0 or i >= cards.size():
		return
	var card := cards[i].card
	if cards[i].gone: # played this turn: its number waits for next turn
		Audio.play("denied", 0.0)
		return
	if card == _aim_card:
		_fire_aimed()
		return
	_cancel_aim()
	if not combat.can_play(card):
		Audio.play("denied", 0.0)
		return
	if not card.is_attack():
		_handle_card_drop(card, Vector2.ZERO, CardUI.FADE_END)
		return
	var targets := _aim_targets()
	if targets.is_empty():
		return
	_aim_card = card
	_aim_ui = cards[i]
	_aim_ui.set_selected(true)
	# start on the enemy part under the mouse, if any
	var hovered := _target_at(get_global_mouse_position())
	_aim_target = hovered["component"] if not hovered.is_empty() else targets[0]["component"]
	Audio.play("ui")
	_show_aim()

## Every living enemy part, enemy by enemy.
func _aim_targets() -> Array:
	var out := []
	for panel in enemy_panels:
		if panel.mech.is_defeated():
			continue
		for c in panel.mech.non_destroyed_components():
			out.append({"mech": panel.mech, "component": c, "panel": panel})
	return out

func _aim_entry() -> Dictionary:
	for t in _aim_targets():
		if t["component"] == _aim_target:
			return t
	return {}

func _cycle_target(step: int) -> void:
	var targets := _aim_targets()
	if targets.is_empty():
		_cancel_aim()
		return
	var i := 0
	for j in range(targets.size()):
		if targets[j]["component"] == _aim_target:
			i = j
	_aim_target = targets[posmod(i + step, targets.size())]["component"]
	Audio.play("ui", 0.1, -6.0)
	_show_aim()

func _show_aim() -> void:
	var t := _aim_entry()
	if t.is_empty():
		_cancel_aim()
		return
	_set_targeting(t)
	player_reticle.follow(t["panel"].grid.component_center_global(t["component"]), 1.0, true)
	UIState.set_hovered(t["component"], t["mech"])

func _fire_aimed() -> void:
	var t := _aim_entry()
	var card := _aim_card
	_cancel_aim(false)
	if t.is_empty() or card == null:
		return
	_handle_card_drop(card, t["panel"].grid.component_center_global(t["component"]), CardUI.FADE_END)

func _cancel_aim(hide_reticle: bool = true) -> void:
	if _aim_ui != null and is_instance_valid(_aim_ui):
		_aim_ui.set_selected(false)
	var was_aiming := _aim_card != null
	_aim_card = null
	_aim_ui = null
	_aim_target = null
	if was_aiming:
		_set_targeting({})
		if UIState.hovered_component != null and UIState.hovered_mech != player_mech:
			UIState.clear_hovered(UIState.hovered_component)
		if hide_reticle and player_reticle != null and not combat.has_pending_attack():
			player_reticle.hide_now()

# ---------- gamepad ----------

## Gamepad buttons the fight takes before the cursor does (Gamepad.handler).
func pad_button(b: JoyButton) -> bool:
	if combat == null or _replaying or _reveal_running or end_screen == null or end_screen.visible:
		return false
	match b:
		JOY_BUTTON_LEFT_SHOULDER, JOY_BUTTON_RIGHT_SHOULDER:
			if combat.is_player_turn() and not UIState.input_locked and UIState.dragging_card == null:
				_pad_pick(-1 if b == JOY_BUTTON_LEFT_SHOULDER else 1)
			return true
		JOY_BUTTON_A:
			if _aim_card != null:
				_fire_aimed()
				return true
			if _pad_card != null:
				_pad_play()
				return true
		JOY_BUTTON_DPAD_LEFT, JOY_BUTTON_DPAD_UP:
			if _aim_card != null:
				_cycle_target(-1)
				return true
		JOY_BUTTON_DPAD_RIGHT, JOY_BUTTON_DPAD_DOWN:
			if _aim_card != null:
				_cycle_target(1)
				return true
		JOY_BUTTON_B:
			if _aim_card != null or _pad_card != null:
				_cancel_aim()
				_pad_clear()
				return true
	return false

## While a card aims, the D-pad steps its target instead of the cursor.
func pad_dpad_claimed() -> bool:
	return _aim_card != null

## LB / RB: the previous / next playable card in the fan. An attack aims at
## once; a self card waits, lifted, for A.
func _pad_pick(dir: int) -> void:
	var cards := hand_tray.ordered_cards()
	var playable: Array[int] = []
	for i in range(cards.size()):
		if not cards[i].gone and combat.can_play(cards[i].card):
			playable.append(i)
	if playable.is_empty():
		Audio.play("denied", 0.0)
		return
	var current := _aim_card if _aim_card != null else _pad_card
	var at := -1
	for j in range(playable.size()):
		if cards[playable[j]].card == current:
			at = j
	var next := (0 if dir > 0 else playable.size() - 1) if at < 0 else posmod(at + dir, playable.size())
	_pad_clear()
	_cancel_aim()
	var i := playable[next]
	if cards[i].card.is_attack():
		_hotkey_card(i)
		return
	_pad_card = cards[i].card
	_pad_ui = cards[i]
	_pad_ui.set_selected(true)
	UIState.set_hovered_card(_pad_card)
	Audio.play("ui")

func _pad_play() -> void:
	var card := _pad_card
	_pad_clear()
	var cards := hand_tray.ordered_cards()
	for i in range(cards.size()):
		if cards[i].card == card:
			_hotkey_card(i)
			return

func _pad_clear() -> void:
	if _pad_ui != null and is_instance_valid(_pad_ui):
		_pad_ui.set_selected(false)
	if _pad_card != null:
		UIState.clear_hovered_card(_pad_card)
	_pad_card = null
	_pad_ui = null

# ---------- lethal overheat ----------

## A play that overheats into a possible defeat needs confirming: the first
## press warns and returns false, a second press of the same thing within
## CONFIRM_MS returns true.
func _confirm_lethal(key: String) -> bool:
	if _replaying: # it was confirmed when it was played
		return true
	var now := Time.get_ticks_msec()
	if _confirm_key == key and now < _confirm_until:
		_confirm_key = ""
		return true
	_confirm_key = key
	_confirm_until = now + CONFIRM_MS
	Audio.play("overheat_warn", 0.0)
	if hit_fx != null:
		hit_fx.float_text(player_panel.image_global_rect().get_center(), "This overheat could destroy you.\nDo it again to confirm.", Palette.DANGER, 18)
	combat_log.log_line("Warning: that overheats, and the backlash could finish you. Do it again to confirm.", CombatLog.CAT_TURN)
	return false

# ---------- player targeting ----------

## The live enemy component under a global point, if any.
func _target_at(global_point: Vector2) -> Dictionary:
	if _replay_driving and not _replay_hit.is_empty():
		return _replay_hit
	for panel in enemy_panels:
		if panel.mech.is_defeated():
			continue
		var cell := panel.grid.cell_at(global_point)
		if cell != null and cell.component != null and not cell.component.destroyed:
			return {"mech": panel.mech, "component": cell.component, "panel": panel}
	return {}

func _process(_delta: float) -> void:
	if combat == null or player_reticle == null:
		return
	_update_overheat_glow(_delta)
	if _replaying and not UIState.input_locked:
		UIState.input_locked = true # watching: no dragging cards
	if UIState.is_dragging_attack_card() and combat.is_player_turn():
		var mouse := get_global_mouse_position()
		var hit := _target_at(mouse)
		_set_targeting(hit)
		player_reticle.follow(mouse, UIState.drag_fade, not hit.is_empty())
		if not hit.is_empty():
			UIState.set_hovered(hit["component"], hit["mech"])
		elif UIState.hovered_component != null and not UIState.hovered_passive and UIState.hovered_mech != player_mech:
			UIState.clear_hovered(UIState.hovered_component) # dragged off the enemy part
	elif _aim_card != null:
		if not combat.is_player_turn() or UIState.input_locked or UIState.dragging_card != null:
			_cancel_aim()
	elif _targeted_grid != null:
		_set_targeting({})
	if _pad_card != null and (not combat.is_player_turn() or UIState.input_locked):
		_pad_clear()
	# fast-forward the enemy turn (Shift or Space held, or F toggled on)
	var ff := combat.phase == CombatManager.Phase.ENEMY_TURN \
		and (_ff_on or Input.is_key_pressed(KEY_SHIFT) or Input.is_key_pressed(KEY_SPACE))
	var want: float = GameSettings.speed * (FAST_FORWARD if ff else 1.0)
	if Time.get_ticks_msec() < _hitstop_until:
		want = HITSTOP_SCALE
	if not is_equal_approx(Engine.time_scale, want):
		Engine.time_scale = want

func _set_targeting(hit: Dictionary) -> void:
	var grid: ChassisGridUI = hit["panel"].grid if not hit.is_empty() else null
	if _targeted_grid != null and _targeted_grid != grid:
		_targeted_grid.set_targeted(null)
	_targeted_grid = grid
	if grid != null:
		grid.set_targeted(hit["component"])
	_show_damage_preview(hit)

## What the aimed attack would do, shown rather than written (Logan,
## 2026-10-02: less numbers on screen): the HP it takes off pulses on the
## enemy's health bar (the sure part dark, the rest of the roll paler), and
## the part that takes it (the cover, if something covers it, already ringed
## by the grid) pulses red if it would be destroyed, amber if it might.
func _show_damage_preview(hit: Dictionary) -> void:
	var card: CardData = _aim_card if _aim_card != null else UIState.dragging_card
	var p := {} if hit.is_empty() or card == null or combat == null else combat.preview_attack(card, hit["mech"], hit["component"])
	var panel: EnemyPanel = null if p.is_empty() else hit["panel"]
	if _preview_panel != null and _preview_panel != panel and is_instance_valid(_preview_panel):
		_preview_panel.preview_damage(0, 0)
		_preview_panel.grid.set_doomed(null)
	_preview_panel = panel
	if panel == null:
		return
	var part: ComponentData = p["part"]
	panel.preview_damage(0 if p["may_miss"] else mini(p["lo"], part.current_hp), mini(p["hi"], part.current_hp))
	if p["lethal_lo"] and not p["may_miss"]:
		panel.grid.set_doomed(part, true)
	elif p["lethal_hi"]:
		panel.grid.set_doomed(part, false)
	else:
		panel.grid.set_doomed(null)

## Eases the red edge glow in and out; it pulses slowly while on (steady
## with reduce motion).
func _update_overheat_glow(delta: float) -> void:
	if _overheat_glow == null:
		return
	var on := _glow_on and combat.is_player_turn() and not _replaying
	_glow = move_toward(_glow, 1.0 if on else 0.0, delta * (2.5 if on else 4.0))
	_overheat_glow.visible = _glow > 0.0
	if not _overheat_glow.visible:
		_glow_t = 0.0
		return
	_glow_t += delta
	var pulse := 0.75 if GameSettings.reduce_motion else 0.55 + 0.45 * (0.5 - 0.5 * cos(_glow_t * TAU / 1.4))
	(_overheat_glow.material as ShaderMaterial).set_shader_parameter("strength", _glow * pulse)

## UIState.drop_handler: a dragged card was released at `global_point`.
## Returns whether the card was played; if not, it just returns to the hand.
func _handle_card_drop(card: CardData, global_point: Vector2, drag_distance: float) -> bool:
	var played := false
	# Where the card is now, for its flight: a dragged attack has already
	# turned into the crosshair, so only self cards and key plays fly.
	var ui := hand_tray.card_ui_for(card) if hand_tray != null else null
	var dragged := UIState.dragging_card_ui != null
	var fly_from := ui.global_position if ui != null else Vector2.ZERO
	var fly_rot := ui.rotation_degrees if ui != null else 0.0
	var fly_scale := ui.scale.x if ui != null else 1.0
	if _replaying and not _replay_driving:
		return false
	if combat != null and combat.is_player_turn() and (not UIState.input_locked or _replay_driving):
		var lethal := combat.can_play(card) and combat.would_overheat(card) and combat.overheat_could_kill()
		if lethal and (drag_distance >= CardUI.FADE_END or card.is_attack()) and (not card.is_attack() or not _target_at(global_point).is_empty()) \
				and not _confirm_lethal(CombatManager.card_key(card)):
			if player_reticle != null and not combat.has_pending_attack():
				player_reticle.hide_now()
			_set_targeting({})
			return false
		if card.is_attack():
			var hit := _target_at(global_point)
			if not hit.is_empty():
				var target: ComponentData = hit["component"]
				var r := combat.apply(combat.play_command(card, hit["mech"], target).merged({"paced": true}))
				played = r["ok"]
				if played and not dragged and ui != null:
					_fly_card(ui, fly_from, fly_rot, fly_scale, hit["panel"].grid.component_center_global(target))
				if played and combat.has_pending_attack():
					_run_player_attack(_generation, hit["mech"], target)
				elif played:
					_refresh_all_panels()
					var note := "Set aside" if combat.standby.get("card") == card else ("Intercepted" if card.protocol() == "intercept" else "")
					if note != "" and hit_fx != null:
						hit_fx.float_text(player_panel.image_global_rect().get_center(), note, Palette.PROTOCOL, 20)
		elif drag_distance >= CardUI.FADE_END:
			if card.protocol() == "reroute":
				_open_reroute_picker(card)
			else:
				var r := combat.apply(combat.play_command(card).merged({"paced": true}))
				played = r["ok"]
				var own := player_mech.get_component(card.owner_component_id)
				if played and ui != null and own != null:
					_fly_card(ui, fly_from, fly_rot, fly_scale, player_panel.grid.component_center_global(own))
				if r.get("started_attack", false):
					var pt := combat.pending_target()
					_run_player_attack(_generation, pt["mech"], pt["comp"])
				elif not played and r.get("reason", "") == "nothing_to_replay" and hit_fx != null:
					hit_fx.float_text(player_panel.image_global_rect().get_center(), "Nothing to replay yet", Palette.TEXT_MUTED, 16)
	if not played and player_reticle != null and not combat.has_pending_attack():
		player_reticle.hide_now()
	_set_targeting({})
	return played

## Seconds between two hits of `card` (Logan, 2026-09-30): the more hits,
## the faster they come; the harder each one hits, the more room it gets;
## a volley's land all but at once.
static func hit_gap(card: CardData) -> float:
	if card == null:
		return HIT_INTERVAL
	if card.rule.get("volley", false):
		return VOLLEY_GAP
	var n := maxi(card.hits, 1)
	var per_hit := (card.damage_min + card.damage_max) / 2.0
	var gap := clampf(1.1 / (n + 0.5), MIN_HIT_INTERVAL, HIT_INTERVAL)
	return gap * clampf(0.75 + per_hit / 40.0, 0.8, 1.3)

## Resolves the pending attack's hits, paced by hit_gap(), with a running
## total over the target for a multi-hit card. Returns false if the fight
## was restarted meanwhile.
func _play_hits(gen: int, reticle: TargetingReticle) -> bool:
	var total := 0
	var hits := 0
	while true:
		var card := combat.pending_card()
		var pt := combat.pending_target()
		var mech: MechData = pt.get("mech", null)
		var target: ComponentData = pt.get("comp", null)
		var h := combat.next_hit() # -> _on_hit_landed: number, flash, shake, HP
		if h.is_empty():
			break
		reticle.fire()
		hits += 1
		total += int(h["damage"])
		if hits > 1 and total > 0 and target != null:
			var grid := _grid_for(mech)
			if grid != null and hit_fx != null:
				hit_fx.running_total(grid.component_center_global(target), total, mech == player_mech)
		if h["hits_left"] <= 0:
			break
		await get_tree().create_timer(hit_gap(card), false).timeout
		if gen != _generation:
			return false
	return true

## A played card's flight: a copy leaves where the card was and shrinks
## into what it acts on (the enemy part, or its own part for a self card),
## fading as it lands; the card in the fan hides at once.
const FLY_SECONDS := 0.26

func _fly_card(ui: CardUI, from: Vector2, rot: float, from_scale: float, to: Vector2) -> void:
	ui.hide_now()
	if GameSettings.reduce_motion:
		return
	var ghost := CardUI.new()
	ghost.z_index = 200
	add_child(ghost)
	ghost.setup(ui.card, ui._category, null, ui._component)
	ghost.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ghost.pivot_offset = CardUI.BASE_SIZE / 2.0
	ghost.global_position = from
	ghost.rotation_degrees = rot
	ghost.scale = Vector2(from_scale, from_scale)
	var end_scale := 0.18
	var tw := ghost.create_tween().set_parallel(true)
	tw.tween_property(ghost, "global_position", to - CardUI.BASE_SIZE / 2.0, FLY_SECONDS).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_CUBIC)
	tw.tween_property(ghost, "scale", Vector2(end_scale, end_scale), FLY_SECONDS).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_CUBIC)
	tw.tween_property(ghost, "rotation_degrees", 0.0, FLY_SECONDS)
	tw.tween_property(ghost, "modulate:a", 0.0, FLY_SECONDS * 0.4).set_delay(FLY_SECONDS * 0.6)
	tw.chain().tween_callback(ghost.queue_free)

## Plays out a begun attack (_play_hits: the crosshair locked onto the part,
## each hit's number, flash and shake from _on_hit_landed), then finishes it.
func _run_player_attack(gen: int, mech: MechData, target: ComponentData) -> void:
	UIState.input_locked = true
	turn_panel.set_enabled(false)
	var grid := _grid_for(mech)
	if grid != null:
		player_reticle.follow(grid.component_center_global(target), 1.0, true)
	if not await _play_hits(gen, player_reticle):
		return
	player_reticle.fade_out()
	UIState.input_locked = false
	combat.finish_attack() # may overheat (-> enemy turn) or end the fight
	if combat.is_player_turn():
		turn_panel.set_enabled(true)

func _on_end_turn_pressed() -> void:
	if _replaying and not _replay_driving:
		return
	if combat.is_player_turn() and combat.end_turn_overheats() and combat.overheat_could_kill() and not _confirm_lethal("end_turn"):
		return
	# A turn ended without playing a card is spent venting (the Vent action,
	# which never vents less than the turn's own dispersal). A replay plays
	# its recorded command as it was.
	if not _replay_driving and combat.can_vent():
		combat_log.log_line("%s vents instead of attacking." % player_mech.name, CombatLog.CAT_YOU)
		combat.apply({"type": "vent"})
		return
	combat.apply({"type": "end_turn"})

## Vent, from a replay: the whole turn spent dumping heat (only before a card this turn).
func _vent() -> void:
	if (_replaying and not _replay_driving) or (UIState.input_locked and not _replay_driving) or not combat.can_vent():
		return
	combat_log.log_line("%s vents instead of attacking." % player_mech.name, CombatLog.CAT_YOU)
	combat.apply({"type": "vent"})

# ---------- protocols in the UI ----------

## The primed protocol (and a Standby card): the purple badge by the player's passives, and a glow on the cards it will affect.
func _refresh_primed() -> void:
	if player_panel == null or combat == null:
		return
	var titles: Array[String] = []
	var lines: Array[String] = []
	for p in combat.primed:
		var c: CardData = p["card"]
		var n := c.name
		if p["type"] == "reroute":
			n += " → %s" % str(p["status"]).capitalize()
		titles.append(n)
		lines.append("%s: %s" % [n, c.effect_text])
	if not combat.standby.is_empty():
		titles.append("Standby")
		lines.append("Standby: %s plays itself at the start of your next turn, for 0 heat." % combat.standby["card"].name)
	if titles.is_empty():
		player_panel.set_protocol([])
	else:
		if not combat.primed.is_empty():
			lines.append("Used up by the next card it affects: those glow purple in your hand.")
		player_panel.set_protocol(["Protocol: " + " · ".join(titles), "\n".join(lines)])
	if hand_tray != null:
		hand_tray.refresh_heat()
	# enemies hold protocols too (CombatEnemyTurn): the same badge on their row
	for panel in enemy_panels:
		var list: Array = combat.enemy_primed.get(panel.mech, [])
		if list.is_empty():
			panel.set_protocol([])
		else:
			var c: CardData = list[0]["card"]
			panel.set_protocol(["Protocol: %s" % c.name, "%s\n%s will use it on its next card it affects." % [c.effect_text, panel.mech.name]])

## Reroute: pick the status the next card's status becomes.
func _open_reroute_picker(card: CardData) -> void:
	if _picker != null:
		_picker.queue_free()
	_picker = PanelContainer.new()
	_picker.add_theme_stylebox_override("panel", GlassPanel.panel_style(Palette.PROTOCOL))
	_picker.z_index = 350
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	_picker.add_child(box)
	box.add_child(UIKit.label("Reroute: swap the next card's status to…", 14))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	box.add_child(row)
	for s in CombatManager.REROUTE_OPTIONS:
		var b := UIKit.button(s.capitalize(), Color.TRANSPARENT, Vector2(78, 36), 13)
		b.pressed.connect(_on_reroute_picked.bind(card, s))
		row.add_child(b)
	var cancel := UIKit.button("Cancel", Color.TRANSPARENT, Vector2(90, 32), 12)
	cancel.pressed.connect(_close_picker)
	box.add_child(cancel)
	add_child(_picker)
	await get_tree().process_frame
	if _picker != null:
		_picker.position = (get_viewport_rect().size - _picker.size) / 2.0

func _close_picker() -> void:
	if _picker != null:
		_picker.queue_free()
		_picker = null

func _on_reroute_picked(card: CardData, status: String) -> void:
	_close_picker()
	combat.apply(combat.play_command(card, null, null, {"status": status}).merged({"paced": true}))

func _on_hand_changed() -> void:
	_cancel_aim()
	_pad_clear()
	if hand_tray != null:
		hand_tray.setup(player_mech, combat)

func _on_hit_missed(mech: MechData, component: ComponentData) -> void:
	Audio.play("miss")
	var grid := _grid_for(mech)
	if grid != null and hit_fx != null:
		hit_fx.float_text(grid.component_center_global(component), "MISS", Palette.TEXT_MUTED, 18)

## Settings: Restart fight (standalone) or Eject (during a run).
func _on_restart_pressed() -> void:
	if SceneRouter.is_busy():
		return
	if _replaying:
		_leave_replay()
	elif _in_run():
		_eject()
	else:
		_start_new_combat()

## The end screen's button: Restart, Continue (won) or Eject (lost).
func _on_end_action() -> void:
	if SceneRouter.is_busy(): # a second click during the fade out
		return
	if _replaying:
		_leave_replay()
	elif not _in_run():
		_start_new_combat()
	elif combat.result == CombatManager.Result.WIN:
		_save_record("win")
		RunState.run.fight_won(combat.stats) # -> the reward screen
		RunState.advance()
	else:
		_eject()

func _eject() -> void:
	_save_record("loss" if combat.result == CombatManager.Result.LOSE else "ejected")
	RunState.run.fight_lost(combat.stats)
	RunState.advance() # -> debrief -> War Room

# ---------- enemy turn pacing ----------

func _on_enemy_turn_started() -> void:
	Tutorial.event("turn_ended")
	_refresh_all_panels() # the player's heat just vented (step 4)
	_run_enemy_turn(_generation)

func _run_enemy_turn(gen: int) -> void:
	var hp_before := player_mech.current_hp()
	var alive_before := player_mech.non_destroyed_components()
	UIState.input_locked = true
	player_panel.grid.spotlight = true # show which of your parts each attack lands on
	await get_tree().create_timer(ENEMY_TURN_START_DELAY, false).timeout
	while gen == _generation:
		var action := combat.next_enemy_action()
		if action.is_empty():
			break
		_set_acting_panel(_panel_for(action["mech"]))
		_refresh_intents() # the step now resolving pulses
		var target: ComponentData = action["target"]
		if target != null:
			var target_pos := player_panel.grid.component_center_global(target)
			await enemy_reticle.trace_to(target_pos, player_panel.image_global_rect())
		else:
			await get_tree().create_timer(ENEMY_AFTER_HIT_DELAY, false).timeout # a protocol primes
		if gen != _generation:
			return
		combat.begin_enemy_attack(action)
		if not await _play_hits(gen, enemy_reticle):
			return
		combat.finish_attack() # -> _on_enemy_action: log
		await get_tree().create_timer(ENEMY_AFTER_HIT_DELAY, false).timeout
	if gen != _generation:
		return
	_set_acting_panel(null)
	enemy_reticle.fade_out()
	player_panel.grid.spotlight = false
	UIState.input_locked = false
	_enemy_turn_summary(hp_before, alive_before)
	combat.finish_enemy_turn()

## After the enemy turn, one line on what it cost you ("You took 23 · lost
## Voltage Spike"), over your mech and in the log.
func _enemy_turn_summary(hp_before: int, alive_before: Array[ComponentData]) -> void:
	if combat.is_game_over():
		return
	var taken := hp_before - player_mech.current_hp()
	var lost: Array[String] = []
	for c in alive_before:
		if c.destroyed:
			lost.append(c.name)
	var text := "You took %d" % taken if taken > 0 else "No damage taken"
	if not lost.is_empty():
		text += "  ·  lost " + ", ".join(lost)
	combat_log.log_line(text + ".", CombatLog.CAT_DAMAGE)
	if hit_fx != null:
		hit_fx.float_text(player_panel.image_global_rect().get_center() + Vector2(0, -70), text, Palette.DANGER if not lost.is_empty() else (Palette.WARNING if taken > 0 else Palette.OK), 17)

func _panel_for(mech: MechData) -> EnemyPanel:
	for panel in enemy_panels:
		if panel.mech == mech:
			return panel
	return null

func _set_acting_panel(panel: EnemyPanel) -> void:
	if panel == _acting_panel:
		return
	if _acting_panel != null:
		_acting_panel.set_acting(false)
	_acting_panel = panel
	if panel != null:
		panel.set_acting(true)

# ---------- feedback ----------

## Status stacks last seen, per part and per mech (for the mech-wide ones):
## Object -> {status: stacks}. Rises float up where they land.
var _status_seen: Dictionary = {}
## Statuses seen this fight that the Operator hasn't explained to this
## pilot yet (Tutorial.hint_once); one is explained per player turn.
var _pending_hints: Array[String] = []

func _status_map(list: Array) -> Dictionary:
	var out := {}
	for st in list:
		if st.stacks > 0:
			out[st.status] = st.stacks
	return out

## Every status that went up since the last look floats up over where it
## landed ("+Shock 2", in the status's colour), like a damage number.
func _float_new_statuses() -> void:
	if hit_fx == null or player_mech == null:
		return
	var first := _status_seen.is_empty()
	var mechs: Array[MechData] = [player_mech]
	mechs.append_array(enemy_mechs)
	for m in mechs:
		var grid := _grid_for(m)
		if grid == null:
			continue
		var spots := [[m, m.mech_statuses]]
		for c in m.components:
			if not c.destroyed:
				spots.append([c, c.statuses])
		for spot in spots:
			var now := _status_map(spot[1])
			for st in now: # a status this pilot hasn't had explained yet
				if not _replaying and not Profile.seen_hints.has("status:" + st) and not _pending_hints.has(st) and StatusGlossary.ENTRIES.has(st):
					_pending_hints.append(st)
			var before: Dictionary = _status_seen.get(spot[0], {})
			_status_seen[spot[0]] = now
			if first:
				continue
			var n := 0
			for st in now:
				var gain := int(now[st]) - int(before.get(st, 0))
				if gain <= 0:
					continue
				if spot[0] is ComponentData:
					grid.pop_status(spot[0])
				var at: Vector2
				if spot[0] is MechData:
					at = player_panel.image_global_rect().get_center() if m == player_mech else _panel_for(m).image_global_rect().get_center()
				else:
					at = grid.component_center_global(spot[0])
				hit_fx.float_text(at + Vector2(0, -30 - 20 * n), "+%s %d" % [StatusGlossary.get_entry(st)["label"], gain], Palette.status_color(st), 16)
				n += 1

## A freeze-frame: the game runs at HITSTOP_SCALE until `ms` from now
## (real time, so it isn't stretched by itself).
const HITSTOP_SCALE := 0.05
var _hitstop_until: int = 0

func hitstop(ms: int) -> void:
	if not GameSettings.reduce_motion:
		_hitstop_until = maxi(_hitstop_until, Time.get_ticks_msec() + ms)

## An enemy beaten: a short freeze, a flash, a kick, then blasts popping
## across its sprite (the sprite's own flash and sink are EnemyPanel's).
func _enemy_blows_up(panel: EnemyPanel) -> void:
	if hit_fx == null:
		return
	hitstop(110)
	Audio.play("destroyed", 0.0, 2.0)
	hit_fx.shake(0.8)
	hit_fx.flash_screen(Color(1, 0.85, 0.7), 0.18, 0.4)
	var r := panel.image_global_rect()
	var colors := [Palette.HARDPOINT, Palette.WARNING, Color.WHITE, Palette.HARDPOINT, Palette.LINK]
	var gen := _generation
	for i in range(5):
		var at := r.position + Vector2(r.size.x * randf_range(0.25, 0.75), r.size.y * randf_range(0.25, 0.7))
		hit_fx.sparks(at, colors[i], 22 + i * 4, 1.3 + 0.15 * i)
		if i == 2:
			Audio.play("hit_heavy", 0.15)
		await get_tree().create_timer(0.09, false).timeout
		if gen != _generation:
			return
	hit_fx.sparks(r.get_center(), Color.WHITE, 40, 2.0)

func _grid_for(mech: MechData) -> ChassisGridUI:
	if mech == player_mech:
		return player_panel.grid if player_panel != null else null
	var panel := _panel_for(mech)
	return panel.grid if panel != null else null

## A hit landing on one component: its cells flash, sparks + number + shake.
func _impact(mech: MechData, component: ComponentData, damage: int) -> void:
	var grid := _grid_for(mech)
	if grid == null or hit_fx == null:
		return
	grid.flash(component)
	var on_player := mech == player_mech
	hit_fx.impact(grid.component_center_global(component), damage, Palette.category_color(component.category), on_player)

func _apply_settings() -> void:
	if combat_log != null:
		combat_log.visible = GameSettings.log_open
		log_button.text = "Hide log" if GameSettings.log_open else "Log"

func _toggle_log() -> void:
	Audio.play("ui")
	GameSettings.set_value("log_open", not GameSettings.log_open) # -> changed -> _apply_settings

func _refresh_intents() -> void:
	for panel in enemy_panels:
		var theme: String = combat.enemy_theme.get(panel.mech, "") if combat.is_player_turn() else ""
		panel.set_intents(combat.upcoming_enemy_actions(panel.mech), combat.enemy_will_overheat(panel.mech), combat.enemy_venting(panel.mech), theme)

## Card ↔ part (Logan, 2026-09-30): hovering a card outlines the part that
## grants it; hovering one of your parts lifts its cards in the hand.
func _on_card_hover(card: CardData) -> void:
	if card != null and UIState.dragging_card == null:
		Audio.play("hover", 0.05, -6.0)
	if player_panel != null and is_instance_valid(player_panel):
		player_panel.grid.set_linked(player_mech.get_component(card.owner_component_id) if card != null else null)

var _passive_grid: ChassisGridUI = null

func _on_part_hover(component: ComponentData, mech: MechData) -> void:
	# a passive badge outlines the part it comes from
	if _passive_grid != null and is_instance_valid(_passive_grid):
		_passive_grid.set_linked(null)
	_passive_grid = null
	if component != null and UIState.hovered_passive:
		_passive_grid = _grid_for(mech)
		if _passive_grid != null:
			_passive_grid.set_linked(component)
	if hand_tray != null and is_instance_valid(hand_tray):
		hand_tray.set_linked_part(component if mech == player_mech and not UIState.hovered_passive else null)
	_show_enemy_cards(component if mech != null and mech != player_mech and not UIState.hovered_passive else null, mech)

const ENEMY_CARD_SCALE := 0.8
var _enemy_cards: Control = null

## Hovering an enemy part lays its cards out under that enemy, as cards
## (Logan, 2026-10-13): marked THIS TURN when they're in its plan (the
## intents), CHARGING when charged up, SPENT once played this turn, greyed
## when the part can't act. Display only: the mouse passes through.
func _show_enemy_cards(component: ComponentData, mech: MechData) -> void:
	if _enemy_cards != null and is_instance_valid(_enemy_cards):
		_enemy_cards.queue_free()
	_enemy_cards = null
	if component == null or component.destroyed or component.cards.is_empty() or combat == null or UIState.dragging_card != null:
		return
	var panel := _panel_for(mech)
	if panel == null:
		return
	var planned := {}
	for a in combat.upcoming_enemy_actions(mech):
		if not a.get("cancelled", false):
			planned[a["card"]] = "CHARGING" if a.get("charged", false) or a.get("charge", false) else "THIS TURN"
	var strip := Control.new()
	strip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	strip.z_index = 40
	add_child(strip)
	_enemy_cards = strip
	var w := CardUI.BASE_SIZE.x * ENEMY_CARD_SCALE
	var gap := 8.0
	var total := component.cards.size() * w + (component.cards.size() - 1) * gap
	var screen := get_viewport_rect().size
	var x := clampf(panel.image_global_rect().get_center().x - total / 2.0, 8.0, screen.x - total - 8.0)
	var y := panel.intents_global_bottom() + 22.0
	for i in range(component.cards.size()):
		var card: CardData = component.cards[i]
		var ui := CardUI.new()
		strip.add_child(ui)
		ui.setup(card, component.category, null, component)
		ui.make_display()
		ui.set_state(card.heat_cost, false, not component.is_usable(), combat.is_spent(card))
		ui.scale = Vector2(ENEMY_CARD_SCALE, ENEMY_CARD_SCALE)
		ui.pivot_offset = Vector2.ZERO
		ui.position = Vector2(x + i * (w + gap), y)
		var tag: String = planned.get(card, "")
		if tag != "":
			var l := UIKit.label(tag, 11, Palette.WARNING if tag == "THIS TURN" else Palette.LINK)
			l.mouse_filter = Control.MOUSE_FILTER_IGNORE
			l.position = ui.position + Vector2(0, -18)
			strip.add_child(l)
			var edge := ColorRect.new() # a yellow edge on the planned card
			edge.color = Color(Palette.WARNING if tag == "THIS TURN" else Palette.LINK, 0.9)
			edge.mouse_filter = Control.MOUSE_FILTER_IGNORE
			edge.position = ui.position + Vector2(0, -3)
			edge.size = Vector2(w, 3)
			strip.add_child(edge)

## Hovering an enemy intent outlines the part of your mech it's aimed at.
func _on_intent_hover(intent: Dictionary) -> void:
	if player_panel == null:
		return
	var target: ComponentData = intent.get("target", null)
	player_panel.grid.set_targeted(target if target != null and not target.destroyed else null)

## A hovered status lights the parts holding it: on its own mech (a badge),
## or on every mech (a status word in card text).
func _on_status_hover(status: String, mech: MechData) -> void:
	if player_panel != null:
		player_panel.grid.set_status_lit(status if mech == null or mech == player_mech else "")
	for panel in enemy_panels:
		panel.grid.set_status_lit(status if mech == null or mech == panel.mech else "")

# ---------- CombatManager signal handlers ----------

func _label_for(mech: MechData) -> String:
	if mech == player_mech:
		return player_mech.name
	return enemy_labels.get(mech, mech.name)

func _find_card_name(mech: MechData, component_id: String, card_id: String) -> String:
	var comp := mech.get_component(component_id)
	if comp == null:
		return card_id
	for c in comp.cards:
		if c.id == card_id:
			return c.name
	return card_id

func _refresh_all_panels() -> void:
	if player_panel != null:
		player_panel.refresh()
	for panel in enemy_panels:
		panel.refresh()
		# Either defeat route (all hardpoints, or the HP threshold) plays this once.
		if panel.mech.is_defeated() and not panel.defeat_played:
			if panel.mech.retreated:
				panel.play_retreated()
			else:
				panel.play_defeated()
				_enemy_blows_up(panel)
	if hand_tray != null:
		hand_tray.prune_destroyed()
		hand_tray.refresh_heat()
	_refresh_primed()
	if combat != null and not enemy_panels.is_empty():
		_refresh_intents()
	if combat != null and turn_panel != null:
		var playable := combat.hand_cards().filter(func(c): return combat.can_play(c) and not combat.would_overheat(c)).size()
		turn_panel.set_card_state(combat.cards_left(player_mech) + combat.bonus_cards.size(), combat.can_vent(), playable)
	if description_box != null:
		description_box.refresh()
	_float_new_statuses()

func _on_card_played(mech: MechData, card: CardData) -> void:
	if mech == player_mech:
		Tutorial.event("card_played")
		Audio.play("prime" if card.protocol() != "" else "card")
	combat_log.log_line("%s played %s%s." % [_label_for(mech), card.name, (" (%d left)" % combat.cards_left(mech)) if mech == player_mech else ""], CombatLog.CAT_YOU if mech == player_mech else CombatLog.CAT_ENEMY)
	_refresh_all_panels()

func _on_component_damaged(mech: MechData, component: ComponentData, amount: int) -> void:
	_refresh_all_panels()
	if amount > 0:
		combat_log.log_line("%s's %s took %d dmg (%d/%d HP)." % [_label_for(mech), component.name, amount, component.current_hp, component.max_hp], CombatLog.CAT_DAMAGE)

func _on_component_destroyed(mech: MechData, component: ComponentData) -> void:
	Audio.play("destroyed", 0.1)
	_refresh_all_panels()
	combat_log.log_line("%s's %s was destroyed!" % [_label_for(mech), component.name], CombatLog.CAT_DAMAGE)
	var grid := _grid_for(mech)
	if grid != null and hit_fx != null:
		hit_fx.part_destroyed(grid.component_center_global(component), Palette.category_color(component.category))
		hit_fx.smolder(grid.component_center_global(component))


func _on_overheated(mech: MechData, backlash: int) -> void:
	Audio.play("overheat", 0.0)
	_refresh_all_panels()
	if hit_fx != null:
		if mech == player_mech:
			hit_fx.flash_screen(Palette.DANGER, 0.35, 0.5)
			hit_fx.shake(0.75)
			hit_fx.float_text(player_panel.image_global_rect().get_center(), "OVERHEAT −%d" % backlash, Palette.DANGER, 30)
		else:
			# over the enemy that overheated, in heat amber, so it never reads as the player's damage
			var panel := _panel_for(mech)
			hit_fx.shake(0.3)
			if panel != null:
				hit_fx.float_text(panel.image_global_rect().get_center(), "%s OVERHEATED\n−%d to itself" % [_label_for(mech).to_upper(), backlash], Palette.WARNING, 24)
	combat_log.log_line("%s overheated! %d dmg spread across its components. Turn forced to end." % [_label_for(mech), backlash], CombatLog.CAT_DAMAGE)

## The first time a pilot meets a status, the Operator explains it once,
## at the start of a player turn (one a turn, so it never piles up).
func _explain_a_status() -> void:
	while not _pending_hints.is_empty():
		var st: String = _pending_hints.pop_front()
		if Profile.seen_hints.has("status:" + st):
			continue
		var e := StatusGlossary.get_entry(st)
		Tutorial.hint_once("status:" + st, str(e.get("tip", "%s: %s" % [e["label"], e["rule"]])))
		return

func _on_turn_changed(phase, turn_number: int) -> void:
	if turn_panel == null:
		return
	if phase == CombatManager.Phase.PLAYER_TURN:
		turn_plate.set_turn_number(turn_number)
		if not combat.is_game_over():
			Audio.play("turn", 0.0)
			_turn_flash("YOUR TURN · %d" % turn_number, Palette.TEXT)
			_explain_a_status.call_deferred()
	elif phase == CombatManager.Phase.ENEMY_TURN and not combat.is_game_over():
		_turn_flash("ENEMY TURN", Palette.HARDPOINT)
		combat_log.log_line("— Turn %d: your move —" % turn_number)
	else:
		turn_plate.set_label("Enemy turn")
	turn_panel.set_enabled(phase == CombatManager.Phase.PLAYER_TURN)
	_refresh_all_panels()

func _on_enemy_action(entry: Dictionary) -> void:
	var mech: MechData = entry["mech"]
	var card_name := _find_card_name(mech, entry["component"], entry["card"])
	var target_comp := player_mech.get_component(entry["target"])
	var target_name: String = target_comp.name if target_comp != null else entry["target"]
	if entry.get("protocol", "") != "":
		combat_log.log_line("%s primed %s." % [_label_for(mech), card_name], CombatLog.CAT_ENEMY)
	else:
		combat_log.log_line("%s used %s on your %s for %d dmg." % [_label_for(mech), card_name, target_name, entry["damage"]], CombatLog.CAT_ENEMY)
	_refresh_all_panels()

## A passive fired: its badge pulses, and a turn-start one says what it gave.
func _on_passive_triggered(mech: MechData, component: ComponentData) -> void:
	var row: PassiveRow = player_panel.passive_row if mech == player_mech else null
	var panel := _panel_for(mech)
	if panel != null:
		row = panel.passive_row
	var icon := row.icon_for(component) if row != null else null
	if icon == null:
		return
	icon.pulse()
	if component.passive_type() == ComponentData.PASSIVE_TURN_START_STATUS and hit_fx != null:
		var text := "+%d %s" % [int(component.passive.get("stacks", 0)), str(component.passive.get("status", "")).capitalize()]
		hit_fx.float_text(icon.get_global_rect().get_center() + Vector2(0, -8), text, Palette.LINK, 16)

## A boss at half HP changes how it fights: its line, big.
func _on_boss_phase(mech: MechData) -> void:
	var who := mech.title if mech.title != "" else _label_for(mech)
	var line: String = mech.lines.get("phase2", "")
	Audio.play("boss_phase", 0.0)
	combat_log.log_line("%s changes tactics.%s" % [who, "" if line == "" else " \"%s\"" % line], CombatLog.CAT_ENEMY)
	show_banner(who.to_upper(), line if line != "" else "changes tactics", Palette.DANGER)

## A chance effect didn't land: say so where it would have, like a MISS.
func _on_chance_failed(mech: MechData, component: ComponentData) -> void:
	var grid := _grid_for(mech)
	if grid != null and hit_fx != null and component != null:
		hit_fx.float_text(grid.component_center_global(component) + Vector2(0, -22), "no effect", Palette.TEXT_MUTED, 16)

func _on_mech_vented(mech: MechData, amount: int) -> void:
	Audio.play("vent")
	combat_log.log_line("%s vented %d heat." % [_label_for(mech), amount], CombatLog.CAT_YOU if mech == player_mech else CombatLog.CAT_ENEMY)
	var grid := _grid_for(mech)
	if hit_fx != null and grid != null:
		var at := player_panel.image_global_rect().get_center() if mech == player_mech else grid.get_global_rect().get_center()
		hit_fx.float_text(at, "VENT −%d" % amount, Palette.LINK, 20)
	_refresh_all_panels()

func _on_enemy_retreated(mech: MechData) -> void:
	combat_log.log_line("%s retreats: nothing left to fight with." % _label_for(mech), CombatLog.CAT_ENEMY)
	_refresh_all_panels()

func _on_enemy_set_aside(mech: MechData, card: CardData) -> void:
	combat_log.log_line("%s set %s aside for next turn (Standby)." % [_label_for(mech), card.name], CombatLog.CAT_ENEMY)

## A quick word across the middle of the screen as a turn starts.
func _turn_flash(text: String, color: Color) -> void:
	var l := UIKit.label(text, 30, color)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.z_index = 250
	add_child(l)
	await get_tree().process_frame
	var screen := get_viewport_rect().size
	l.position = Vector2((screen.x - l.size.x) / 2.0, screen.y * 0.5)
	l.modulate.a = 0.0
	var tw := l.create_tween()
	tw.tween_property(l, "modulate:a", 0.9, 0.15)
	tw.parallel().tween_property(l, "position:x", l.position.x + 12.0, 0.7)
	tw.tween_property(l, "modulate:a", 0.0, 0.3)
	tw.finished.connect(l.queue_free)

## A two-line banner across the upper middle of the screen that fades in,
## holds and fades out on its own (boss intros and phase changes).
func show_banner(title: String, line: String, color: Color) -> void:
	var box := PanelContainer.new()
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.z_index = 300
	box.add_theme_stylebox_override("panel", GlassPanel.panel_style(color, 16.0))
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 4)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(v)
	var t := UIKit.label(title, 22, color)
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(t)
	if line != "":
		var l := UIKit.label("\"%s\"" % line, 15, Palette.TEXT)
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		v.add_child(l)
	add_child(box)
	box.modulate.a = 0.0
	await get_tree().process_frame
	var screen := get_viewport_rect().size
	box.position = Vector2((screen.x - box.size.x) / 2.0, screen.y * 0.3)
	var tw := box.create_tween()
	tw.set_ignore_time_scale(true)
	tw.tween_property(box, "modulate:a", 1.0, 0.25)
	tw.tween_interval(2.6)
	tw.tween_property(box, "modulate:a", 0.0, 0.5)
	tw.finished.connect(box.queue_free)

var _last_hit_sfx_ms: int = 0
## A hit this big gets a short freeze-frame and the heavy thud on top.
const BIG_HIT := 20
## Your HP share the low-HP alarm sounds at (once each time it's crossed).
const LOW_HP_SHARE := 0.3
var _low_hp_warned: bool = false

## Hit sounds by weapon type (Logan, 2026-09-30), from the attacking part's
## Refit Bay id: melee scrapes, guns crack, explosives boom, energy zaps.
const HIT_WORDS := {
	"hit_blade": ["blade", "axe", "saw", "whip", "fang", "rapier", "hammer", "fist", "maw", "driver", "anchor", "hook", "leech"],
	"hit_rocket": ["rocket", "mortar", "dropper", "swarm", "flak", "cataclysm", "firestorm", "schism"],
	"hit_energy": ["laser", "arc", "tesla", "voltage", "ion", "coil", "plasma", "nova", "heat_lance", "thermal", "resonance", "spike_rifle"],
}

static func hit_sound(part: ComponentData) -> String:
	if part == null:
		return "hit"
	for key in ["hit_energy", "hit_rocket", "hit_blade"]:
		for w in HIT_WORDS[key]:
			if part.library_id.contains(w):
				return key
	return "hit_gun"

func _on_hit_landed(mech: MechData, component: ComponentData, damage: int) -> void:
	var now := Time.get_ticks_msec()
	if now - _last_hit_sfx_ms >= 45: # a volley's hits share one sound
		_last_hit_sfx_ms = now
		if damage <= 0:
			Audio.play("shield")
		else:
			Audio.play(hit_sound(combat.pending_attacker_component()))
			if damage >= BIG_HIT:
				Audio.play("hit_heavy", 0.06, -4.0)
	if damage >= BIG_HIT:
		hitstop(40 + mini(damage, 40))
	_refresh_all_panels()
	_impact(mech, component, damage)
	if mech == player_mech:
		var low := player_mech.current_hp() <= player_mech.max_hp() * LOW_HP_SHARE
		if low and not _low_hp_warned:
			Audio.play("low_hp", 0.0)
			if hit_fx != null:
				hit_fx.float_text(player_panel.image_global_rect().get_center() + Vector2(0, -40), "HP LOW", Palette.DANGER, 20)
		_low_hp_warned = low

func _on_game_over(result) -> void:
	Tutorial.reached("combat_over", {})
	UIState.input_locked = true
	if turn_panel != null:
		turn_panel.set_enabled(false)
	if player_reticle != null:
		player_reticle.hide_now()
	if enemy_reticle != null:
		enemy_reticle.hide_now()
	combat_log.log_line("VICTORY!" if result == CombatManager.Result.WIN else "DEFEAT.")
	Audio.play("victory" if result == CombatManager.Result.WIN else "defeat", 0.0)
	if result == CombatManager.Result.WIN:
		for m in enemy_mechs:
			if m.tier == "boss" and m.lines.has("defeat"):
				combat_log.log_line("%s: \"%s\"" % [m.title if m.title != "" else m.name, m.lines["defeat"]], CombatLog.CAT_ENEMY)
	var action := "Restart"
	if _replaying:
		action = "Back"
	elif _in_run():
		action = "Continue" if result == CombatManager.Result.WIN else "Eject"
	end_screen.show_result(result, action, combat.stats)

# ---------- recording and replays ----------

## A run fight (a replay is never one).
func _in_run() -> bool:
	return not _replaying and RunState.is_active()

## Saves this fight's recording once it's over or left, and tells the run
## which file it went to (its fight log names it).
func _save_record(result: String) -> void:
	if _record.is_empty() or combat == null:
		return
	FightRecord.finish(_record, combat, result)
	var name := Replays.save(_record)
	_record = {}
	if _in_run():
		RunState.run.last_replay = name

## The top-left strip while watching: what this is, and a way out.
func _build_replay_bar() -> void:
	_replay_bar = HBoxContainer.new()
	_replay_bar.add_theme_constant_override("separation", 10)
	_replay_bar.position = Vector2(SIDE_MARGIN, SIDE_MARGIN)
	_replay_bar.z_index = 150
	var when := str(replay_record.get("date", "")).replace("T", " ").left(16)
	var where := str(replay_record.get("location", ""))
	var l := UIKit.label("REPLAY%s%s" % ["  ·  " + where if where != "" else "", "  ·  " + when if when != "" else ""], 15, Palette.LINK)
	l.add_theme_color_override("font_outline_color", Color.BLACK)
	l.add_theme_constant_override("outline_size", 4)
	_replay_bar.add_child(l)
	var leave := GlassPanel.button("Leave replay", 12)
	leave.custom_minimum_size = Vector2(110, 26)
	leave.pressed.connect(_leave_replay)
	_replay_bar.add_child(leave)
	add_child(_replay_bar)

## Feeds the recorded commands in, each once the player's turn is ready
## (attacks played out, the enemy turn done), after a short beat.
func _replay_drive(gen: int) -> void:
	for cmd in replay_record.get("commands", []):
		while gen == _generation and not combat.is_player_turn():
			if combat.is_game_over():
				return
			await get_tree().process_frame
		if gen != _generation:
			return
		await get_tree().create_timer(REPLAY_STEP, false).timeout
		if gen != _generation:
			return
		if not await _replay_command(gen, cmd):
			if gen == _generation:
				combat_log.log_line("The replay went out of step here: the game's rules or parts have changed since this fight was played.", CombatLog.CAT_TURN)
				show_banner("REPLAY OUT OF STEP", "The rules or parts changed since this fight was played.", Palette.WARNING)
			return
	while gen == _generation and not combat.is_player_turn() and not combat.is_game_over():
		await get_tree().process_frame
	if gen == _generation and not combat.is_game_over():
		show_banner("END OF RECORDING", "The pilot left the fight here.", Palette.TEXT_MUTED)
		end_screen.show_result(CombatManager.Result.LOSE, "Back", combat.stats)

## Plays one recorded command the way the pilot did: the card lifts, an
## attack's crosshair finds its part, then it goes through the same path as
## a drop. Returns whether the fight took it.
func _replay_command(gen: int, cmd: Dictionary) -> bool:
	var before := combat.command_log.size()
	match str(cmd.get("type", "")):
		"play":
			var card := combat.find_card(str(cmd.get("card", "")))
			if card == null:
				return false
			var ui := hand_tray.card_ui_for(card)
			if ui != null:
				ui.set_selected(true)
			UIState.set_hovered_card(card)
			_replay_hit = {}
			var point := Vector2.ZERO
			if card.is_attack():
				var t: Array = cmd.get("target", [])
				var mech := combat.mech_at(int(t[0])) if t.size() == 2 else null
				var comp := mech.get_component(str(t[1])) if mech != null else null
				var panel := _panel_for(mech) if mech != null else null
				if comp == null or panel == null:
					return false
				point = panel.grid.component_center_global(comp)
				_replay_hit = {"mech": mech, "component": comp, "panel": panel}
				player_reticle.follow(point, 1.0, true)
				_set_targeting(_replay_hit)
			await get_tree().create_timer(REPLAY_STEP, false).timeout
			if gen != _generation:
				return true
			if ui != null and is_instance_valid(ui):
				ui.set_selected(false)
			UIState.clear_hovered_card(card)
			_replay_driving = true
			if card.protocol() == "reroute":
				combat.apply(combat.play_command(card, null, null, cmd.get("options", {})).merged({"paced": true}))
			else:
				_handle_card_drop(card, point, CardUI.FADE_END)
			_replay_driving = false
			_replay_hit = {}
		"vent":
			_replay_driving = true
			_vent()
			_replay_driving = false
		"end_turn":
			_replay_driving = true
			_on_end_turn_pressed()
			_replay_driving = false
	return combat.command_log.size() > before

func _leave_replay() -> void:
	if SceneRouter.is_busy():
		return
	_generation += 1 # stops the replay's coroutines
	replay_record = {}
	SceneRouter.go(replay_return)

