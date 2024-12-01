package paint

import "core:time"
import rl "vendor:raylib"

POINT_DISTANCE_MIN :: 2.0 // Minimum distance between points
SPLINE_SEGMENTS :: 20 // Number of segments per spline curve
SMOOTH_FACTOR :: 0.25
HANDLE_SIZE :: 5

DrawState :: struct {
	smooth_lines: bool,
	points:       [dynamic]rl.Vector2,
	is_drawing:   bool,
	last_point:   rl.Vector2,
}

Canvas :: struct {
	texture:       rl.RenderTexture2D, // Main Canvas
	width:         i32,
	height:        i32,
	position:      rl.Vector2, // Canvas Position in window
	scale:         f32, // zoom
	offset:        rl.Vector2, // pan
	is_dragging:   bool,
	drag_start:    rl.Vector2,
	last_offset:   rl.Vector2,
	history:       History,
	resize_handle: ResizeHandle,
	is_resizing:   bool,
	dirty:         bool,
}

ResizeHandle :: enum {
	None,
	TopLeft,
	TopRight,
	BottomLeft,
	BottomRight,
}

create_canvas :: proc(width, height: i32) -> Canvas {
	canvas := Canvas {
		texture = rl.LoadRenderTexture(width, height),
		width = width,
		height = height,
		position = {TOOLBAR_WIDTH, MENUBAR_HEIGHT},
		scale = 1.0,
		offset = {0.0, 0.0},
		is_dragging = false,
		drag_start = {0.0, 0.0},
		last_offset = {0.0, 0.0},
		history = {operations = make([dynamic]Operation), max_entries = 10, curr_index = 0},
	}

	rl.BeginTextureMode(canvas.texture)
	rl.ClearBackground(rl.WHITE)
	rl.EndTextureMode()

	return canvas
}

destroy_canvas :: proc(canvas: ^Canvas) {
	for op in canvas.history.operations {
		destroy_op(op)
	}
	delete(canvas.history.operations)
	rl.UnloadRenderTexture(canvas.texture)
}

resize_canvas :: proc(canvas: ^Canvas, new_width, new_height: i32) {
	old_texture := canvas.texture
	defer rl.UnloadRenderTexture(old_texture)

	canvas.texture = rl.LoadRenderTexture(new_width, new_height)
	canvas.width = new_width
	canvas.height = new_height

	// Clear new canvas to white
	rl.BeginTextureMode(canvas.texture)
	rl.ClearBackground(rl.WHITE)

	// Copy old content
	source_rect := rl.Rectangle {
		0,
		0,
		f32(old_texture.texture.width),
		-f32(old_texture.texture.height),
	}
	dest_rect := rl.Rectangle {
		0,
		0,
		f32(old_texture.texture.width),
		f32(old_texture.texture.height),
	}
	rl.DrawTexturePro(old_texture.texture, source_rect, dest_rect, {0, 0}, 0, rl.WHITE)

	rl.EndTextureMode()
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

	if !canvas.is_dragging {
		update_resize_handles(canvas)
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

	draw_resize_handles(canvas)
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
			copied_points := clone_points(state.draw_state.points[:])

			stroke_op := Operation(
				StrokeOperation {
					info = {type = OperationType.Stroke, timestamp = time.now()._nsec},
					points = copied_points,
					color = state.primary_color,
					size = i32(state.brush_size),
				},
			)
			push_op(&state.canvas, stroke_op)
			reset_drawing(&state.draw_state)
		}
	}
}

draw_image_at :: proc(canvas: ^Canvas, image: rl.Image, pos: rl.Vector2) {
	texture := rl.LoadTextureFromImage(image)
	defer rl.UnloadTexture(texture)

	rl.BeginTextureMode(canvas.texture)
	defer rl.EndTextureMode()

	source_rect := rl.Rectangle{0, 0, f32(image.width), f32(image.height)}
	dest_rect := rl.Rectangle{pos.x, pos.y, f32(image.width), f32(image.height)}
	rl.DrawTexturePro(texture, source_rect, dest_rect, {0, 0}, 0, rl.WHITE)
}


draw_image :: proc(canvas: ^Canvas, filepath: cstring) -> bool {
	image := rl.LoadImage(filepath)
	if image.data == nil {
		return false
	}
	// defer rl.UnloadImage(image)

	if image.format != .UNCOMPRESSED_R8G8B8A8 {
		rl.ImageFormat(&image, .UNCOMPRESSED_R8G8B8A8)
	}

	pos: rl.Vector2
	if is_canvas_empty(canvas) {
		// If canvas is empty, resize it to match the image
		resize_canvas(canvas, image.width, image.height)
		pos = {0, 0}

		// Draw the image directly
		texture := rl.LoadTextureFromImage(image)
		defer rl.UnloadTexture(texture)

		rl.BeginTextureMode(canvas.texture)
		rl.DrawTexture(texture, 0, 0, rl.WHITE)
		rl.EndTextureMode()
	} else {
		// If canvas has content, paste image at cursor position
		mouse_pos := window_to_canvas_coords(canvas, rl.GetMousePosition())
		pos = {mouse_pos.x - f32(image.width) / 2, mouse_pos.y - f32(image.height) / 2}

		texture := rl.LoadTextureFromImage(image)
		defer rl.UnloadTexture(texture)

		rl.BeginTextureMode(canvas.texture)
		source_rect := rl.Rectangle{0, 0, f32(image.width), f32(image.height)}
		dest_rect := rl.Rectangle{pos.x, pos.y, f32(image.width), f32(image.height)}
		rl.DrawTexturePro(texture, source_rect, dest_rect, {0, 0}, 0, rl.WHITE)
		rl.EndTextureMode()
	}

	// Create and store the operation for undo/redo
	img_op := Operation(
		ImageOperation {
			info = {type = OperationType.Image, timestamp = time.now()._nsec},
			image = image,
			width = image.width,
			height = image.height,
			pos = pos,
		},
	)
	push_op(canvas, img_op)

	return true
}

draw_resize_handles :: proc(canvas: ^Canvas) {
	if canvas.scale <= 0 do return

	// Calculate canvas corners in screen space
	canvas_rect := get_canvas_rect(canvas)
	handle_color := rl.BLACK

	// Draw corner handles
	corners := [][2]rl.Vector2 {
		{
			{canvas_rect.x - HANDLE_SIZE, canvas_rect.y - HANDLE_SIZE},
			{canvas_rect.x + HANDLE_SIZE, canvas_rect.y + HANDLE_SIZE},
		}, // Top-left
		{
			{canvas_rect.x + canvas_rect.width - HANDLE_SIZE, canvas_rect.y - HANDLE_SIZE},
			{canvas_rect.x + canvas_rect.width + HANDLE_SIZE, canvas_rect.y + HANDLE_SIZE},
		}, // Top-right
		{
			{canvas_rect.x - HANDLE_SIZE, canvas_rect.y + canvas_rect.height - HANDLE_SIZE},
			{canvas_rect.x + HANDLE_SIZE, canvas_rect.y + canvas_rect.height + HANDLE_SIZE},
		}, // Bottom-left
		{
			{
				canvas_rect.x + canvas_rect.width - HANDLE_SIZE,
				canvas_rect.y + canvas_rect.height - HANDLE_SIZE,
			},
			{
				canvas_rect.x + canvas_rect.width + HANDLE_SIZE,
				canvas_rect.y + canvas_rect.height + HANDLE_SIZE,
			},
		}, // Bottom-right
	}

	for corner in corners {
		rl.DrawRectangle(
			i32(corner[0].x),
			i32(corner[0].y),
			HANDLE_SIZE * 2,
			HANDLE_SIZE * 2,
			handle_color,
		)
	}
}

get_canvas_rect :: proc(canvas: ^Canvas) -> rl.Rectangle {
	return {
		x = canvas.position.x,
		y = canvas.position.y,
		width = f32(canvas.width),
		height = f32(canvas.height),
	}
}

update_resize_handles :: proc(canvas: ^Canvas) {
	if canvas.is_resizing {
		mouse_pos := rl.GetMousePosition()
		canvas_rect := get_canvas_rect(canvas)

		#partial switch canvas.resize_handle {
		case .BottomRight:
			new_width := i32((mouse_pos.x - canvas_rect.x) / canvas.scale)
			new_height := i32((mouse_pos.y - canvas_rect.y) / canvas.scale)
			if new_width > 100 && new_height > 100 {
				resize_canvas(canvas, new_width, new_height)
			}
		case .TopLeft, .TopRight, .BottomLeft:
		// Implement other corner resizing if needed
		case .None:
		// Do nothing
		}

		if !rl.IsMouseButtonDown(.LEFT) {
			canvas.is_resizing = false
			canvas.resize_handle = .None
			rl.SetMouseCursor(.ARROW)
		}
	} else {
		// Check if mouse is over any resize handle
		mouse_pos := rl.GetMousePosition()
		canvas_rect := get_canvas_rect(canvas)

		check_corner :: proc(pos: rl.Vector2, corner_x, corner_y: f32) -> bool {
			return rl.CheckCollisionPointRec(
				pos,
				{corner_x - HANDLE_SIZE, corner_y - HANDLE_SIZE, HANDLE_SIZE * 2, HANDLE_SIZE * 2},
			)
		}

		if check_corner(
			mouse_pos,
			canvas_rect.x + canvas_rect.width,
			canvas_rect.y + canvas_rect.height,
		) {
			rl.SetMouseCursor(.POINTING_HAND)
			if rl.IsMouseButtonPressed(.LEFT) {
				canvas.resize_handle = .BottomRight
				canvas.is_resizing = true
			}
			// Add other corners if needed
		} else {
			rl.SetMouseCursor(.ARROW)
		}
	}
}
