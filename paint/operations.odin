package paint

import rl "vendor:raylib"

OperationInfo :: struct {
	type:      OperationType,
	timestamp: i64,
}

OperationType :: enum {
	Stroke,
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

Operation :: union {
	StrokeOperation,
}

History :: struct {
	operations:  [dynamic]Operation,
	curr_index:  int,
	max_entries: int,
}

push_op :: proc(canvas: ^Canvas, op: Operation) {
	if canvas.history.curr_index < len(canvas.history.operations) - 1 {
		resize(&canvas.history.operations, canvas.history.curr_index + 1)
	}

	append(&canvas.history.operations, op)
	canvas.history.curr_index = len(canvas.history.operations) - 1

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
	}
}

undo :: proc(canvas: ^Canvas) {
	if canvas.history.curr_index < 0 do return

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
	apply_op(canvas, canvas.history.operations[canvas.history.curr_index])
}
