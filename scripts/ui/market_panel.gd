extends PanelContainer
## The market (T on the world map, online): trade wood, stone and food with
## other players, and gear and gems for Marks. "Buy" lists everyone else's offers, "Sell" puts one of your
## own up, and "Your offers" shows what you have up (to take down) and what
## sold. The server decides everything (data/market.json); the screen is
## redrawn from each answer it sends.

const ME := Color(1.0, 0.85, 0.45)
const GOOD := Color(0.6, 0.9, 0.5)
const BAD := Color(1.0, 0.55, 0.42)
const REFRESH := 20.0          ## seconds between asking the server while open
const TABS := ["buy", "sell", "mine"]

var _tab := "buy"
var _filter := ""              ## "buy": only offers giving this good ("" for all)
var _tab_buttons := {}         ## tab -> Button
var _rule: Label
var _rates: Label
var _scroll: ScrollContainer
var _body: VBoxContainer
var _note: Label
var _refresh_left := 0.0
# The sell form, kept across redraws.
var _sell: VBoxContainer
var _give: OptionButton
var _give_amount: SpinBox
var _want: OptionButton
var _want_amount: SpinBox
var _summary: Label
var _price_label: Label
var _post: Button
var _sell_mode := "goods"      ## "goods" (resources) or "items" (gear and gems for Marks)
var _mode_buttons := {}
var _goods_form: VBoxContainer
var _items_form: VBoxContainer
var _item_pick: OptionButton
var _item_amount: SpinBox
var _item_price: SpinBox
var _item_summary: Label
var _item_post: Button


func _ready() -> void:
	add_theme_stylebox_override("panel", MenuStyle.panel(0.95))
	custom_minimum_size = Vector2(760, 0)
	visible = false
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	add_child(box)
	var head := HBoxContainer.new()
	set_meta("window_head", head)
	head.add_theme_constant_override("separation", 10)
	box.add_child(head)
	head.add_child(Icons.rect("market", 36))
	var title := MenuStyle.title("Market", 30)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(title)
	var close := Button.new()
	close.text = "×"
	close.focus_mode = Control.FOCUS_NONE
	close.add_theme_font_size_override("font_size", 20)
	close.pressed.connect(close_panel)
	head.add_child(close)
	_rule = MenuStyle.label("", 14, MenuStyle.MUTED)
	_rule.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(_rule)
	set_meta("window_help", _rule)
	var tabs := HBoxContainer.new()
	tabs.add_theme_constant_override("separation", 8)
	box.add_child(tabs)
	for tab: String in TABS:
		var b := _small({"buy": "Buy", "sell": "Sell", "mine": "Your offers"}[tab], func() -> void: _show(tab))
		b.toggle_mode = true
		b.custom_minimum_size = Vector2(150, 34)
		_tab_buttons[tab] = b
		tabs.add_child(b)
	_rates = MenuStyle.label("", 14, MenuStyle.MUTED)
	_rates.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(_rates)
	_scroll = ScrollContainer.new()
	_scroll.custom_minimum_size = Vector2(0, 380)
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	box.add_child(_scroll)
	_body = VBoxContainer.new()
	_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_body.add_theme_constant_override("separation", 8)
	_scroll.add_child(_body)
	_note = MenuStyle.label("", 16, ME)
	_note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(_note)
	var buttons := HBoxContainer.new()
	buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	buttons.add_theme_constant_override("separation", 12)
	buttons.add_child(MenuStyle.button("Refresh", Economy.ask_market, 180.0))
	var close_button := MenuStyle.button("Close", close_panel, 180.0)
	buttons.add_child(close_button)
	set_meta("window_close", close_button)   ## in a GameWindow its own close button does this
	box.add_child(buttons)
	_build_sell_form()
	Economy.market_changed.connect(func(error: String) -> void:
		if visible:
			_note.text = error
			_note.add_theme_color_override("font_color", BAD if error != "" else ME)
			_fill())


func _unhandled_input(event: InputEvent) -> void:
	if not event is InputEventKey or not event.pressed or event.echo:
		return
	if get_viewport().gui_get_focus_owner() is LineEdit:
		return
	if event.physical_keycode == KEY_T and not get_tree().paused and Economy.online:
		toggle()
		get_viewport().set_input_as_handled()
	elif event.physical_keycode == KEY_ESCAPE and visible:
		close_panel()
		get_viewport().set_input_as_handled()


func _process(delta: float) -> void:
	if not visible:
		return
	_refresh_left -= delta
	if _refresh_left <= 0.0:
		_refresh_left = REFRESH
		Economy.ask_market()
	if _tab == "sell":
		_update_summary()


func toggle() -> void:
	if visible:
		close_panel()
	else:
		open_panel()


func open_panel() -> void:
	var r := Economy.market_rules
	_rule.text = "Trade wood, stone and food with other players, and gear and gems for Marks. Your goods wait at the market until someone buys the whole offer; the buyer gets them at once and you get the price, less the market's %d%% cut. Offers run for %d hours, then come back to you. Opens at keep level %d." % [
			roundi(float(r.get("fee", 0.0)) * 100.0), int(r.get("offer_hours", 48)), int(r.get("unlock_keep", 1))]
	_note.text = "" if not Economy.market.is_empty() else "Asking the server..."
	_note.add_theme_color_override("font_color", ME)
	_refresh_left = REFRESH
	Economy.ask_market()
	_show(_tab)
	visible = true


func close_panel() -> void:
	visible = false


func _show(tab: String) -> void:
	_tab = tab
	for t: String in _tab_buttons:
		_tab_buttons[t].button_pressed = t == tab
	if tab == "sell":
		_reset_sell_limits()
		_fill_item_picker()
	_fill()


# --- Drawing -------------------------------------------------------------------------

func _fill() -> void:
	if _sell.get_parent() != null:
		_sell.get_parent().remove_child(_sell)
	for child in _body.get_children():
		_body.remove_child(child)
		child.queue_free()
	_rates.text = _rates_text()
	match _tab:
		"buy":
			_fill_buy()
		"sell":
			_body.add_child(_sell)
			_update_summary()
			_update_item_summary()
		"mine":
			_fill_mine()


func _fill_buy() -> void:
	var filters := HBoxContainer.new()
	filters.add_theme_constant_override("separation", 8)
	filters.add_child(MenuStyle.label("Offers giving:", 15, MenuStyle.MUTED))
	for good: String in [""] + Array(Economy.market_rules.get("goods", [])) + ["gear", "gems"]:
		var b := _small("All" if good == "" else good.capitalize(), func() -> void:
			_filter = good
			_fill())
		b.toggle_mode = true
		b.button_pressed = _filter == good
		if good != "":
			b.icon = Icons.get_icon({"gear": "commanders", "gems": "gem"}.get(good, good), 20)
		filters.add_child(b)
	_body.add_child(filters)
	var offers: Array = Economy.market.get("offers", []).filter(func(o: Dictionary) -> bool:
		return _filter == "" or String(o.give) == _filter or (_filter == "gear" and String(o.give).begins_with("gear:")) \
				or (_filter == "gems" and not Economy.gear_rules.gem_parts(String(o.give)).is_empty()))
	if offers.is_empty():
		_body.add_child(MenuStyle.label("No offers right now. Put one up under Sell.", 15, MenuStyle.MUTED))
		return
	# The best price first: the least asked for each good given.
	offers.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return _price(a) < _price(b) if String(a.give) == String(b.give) and String(a.want) == String(b.want) \
				else String(a.give) + String(a.want) < String(b.give) + String(b.want))
	var grid := _grid(5)
	for text: String in ["Seller", "Gives", "Wants", "Price", ""]:
		grid.add_child(MenuStyle.label(text, 14, MenuStyle.MUTED))
	for o: Dictionary in offers:
		var tag := String(o.get("tag", ""))
		var who := MenuStyle.label(("[%s] " % tag if tag != "" else "") + String(o.seller_name), 16, MenuStyle.TEXT)
		who.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		who.clip_text = true
		grid.add_child(who)
		grid.add_child(_offer_goods(o))
		grid.add_child(_goods(String(o.want), int(o.want_amount)))
		grid.add_child(MenuStyle.label(_price_text(o), 14, MenuStyle.MUTED))
		var why := Economy.check_buy(o)
		var buy := _small("Buy", func() -> void:
			var refused := Economy.buy_offer(o)
			_note.text = refused if refused != "" else "Buying..."
			_note.add_theme_color_override("font_color", BAD if refused != "" else ME))
		buy.disabled = why != ""
		buy.tooltip_text = why
		grid.add_child(buy)
	_body.add_child(grid)


func _fill_mine() -> void:
	var mine: Array = Economy.market.get("mine", [])
	var most := int(Economy.market_rules.get("max_offers", 5))
	var items := mine.filter(func(o: Dictionary) -> bool: return String(o.want) == "marks").size()
	_body.add_child(MenuStyle.label("Your offers (%d of %d resources, %d of %d gear and gems)" % [mine.size() - items, most, items,
			int(Economy.market_item_rules().get("max_offers", 5))], 17, MenuStyle.GOLD))
	if mine.is_empty():
		_body.add_child(MenuStyle.label("You have no offers up.", 15, MenuStyle.MUTED))
	else:
		var grid := _grid(5)
		for text: String in ["Gives", "Wants", "You get", "Runs out in", ""]:
			grid.add_child(MenuStyle.label(text, 14, MenuStyle.MUTED))
		for o: Dictionary in mine:
			grid.add_child(_offer_goods(o))
			grid.add_child(_goods(String(o.want), int(o.want_amount)))
			grid.add_child(_goods(String(o.want), int(o.proceeds)))
			grid.add_child(MenuStyle.label(_hours(float(o.expires) - Economy.now()), 15, MenuStyle.TEXT))
			grid.add_child(_small("Take down", func() -> void:
				Economy.cancel_offer(int(o.id))
				_note.text = "Taking it down..."
				_note.add_theme_color_override("font_color", ME)))
		_body.add_child(grid)
	_body.add_child(HSeparator.new())
	_body.add_child(MenuStyle.label("Recently sold", 17, MenuStyle.GOLD))
	var sold: Array = Economy.market.get("sold", [])
	if sold.is_empty():
		_body.add_child(MenuStyle.label("Nothing sold yet.", 15, MenuStyle.MUTED))
	for o: Dictionary in sold:
		var line := MenuStyle.label("%s bought %s for %s; you got %s." % [String(o.get("buyer_name", "Someone")),
				Economy.market_good_name(String(o.give), int(o.give_amount), o.get("item")),
				Economy.market_good_name(String(o.want), int(o.want_amount)), Economy.market_good_name(String(o.want), int(o.proceeds))],
				15, GOOD)
		line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_body.add_child(line)


# --- The sell form ---------------------------------------------------------------------

func _build_sell_form() -> void:
	_sell = VBoxContainer.new()
	_sell.add_theme_constant_override("separation", 12)
	var modes := HBoxContainer.new()
	modes.add_theme_constant_override("separation", 8)
	_sell.add_child(modes)
	for mode: String in ["goods", "items"]:
		var b := _small("Resources" if mode == "goods" else "Gear and gems for Marks", func() -> void: _set_sell_mode(mode))
		b.toggle_mode = true
		b.button_pressed = mode == _sell_mode
		_mode_buttons[mode] = b
		modes.add_child(b)
	_goods_form = VBoxContainer.new()
	_goods_form.add_theme_constant_override("separation", 12)
	_sell.add_child(_goods_form)
	_build_items_form()
	_sell.add_child(_items_form)
	_set_sell_mode(_sell_mode)
	var sell := _goods_form
	var grid := _grid(3)
	_give = _goods_picker()
	_give_amount = _amount_spin()
	_want = _goods_picker()
	_want.select(1)
	_want_amount = _amount_spin()
	grid.add_child(MenuStyle.label("You give", 16, MenuStyle.TEXT))
	grid.add_child(_give)
	grid.add_child(_give_amount)
	grid.add_child(MenuStyle.label("You want", 16, MenuStyle.TEXT))
	grid.add_child(_want)
	grid.add_child(_want_amount)
	sell.add_child(grid)
	var quick := HBoxContainer.new()
	quick.add_theme_constant_override("separation", 8)
	_price_label = MenuStyle.label("", 15, MenuStyle.MUTED)
	quick.add_child(_price_label)
	for rate: float in [0.5, 0.75, 1.0, 1.25, 1.5, 2.0]:
		quick.add_child(_small(_num(rate), func() -> void:
			_want_amount.value = roundf(_give_amount.value * rate)))
	sell.add_child(quick)
	_summary = MenuStyle.label("", 16, MenuStyle.TEXT)
	_summary.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	sell.add_child(_summary)
	_post = GameTheme.primary(MenuStyle.button("Put up offer", _post_offer, 240.0))
	_post.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	sell.add_child(_post)
	_give.item_selected.connect(func(_i: int) -> void: _reset_sell_limits())
	_want.item_selected.connect(func(_i: int) -> void: _update_summary())
	_give_amount.value_changed.connect(func(_v: float) -> void: _update_summary())
	_want_amount.value_changed.connect(func(_v: float) -> void: _update_summary())


func _set_sell_mode(mode: String) -> void:
	_sell_mode = mode
	for m: String in _mode_buttons:
		_mode_buttons[m].button_pressed = m == mode
	_goods_form.visible = mode == "goods"
	_items_form.visible = mode == "items"
	if mode == "items":
		_fill_item_picker()


func _build_items_form() -> void:
	## Gear from your bag or gems from your pouch, for Marks.
	_items_form = VBoxContainer.new()
	_items_form.add_theme_constant_override("separation", 12)
	var grid := _grid(2)
	_item_pick = OptionButton.new()
	_item_pick.focus_mode = Control.FOCUS_NONE
	_item_pick.custom_minimum_size = Vector2(420, 0)
	_item_amount = _amount_spin()
	_item_amount.min_value = 1
	_item_price = _amount_spin()
	grid.add_child(MenuStyle.label("You sell", 16, MenuStyle.TEXT))
	grid.add_child(_item_pick)
	grid.add_child(MenuStyle.label("How many", 16, MenuStyle.TEXT))
	grid.add_child(_item_amount)
	grid.add_child(MenuStyle.label("Price in Marks", 16, MenuStyle.TEXT))
	grid.add_child(_item_price)
	_items_form.add_child(grid)
	_item_summary = MenuStyle.label("", 16, MenuStyle.TEXT)
	_item_summary.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_items_form.add_child(_item_summary)
	_item_post = GameTheme.primary(MenuStyle.button("Put up offer", _post_item_offer, 240.0))
	_item_post.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_items_form.add_child(_item_post)
	_item_pick.item_selected.connect(func(_i: int) -> void: _reset_item_limits())
	_item_amount.value_changed.connect(func(_v: float) -> void: _update_item_summary())
	_item_price.value_changed.connect(func(_v: float) -> void: _update_item_summary())


func _fill_item_picker() -> void:
	## Every piece of gear in your bag and every gem in your pouch; metadata
	## {"item": id} or {"gem": key}.
	if _item_pick == null or Economy.player_castle == null or Economy.gear_rules == null:
		return
	var g := Economy.gear_rules
	var keep: Variant = _item_pick.get_item_metadata(_item_pick.selected) if _item_pick.selected >= 0 else null
	_item_pick.clear()
	for item: Dictionary in Economy.player_castle.armoury.bag:
		_item_pick.add_item("%s (%s %s %s)" % [item.name, String(g.rarities.get(item.rarity, {}).get("name", item.rarity)).to_lower(),
				item.side, String(g.slot_names.get(item.slot, item.slot)).to_lower()])
		_item_pick.set_item_metadata(_item_pick.item_count - 1, {"item": int(item.id)})
	for key: String in Economy.player_castle.armoury.gems:
		if g.gem_parts(key).is_empty():
			continue
		_item_pick.add_item("%s (%d in your pouch)" % [g.gem_name(key), GearRules.gem_count(Economy.player_castle, key)])
		_item_pick.set_item_metadata(_item_pick.item_count - 1, {"gem": key})
	for i in _item_pick.item_count:
		if _item_pick.get_item_metadata(i) == keep:
			_item_pick.select(i)
	_reset_item_limits()


func _item_choice() -> Dictionary:
	return _item_pick.get_item_metadata(_item_pick.selected) if _item_pick.selected >= 0 else {}


func _item_good() -> String:
	## "gear:rare" or a gem key for the picked item ("" if none).
	var pick := _item_choice()
	if pick.has("gem"):
		return String(pick.gem)
	for x: Dictionary in Economy.player_castle.armoury.bag:
		if int(x.id) == int(pick.get("item", -1)):
			return "gear:" + String(x.rarity)
	return ""


func _reset_item_limits() -> void:
	var pick := _item_choice()
	var gems := pick.has("gem")
	_item_amount.editable = gems
	_item_amount.max_value = mini(GearRules.gem_count(Economy.player_castle, String(pick.gem)),
			int(Economy.market_item_rules().get("gem_lot", 10))) if gems else 1
	_item_amount.value = 1
	var range_ := Economy.item_price_range(_item_good(), int(_item_amount.value))
	if not range_.is_empty():
		_item_price.value = clampi(int(_item_price.value), int(range_[0]), int(range_[1]))
	_update_item_summary()


func _update_item_summary() -> void:
	if _item_summary == null or _sell_mode != "items":
		return
	var pick := _item_choice()
	if pick.is_empty():
		_item_summary.text = "Your bag and gem pouch are empty. Beat robber barons for gear and gems."
		_item_post.disabled = true
		return
	var amount := int(_item_amount.value)
	var price := int(_item_price.value)
	var lines: PackedStringArray = []
	var good := _item_good()
	var range_ := Economy.item_price_range(good, amount)
	if not range_.is_empty():
		lines.append("Ask between %d and %d Marks. You get %d Marks when it sells." % [int(range_[0]), int(range_[1]),
				Economy.market_proceeds(price)])
	if pick.has("item"):
		for x: Dictionary in Economy.player_castle.armoury.bag:
			if int(x.id) == int(pick.item):
				lines.append("%s. Gems in it go with it." % Economy.gear_rules.item_text(x) if not x.get("gems", []).is_empty()
						else Economy.gear_rules.item_text(x))
	var going: Variant = Economy.market.get("rates", {}).get("%s>marks" % good)
	if going != null:
		lines.append("Recent sales went for %s Marks each." % _num(float(going)))
	lines.append("You have %d Marks." % int(Economy.player_castle.armoury.get("marks", 0)))
	var why := Economy.check_item_offer(int(pick.get("item", 0)), String(pick.get("gem", "")), amount, price)
	if why != "":
		lines.append(why)
	_item_summary.text = "\n".join(lines)
	_item_post.disabled = why != ""


func _post_item_offer() -> void:
	var pick := _item_choice()
	var why := Economy.post_item_offer(int(pick.get("item", 0)), String(pick.get("gem", "")), int(_item_amount.value),
			int(_item_price.value))
	_note.text = why if why != "" else "Putting your offer up..."
	_note.add_theme_color_override("font_color", BAD if why != "" else ME)
	if why == "":
		_show("mine")


func _goods_picker() -> OptionButton:
	var pick := OptionButton.new()
	pick.focus_mode = Control.FOCUS_NONE
	pick.custom_minimum_size = Vector2(160, 0)
	for good: String in Economy.market_rules.get("goods", ["wood", "stone", "food"]):
		pick.add_icon_item(Icons.get_icon(good, 20), good.capitalize())
		pick.set_item_metadata(pick.item_count - 1, good)
	return pick


func _amount_spin() -> SpinBox:
	var spin := SpinBox.new()
	spin.min_value = 0
	spin.max_value = 1000000
	spin.step = 1
	spin.custom_minimum_size = Vector2(140, 0)
	return spin


func _picked(pick: OptionButton) -> String:
	return String(pick.get_item_metadata(pick.selected)) if pick.selected >= 0 else ""


func _reset_sell_limits() -> void:
	## The most you can give: what you have, up to one offer's limit.
	var give := _picked(_give)
	var most := mini(floori(float(Economy.player_castle.resources.get(give, 0.0))), Economy.market_lot_limit())
	_give_amount.max_value = maxi(most, 0)
	_want_amount.max_value = ceili(Economy.market_lot_limit() * float(Economy.market_rules.get("max_rate", 2.0)))
	_update_summary()


func _update_summary() -> void:
	var give := _picked(_give)
	var want := _picked(_want)
	var ga := int(_give_amount.value)
	var wa := int(_want_amount.value)
	var lines: PackedStringArray = []
	_price_label.text = "%s per %s:" % [want.capitalize(), give]
	if ga > 0 and wa > 0 and give != want:
		lines.append("Price: %s %s for each %s. You get %d %s when it sells." % [_num(float(wa) / ga), want, give,
				Economy.market_proceeds(wa), want])
		var going: Variant = Economy.market.get("rates", {}).get("%s>%s" % [give, want])
		if going != null:
			lines.append("Recent trades went for %s %s per %s." % [_num(float(going)), want, give])
	lines.append("You have %d %s; one offer gives at most %d." % [floori(float(Economy.player_castle.resources.get(give, 0.0))),
			give, Economy.market_lot_limit()])
	var why := Economy.check_offer(give, ga, want, wa)
	if why != "" and (ga > 0 or wa > 0):
		lines.append(why)
	_summary.text = "\n".join(lines)
	_post.disabled = why != ""


func _post_offer() -> void:
	var why := Economy.post_offer(_picked(_give), int(_give_amount.value), _picked(_want), int(_want_amount.value))
	_note.text = why if why != "" else "Putting your offer up..."
	_note.add_theme_color_override("font_color", BAD if why != "" else ME)
	if why == "":
		_give_amount.value = 0
		_want_amount.value = 0
		_show("mine")


# --- Helpers ---------------------------------------------------------------------------

func _rates_text() -> String:
	## The going rates from recent sales, as one line.
	var rates: Dictionary = Economy.market.get("rates", {})
	if rates.is_empty():
		return ""
	var parts: PackedStringArray = []
	for key: String in rates:
		var pair := key.split(">")
		if pair[1] == "marks":
			parts.append("%s = %s Marks" % [_good_label(pair[0]), _num(float(rates[key]))])
		else:
			parts.append("1 %s = %s %s" % [pair[0], _num(float(rates[key])), pair[1]])
	return "Recent trades: " + ",  ".join(parts)


func _good_label(good: String) -> String:
	## "1 Flawed Ruby", "rare gear".
	if good.begins_with("gear:"):
		return "%s gear" % good.substr(5)
	return Economy.market_good_name(good, 1)


func _price_text(o: Dictionary) -> String:
	if String(o.want) == "marks":
		if String(o.give).begins_with("gear:"):
			return "%s gear" % String(o.give).substr(5)
		return "%s Marks each" % _num(_price(o))
	return "%s %s per %s" % [_num(_price(o)), o.want, o.give]


func _offer_goods(o: Dictionary) -> Control:
	## What an offer gives: resources with their icon, gems by name, or the gear (its stats as a tooltip).
	var good := String(o.give)
	var item: Variant = o.get("item")
	var g := Economy.gear_rules
	if item is Dictionary and not item.is_empty() and g != null:
		var label := MenuStyle.label(String(item.get("name", "")), 15, g.rarity_color(String(item.get("rarity", ""))))
		label.tooltip_text = "%s %s %s: %s" % [String(g.rarities.get(item.get("rarity", ""), {}).get("name", "")), item.get("side", ""),
				String(g.slot_names.get(item.get("slot", ""), "")).to_lower(), g.item_text(GearRules._read_item(item))]
		if not item.get("gems", []).is_empty():
			label.tooltip_text += "\nGems: " + ", ".join(Array(item.gems).map(func(k: Variant) -> String: return g.gem_name(String(k))))
		label.mouse_filter = Control.MOUSE_FILTER_STOP
		return label
	if g != null and not g.gem_parts(good).is_empty():
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 4)
		row.add_child(Icons.rect("gem", 20))
		var label := MenuStyle.label(Economy.market_good_name(good, int(o.give_amount)), 15, g.gem_color(good))
		label.tooltip_text = g.gem_text(good) + " each"
		label.mouse_filter = Control.MOUSE_FILTER_STOP
		row.add_child(label)
		return row
	return _goods(good, int(o.give_amount))


static func _price(o: Dictionary) -> float:
	return float(o.want_amount) / maxf(1.0, float(o.give_amount))


func _goods(good: String, amount: int) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 4)
	row.add_child(Icons.rect(good, 20))
	row.add_child(MenuStyle.label(str(amount), 16, MenuStyle.TEXT))
	return row


func _grid(columns: int) -> GridContainer:
	var grid := GridContainer.new()
	grid.columns = columns
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_theme_constant_override("h_separation", 22)
	grid.add_theme_constant_override("v_separation", 6)
	return grid


func _small(text: String, action: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(80, 32)
	b.add_theme_font_size_override("font_size", 15)
	b.pressed.connect(action)
	return b


static func _num(x: float) -> String:
	return str(snappedf(x, 0.01))


static func _hours(seconds: float) -> String:
	var m := maxi(0, ceili(seconds / 60.0))
	return "%dh %02dm" % [m / 60, m % 60]
