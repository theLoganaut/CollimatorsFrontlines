class_name StatusGlossary
extends RefCounted
## Rule text for the Description Box's status glossary (UI & Screens:
## "Status glossary: the rule text ... for each status on the hovered
## component"). Mirrors Statuses & Links / Refit Bay's Statuses tab, with
## the Combat Slice's clarifications where the base rule had a gap.

## "tip": the Operator's one-time plain-words note the first time a pilot
## meets the status in a fight (CombatScene._explain_a_status).
const ENTRIES := {
	"shock": {
		"label": "Shock",
		"rule": "The part deals 1/3 less damage (rounded down) on every hit while it has any stacks. Lasts one of its owner's turns per stack.",
		"decay": "Loses 1 stack at the end of its own side's turn.",
		"tip": "Shock. A shocked part hits for a third less while it's on. It wears off a stack each turn.",
	},
	"acid": {
		"label": "Acid",
		"rule": "The part takes 1/3 more damage from every hit while it has any stacks. Lasts one of its owner's turns per stack.",
		"decay": "Lose 1 at end of turn.",
		"tip": "Acid. A part with Acid takes a third more damage. It drops a stack each turn.",
	},
	"absorb": {
		"label": "Absorb",
		"rule": "The next hit on this mech is reduced by 1 per stack, and the part it lands on heals that much (a destroyed part stays destroyed). All stacks go on that one hit, or at the start of this mech's next turn.",
		"decay": "All stacks are lost the instant a hit triggers it, or at the start of this mech's own turn.",
		"tip": "Absorb soaks up the next hit on that mech and patches the part it lands on. It's spent after one hit, or when that mech's turn starts.",
	},
	"deflect": {
		"label": "Deflect",
		"rule": "Every hit on this mech deals 1 less damage per stack. Each hit it blocks uses up half the stacks (rounded up); unused stacks stay.",
		"decay": "Each hit it reduces removes ceil(stacks/2) — a single stack is used up on the very next hit.",
		"tip": "Deflect knocks a flat amount off every hit, and wears down as it blocks. Lots of small hits strip it fast.",
	},
	"burn": {
		"label": "Burn",
		"rule": "Adds 1 Heat per stack to its mech at the start of its owner's turn. Lasts one of its owner's turns per stack.",
		"decay": "Lose 1 at end of turn.",
		"tip": "Burn adds heat at the start of that mech's turn, one per stack. Watch your max.",
	},
	"disabled": {
		"label": "Disabled",
		"rule": "The part's cards can't be played. Lasts one of its owner's turns per stack.",
		"decay": "Lose 1 at the end of its owner's turn: on your part, the end of your turn; on an enemy's, the end of theirs.",
		"tip": "Disabled parts can't be used until it wears off at the end of their owner's turn.",
	},
	"offline": {
		"label": "Offline",
		"rule": "The part's cards can't be played for the rest of this fight. It's back for the next one.",
		"decay": "Clears when the fight ends.",
		"tip": "Offline means that part is out for the rest of the fight. It's back for the next one.",
	},
	"freeze": {
		"label": "Freeze",
		"rule": "Play a card from the frozen part and it goes Offline for the rest of the fight. Wait it out: lasts one of its owner's turns per stack.",
		"decay": "Lose 1 at end of turn.",
		"tip": "Freeze: use that part and it goes Offline for the fight. Wait it out; it drops a stack each turn.",
	},
	"coolant": {
		"label": "Coolant",
		"rule": "The part's cards cost 1 less Heat. Each card played from it uses 1 stack.",
		"decay": "Lose 1 each time the component is used.",
		"tip": "Coolant makes that part's cards cost 1 less heat. Each use spends a stack.",
	},
	"jam": {
		"label": "Jam",
		"rule": "The part's cards cost 1 more Heat. Each card played from it clears 1 stack.",
		"decay": "Lose 1 each time the component is used.",
		"tip": "Jam makes that part's cards cost 1 more heat. Each use clears a stack.",
	},
	"smoke": {
		"label": "Smoke",
		"rule": "The mech vents 1 less Heat per stack; each point held back uses 1 stack. It also loses 1 stack at the end of each of its turns.",
		"decay": "Consumed by venting, and lose 1 at end of turn.",
		"tip": "Smoke holds back that mech's venting, a point per stack. It burns off as the heat vents.",
	},
	"destroyed": {
		"label": "Destroyed",
		"rule": "HP hit 0. Its cards and passive are gone, and it can't be repaired: the next refit clears its wreck off the chassis.",
		"decay": "Permanent. Its cards are removed from the hand.",
	},
}

## Keywords card text uses in place of a sentence (Slay-the-Spire short),
## explained in the same glossary when a hovered card or part mentions them.
## "pattern" (a regex) when the word comes in more than one form.
const KEYWORDS := {
	"vent": {"label": "Vent", "rule": "Lose that much Heat. Smoke on your mech eats into it."},
	"pierce": {"label": "Pierce", "rule": "Ignores Deflect, Absorb and cover."},
	"reclaim": {"label": "Reclaim", "rule": "Heals your most damaged part for that share of the damage dealt."},
	"linked": {"label": "Linked", "rule": "The parts this part's link arrows point at on the grid (hover the part to see its arrows)."},
	"overheat": {"label": "Overheat", "pattern": "Overheat(?:ing|s|ed)?", "rule": "Going over Max Heat: backlash damage (15% of max HP) spread across your parts, and the turn ends."},
}
## Other forms of a status's name in card text ("Double damage vs Frozen").
const STATUS_FORMS := {"Frozen": "freeze"}

## The keyword entries a piece of card or passive text mentions.
static func keywords_in(text: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for key in KEYWORDS:
		var e: Dictionary = KEYWORDS[key]
		if RegEx.create_from_string("\\b%s\\b" % e.get("pattern", e["label"])).search(text) != null:
			out.append(e)
	return out

## Card or passive text as BBCode for a RichTextLabel (UIKit.rich_label):
## every status and keyword it names is tinted and is a link whose meta is
## the word, so hovering it opens its rule (lookup(), HoloHint). One pass
## over the text, so a rule never gets tagged inside another.
static func annotate(text: String) -> String:
	var patterns: Array[String] = []
	for st in ENTRIES:
		if st != "destroyed":
			patterns.append(ENTRIES[st]["label"])
	for form in STATUS_FORMS:
		patterns.append(form)
	for key in KEYWORDS:
		patterns.append(KEYWORDS[key].get("pattern", KEYWORDS[key]["label"]))
	var re := RegEx.create_from_string("\\b(%s)\\b" % "|".join(patterns))
	var out := ""
	var at := 0
	for m in re.search_all(text):
		out += _escape(text.substr(at, m.get_start() - at))
		var word := m.get_string()
		var e := lookup(word)
		out += "[color=#%s][url=%s]%s[/url][/color]" % [(e["color"] as Color).lightened(0.15).to_html(false), word, word]
		at = m.get_end()
	return out + _escape(text.substr(at))

## The status a word in card text names ("shock", "freeze" for "Frozen"), or "".
static func status_id(word: String) -> String:
	if STATUS_FORMS.has(word):
		return STATUS_FORMS[word]
	for st in ENTRIES:
		if st != "destroyed" and ENTRIES[st]["label"] == word:
			return st
	return ""

## The status or keyword a word in card text names: {label, rule, color},
## or {} if it names none ("Frozen" is Freeze, "Overheats" is Overheat).
static func lookup(word: String) -> Dictionary:
	for st in ENTRIES:
		if st != "destroyed" and ENTRIES[st]["label"] == word:
			return {"label": ENTRIES[st]["label"], "rule": ENTRIES[st]["rule"], "color": Palette.status_color(st)}
	if STATUS_FORMS.has(word):
		var st: String = STATUS_FORMS[word]
		return {"label": ENTRIES[st]["label"], "rule": ENTRIES[st]["rule"], "color": Palette.status_color(st)}
	for key in KEYWORDS:
		var e: Dictionary = KEYWORDS[key]
		if RegEx.create_from_string("^(%s)$" % e.get("pattern", e["label"])).search(word) != null:
			return {"label": e["label"], "rule": e["rule"], "color": Palette.LINK}
	return {}

## Every status in `statuses` (names) and every keyword `text` mentions, as
## {label, rule, color}, without repeats: what a card or part needs explained.
static func entries_for(text: String, statuses: Array = []) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var seen := {}
	for st in statuses:
		var entry := get_entry(str(st))
		if not seen.has(entry["label"]):
			seen[entry["label"]] = true
			out.append({"label": entry["label"], "rule": entry["rule"], "color": Palette.status_color(str(st))})
	for e in keywords_in(text):
		if not seen.has(e["label"]):
			seen[e["label"]] = true
			out.append({"label": e["label"], "rule": e["rule"], "color": Palette.LINK})
	return out

static func _escape(s: String) -> String:
	return s.replace("[", "[lb]")

static func get_entry(status_name: String) -> Dictionary:
	return ENTRIES.get(status_name, {"label": status_name.capitalize(), "rule": "(not implemented this slice)", "decay": ""})
