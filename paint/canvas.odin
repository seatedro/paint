package paint

import "core:fmt"
import rl "vendor:raylib"

POINT_DISTANCE_MIN :: 2.0 // Minimum distance between points
SPLINE_SEGMENTS :: 20 // Number of segments per spline curve
SMOOTH_FACTOR :: 0.25

DrawState :: struct {
	smooth_lines: bool,
	points:       [dynamic]rl.Vector2,
	is_drawing:   bool,
	last_point:   rl.Vector2,
}

Canvas :: struct {
	texture:     rl.RenderTexture2D, // Main Canvas
	width:       i32,
	height:      i32,
	position:    rl.Vector2, // Canvas Position in window
	scale:       f32, // zoom
	offset:      rl.Vector2, // pan
	is_dragging: bool,
	drag_start:  rl.Vector2,
	last_offset: rl.Vector2,
}

create_canvas :: proc(width, height: i32) -> Canvas {
	canvas := Canvas {
		texture     = rl.LoadRenderTexture(width, height),
		width       = width,
		height      = height,
		position    = {TOOLBAR_WIDTH, MENUBAR_HEIGHT},
		scale       = 1.0,
		offset      = {0.0, 0.0},
		is_dragging = false,
		drag_start  = {0.0, 0.0},
		last_offset = {0.0, 0.0},
	}

	rl.BeginTextureMode(canvas.texture)
	rl.ClearBackground(rl.WHITE)
	rl.EndTextureMode()

	return canvas
}

destroy_canvas :: proc(canvas: ^Canvas) {
	rl.UnloadRenderTexture(canvas.texture)
}

update_canvas :: proc(canvas: ^Canvas) {
	// Handle zooming
	wheel := rl.GetMouseWheelMove()
	if rl.IsKeyDown(.LEFT_CONTROL) && wheel != 0.0 {
		scale := canvas.scale
		if wheel >= 0.0 {
			scale *= 1.1
		} else {
			scale *= 0.9
		}

		fmt.println("scale :: %d", scale)

		old_scale := canvas.scale
		canvas.scale = clamp(scale, 0.1, 10.0)

		if old_scale != scale {
			mouse_pos := rl.GetMousePosition()
			zoom_center_x := (mouse_pos.x - canvas.position.x - canvas.offset.x) / old_scale
			zoom_center_y := (mouse_pos.y - canvas.position.y - canvas.offset.y) / old_scale

			canvas.offset.x = mouse_pos.x - canvas.position.x - (zoom_center_x * scale)
			canvas.offset.y = mouse_pos.y - canvas.position.y - (zoom_center_y * scale)
		}
	}

	// Handle Panning
	if rl.IsMouseButtonDown(.MIDDLE) || (rl.IsKeyDown(.SPACE) && rl.IsMouseButtonDown(.LEFT)) {
		if !canvas.is_dragging {
			canvas.is_dragging = true
			canvas.drag_start = rl.GetMousePosition()
			canvas.last_offset = canvas.offset
		}
		mouse_pos := rl.GetMousePosition()
		canvas.offset.x = canvas.last_offset.x + (mouse_pos.x - canvas.drag_start.x)
		canvas.offset.y = canvas.last_offset.y + (mouse_pos.y - canvas.drag_start.y)
	} else {
		canvas.is_dragging = false
	}
}

window_to_canvas_coords :: proc(canvas: ^Canvas, window_pos: rl.Vector2) -> rl.Vector2 {
	return {
		(window_pos.x - canvas.position.x - canvas.offset.x) / canvas.scale,
		(window_pos.y - canvas.position.y - canvas.offset.y) / canvas.scale,
	}
}

draw_canvas :: proc(canvas: ^Canvas) {
	source_rect := rl.Rectangle {
		0,
		0,
		f32(canvas.texture.texture.width),
		-f32(canvas.texture.texture.height), // Flips texture
	}
	dest_rect := rl.Rectangle {
		canvas.position.x + canvas.offset.x,
		canvas.position.y + canvas.offset.y,
		f32(canvas.width) * canvas.scale,
		f32(canvas.height) * canvas.scale,
	}

	if state.show_grid {
		grid_size := i32(10 * canvas.scale)
		start_x := i32(dest_rect.x)
		start_y := i32(dest_rect.y)
		end_x := start_x + i32(dest_rect.width)
		end_y := start_y + i32(dest_rect.height)

		for y := start_y; y < end_y; y += grid_size {
			for x := start_x; x < end_x; x += grid_size {
				color := (((x / grid_size + y / grid_size) % 2) == 0) ? rl.LIGHTGRAY : rl.WHITE
				rl.DrawRectangle(x, y, grid_size, grid_size, color)
			}
		}
	}

	rl.DrawTexturePro(canvas.texture.texture, source_rect, dest_rect, {0, 0}, 0.0, rl.WHITE)
	rl.DrawRectangleLinesEx(dest_rect, 1, rl.BLACK)
}

create_draw_state :: proc() -> DrawState {
	return DrawState{points = make([dynamic]rl.Vector2), is_drawing = false}
}

destroy_draw_state :: proc(state: ^DrawState) {
	delete(state.points)
}

reset_drawing :: proc(state: ^DrawState) {
	clear(&state.points)
	state.is_drawing = false
}

// Returns true if point was added
add_point :: proc(state: ^DrawState, point: rl.Vector2) {
	if len(state.points) == 0 {
		append(&state.points, point)
		state.last_point = point
		return
	}

	// Check distance from last point
	dist := rl.Vector2Distance(point, state.last_point)
	if dist < POINT_DISTANCE_MIN {
		return
	}

	// Add point with smoothing
	smoothed_point := rl.Vector2 {
		state.last_point.x + (point.x - state.last_point.x) * (1 - SMOOTH_FACTOR),
		state.last_point.y + (point.y - state.last_point.y) * (1 - SMOOTH_FACTOR),
	}

	append(&state.points, smoothed_point)
	state.last_point = smoothed_point
}

draw_stroke :: proc(canvas: ^Canvas, points: []rl.Vector2, color: rl.Color, size: i32) {
	if len(points) < 2 do return

	rl.BeginTextureMode(canvas.texture)
	defer rl.EndTextureMode()

	// For very short strokes, just draw a line
	if len(points) == 2 {
		rl.DrawLineEx(points[0], points[1], f32(size), color)
		rl.DrawCircleV(points[0], f32(size) / 2, color)
		rl.DrawCircleV(points[1], f32(size) / 2, color)
		return
	}

	// For longer strokes, use Catmull-Rom spline
	// Add control points at the start and end
	extended_points := make([dynamic]rl.Vector2, 0, len(points) + 2)
	defer delete(extended_points)

	start_control := points[0] - (points[1] - points[0])
	append(&extended_points, start_control)

	for point in points {
		append(&extended_points, point)
	}

	end_control := points[len(points) - 1] + (points[len(points) - 1] - points[len(points) - 2])
	append(&extended_points, end_control)

	rl.DrawSplineCatmullRom(
		raw_data(extended_points[:]),
		i32(len(extended_points)),
		f32(size),
		color,
	)

	rl.DrawCircleV(points[0], f32(size) / 2, color)
	rl.DrawCircleV(points[len(points) - 1], f32(size) / 2, color)
}

update_drawing :: proc(state: ^State, canvas_pos: rl.Vector2, color: rl.Color) {

	if canvas_pos.x >= 0 &&
	   canvas_pos.x < f32(state.canvas.width) &&
	   canvas_pos.y >= 0 &&
	   canvas_pos.y < f32(state.canvas.height) {
		if state.canvas.is_dragging do return

		if rl.IsMouseButtonDown(.LEFT) {
			if !state.draw_state.is_drawing {
				state.draw_state.is_drawing = true
				clear(&state.draw_state.points)
				add_point(&state.draw_state, canvas_pos)
			} else {
				add_point(&state.draw_state, canvas_pos)
				if len(state.draw_state.points) > 0 {
					draw_stroke(
						&state.canvas,
						state.draw_state.points[:],
						state.primary_color,
						i32(state.brush_size),
					)
				}
			}
		} else if state.draw_state.is_drawing {
			// If we only had one point and we let go, it was a tap
			if len(state.draw_state.points) == 1 {
				rl.BeginTextureMode(state.canvas.texture)
				rl.DrawCircleV(state.draw_state.points[0], f32(state.brush_size), color)
				rl.EndTextureMode()
			}
			reset_drawing(&state.draw_state)
		}
	}
}
