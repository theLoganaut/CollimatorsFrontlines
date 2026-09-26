class_name Palette
extends RefCounted
## The dark palette from Refit Bay, as recorded on the UI & Screens Notion
## page. Placeholder art throughout, but these are the real category/status
## colors so the grid reads the same way Refit Bay's own grid does.

const BG := Color("0a0d12")
const PANEL := Color("12161d")
const PANEL_2 := Color("171b23")
const BORDER := Color("252b36")
const TEXT := Color("e8ebf0")
const TEXT_MUTED := Color("8189a0")

const HARDPOINT := Color("e5622f")
const REACTOR := Color("3fc4b8")
const PROTOCOL := Color("a486e0")
const CHASSIS := Color("6f93bd")

const DANGER := Color("d3402a")
const WARNING := Color("d0a12b")
const LINK := Color("f5cc45")
const OK := Color("2f9f96")

static func category_color(category: String) -> Color:
	match category:
		ComponentData.CATEGORY_HARDPOINT:
			return HARDPOINT
		ComponentData.CATEGORY_REACTOR:
			return REACTOR
		ComponentData.CATEGORY_PROTOCOL:
			return PROTOCOL
		_:
			return CHASSIS
