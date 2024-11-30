package paint

import "core:c"
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
