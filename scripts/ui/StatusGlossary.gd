class_name StatusGlossary
extends RefCounted
## Rule text for the Description Box's status glossary (UI & Screens:
## "Status glossary: the rule text ... for each status on the hovered
## component"). Mirrors Statuses & Links / Refit Bay's Statuses tab, with
## the Combat Slice's clarifications where the base rule had a gap.

const ENTRIES := {
	"shock": {
		"label": "Shock",
		"rule": "Deals 2/3 damage (rounded down) on every hit while it holds any Shock.",
		"decay": "Loses 1 stack at the end of its own side's turn.",
	},
	"absorb": {
		"label": "Absorb",
		"rule": "The next hit on this mech is reduced by the stacks, and the hit component heals that much (can't revive a destroyed one).",
		"decay": "All stacks are lost the instant a hit triggers it, or at the start of this mech's own turn.",
	},
	"deflect": {
		"label": "Deflect",
		"rule": "Incoming damage is reduced by the stacks (a flat amount) on every hit.",
		"decay": "Each hit it reduces removes ceil(stacks/2) — a single stack is used up on the very next hit.",
	},
	"destroyed": {
		"label": "Destroyed",
		"rule": "HP hit 0. Gone for the rest of the run.",
		"decay": "Permanent. Its cards are removed from the hand.",
	},
}

static func get_entry(status_name: String) -> Dictionary:
	return ENTRIES.get(status_name, {"label": status_name.capitalize(), "rule": "(not implemented this slice)", "decay": ""})
