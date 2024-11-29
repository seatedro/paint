package paint

import rl "vendor:raylib"


update :: proc() {
	state.window_size = {f32(rl.GetScreenWidth()), f32(rl.GetScreenHeight())}

	update_canvas(&state.canvas)

	mouse_pos := rl.GetMousePosition()
	canvas_pos := window_to_canvas_coords(&state.canvas, mouse_pos)

	update_drawing(state, canvas_pos, state.primary_color)
}


draw :: proc() {
	rl.BeginDrawing()
	rl.ClearBackground(rl.DARKGRAY)

	draw_canvas(&state.canvas)

	// Draw toolbar on left
	rl.DrawRectangle(
		0,
		MENUBAR_HEIGHT,
		TOOLBAR_WIDTH,
		i32(state.window_size.y - MENUBAR_HEIGHT),
		rl.GRAY,
	)

	// Draw status bar at bottom
	rl.DrawRectangle(
		0,
		i32(state.window_size.y) - STATUSBAR_HEIGHT,
		i32(state.window_size.x),
		STATUSBAR_HEIGHT,
		rl.LIGHTGRAY,
	)


	draw_menu_bar()


	rl.EndDrawing()
}

@(export)
paint_update :: proc() -> bool {
	if rl.IsFileDropped() {
		rl.UnloadFont(ui_font) // Clean up old font before loading new one
	}
	update()
	draw()
	return !rl.WindowShouldClose()
}

@(export)
paint_init_window :: proc() {
	rl.SetConfigFlags(
		{.WINDOW_RESIZABLE, .VSYNC_HINT, .WINDOW_TOPMOST, .MSAA_4X_HINT, .WINDOW_HIGHDPI},
	)
	rl.InitWindow(1280, 720, "paint 2.0")
	rl.SetWindowPosition(200, 200)
	rl.SetTargetFPS(60)

	ui_font = rl.LoadFontEx(cstring("assets/microsoftsansserif.ttf"), FONT_SIZE, nil, 0)
}

@(export)
paint_init :: proc() {
	state = new(State)

	state^ = State {
		active_tab      = .Home,
		selected_tool   = .Pencil,
		primary_color   = rl.BLACK,
		secondary_color = rl.WHITE,
		brush_size      = 5,
		show_grid       = true,
		zoom_level      = 1.0,
		window_size     = {1280, 720},
		canvas          = create_canvas(1920, 1080),
		draw_state      = create_draw_state(),
	}

	paint_hot_reloaded(state)
	init_menu_style()

}

@(export)
paint_shutdown :: proc() {
	destroy_draw_state(&state.draw_state)
	destroy_canvas(&state.canvas)
	free(state)
	rl.UnloadFont(ui_font)
}

@(export)
paint_shutdown_window :: proc() {
	rl.CloseWindow()
}

@(export)
paint_memory :: proc() -> rawptr {
	return state
}

@(export)
paint_memory_size :: proc() -> int {
	return size_of(State)
}

@(export)
paint_hot_reloaded :: proc(mem: rawptr) {
	state = (^State)(mem)
	ui_font = rl.LoadFontEx(cstring("assets/microsoftsansserif.ttf"), FONT_SIZE, nil, 0)
}

@(export)
paint_force_reload :: proc() -> bool {
	return rl.IsKeyPressed(.PERIOD)
}

@(export)
paint_force_restart :: proc() -> bool {
	return rl.IsKeyPressed(.COMMA)
}
