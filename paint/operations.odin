package paint

import rl "vendor:raylib"

OperationInfo :: struct {
	type:      OperationType,
	timestamp: i64,
}

OperationType :: enum {
	Stroke,
	Erase,
	Fill,
	Shape,
	Text,
	Image,
}

StrokeOperation :: struct {
	using info: OperationInfo,
	points:     []rl.Vector2,
	color:      rl.Color,
	size:       i32,
}

ImageOperation :: struct {
	using info: OperationInfo,
	image:      rl.Image,
	pos:        rl.Vector2,
	width:      i32,
	height:     i32,
}

Operation :: union {
	StrokeOperation,
	ImageOperation,
}

History :: struct {
	operations:  [dynamic]Operation,
	curr_index:  int,
	max_entries: int,
}

push_op :: proc(canvas: ^Canvas, op: Operation) {
	if canvas.history.curr_index < len(canvas.history.operations) - 1 {
		// Clean up operations that will be removed
		for i := canvas.history.curr_index + 1; i < len(canvas.history.operations); i += 1 {
			destroy_op(canvas.history.operations[i])
		}
		resize(&canvas.history.operations, canvas.history.curr_index + 1)
	}

	append(&canvas.history.operations, op)
	canvas.history.curr_index = len(canvas.history.operations) - 1
	canvas.dirty = true

	// if len(canvas.history.operations) > canvas.history.max_entries {
	// 	ordered_remove(&canvas.history.operations, 0)
	// 	canvas.history.curr_index -= 1
	// }
}

apply_op :: proc(canvas: ^Canvas, op: Operation) {
	// rl.BeginTextureMode(canvas.texture)
	// defer rl.EndTextureMode()

	switch op in op {
	case StrokeOperation:
		draw_stroke(canvas, op.points, op.color, op.size)
	case ImageOperation:
		if is_canvas_empty(canvas) {
			resize_canvas(canvas, op.width, op.height)
			tex := rl.LoadTextureFromImage(op.image)
			defer rl.UnloadTexture(tex)

			rl.BeginTextureMode(canvas.texture)
			rl.DrawTexture(tex, 0, 0, rl.WHITE)
			rl.EndTextureMode()
		} else {
			draw_image_at(canvas, op.image, op.pos)
		}
	}
}

undo :: proc(canvas: ^Canvas) {
	if canvas.history.curr_index < 0 {
		canvas.dirty = false
		return
	}

	canvas.history.curr_index -= 1

	// Clear canvas
	rl.BeginTextureMode(canvas.texture)
	rl.ClearBackground(rl.WHITE)
	rl.EndTextureMode()


	for i := 0; i <= canvas.history.curr_index; i += 1 {
		apply_op(canvas, canvas.history.operations[i])
	}
}

redo :: proc(canvas: ^Canvas) {
	if canvas.history.curr_index >= len(canvas.history.operations) - 1 do return


	canvas.history.curr_index += 1
	canvas.dirty = true
	apply_op(canvas, canvas.history.operations[canvas.history.curr_index])
}

destroy_op :: proc(op: Operation) {
	switch o in op {
	case ImageOperation:
		rl.UnloadImage(o.image)
	case StrokeOperation:
		delete(o.points)
	}
}
