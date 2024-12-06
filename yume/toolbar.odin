package yume

import rl "vendor:raylib"

ToolButton :: struct {
	tool:        Tool,
	rect:        rl.Rectangle,
	tooltip:     string,
	source_rect: rl.Rectangle,
}

ToolbarState :: struct {
	active_tool: Tool,
	hover_tool:  Maybe(Tool),
}

TOOL_BUTTON_SIZE :: 24
TOOL_PADDING :: 4
TOOLS_PER_ROW :: 2

toolbar_buttons := []ToolButton {
	{tool = .Pencil, tooltip = "Pencil tool (P)", source_rect = {get_tool_pos(6), 0, 16, 16}},
	{tool = .Brush, tooltip = "Brush tool (B)", source_rect = {get_tool_pos(7), 0, 16, 16}},
	{tool = .Eraser, tooltip = "Eraser tool (E)", source_rect = {get_tool_pos(2), 0, 16, 16}},
	{tool = .Fill, tooltip = "Fill with Color (F)", source_rect = {get_tool_pos(3), 0, 16, 16}},
	{tool = .ColorPicker, tooltip = "Pick Color (I)", source_rect = {get_tool_pos(4), 0, 16, 16}},
	{tool = .Text, tooltip = "Text (T)", source_rect = {get_tool_pos(9), 0, 16, 16}},
	{tool = .Rectangle, tooltip = "Rectangle (R)", source_rect = {get_tool_pos(12), 0, 16, 16}},
	{tool = .Sniper, tooltip = "Snipe (S)", source_rect = {get_tool_pos(16), 0, 16, 16}},
}
toolbar_state: ToolbarState
toolbar_texture: rl.Texture2D

init_toolbar :: proc() {
	toolbar_texture = rl.LoadTexture("assets/tools.png")
	toolbar_state.active_tool = .Pencil

	for &button, idx in &toolbar_buttons {
		button.rect = get_button_rect(idx)
	}
}

destroy_toolbar :: proc() {
	rl.UnloadTexture(toolbar_texture)
}

get_tool_pos :: proc(index: int) -> f32 {
	return f32(16 * index)
}

get_button_rect :: proc(index: int) -> rl.Rectangle {
	row := index / TOOLS_PER_ROW
	col := index % TOOLS_PER_ROW

	x := TOOL_PADDING + f32(col) * (TOOL_BUTTON_SIZE + TOOL_PADDING)
	y := MENUBAR_HEIGHT + TOOL_PADDING + f32(row) * (TOOL_BUTTON_SIZE + TOOL_PADDING)

	return {x, y, TOOL_BUTTON_SIZE, TOOL_BUTTON_SIZE}
}

draw_tool_button :: proc(button: ToolButton, is_active: bool, is_hover: bool = false) {
	bg_color := (is_active || is_hover) ? rl.WHITE : rl.LIGHTGRAY
	rl.DrawTexturePro(toolbar_texture, button.source_rect, button.rect, {0, 0}, 0, bg_color)
	if is_active || is_hover {
		rl.DrawRectangleLinesEx(button.rect, 1, rl.BLACK)
	}
}

draw_tooltip :: proc(button: ToolButton) {
	mouse_pos := rl.GetMousePosition()
	tooltip_size := rl.MeasureTextEx(ui_font, cstring(raw_data(button.tooltip)), FONT_SIZE, 1)

	tooltip_x := mouse_pos.x + 10
	tooltip_y := mouse_pos.y + 10

	rl.DrawRectangle(
		i32(tooltip_x - 4),
		i32(tooltip_y - 4),
		i32(tooltip_size.x + 8),
		i32(tooltip_size.y + 8),
		rl.WHITE,
	)
	rl.DrawRectangleLines(
		i32(tooltip_x - 4),
		i32(tooltip_y - 4),
		i32(tooltip_size.x + 8),
		i32(tooltip_size.y + 8),
		rl.BLACK,
	)
	rl.DrawTextEx(
		ui_font,
		cstring(raw_data(button.tooltip)),
		{tooltip_x, tooltip_y},
		FONT_SIZE,
		1,
		rl.BLACK,
	)
}

update_toolbar :: proc() {
	mouse_pos := rl.GetMousePosition()
	toolbar_state.hover_tool = nil
	for button in toolbar_buttons {
		if rl.CheckCollisionPointRec(mouse_pos, button.rect) {
			toolbar_state.hover_tool = button.tool

			if rl.IsMouseButtonPressed(.LEFT) {
				toolbar_state.active_tool = button.tool
				state.selected_tool = button.tool
			}
			break
		}
	}

	if !rl.IsKeyDown(.LEFT_CONTROL) && !rl.IsKeyDown(.LEFT_ALT) {
		#partial switch rl.GetKeyPressed() {
		case .P:
			toolbar_state.active_tool = .Pencil
			state.selected_tool = .Pencil
		case .B:
			toolbar_state.active_tool = .Brush
			state.selected_tool = .Brush
		case .E:
			toolbar_state.active_tool = .Eraser
			state.selected_tool = .Eraser
		case .F:
			toolbar_state.active_tool = .Fill
			state.selected_tool = .Fill
		case .I:
			toolbar_state.active_tool = .ColorPicker
			state.selected_tool = .ColorPicker
		case .T:
			toolbar_state.active_tool = .Text
			state.selected_tool = .Text
		case .R:
			toolbar_state.active_tool = .Rectangle
			state.selected_tool = .Rectangle
		case .S:
			toolbar_state.active_tool = .Sniper
			state.selected_tool = .Sniper
		}
	}
}

draw_toolbar :: proc() {
	rl.DrawRectangle(
		0,
		MENUBAR_HEIGHT,
		TOOLBAR_WIDTH,
		i32(state.window_size.y - MENUBAR_HEIGHT),
		rl.GRAY,
	)

	rl.DrawLine(TOOLBAR_WIDTH, MENUBAR_HEIGHT, TOOLBAR_WIDTH, i32(state.window_size.y), rl.BLACK)

	for button in toolbar_buttons {
		is_active := button.tool == toolbar_state.active_tool
		draw_tool_button(button, is_active, false)
	}

	if toolbar_state.hover_tool != nil {
		for button in toolbar_buttons {
			if button.tool == toolbar_state.hover_tool {
				draw_tool_button(button, false, true)
				draw_tooltip(button)
				break
			}
		}
	}
}
