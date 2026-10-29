extends PanelContainer
## The market (T on the world map, online): trade wood, stone and food with
## other players. "Buy" lists everyone else's offers, "Sell" puts one of your
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


func _ready() -> void:
	add_theme_stylebox_override("panel", MenuStyle.panel(0.95))
	custom_minimum_size = Vector2(760, 0)
	visible = false
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	add_child(box)
	var head := HBoxContainer.new()
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
	buttons.add_child(MenuStyle.button("Close", close_panel, 180.0))
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
	_rule.text = "Trade wood, stone and food with other players. Your goods wait at the market until someone buys the whole offer; the buyer gets them at once and you get the price, less the market's %d%% cut. Offers run for %d hours, then come back to you. Opens at keep level %d." % [
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
		"mine":
			_fill_mine()


func _fill_buy() -> void:
	var filters := HBoxContainer.new()
	filters.add_theme_constant_override("separation", 8)
	filters.add_child(MenuStyle.label("Offers giving:", 15, MenuStyle.MUTED))
	for good: String in [""] + Array(Economy.market_rules.get("goods", [])):
		var b := _small("All" if good == "" else good.capitalize(), func() -> void:
			_filter = good
			_fill())
		b.toggle_mode = true
		b.button_pressed = _filter == good
		if good != "":
			b.icon = Icons.get_icon(good, 20)
		filters.add_child(b)
	_body.add_child(filters)
	var offers: Array = Economy.market.get("offers", []).filter(func(o: Dictionary) -> bool:
		return _filter == "" or String(o.give) == _filter)
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
		grid.add_child(_goods(String(o.give), int(o.give_amount)))
		grid.add_child(_goods(String(o.want), int(o.want_amount)))
		grid.add_child(MenuStyle.label("%s %s per %s" % [_num(_price(o)), o.want, o.give], 14, MenuStyle.MUTED))
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
	_body.add_child(MenuStyle.label("Your offers (%d of %d)" % [mine.size(), most], 17, MenuStyle.GOLD))
	if mine.is_empty():
		_body.add_child(MenuStyle.label("You have no offers up.", 15, MenuStyle.MUTED))
	else:
		var grid := _grid(5)
		for text: String in ["Gives", "Wants", "You get", "Runs out in", ""]:
			grid.add_child(MenuStyle.label(text, 14, MenuStyle.MUTED))
		for o: Dictionary in mine:
			grid.add_child(_goods(String(o.give), int(o.give_amount)))
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
		var line := MenuStyle.label("%s bought %d %s for %d %s; you got %d %s." % [String(o.get("buyer_name", "Someone")),
				int(o.give_amount), o.give, int(o.want_amount), o.want, int(o.proceeds), o.want], 15, GOOD)
		line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_body.add_child(line)


# --- The sell form ---------------------------------------------------------------------

func _build_sell_form() -> void:
	_sell = VBoxContainer.new()
	_sell.add_theme_constant_override("separation", 12)
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
	_sell.add_child(grid)
	var quick := HBoxContainer.new()
	quick.add_theme_constant_override("separation", 8)
	_price_label = MenuStyle.label("", 15, MenuStyle.MUTED)
	quick.add_child(_price_label)
	for rate: float in [0.5, 0.75, 1.0, 1.25, 1.5, 2.0]:
		quick.add_child(_small(_num(rate), func() -> void:
			_want_amount.value = roundf(_give_amount.value * rate)))
	_sell.add_child(quick)
	_summary = MenuStyle.label("", 16, MenuStyle.TEXT)
	_summary.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_sell.add_child(_summary)
	_post = GameTheme.primary(MenuStyle.button("Put up offer", _post_offer, 240.0))
	_post.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_sell.add_child(_post)
	_give.item_selected.connect(func(_i: int) -> void: _reset_sell_limits())
	_want.item_selected.connect(func(_i: int) -> void: _update_summary())
	_give_amount.value_changed.connect(func(_v: float) -> void: _update_summary())
	_want_amount.value_changed.connect(func(_v: float) -> void: _update_summary())


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
		parts.append("1 %s = %s %s" % [pair[0], _num(float(rates[key])), pair[1]])
	return "Recent trades: " + ",  ".join(parts)


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
