package paint

import "core:math"
import "core:time"
import rl "vendor:raylib"

POINT_DISTANCE_MIN :: 2.0 // Minimum distance between points
SPLINE_SEGMENTS :: 20 // Number of segments per spline curve
SMOOTH_FACTOR :: 0.25
HANDLE_SIZE :: 5
CAMERA_ANGLE :: math.PI / 6.0 // 30 degrees in radians

DrawState :: struct {
	smooth_lines: bool,
	points:       [dynamic]rl.Vector2,
	is_drawing:   bool,
	last_point:   rl.Vector2,
}

Canvas :: struct {
	texture:       rl.RenderTexture2D, // Main Canvas
	container:     struct {
		width, height: i32,
		position:      rl.Vector2, // Canvas Position in window
	},
	camera:        struct {
		x, y, z: f32, // distancce from camera to canvas
	},
	pointer:       struct {
		x, y: f32,
	},
	is_dragging:   bool,
	drag_start:    rl.Vector2,
	last_offset:   rl.Vector2,
	history:       History,
	resize_handle: ResizeHandle,
	is_resizing:   bool,
	dirty:         bool,
	pixel_ratio:   f32,
	mode:          CanvasMode,
}

CanvasMode :: enum {
	Fixed,
	Infinite,
}

ResizeHandle :: enum {
	None,
	TopLeft,
	TopRight,
	BottomLeft,
	BottomRight,
}

ScreenCoords :: struct {
	x, y:          f32, // Position
	width, height: f32, // Dimensions
}

create_canvas :: proc(width, height: i32, infinite := false, mode := CanvasMode.Fixed) -> Canvas {
	container_width := i32(rl.GetScreenWidth() - TOOLBAR_WIDTH)
	container_height := i32(rl.GetScreenHeight() - MENUBAR_HEIGHT - STATUSBAR_HEIGHT)

	canvas := Canvas {
		mode = mode,
		texture = rl.LoadRenderTexture(width, height),
		container = {
			width = container_width,
			height = container_height,
			position = {TOOLBAR_WIDTH, MENUBAR_HEIGHT},
		},
		camera = {
			x = f32(width) / 2, // Center on canvas
			y = f32(height) / 2,
			z = f32(container_width) / (2 * math.tan_f32(CAMERA_ANGLE)), // Initial zoom to fit
		},
		pixel_ratio = 1.0, // TODO: Handle high DPI
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
	if canvas.mode != .Fixed do return

	old_texture := canvas.texture
	defer rl.UnloadRenderTexture(old_texture)

	canvas.texture = rl.LoadRenderTexture(new_width, new_height)

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

	// Update camera for new dimensions
	canvas.camera.x = f32(new_width) / 2
	canvas.camera.y = f32(new_height) / 2
}

update_canvas :: proc(canvas: ^Canvas) {
	// Handle zooming
	wheel := rl.GetMouseWheelMove()
	if rl.IsKeyDown(.LEFT_CONTROL) && wheel != 0.0 {
		// Scale zoom amount
		zoom_factor: f32 = 50.0
		delta_z := -wheel * zoom_factor

		// Get current pointer position for anchor point
		mouse_pos := rl.GetMousePosition()
		canvas_pos := window_to_canvas_coords(canvas, mouse_pos)

		scale_with_anchor(canvas, canvas_pos.x, canvas_pos.y, delta_z)
	}

	// Handle Panning
	if rl.IsMouseButtonDown(.MIDDLE) || (rl.IsKeyDown(.SPACE) && rl.IsMouseButtonDown(.LEFT)) {
		if !canvas.is_dragging {
			canvas.is_dragging = true
			canvas.drag_start = rl.GetMousePosition()

			if canvas.mode == .Fixed {
				clamp_camera_bounds(canvas)
			}
		}

		mouse_pos := rl.GetMousePosition()
		// Get scale for proper movement conversion
		screen := camera_to_screen_coords(canvas)
		scale_x, scale_y := get_scale(canvas, screen)

		// Calculate movement in canvas space
		delta_x := (mouse_pos.x - canvas.drag_start.x) / scale_x
		delta_y := (mouse_pos.y - canvas.drag_start.y) / scale_y

		// Update camera position
		canvas.camera.x -= delta_x
		canvas.camera.y -= delta_y

		canvas.drag_start = mouse_pos
	} else {
		canvas.is_dragging = false
	}

	// Update pointer position
	mouse_pos := rl.GetMousePosition()
	canvas.pointer = {
		x = (mouse_pos.x - canvas.container.position.x),
		y = (mouse_pos.y - canvas.container.position.y),
	}

	if !canvas.is_dragging {
		update_resize_handles(canvas)
	}
}

window_to_canvas_coords :: proc(canvas: ^Canvas, window_pos: rl.Vector2) -> rl.Vector2 {
	screen := camera_to_screen_coords(canvas)
	scale_x, scale_y := get_scale(canvas, screen)

	// Adjust for container position and scale
	x := (window_pos.x - canvas.container.position.x) / scale_x + screen.x
	y := (window_pos.y - canvas.container.position.y) / scale_y + screen.y

	return {x, y}
}

camera_to_screen_coords :: proc(canvas: ^Canvas) -> ScreenCoords {
	aspect := f32(canvas.container.width) / f32(canvas.container.height)
	width := 2 * canvas.camera.z * math.tan_f32(CAMERA_ANGLE)
	height := width / aspect

	return ScreenCoords {
		x = canvas.camera.x - width / 2,
		y = canvas.camera.y - height / 2,
		width = width,
		height = height,
	}
}

// Scale camera while maintaining focus point
scale_with_anchor :: proc(canvas: ^Canvas, anchor_x, anchor_y: f32, delta_z: f32) {
	old_screen := camera_to_screen_coords(canvas)
	old_scale_x, old_scale_y := get_scale(canvas, old_screen)

	// Calculate new camera position
	new_z := canvas.camera.z + delta_z
	new_screen := camera_to_screen_coords(canvas)
	new_scale_x, new_scale_y := get_scale(canvas, new_screen)

	// Adjust camera position to maintain anchor point
	canvas.camera.x =
		(anchor_x * (new_scale_x - old_scale_x) + old_scale_x * canvas.camera.x) / new_scale_x
	canvas.camera.y =
		(anchor_y * (new_scale_y - old_scale_y) + old_scale_y * canvas.camera.y) / new_scale_y
	canvas.camera.z = new_z
}

get_scale :: proc(canvas: ^Canvas, screen: ScreenCoords) -> (f32, f32) {
	return f32(canvas.container.width) / screen.width, f32(canvas.container.height) / screen.height
}

// Add bounds checking for fixed canvas mode
clamp_camera_bounds :: proc(canvas: ^Canvas) {
	if canvas.mode != .Fixed do return

	// Get current screen coordinates
	// screen := camera_to_screen_coords(canvas)
	// scale_x, scale_y := get_scale(canvas, screen)

	// Calculate bounds to keep canvas in view
	min_x := f32(canvas.texture.texture.width) * 0.1 // Allow 10% overflow
	min_y := f32(canvas.texture.texture.height) * 0.1
	max_x := f32(canvas.texture.texture.width) * 0.9
	max_y := f32(canvas.texture.texture.height) * 0.9

	// Clamp camera position
	canvas.camera.x = clamp(canvas.camera.x, min_x, max_x)
	canvas.camera.y = clamp(canvas.camera.y, min_y, max_y)

	// Limit zoom for fixed canvas
	min_z := f32(canvas.container.width) / (2 * math.tan_f32(CAMERA_ANGLE)) // Full view
	max_z := min_z * 10 // Maximum 10x zoom
	canvas.camera.z = clamp(canvas.camera.z, min_z, max_z)
}

draw_canvas :: proc(canvas: ^Canvas) {
	screen := camera_to_screen_coords(canvas)
	scale_x, scale_y := get_scale(canvas, screen)

	// Draw canvas texture
	source_rect := rl.Rectangle {
		0,
		0,
		f32(canvas.texture.texture.width),
		-f32(canvas.texture.texture.height), // Flip texture
	}

	dest_rect := rl.Rectangle {
		x      = canvas.container.position.x - screen.x * scale_x,
		y      = canvas.container.position.y - screen.y * scale_y,
		width  = f32(canvas.texture.texture.width) * scale_x,
		height = f32(canvas.texture.texture.height) * scale_y,
	}

	// Draw canvas border in fixed mode
	if canvas.mode == .Fixed {
		rl.DrawRectangleLinesEx(dest_rect, 1, rl.BLACK)
		draw_resize_handles(canvas, dest_rect)
	}

	rl.DrawTexturePro(canvas.texture.texture, source_rect, dest_rect, {0, 0}, 0.0, rl.WHITE)
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

update_drawing :: proc(state: ^State, color: rl.Color) {
	if state.canvas.is_dragging do return

	mouse_pos := rl.GetMousePosition()
	canvas_pos := window_to_canvas_coords(&state.canvas, mouse_pos)

	// Rest of drawing logic remains the same
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
					color,
					i32(state.brush_size),
				)
			}
		}
	} else if state.draw_state.is_drawing {
		// Handle stroke completion - same as before
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
				color = color,
				size = i32(state.brush_size),
			},
		)
		push_op(&state.canvas, stroke_op)
		reset_drawing(&state.draw_state)
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

draw_resize_handles :: proc(canvas: ^Canvas, dest_rect: rl.Rectangle) {
	if canvas.mode != .Fixed do return

	handle_color := rl.BLACK

	// Draw corner handles
	corners := [][2]rl.Vector2 {
		{
			{dest_rect.x - HANDLE_SIZE, dest_rect.y - HANDLE_SIZE},
			{dest_rect.x + HANDLE_SIZE, dest_rect.y + HANDLE_SIZE},
		}, // Top-left
		{
			{dest_rect.x + dest_rect.width - HANDLE_SIZE, dest_rect.y - HANDLE_SIZE},
			{dest_rect.x + dest_rect.width + HANDLE_SIZE, dest_rect.y + HANDLE_SIZE},
		}, // Top-right
		{
			{dest_rect.x - HANDLE_SIZE, dest_rect.y + dest_rect.height - HANDLE_SIZE},
			{dest_rect.x + HANDLE_SIZE, dest_rect.y + dest_rect.height + HANDLE_SIZE},
		}, // Bottom-left
		{
			{
				dest_rect.x + dest_rect.width - HANDLE_SIZE,
				dest_rect.y + dest_rect.height - HANDLE_SIZE,
			},
			{
				dest_rect.x + dest_rect.width + HANDLE_SIZE,
				dest_rect.y + dest_rect.height + HANDLE_SIZE,
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

update_resize_handles :: proc(canvas: ^Canvas) {
	if canvas.mode != .Fixed do return

	if canvas.is_resizing {
		mouse_pos := rl.GetMousePosition()
		canvas_pos := window_to_canvas_coords(canvas, mouse_pos)

		#partial switch canvas.resize_handle {
		case .BottomRight:
			new_width := i32(canvas_pos.x)
			new_height := i32(canvas_pos.y)
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
		// screen := camera_to_screen_coords(canvas)
		// scale_x, scale_y := get_scale(canvas, screen)

		check_corner :: proc(pos: rl.Vector2, corner_x, corner_y: f32) -> bool {
			return rl.CheckCollisionPointRec(
				pos,
				{corner_x - HANDLE_SIZE, corner_y - HANDLE_SIZE, HANDLE_SIZE * 2, HANDLE_SIZE * 2},
			)
		}

		canvas_rect := get_canvas_rect(canvas)
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

get_canvas_rect :: proc(canvas: ^Canvas) -> rl.Rectangle {
	screen := camera_to_screen_coords(canvas)
	scale_x, scale_y := get_scale(canvas, screen)

	return rl.Rectangle {
		x = canvas.container.position.x - screen.x * scale_x,
		y = canvas.container.position.y - screen.y * scale_y,
		width = f32(canvas.texture.texture.width) * scale_x,
		height = f32(canvas.texture.texture.height) * scale_y,
	}
}


toggle_canvas_mode :: proc(canvas: ^Canvas) {
	canvas.mode = canvas.mode == .Fixed ? .Infinite : .Fixed

	// Reset camera when switching modes
	if canvas.mode == .Fixed {
		// Center on canvas
		canvas.camera.x = f32(canvas.texture.texture.width) / 2
		canvas.camera.y = f32(canvas.texture.texture.height) / 2
		canvas.camera.z = f32(canvas.container.width) / (2 * math.tan_f32(CAMERA_ANGLE))
	}
}
