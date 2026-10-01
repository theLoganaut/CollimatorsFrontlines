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
	"acid": {
		"label": "Acid",
		"rule": "Component takes 1/3 more damage.",
		"decay": "Lose 1 at end of turn.",
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
	"burn": {
		"label": "Burn",
		"rule": "+1 Heat per stack at turn start.",
		"decay": "Lose 1 at end of turn.",
	},
	"disabled": {
		"label": "Disabled",
		"rule": "Component can't be used.",
		"decay": "Lose 1 at the end of its owner's turn: on your part, the end of your turn; on an enemy's, the end of theirs.",
	},
	"offline": {
		"label": "Offline",
		"rule": "Component can't be used for the rest of this fight.",
		"decay": "Clears when the fight ends.",
	},
	"freeze": {
		"label": "Freeze",
		"rule": "If the component is used, Freeze is removed and the component goes Offline.",
		"decay": "Lose 1 at end of turn.",
	},
	"coolant": {
		"label": "Coolant",
		"rule": "Component costs 1 less Heat.",
		"decay": "Lose 1 each time the component is used.",
	},
	"jam": {
		"label": "Jam",
		"rule": "Component costs 1 more Heat.",
		"decay": "Lose 1 each time the component is used.",
	},
	"smoke": {
		"label": "Smoke",
		"rule": "Venting is reduced by the stacks, and each point vented removes 1 stack first.",
		"decay": "Consumed by venting, and lose 1 at end of turn.",
	},
	"destroyed": {
		"label": "Destroyed",
		"rule": "HP hit 0. Gone for the rest of the run.",
		"decay": "Permanent. Its cards are removed from the hand.",
	},
}

## Keywords card text uses in place of a sentence (Slay-the-Spire short),
## explained in the same glossary when a hovered card or part mentions them.
const KEYWORDS := {
	"vent": {"label": "Vent", "rule": "Lose that much Heat. Smoke on your mech eats into it."},
	"pierce": {"label": "Pierce", "rule": "Ignores Deflect, Absorb and cover."},
	"lifesteal": {"label": "Lifesteal", "rule": "Heals your most damaged part for that share of the damage dealt."},
}

## The keyword entries a piece of card or passive text mentions.
static func keywords_in(text: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for key in KEYWORDS:
		var e: Dictionary = KEYWORDS[key]
		if RegEx.create_from_string("\\b%s\\b" % e["label"]).search(text) != null:
			out.append(e)
	return out

static func get_entry(status_name: String) -> Dictionary:
	return ENTRIES.get(status_name, {"label": status_name.capitalize(), "rule": "(not implemented this slice)", "decay": ""})
