class_name Crafting
## Production, RimWorld bills simplified. Each workstation keeps one bill per recipe it can make:
## mode "off", "forever", or "until" (keep making while the stockpile holds fewer than `target` of
## the product). A villager with Crafting work takes an active bill whose ingredients are in stock,
## fetches them tile by tile, works at the station for the recipe time, then hauls the product to
## the stockpile.
## Crafting tree for the player: docs/crafting.md. Keep it in sync with RECIPES.

const STATIONS := {
	"kiln": {"name": "Carvoaria", "info": "Queima madeira devagar, sem chama aberta, até virar carvão."},
	"furnace": {"name": "Fornalha", "info": "Funde minério com carvão em barras de metal."},
}
# in / out: resource -> amount per batch. time: seconds of work at the station per batch.
const RECIPES := {
	"charcoal": {"name": "Carvão", "station": "kiln", "in": {"wood": 3}, "out": {"charcoal": 3}, "time": 12.0},
	"iron_bar": {"name": "Barra de ferro", "station": "furnace", "in": {"iron_ore": 2, "charcoal": 2},
		"out": {"iron": 2}, "time": 15.0},
}
const MODES := ["off", "forever", "until"]
const MODE_NAMES := {"off": "Desligado", "forever": "Repetir sempre", "until": "Fazer até ter"}
const DEFAULT_TARGET := 10


static func is_station(item: String) -> bool:
	return STATIONS.has(item)


static func recipes_for(station_item: String) -> Array[String]:
	var out: Array[String] = []
	for id: String in RECIPES:
		if RECIPES[id].station == station_item:
			out.append(id)
	return out


static func product(id: String) -> String:
	return RECIPES[id].out.keys()[0]


# "3 madeira → 3 carvão · 12 s"
static func describe(id: String) -> String:
	var r: Dictionary = RECIPES[id]
	return "%s → %s · %d s" % [_list(r.in), _list(r.out), int(r.time)]


static func _list(items: Dictionary) -> String:
	var parts: PackedStringArray = []
	for kind: String in items:
		parts.append("%d %s" % [items[kind], Game.RESOURCES[kind].name])
	return " + ".join(parts)


# Why a bill isn't being worked right now ("" = it can be).
static func blocker(bill: Dictionary, id: String) -> String:
	var r: Dictionary = RECIPES[id]
	if bill.mode == "off":
		return "desligado"
	if bill.mode == "until" and Game.stock[product(id)] >= bill.target:
		return "meta atingida"
	for kind: String in r.in:
		if Game.withdraw_tile(kind, r.in[kind], Vector3.ZERO) == null:
			return "falta %s" % Game.RESOURCES[kind].name
	if not Game.has_room(product(id)):
		return "sem espaço no estoque"
	return ""


# First recipe of this station that wants work and can be done now, or "".
static func next_recipe(st: Dictionary) -> String:
	for id: String in st.bills:
		if blocker(st.bills[id], id) == "":
			return id
	return ""
