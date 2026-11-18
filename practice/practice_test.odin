package practice

import "core:mem"
import "core:testing"

@(test)
header_has_known_wire_layout :: proc(t: ^testing.T) {
	h, err := make_header(.Data, true, 512)
	testing.expect_value(t, err, .None)
	testing.expect_value(t, size_of(Header), 2)
	testing.expect_value(t, transmute(u16)h, 0x2009)
	wire := encode_header(h)
	testing.expect_value(t, wire, [2]u8{0x09, 0x20})
	decoded, decode_err := decode_header(wire[:])
	testing.expect_value(t, decode_err, .None)
	testing.expect_value(t, decoded.kind, .Data)
	testing.expect_value(t, decoded.compressed, true)
	testing.expect_value(t, decoded.payload_size, 512)
}

@(test)
header_validates_before_narrowing :: proc(t: ^testing.T) {
	for length in ([3]int{-1, 4096, 65536}) {
		_, err := make_header(.Data, false, length)
		testing.expect_value(t, err, .Payload_Too_Large)
	}
	for length in ([2]int{0, 4095}) {
		h, err := make_header(.Ping, false, length)
		testing.expect_value(t, err, .None)
		testing.expect_value(t, int(h.payload_size), length)
	}
	_, invalid_err := make_header(Message_Kind(7), false, 0)
	testing.expect_value(t, invalid_err, .Unknown_Kind)
}

@(test)
header_rejects_short_or_unknown_input :: proc(t: ^testing.T) {
	short := [1]u8{1}
	_, short_err := decode_header(short[:])
	testing.expect_value(t, short_err, .Too_Short)
	unknown := [2]u8{7, 0}
	_, unknown_err := decode_header(unknown[:])
	testing.expect_value(t, unknown_err, .Unknown_Kind)
}

@(test)
bit_field_truncates_and_sign_extends :: proc(t: ^testing.T) {
	Signed :: bit_field u8 { delta: i8 | 5, reserved: u8 | 3 }
	value := Signed{}
	runtime_value := i8(31)
	value.delta = runtime_value
	testing.expect_value(t, value.delta, -1)
	runtime_value = -16
	value.delta = runtime_value
	testing.expect_value(t, value.delta, -16)
	h := Header{}
	too_large := u16(4096)
	h.payload_size = too_large
	testing.expect_value(t, h.payload_size, 0)
}

@(test)
or_return_propagates_failure_and_keeps_named_result :: proc(t: ^testing.T) {
	value, err := doubled_count("12")
	testing.expect_value(t, value, 24)
	testing.expect_value(t, err, .None)
	value, err = doubled_count("bad")
	testing.expect_value(t, value, 0)
	testing.expect_value(t, err, .Invalid_Number)
	value, err = doubled_count("-2")
	testing.expect_value(t, value, 0)
	testing.expect_value(t, err, .Negative_Number)
}

@(test)
or_return_supports_false_as_failure :: proc(t: ^testing.T) {
	value, ok := increment_if_integer("8")
	testing.expect_value(t, value, 9)
	testing.expect_value(t, ok, true)
	value, ok = increment_if_integer("nope")
	testing.expect_value(t, value, 0)
	testing.expect_value(t, ok, false)
}

@(test)
defer_runs_at_block_exit_in_reverse_order_with_late_values :: proc(t: ^testing.T) {
	// snippet: defer
	trace := make([dynamic]int)
	defer delete(trace)
	{
		value := 10
		defer append(&trace, value)
		defer append(&trace, 20)
		value = 30
		testing.expect_value(t, len(trace), 0)
	}
	testing.expect_value(t, len(trace), 2)
	testing.expect_value(t, trace[0], 20)
	testing.expect_value(t, trace[1], 30)
	// endsnippet: defer
}

@(test)
failure_cleans_up_and_success_transfers_ownership :: proc(t: ^testing.T) {
	items, err := parse_counts([]string{"3", "4"})
	testing.expect_value(t, err, .None)
	defer delete(items)
	testing.expect_value(t, len(items), 2)
	testing.expect_value(t, items[1], 4)
	failed, failed_err := parse_counts([]string{"3", "bad"})
	testing.expect_value(t, failed_err, .Invalid_Number)
	testing.expect_value(t, len(failed), 0)
	testing.expect_value(t, cap(failed), 0)
}

@(test)
owned_result_survives_scratch_scope :: proc(t: ^testing.T) {
	result, err := clone_via_scratch("persistent", context.allocator)
	testing.expect_value(t, err, nil)
	defer delete(result)
	testing.expect_value(t, result, "persistent")
	tiny_buffer: [1]byte
	tiny_arena: mem.Arena
	mem.arena_init(&tiny_arena, tiny_buffer[:])
	_, oom := clone_via_scratch("persistent", mem.arena_allocator(&tiny_arena))
	testing.expect(t, oom != nil)
}

@(test)
parse_counts_reports_allocator_failure :: proc(t: ^testing.T) {
	tiny_buffer: [1]byte
	tiny_arena: mem.Arena
	mem.arena_init(&tiny_arena, tiny_buffer[:])
	items, err := parse_counts([]string{"3", "4"}, mem.arena_allocator(&tiny_arena))
	testing.expect_value(t, err, .Allocation_Failed)
	testing.expect_value(t, len(items), 0)
}

@(test)
counts_validate_complete_input_and_numeric_boundaries :: proc(t: ^testing.T) {
	for text in ([]string{"", "12x", "9999999999999999999999999999999"}) {
		_, err := parse_count(text)
		testing.expect_value(t, err, .Invalid_Number)
	}
	_, too_large := parse_count("1000001")
	testing.expect_value(t, too_large, .Count_Too_Large)
	value, err := doubled_count("1000000")
	testing.expect_value(t, err, .None)
	testing.expect_value(t, value, 2000000)
	items, empty_err := parse_counts(nil)
	defer delete(items)
	testing.expect_value(t, empty_err, .None)
	testing.expect_value(t, len(items), 0)
}

@(test)
context_changes_are_scoped_and_passed_to_callees :: proc(t: ^testing.T) {
	previous := context.user_index
	{
		context.user_index = 77
		testing.expect_value(t, read_context_index(), 77)
	}
	testing.expect_value(t, context.user_index, previous)
}

@(test)
dynamic_array_copy_shares_data_but_copies_length :: proc(t: ^testing.T) {
	// snippet: dynamic-alias
	owner := make([dynamic]int, 0, 4)
	defer delete(owner)
	append(&owner, 10)
	alias := owner
	append(&owner, 20) // within capacity: intentionally does not reallocate
	testing.expect_value(t, len(owner), 2)
	testing.expect_value(t, len(alias), 1)
	alias[0] = 99
	testing.expect_value(t, owner[0], 99)
	view := owner[:]
	view[1] = 88
	testing.expect_value(t, owner[1], 88)
	// endsnippet: dynamic-alias
}

@(test)
tagged_union_has_empty_state_and_distinct_cases :: proc(t: ^testing.T) {
	event: Event
	testing.expect_value(t, event, nil)
	testing.expect_value(t, event_amount(event), 0)
	event = Resize{columns = 120}
	testing.expect_value(t, event_amount(event), 120)
	event = Input{bytes = "abc"}
	testing.expect_value(t, event_amount(event), 3)
}

@(test)
bit_set_and_enum_indexed_array :: proc(t: ^testing.T) {
	// snippet: bit-set
	allowed := Permissions{.Read, .Write}
	testing.expect(t, .Read in allowed)
	testing.expect(t, .Execute not_in allowed)
	readonly := allowed & Permissions{.Read}
	testing.expect_value(t, readonly, Permissions{.Read})
	names := [Permission]string{.Read = "r", .Write = "w", .Execute = "x"}
	testing.expect_value(t, names[.Write], "w")
	// endsnippet: bit-set
}

@(test)
soa_exposes_columns_and_preserves_element_syntax :: proc(t: ^testing.T) {
	// snippet: soa
	// snippet: soa-access
	particles: #soa[2]Particle
	particles[0] = Particle{1, 2, 3}
	particles[1] = Particle{4, 5, 6}
	particles.x[0] += 10
	// endsnippet: soa-access
	testing.expect_value(t, particles[0].x, 11)
	testing.expect_value(t, particles.x[1], 4)
	testing.expect(t, &particles[0].x == &particles.x[0])
	testing.expect(t, uintptr(&particles.x[1]) - uintptr(&particles.x[0]) == size_of(f32))
	// endsnippet: soa
}

@(test)
array_multiply_is_elementwise_matrix_multiply_is_algebraic :: proc(t: ^testing.T) {
	// snippet: array-matrix
	a := [3]f32{1, 2, 3}
	b := [3]f32{4, 5, 6}
	testing.expect_value(t, a * b, [3]f32{4, 10, 18})
	testing.expect_value(t, swizzle(a, 2, 0), [2]f32{3, 1})
	m := matrix[2, 2]f32{1, 2, 3, 4}
	n := matrix[2, 2]f32{5, 6, 7, 8}
	product := m * n
	testing.expect_value(t, product[0, 0], 19)
	testing.expect_value(t, product[1, 1], 50)
	// endsnippet: array-matrix
}

@(test)
generic_and_explicit_overloads :: proc(t: ^testing.T) {
	testing.expect_value(t, identity(User_ID(42)), User_ID(42))
	testing.expect_value(t, twice(i32(3)), i32(6))
	testing.expect_value(t, twice(f32(1.5)), f32(3))
}
