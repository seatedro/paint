package paint

import "core:c"
import rl "vendor:raylib"

// Helper to create a color value
get_color :: proc(r, g, b, a: u8) -> c.int {
	return c.int(rl.ColorToInt({r, g, b, a}))
}
