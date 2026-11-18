package practice

import "core:mem"
import "core:strings"

// snippet: scratch
clone_via_scratch :: proc(input: string, output_allocator: mem.Allocator) -> (result: string, err: mem.Allocator_Error) {
	buffer: [1024]byte
	arena: mem.Arena
	mem.arena_init(&arena, buffer[:])
	context.allocator = mem.arena_allocator(&arena)

	scratch := strings.clone(input) or_return
	// Copy into caller-owned storage before the local buffer's lifetime ends.
	return strings.clone(scratch, output_allocator)
}
// endsnippet: scratch

read_context_index :: proc() -> int {
	return context.user_index
}
