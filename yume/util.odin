package yume

import "core:c"
import "core:fmt"
import rl "vendor:raylib"
// Helper to create a color value
get_color :: proc(r, g, b, a: u8) -> c.int {
	return c.int(rl.ColorToInt({r, g, b, a}))
}

clone_points :: proc(points: []rl.Vector2) -> []rl.Vector2 {
	if len(points) == 0 do return nil
	new_points := make([]rl.Vector2, len(points))
	copy(new_points, points)
	return new_points
}

handle_file_drop :: proc() {
	files := rl.LoadDroppedFiles()
	defer rl.UnloadDroppedFiles(files)

	if files.count > 0 {
		image := rl.LoadImage(files.paths[0])
		if image.data == nil {
			return
		}
		defer rl.UnloadImage(image)

		if image.format != .UNCOMPRESSED_R8G8B8A8 {
			rl.ImageFormat(&image, .UNCOMPRESSED_R8G8B8A8)
		}
		success := draw_image(&state.canvas, image)
		if !success {
			//TODO: Show an error dialog
			fmt.println("failed to load image:", files.paths[0])
		}
	}
}

is_canvas_empty :: proc(canvas: ^Canvas) -> bool {
	if canvas.dirty {
		image := rl.LoadImageFromTexture(canvas.texture.texture)
		defer rl.UnloadImage(image)

		pixels := ([^]rl.Color)(image.data)
		for i := 0; i32(i) < image.width * image.height; i += 1 {
			pixel := pixels[i]
			if pixel.r != 255 || pixel.g != 255 || pixel.b != 255 || pixel.a != 255 {
				return false
			}
		}
		return true
	}
	return true
}
