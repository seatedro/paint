package paint

import rl "vendor:raylib"

PIXEL_WINDOW_HEIGHT :: 180

Tab :: enum {
	Home,
	View,
}

Tool :: enum {
	Pencil,
	Brush,
	Eraser,
	Fill,
	ColorPicker,
	Text,
	Shape,
}

State :: struct {
	active_tab:      Tab,
	selected_tool:   Tool,
	primary_color:   rl.Color,
	secondary_color: rl.Color,
	brush_size:      int,
	show_grid:       bool,
	zoom_level:      f32,
	window_size:     rl.Vector2,
}
state: ^State


update :: proc() {
	// state.window_size = {f32(rl.GetScreenWidth()), f32(rl.GetScreenHeight())}
}

draw :: proc() {
	rl.BeginDrawing()
	rl.ClearBackground(rl.WHITE)

	// Draw ribbon area at top
	rl.DrawRectangle(0, 0, i32(state.window_size.x), 20, rl.LIGHTGRAY)

	// Draw toolbar on left
	rl.DrawRectangle(0, 20, 60, i32(state.window_size.y) - 80, rl.GRAY)

	// Draw status bar at bottom
	rl.DrawRectangle(0, i32(state.window_size.y) - 20, i32(state.window_size.x), 20, rl.DARKGRAY)

	// Draw canvas area (remaining space)
	rl.DrawRectangle(
		60,
		20,
		i32(state.window_size.x) - 60,
		i32(state.window_size.y) - 80,
		rl.WHITE,
	)

	rl.EndDrawing()
}

@(export)
paint_update :: proc() -> bool {
	update()
	draw()
	return !rl.WindowShouldClose()
}

@(export)
paint_init_window :: proc() {
	rl.SetConfigFlags({.WINDOW_RESIZABLE, .VSYNC_HINT, .WINDOW_TOPMOST})
	rl.InitWindow(1280, 720, "paint 2.0")
	rl.SetWindowPosition(200, 200)
	rl.SetTargetFPS(60)
}

@(export)
paint_init :: proc() {
	state = new(State)

	state^ = State {
		active_tab      = .Home,
		selected_tool   = .Pencil,
		primary_color   = rl.BLACK,
		secondary_color = rl.WHITE,
		brush_size      = 1,
		show_grid       = false,
		zoom_level      = 1.0,
		window_size     = {1280, 720},
	}

	paint_hot_reloaded(state)
}

@(export)
paint_shutdown :: proc() {
	free(state)
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
}

@(export)
paint_force_reload :: proc() -> bool {
	return rl.IsKeyPressed(.PERIOD)
}

@(export)
paint_force_restart :: proc() -> bool {
	return rl.IsKeyPressed(.COMMA)
}
