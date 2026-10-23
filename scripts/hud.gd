extends Label
## Bottom-center hints for the current mode.


func _ready() -> void:
	Game.mode_changed.connect(_refresh)
	_refresh()


func _refresh() -> void:
	text = ""
	if Game.building:
		if Game.build_tool == "demolish":
			text = "DEMOLIR — arraste sobre construções para marcar (Shift desmarca)   X volta a construir"
		elif Game.build_tool == "roof":
			text = "TELHADO — arraste do canto de uma parede ao canto oposto, por cima delas · R gira a cumeeira"
		else:
			text = "CONSTRUIR %s — arraste para planejar · altura: roda ou + / - · R gira · Shift apaga planos" \
				% Pieces.ITEMS[Game.build_item].name.to_upper()
		text += "\nX demolir · B / botão direito / Esc sai"
	elif Game.pending_area:
		var editing: String = " (editando #%d)" % Game.pending_area.order.id if Game.pending_area.order else ""
		text = "Arraste sobre os blocos do chão: %s%s" % [Game.ORDER_NAMES[Game.pending_area.kind], editing]
		if Game.pending_area.kind == "dig":
			text += "\nPROFUNDIDADE: %d camada(s) a partir da superfície (roda do mouse ou + / -)" % Game.dig_depth
		text += "   (botão direito / Esc cancela)"
