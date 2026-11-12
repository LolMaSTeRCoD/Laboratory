extends RefCounted
## Original stone-and-forged-iron interface. Textures are generated once from
## vector artwork, so the exported game has no external texture dependency.

static var _textures: Dictionary = {}

static func frame_style() -> StyleBoxTexture:
	return _style("frame",16.0,12.0)

static func inset_style() -> StyleBoxTexture:
	return _style("inset",10.0,8.0)

static func heading_style() -> StyleBoxTexture:
	return _style("heading",9.0,5.0)

static func button_style(state: String = "normal") -> StyleBoxTexture:
	return _style(state,10.0,4.0)

static func _style(kind: String, horizontal_margin: float, vertical_margin: float) -> StyleBoxTexture:
	if not _textures.has(kind):
		var image := Image.new()
		var result := image.load_svg_from_string(_artwork(kind))
		assert(result == OK,"Unable to generate the original frost interface artwork")
		_textures[kind] = ImageTexture.create_from_image(image)
	var style := StyleBoxTexture.new()
	style.texture = _textures[kind]
	var border := 22.0 if kind == "frame" else 8.0
	for side in [SIDE_LEFT,SIDE_TOP,SIDE_RIGHT,SIDE_BOTTOM]:
		style.set_texture_margin(side,border)
	style.axis_stretch_horizontal = StyleBoxTexture.AXIS_STRETCH_MODE_TILE
	style.axis_stretch_vertical = StyleBoxTexture.AXIS_STRETCH_MODE_TILE
	style.content_margin_left = horizontal_margin
	style.content_margin_right = horizontal_margin
	style.content_margin_top = vertical_margin
	style.content_margin_bottom = vertical_margin
	return style

static func _artwork(kind: String) -> String:
	var frame := kind == "frame"
	var base := "#11191e"
	var upper := "#4e6069"
	var lower := "#1a262d"
	var accent := "#89b8c9"
	match kind:
		"hover":
			base = "#20323a"
			upper = "#92bbc8"
			lower = "#365365"
			accent = "#b8e5ed"
		"pressed":
			base = "#132b35"
			upper = "#c3b479"
			lower = "#526b74"
			accent = "#c7f1f5"
		"disabled":
			base = "#10171c"
			upper = "#2e3d43"
			lower = "#182229"
			accent = "#3e5660"
		"heading":
			base = "#1e303a"
			upper = "#708a93"
			lower = "#344b56"
		"inset":
			base = "#0d151a"
			upper = "#354954"
			lower = "#18272f"
		"frame":
			base = "#20272a"
			upper = "#7d8d92"
			lower = "#273943"
	var inset := 10 if frame else 4
	var svg := '<svg xmlns="http://www.w3.org/2000/svg" width="192" height="192" viewBox="0 0 192 192"><defs><linearGradient id="iron" x2="0" y2="1"><stop stop-color="%s"/><stop offset="0.45" stop-color="%s"/><stop offset="1" stop-color="#10191f"/></linearGradient><linearGradient id="stone" x2="1" y2="1"><stop stop-color="%s"/><stop offset="1" stop-color="#0e161b"/></linearGradient></defs><rect width="192" height="192" rx="3" fill="#080e12"/><rect x="1" y="1" width="190" height="190" rx="3" fill="url(#iron)"/><rect x="%d" y="%d" width="%d" height="%d" rx="2" fill="url(#stone)"/>' % [upper,lower,base,inset,inset,192-inset*2,192-inset*2]
	if frame:
		svg += '<rect x="4" y="4" width="184" height="184" rx="2" fill="none" stroke="#0b1319" stroke-width="3"/><rect x="8" y="8" width="176" height="176" fill="none" stroke="#8da5ac" stroke-opacity="0.45"/><path d="M13 12h72l-13 36-59 9zM180 17v64l-44-11-17-52zM16 103l57 13 7 60H16zM93 91l44-13 41 27v66l-51 5-30-36z" fill="#7e9695" opacity="0.035"/>'
	# Uneven mineral flecks and short hairline fractures, rather than a flat fill.
	var random := RandomNumberGenerator.new()
	random.seed = 291704
	for index in range(150):
		var x := random.randi_range(9,181)
		var y := random.randi_range(9,181)
		var width := random.randi_range(1,5)
		var opacity := random.randf_range(0.025,0.095)
		svg += '<path d="M%d %dl%d -1" stroke="#b6c4c8" stroke-width="0.7" opacity="%.3f"/>' % [x,y,width,opacity]
	for crack in ['M24 41l12 4 3 9 11 5','M116 30l-4 13 7 9-2 12','M39 137l9-7 12 4 5-6','M146 112l-12 7 4 11-8 7']:
		svg += '<path d="%s" fill="none" stroke="#02090d" stroke-width="1" opacity="0.32"/>' % crack
	if not frame:
		svg += '<rect x="5.5" y="5.5" width="181" height="181" rx="1" fill="none" stroke="%s" stroke-opacity="0.32"/>' % accent
	# Hammered corner plates, rivets and an original angular frost motif.
	for transform in ['','translate(192 0) scale(-1 1)','translate(0 192) scale(1 -1)','translate(192 192) scale(-1 -1)']:
		svg += '<g transform="%s">' % transform
		if frame:
			svg += '<path d="M2 2h30L20 8H8v12L2 32z" fill="url(#iron)" stroke="#91a2a4" stroke-width="0.7"/><path d="M7 28V12l5-5h16M11 22V13l2-2h9" fill="none" stroke="%s" stroke-width="0.9" opacity="0.8"/><path d="M7 7l4-3 3 3-3 4z" fill="#b7dce2"/><circle cx="4" cy="19" r="1.3" fill="#10181d"/><circle cx="19" cy="4" r="1.3" fill="#10181d"/>' % accent
		else:
			svg += '<path d="M2 9V2h7L6 4H4v2z" fill="%s" opacity="0.75"/>' % accent
		svg += '</g>'
	return svg+'</svg>'

static func section(parent: Control, text: String) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_theme_stylebox_override("panel",heading_style())
	var label := Label.new()
	label.text = "✦  "+text+"  ✦"
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size",12)
	label.add_theme_color_override("font_color",Color(0.85,0.89,0.79))
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(label)
	parent.add_child(panel)
	return panel
