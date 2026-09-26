extends Node
## Autoload (see project.godot [autoload]). Loads mech definitions from disk
## on demand and hands out fresh, independent MechData instances — combat
## mutates HP/heat/statuses heavily, so every fight (and every test) gets
## its own clone rather than sharing state.

const BASTION_PATH := "res://data/mechs/bastion.json"
const SCRAP_WARDEN_PATH := "res://data/mechs/scrap_warden.json"

func fresh_mech(path: String) -> MechData:
	return DataLoader.load_mech_from_file(path)

func fresh_bastion() -> MechData:
	return fresh_mech(BASTION_PATH)

func fresh_scrap_warden() -> MechData:
	return fresh_mech(SCRAP_WARDEN_PATH)
