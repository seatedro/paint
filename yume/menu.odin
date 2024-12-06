package yume

import rl "vendor:raylib"

MenuItem :: struct {
	label:    string,
	shortcut: string, // For things like "Ctrl+S"
	enabled:  bool,
}

Menu :: struct {
	label: string,
	items: []MenuItem,
}

MenuState :: struct {
	active_menu: int, // Currently active top-level menu
	active_item: int, // Currently active menu item
	menu_open:   bool, // Whether any menu is currently open
	hot_item:    MenuItem, // Item under mouse cursor
	last_click:  f64, // Time of last click for double-click detection
}


menus := []Menu {
	{
		label = "File",
		items = []MenuItem {
			{label = "New", shortcut = "Ctrl+N", enabled = true},
			{label = "Open...", shortcut = "Ctrl+O", enabled = true},
			{label = "Save", shortcut = "Ctrl+S", enabled = true},
			{label = "Save As...", enabled = true},
		},
	},
	{
		label = "Edit",
		items = []MenuItem {
			{label = "Undo", shortcut = "Ctrl+Z", enabled = true},
			{label = "Repeat", shortcut = "F4", enabled = false},
			{label = "Cut", shortcut = "Ctrl+X", enabled = false},
			{label = "Copy", shortcut = "Ctrl+C", enabled = false},
			{label = "Paste", shortcut = "Ctrl+V", enabled = false},
		},
	},
	{
		label = "View",
		items = []MenuItem {
			{label = "Zoom In", shortcut = "Ctrl++", enabled = true},
			{label = "Zoom Out", shortcut = "Ctrl+-", enabled = true},
			{label = "Show Grid", shortcut = "Ctrl+G", enabled = true},
			{label = "Actual Size", shortcut = "Ctrl+0", enabled = true},
			{label = "Infinite Canvas", shortcut = "Ctrl+Alt+I", enabled = true},
		},
	},
	{
		label = "Image",
		items = []MenuItem {
			{label = "Flip/Rotate", shortcut = "Ctrl+R", enabled = true},
			{label = "Stretch/Skew", enabled = true},
			{label = "Invert Colors", enabled = true},
			{label = "Clear Image", shortcut = "Ctrl+Shift+N", enabled = true},
		},
	},
	{
		label = "Options",
		items = []MenuItem {
			{label = "Color Box", enabled = true},
			{label = "Tool Box", enabled = true},
			{label = "Status Bar", enabled = true},
			{label = "Draw Opaque", enabled = true},
		},
	},
	{
		label = "Help",
		items = []MenuItem {
			{label = "Help Topics", shortcut = "F1", enabled = true},
			{label = "About yume", enabled = true},
		},
	},
}
menu_state: MenuState


init_menu_style :: proc() {
	// Set up the default style
	rl.GuiLoadStyleDefault()

	// Configure colors to match yume
	rl.GuiSetStyle(
		.DEFAULT,
		i32(rl.GuiControlProperty.BASE_COLOR_NORMAL),
		get_color(240, 240, 240, 255),
	)
	rl.GuiSetStyle(
		.DEFAULT,
		i32(rl.GuiControlProperty.BASE_COLOR_FOCUSED),
		get_color(230, 230, 230, 255),
	)
	rl.GuiSetStyle(
		.DEFAULT,
		i32(rl.GuiControlProperty.BASE_COLOR_PRESSED),
		get_color(200, 200, 200, 255),
	)

	// Text colors
	rl.GuiSetStyle(.DEFAULT, i32(rl.GuiControlProperty.TEXT_COLOR_NORMAL), get_color(0, 0, 0, 255))
	rl.GuiSetStyle(
		.DEFAULT,
		i32(rl.GuiControlProperty.TEXT_COLOR_FOCUSED),
		get_color(0, 0, 0, 255),
	)
	rl.GuiSetStyle(
		.DEFAULT,
		i32(rl.GuiControlProperty.TEXT_COLOR_PRESSED),
		get_color(0, 0, 0, 255),
	)

	// Border styling
	rl.GuiSetStyle(
		.DEFAULT,
		i32(rl.GuiControlProperty.BORDER_COLOR_NORMAL),
		get_color(200, 200, 200, 255),
	)
	rl.GuiSetStyle(.DEFAULT, i32(rl.GuiControlProperty.BORDER_WIDTH), 1)

	// Text properties
	rl.GuiSetStyle(.DEFAULT, i32(rl.GuiControlProperty.TEXT_PADDING), 4)
	rl.GuiSetStyle(
		.DEFAULT,
		i32(rl.GuiControlProperty.TEXT_ALIGNMENT),
		i32(rl.GuiTextAlignment.TEXT_ALIGN_LEFT),
	)
}

draw_menu_item :: proc(bounds: rl.Rectangle, item: MenuItem, is_active: bool) -> bool {
	// Draw background
	bg_color := is_active ? rl.LIGHTGRAY : rl.WHITE
	rl.DrawRectangleRec(bounds, bg_color)

	// Draw text
	text_pos := rl.Vector2{bounds.x + 8, bounds.y + (bounds.height - FONT_SIZE) / 2}
	rl.DrawTextEx(ui_font, cstring(raw_data(item.label)), text_pos, FONT_SIZE, 1, rl.BLACK)

	// Draw shortcut if present
	if len(item.shortcut) > 0 {
		shortcut_width :=
			rl.MeasureTextEx(ui_font, cstring(raw_data(item.shortcut)), FONT_SIZE, 1).x
		shortcut_pos := rl.Vector2 {
			bounds.x + bounds.width - shortcut_width - 8,
			bounds.y + (bounds.height - FONT_SIZE) / 2,
		}
		rl.DrawTextEx(
			ui_font,
			cstring(raw_data(item.shortcut)),
			shortcut_pos,
			FONT_SIZE,
			1,
			rl.DARKGRAY,
		)
	}

	// Check mouse interaction
	mouse_pos := rl.GetMousePosition()
	is_hovered := rl.CheckCollisionPointRec(mouse_pos, bounds)
	was_clicked := is_hovered && rl.IsMouseButtonPressed(.LEFT)

	//TODO: Make this a part of the struct MenuItem somehow
	if item.label == "Infinite Canvas" && state.canvas.mode == .Infinite {
		check_x := bounds.x + bounds.width - 24
		check_y := bounds.y + (bounds.width - FONT_SIZE) / 2
		rl.DrawTextEx(ui_font, "✓", {check_x, check_y}, FONT_SIZE, 1, rl.BLACK)
	}

	return was_clicked && item.enabled
}

draw_menu_dropdown :: proc(menu: Menu, pos: rl.Vector2) {
	if len(menu.items) == 0 do return

	// Calculate menu dimensions
	max_width := f32(200) // Set minimum width
	for item in menu.items {
		text_width := rl.MeasureTextEx(ui_font, cstring(raw_data(item.label)), FONT_SIZE, 1).x
		if len(item.shortcut) > 0 {
			text_width +=
				40 + rl.MeasureTextEx(ui_font, cstring(raw_data(item.shortcut)), FONT_SIZE, 1).x
		}
		max_width = max(max_width, text_width)
	}

	// Draw menu background with white backdrop and border
	menu_bounds := rl.Rectangle {
		pos.x,
		pos.y,
		max_width + 32, // Increased padding
		f32(len(menu.items)) * MENU_ITEM_HEIGHT + 4, // Added slight padding
	}

	// Draw drop shadow
	shadow_bounds := menu_bounds
	shadow_bounds.x += 2
	shadow_bounds.y += 2
	rl.DrawRectangleRec(shadow_bounds, {0, 0, 0, 15})

	// Draw main background
	rl.DrawRectangleRec(menu_bounds, rl.WHITE)
	rl.DrawRectangleLinesEx(menu_bounds, 1, {180, 180, 180, 255})

	// Track mouse position for hover effects
	mouse_pos := rl.GetMousePosition()

	// Draw each menu item
	for item, idx in menu.items {
		item_bounds := rl.Rectangle {
			menu_bounds.x + 2, // Slight inset
			menu_bounds.y + 2 + f32(idx) * MENU_ITEM_HEIGHT,
			menu_bounds.width - 4,
			MENU_ITEM_HEIGHT,
		}

		// Check hover state
		is_hovered := rl.CheckCollisionPointRec(mouse_pos, item_bounds)
		if is_hovered {
			menu_state.hot_item = item
		}

		// Draw the menu item
		if is_hovered {
			rl.DrawRectangleRec(item_bounds, {230, 230, 230, 255})
		}

		// Draw text
		text_pos := rl.Vector2 {
			item_bounds.x + 8,
			item_bounds.y + (item_bounds.height - f32(FONT_SIZE)) / 2,
		}
		text_color := item.enabled ? rl.BLACK : rl.GRAY
		rl.DrawTextEx(ui_font, cstring(raw_data(item.label)), text_pos, FONT_SIZE, 1, text_color)

		// Draw shortcut if present
		if len(item.shortcut) > 0 {
			shortcut_width :=
				rl.MeasureTextEx(ui_font, cstring(raw_data(item.shortcut)), FONT_SIZE, 1).x
			shortcut_pos := rl.Vector2 {
				item_bounds.x + item_bounds.width - shortcut_width - 16,
				item_bounds.y + (item_bounds.height - f32(FONT_SIZE)) / 2,
			}
			rl.DrawTextEx(
				ui_font,
				cstring(raw_data(item.shortcut)),
				shortcut_pos,
				FONT_SIZE,
				1,
				rl.GRAY,
			)
		}

		// Handle click
		if is_hovered && rl.IsMouseButtonPressed(.LEFT) && item.enabled {
			handle_menu_action(menu.label, item)
			menu_state.menu_open = false
		}
	}
}

draw_menu_bar :: proc() {
	menu_bar_bounds := rl.Rectangle{0, 0, state.window_size.x, MENUBAR_HEIGHT}

	// Draw menu bar background
	rl.DrawRectangleRec(menu_bar_bounds, rl.LIGHTGRAY)
	rl.DrawLine(0, MENUBAR_HEIGHT, i32(state.window_size.x), MENUBAR_HEIGHT, rl.DARKGRAY)

	x_pos: f32 = 5
	mouse_pos := rl.GetMousePosition()

	// Draw each menu
	for menu, idx in menus {
		text_size := rl.MeasureTextEx(ui_font, cstring(raw_data(menu.label)), FONT_SIZE, 1)
		menu_bounds := rl.Rectangle{x_pos, 0, text_size.x + MENU_ITEM_PADDING * 2, MENUBAR_HEIGHT}

		is_hovered := rl.CheckCollisionPointRec(mouse_pos, menu_bounds)

		if is_hovered {
			rl.DrawRectangleRec(menu_bounds, rl.WHITE)
			if rl.IsMouseButtonPressed(.LEFT) {
				if menu_state.active_menu == idx {
					menu_state.menu_open = !menu_state.menu_open
				} else {
					menu_state.active_menu = idx
					menu_state.menu_open = true
				}
			}
		}

		text_pos := rl.Vector2 {
			menu_bounds.x + MENU_ITEM_PADDING,
			menu_bounds.y + (menu_bounds.height - text_size.y) / 2,
		}
		rl.DrawTextEx(ui_font, cstring(raw_data(menu.label)), text_pos, FONT_SIZE, 1, rl.BLACK)

		// Draw dropdown if this menu is active
		if menu_state.menu_open && menu_state.active_menu == idx {
			draw_menu_dropdown(menu, {menu_bounds.x, menu_bounds.y + menu_bounds.height})
		}

		x_pos += menu_bounds.width
	}

	// Close menu if clicked outside
	if menu_state.menu_open && rl.IsMouseButtonPressed(.LEFT) {
		mouse_y := mouse_pos.y
		if mouse_y > MENUBAR_HEIGHT {
			menu_state.menu_open = false
		}
	}
}


handle_menu_action :: proc(menu_label: string, item: MenuItem) {
	switch menu_label {
	case "File":
		switch item.label {
		case "New":
		// TODO: Implement new document
		case "Open...":
		// TODO: Implement open dialog
		case "Save":
		// TODO: Implement save
		case "Save As...":
		// TODO: Implement save as dialog
		}
	case "Edit":
		switch item.label {
		case "Undo":
		// TODO: Implement undo
		case "Redo":
		// TODO: Implement redo
		case "Cut":
		// TODO: Implement cut
		case "Copy":
		// TODO: Implement copy
		case "Paste":
		// TODO: Implement paste
		}
	case "View":
		switch item.label {
		case "Infinite Canvas":
			toggle_canvas_mode(&state.canvas)
		}
	// Add other menu categories
	}
}
