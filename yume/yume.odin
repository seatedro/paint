package yume

import "core:fmt"
import rl "vendor:raylib"


update :: proc() {
	state.window_size = {f32(rl.GetScreenWidth()), f32(rl.GetScreenHeight())}

	// Handle dropped files
	if (rl.IsFileDropped()) {
		handle_file_drop()
	}

	// Handle pasting images
	// handle_paste()

	ctrl_pressed := rl.IsKeyDown(.LEFT_CONTROL) || rl.IsKeyDown(.RIGHT_CONTROL)
	#partial switch ODIN_OS {
	case .Darwin:
		// On macOS, use Command instead of Control
		ctrl_pressed = rl.IsKeyDown(.LEFT_SUPER) || rl.IsKeyDown(.RIGHT_SUPER)
	}

	// Check for undo combo
	if ctrl_pressed && rl.IsKeyDown(.Z) && !rl.IsKeyDown(.LEFT_SHIFT) {
		if !state.is_undo_combo_active {
			undo(&state.canvas)
			state.is_undo_combo_active = true
		}
	} else {
		state.is_undo_combo_active = false
	}

	// Check for redo combo (Ctrl+Y or Ctrl+Shift+Z)
	redo_pressed :=
		ctrl_pressed && (rl.IsKeyDown(.Y) || (rl.IsKeyDown(.LEFT_SHIFT) && rl.IsKeyDown(.Z)))
	if redo_pressed {
		if !state.is_redo_combo_active {
			redo(&state.canvas)
			state.is_redo_combo_active = true
		}
	} else {
		state.is_redo_combo_active = false
	}


	update_canvas(&state.canvas)
	update_toolbar()

	update_drawing(state, state.primary_color)
}


draw :: proc() {
	rl.BeginDrawing()
	switch state.canvas.mode {
	case .Fixed:
		rl.ClearBackground(rl.DARKGRAY)
	case .Infinite:
		rl.ClearBackground(rl.WHITE)
	}

	draw_canvas(&state.canvas)

	// Draw toolbar on left
	// rl.DrawRectangle(
	// 	0,
	// 	MENUBAR_HEIGHT,
	// 	TOOLBAR_WIDTH,
	// 	i32(state.window_size.y - MENUBAR_HEIGHT),
	// 	rl.GRAY,
	// )

	// Draw status bar at bottom with FPS counter
	status_bar_y := i32(state.window_size.y) - STATUSBAR_HEIGHT
	rl.DrawRectangle(0, status_bar_y, i32(state.window_size.x), STATUSBAR_HEIGHT, rl.LIGHTGRAY)

	// Mode Indicator
	mode_text :=
		state.canvas.mode == .Infinite ? "Canvas: Infinite" : fmt.tprintf("Canvas: {}x{}", state.canvas.container.width, state.canvas.container.height)
	mode_text_pos := rl.Vector2{10, f32(status_bar_y) + f32(STATUSBAR_HEIGHT) / 2 - FONT_SIZE / 2}
	rl.DrawTextEx(ui_font, cstring(raw_data(mode_text)), mode_text_pos, FONT_SIZE, 1, rl.BLACK)

	fps_text := fmt.tprintf("FPS: %d", rl.GetFPS())
	fps_text_pos := rl.Vector2 {
		f32(
			state.window_size.x -
			rl.MeasureTextEx(ui_font, cstring(raw_data(fps_text)), FONT_SIZE, 1).x -
			10,
		),
		f32(status_bar_y) + f32(STATUSBAR_HEIGHT) / 2 - FONT_SIZE / 2,
	}
	rl.DrawTextEx(ui_font, cstring(raw_data(fps_text)), fps_text_pos, FONT_SIZE, 1, rl.BLACK)


	draw_menu_bar()
	draw_toolbar()
	rl.EndDrawing()
}

@(export)
yume_update :: proc() -> bool {
	update()
	draw()
	return !rl.WindowShouldClose()
}

@(export)
yume_init_window :: proc() {
	rl.SetConfigFlags({.WINDOW_RESIZABLE, .VSYNC_HINT, .WINDOW_TOPMOST, .MSAA_4X_HINT})
	rl.SetWindowMonitor(0)
	rl.InitWindow(1280, 720, "yume 2.0")
	rl.SetWindowPosition(0, 0)
	rl.SetTargetFPS(60)

	// ui_font = rl.LoadFontEx(cstring("assets/W95FA.otf"), FONT_SIZE, nil, 0)
}

@(export)
yume_init :: proc() {
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
		canvas          = create_canvas(800, 600),
		draw_state      = create_draw_state(),
	}

	yume_hot_reloaded(state)
	init_menu_style()
	init_toolbar()
}

@(export)
yume_shutdown :: proc() {
	destroy_draw_state(&state.draw_state)
	destroy_canvas(&state.canvas)
	destroy_toolbar()
	free(state)
	rl.UnloadFont(ui_font)
}

@(export)
yume_shutdown_window :: proc() {
	rl.CloseWindow()
}

@(export)
yume_memory :: proc() -> rawptr {
	return state
}

@(export)
yume_memory_size :: proc() -> int {
	return size_of(State)
}

@(export)
yume_hot_reloaded :: proc(mem: rawptr) {
	state = (^State)(mem)
	ui_font = rl.LoadFontEx(cstring("assets/W95FA.otf"), FONT_SIZE, nil, 0)
}

@(export)
yume_force_reload :: proc() -> bool {
	return rl.IsKeyPressed(.PERIOD)
}

@(export)
yume_force_restart :: proc() -> bool {
	return rl.IsKeyPressed(.COMMA)
}
