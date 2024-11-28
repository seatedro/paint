// main.odin
package main

import "core:c"
import "core:fmt"
import "core:os"
import "core:time"
import rl "vendor:raylib"

foreign import onnx_bridge "build/libonnx_bridge.a"

Point :: struct {
	x: f32,
	y: f32,
}

ImageData :: struct {
	data:          [^]u8,
	width:         c.int,
	height:        c.int,
	channels:      c.int,
	scaled_width:  c.int,
	scaled_height: c.int,
	scale:         f32,
}

SegmentationResult :: struct {
	mask:   [^]f32,
	width:  c.int,
	height: c.int,
	score:  f32,
}

@(default_calling_convention = "c")
foreign onnx_bridge {
	create_onnx_context :: proc(encoder_path: cstring, decoder_path: cstring) -> rawptr ---
	destroy_onnx_context :: proc(ctx: rawptr) ---
	process_image :: proc(ctx: rawptr, image: ^ImageData) -> c.int ---
	run_segmentation :: proc(ctx: rawptr, points: [^]Point, num_points: c.int, orig_width: c.int, orig_height: c.int, result: ^SegmentationResult) -> c.int ---
	get_last_error :: proc(ctx: rawptr) -> cstring ---
	free_segmentation_result :: proc(result: ^SegmentationResult) ---
}

log :: proc(format: string, args: ..any) {
	now := time.now()
	fmt.printf("[%v] ", now)
	fmt.printf(format, ..args)
	fmt.println()
}

sam :: proc() {
	log("Starting Odingboard! application")

	// Initialize window with a reasonable fixed size
	window_width := 1280
	window_height := 720
	rl.InitWindow(i32(window_width), i32(window_height), "odingboard (paint 2.0)")
	defer rl.CloseWindow()
	rl.SetTargetFPS(60)
	log("Window initialized")

	camera_pos := rl.Vector2{0, 0}
	drag_start: rl.Vector2
	is_dragging := false
	zoom := 1.0 // We can add zoom functionality later

	// Load test image
	log("Loading test image...")
	image := rl.LoadImage("consultant.jpeg")
	if image.data == nil {
		log("ERROR: Failed to load test.png")
		return
	}
	defer rl.UnloadImage(image)
	log("Image loaded successfully: %dx%d", image.width, image.height)

	// Convert to RGB if necessary
	if image.format != .UNCOMPRESSED_R8G8B8 {
		log("Converting image to RGB format...")
		rl.ImageFormat(&image, .UNCOMPRESSED_R8G8B8)
		log("Image converted to RGB")
	}

	// Create texture for display
	texture := rl.LoadTextureFromImage(image)
	defer rl.UnloadTexture(texture)
	log("Display texture created")

	transform := Transform {
		scale    = 1.0,
		offset_x = camera_pos.x,
		offset_y = camera_pos.y,
	}

	// Convert to ImageData format
	img_data := ImageData {
		data     = cast([^]u8)image.data,
		width    = image.width,
		height   = image.height,
		channels = 3, // RGB
	}
	log(
		"Image data prepared: %dx%d (%d channels)",
		img_data.width,
		img_data.height,
		img_data.channels,
	)

	// Initialize ONNX
	log("Creating ONNX context...")
	ctx := create_onnx_context("models/sam_encoder.onnx", "models/sam_decoder.onnx")
	if ctx == nil {
		log("ERROR: Failed to create ONNX context")
		return
	}
	defer destroy_onnx_context(ctx)
	log("ONNX context created successfully")

	log("Processing image through encoder...")
	if process_image(ctx, &img_data) != 0 {
		log("ERROR: Failed to process image: %s", get_last_error(ctx))
		return
	}
	log("Image processed successfully")

	// Initialize interaction state
	points := make([dynamic]Point, 0, 10)
	defer delete(points)
	result: SegmentationResult
	mask_texture: rl.Texture2D


	log("Ready for interaction")
	log("Controls: Click to add points | SPACE to segment | R to reset | ESC to quit")

	for !rl.WindowShouldClose() {
		if rl.IsMouseButtonPressed(.RIGHT) {
			is_dragging = true
			drag_start = rl.GetMousePosition()
		} else if rl.IsMouseButtonReleased(.RIGHT) {
			is_dragging = false
		}

		if is_dragging {
			current_pos := rl.GetMousePosition()
			delta := rl.Vector2{current_pos.x - drag_start.x, current_pos.y - drag_start.y}
			camera_pos.x += delta.x
			camera_pos.y += delta.y
			drag_start = current_pos
		}
		// Handle input
		if rl.IsMouseButtonPressed(.LEFT) {
			mouse_pos := rl.GetMousePosition()

			// Convert screen coordinates to image coordinates
			image_point := screen_to_image(
				mouse_pos.x,
				mouse_pos.y,
				transform,
				image.width,
				image.height,
			)

			if image_point.x >= 0 &&
			   image_point.x < f32(image.width) &&
			   image_point.y >= 0 &&
			   image_point.y < f32(image.height) {
				append(&points, image_point)
				log(
					"Added point at (%.1f, %.1f) - Total points: %d",
					image_point.x,
					image_point.y,
					len(points),
				)
			}
		}

		if rl.IsKeyPressed(.SPACE) && len(points) > 0 {
			log("Running segmentation with %d points...", len(points))
			start_time := time.now()

			if run_segmentation(
				   ctx,
				   raw_data(points[:]),
				   c.int(len(points)),
				   img_data.width,
				   img_data.height,
				   &result,
			   ) ==
			   0 {
				// Create visualization with proper coordinate transformation
				mask_img := rl.GenImageColor(image.width, image.height, rl.BLANK)
				pixel_count := 0

				for y in 0 ..< result.height {
					for x in 0 ..< result.width {
						if result.mask[y * result.width + x] > 0.0 {
							rl.ImageDrawPixel(&mask_img, x, y, {255, 0, 0, 128})
							pixel_count += 1
						}
					}
				}

				if mask_texture.id != 0 {
					rl.UnloadTexture(mask_texture)
				}
				mask_texture = rl.LoadTextureFromImage(mask_img)
				rl.UnloadImage(mask_img)
			}
		}

		if rl.IsKeyPressed(.R) {
			clear(&points)
			if mask_texture.id != 0 {
				rl.UnloadTexture(mask_texture)
				mask_texture.id = 0
			}
			log("Reset: Cleared points and mask")
		}

		// Draw
		rl.BeginDrawing()
		{
			rl.ClearBackground(rl.RAYWHITE)

			// Draw original image
			source_rect := rl.Rectangle{0, 0, f32(image.width), f32(image.height)}
			dest_rect := rl.Rectangle {
				camera_pos.x,
				camera_pos.y,
				f32(image.width),
				f32(image.height),
			}
			rl.DrawTexturePro(texture, source_rect, dest_rect, {}, 0, rl.WHITE)

			// Draw mask overlay if available
			if mask_texture.id != 0 {
				rl.DrawTexturePro(mask_texture, source_rect, dest_rect, {}, 0, rl.WHITE)
			}

			// Draw points
			for point in points {
				screen_point := image_to_screen(point.x, point.y, transform)
				rl.DrawCircle(i32(screen_point.x), i32(screen_point.y), 5, rl.RED)
			}

			// Draw instructions
			rl.DrawText(
				"Click: Add points | Right-click drag: Pan | SPACE: Segment | R: Reset | ESC: Quit",
				10,
				10,
				20,
				rl.DARKGRAY,
			)

			// Draw point count if any
			if len(points) > 0 {
				text := fmt.tprintf("Points: %d", len(points))
				rl.DrawText(cstring(raw_data(text)), 10, 40, 20, rl.DARKGRAY)
			}

			// Draw IoU score if available
			if result.score > 0 {
				text := fmt.tprintf("IoU Score: %.3f", result.score)
				rl.DrawText(cstring(raw_data(text)), 10, 70, 20, rl.DARKGRAY)
			}
		}
		rl.EndDrawing()
	}

	if mask_texture.id != 0 {
		rl.UnloadTexture(mask_texture)
	}
	log("Application terminated")
}

Transform :: struct {
	scale:    f32, // Display scale
	offset_x: f32, // Display offset X
	offset_y: f32, // Display offset Y
}

transform_point_to_model :: proc(point: Point, image_width, image_height: i32) -> Point {
	return point
}

screen_to_image :: proc(x, y: f32, transform: Transform, image_width, image_height: i32) -> Point {
	// Convert screen coordinates to image coordinates
	// img_x := x - transform.offset_x
	// img_y := y - transform.offset_y
	img_x := x
	img_y := y
	return Point{img_x, img_y}
}

image_to_screen :: proc(x, y: f32, transform: Transform) -> Point {
	// Convert image coordinates to screen coordinates
	// screen_x := x + transform.offset_x
	// screen_y := y + transform.offset_y
	screen_x := x
	screen_y := y
	return Point{screen_x, screen_y}
}
