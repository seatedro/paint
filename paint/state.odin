package paint

import rl "vendor:raylib"

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
	active_tab:           Tab,
	selected_tool:        Tool,
	primary_color:        rl.Color,
	secondary_color:      rl.Color,
	brush_size:           int,
	show_grid:            bool,
	zoom_level:           f32,
	window_size:          rl.Vector2,
	menu_hover:           MenuItem,
	menu_state:           MenuState,
	canvas:               Canvas,
	last_point:           rl.Vector2,
	draw_state:           DrawState,
	is_undo_combo_active: bool,
	is_redo_combo_active: bool,
}

/// Globals
state: ^State
ui_font: rl.Font
