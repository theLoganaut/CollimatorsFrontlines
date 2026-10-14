extends HubScreen
## Livery Bay: paint schemes for your mech, bought with Chips (Logan,
## 2026-09-28: a new cosmetic should take several days of play). Until
## there's art, a livery paints the mech image behind the grid in combat.
## Buy one to own it for good; wear any you own.

const TILE := Vector2(210, 196)
const SWATCH := Vector2(186, 110)

var _grid: GridContainer
var _message: Label

func screen_title() -> String:
	return "Livery Bay"

func backdrop_name() -> String:
	return "livery_bay"

func _build() -> void:
	_grid = GridContainer.new()
	_grid.columns = 5
	_grid.add_theme_constant_override("h_separation", 12)
	_grid.add_theme_constant_override("v_separation", 12)
	add_child(_grid)
	_message = UIKit.label("", 14, Palette.TEXT_MUTED)
	add_child(_message)
	_fill()

func _fill() -> void:
	for c in _grid.get_children():
		c.queue_free()
	for l in Meta.liveries():
		_grid.add_child(_tile(l))
	refresh_chips()

func _tile(l: Dictionary) -> Control:
	var owned: bool = Profile.liveries.has(l["id"])
	var worn: bool = Profile.livery == l["id"]
	var box := HubScreen.card(Palette.LINK if worn else Palette.BORDER)
	box.custom_minimum_size = TILE
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 6)
	box.add_child(v)
	var swatch := Control.new()
	swatch.custom_minimum_size = SWATCH
	swatch.mouse_filter = Control.MOUSE_FILTER_IGNORE
	swatch.draw.connect(func(): Meta.paint_livery(swatch, Rect2(Vector2.ZERO, SWATCH), l))
	v.add_child(swatch)
	var row := HBoxContainer.new()
	row.add_child(UIKit.label(l["name"], 15, Palette.TEXT))
	row.add_child(UIKit.spacer())
	if l.get("tier", "free") == "premium":
		row.add_child(UIKit.label("Premium", 11, Palette.rarity_color("prototype")))
	v.add_child(row)
	var price := Meta.livery_price(l)
	var btn: Button
	if worn:
		btn = HubScreen.glass_button("Wearing", Color.TRANSPARENT, Vector2(0, 32), 13)
		btn.disabled = true
	elif owned:
		btn = HubScreen.glass_button("Wear", Palette.REACTOR, Vector2(0, 32), 13)
		btn.pressed.connect(func(): Profile.wear_livery(l["id"]); _message.text = "%s on. It shows in your next fight." % l["name"]; _fill())
	else:
		btn = HubScreen.glass_button("Buy · %s Chips" % HubScreen._thousands(price), Palette.SCRAPS if Profile.chips >= price else Color.TRANSPARENT, Vector2(0, 32), 13)
		btn.disabled = Profile.chips < price
		btn.pressed.connect(func():
			if Profile.buy_livery(l["id"]):
				Profile.wear_livery(l["id"])
				_message.text = "%s bought and on." % l["name"]
			_fill())
	v.add_child(btn)
	return box

func _layout(screen: Vector2) -> void:
	var w := 5 * TILE.x + 4 * 12.0
	_grid.position = Vector2((screen.x - w) / 2.0, TOP_BAR_H + 30.0)
	_message.position = Vector2((screen.x - w) / 2.0, screen.y - 56.0)
	_message.size = Vector2(w, 30)
