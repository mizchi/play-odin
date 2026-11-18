package practice

import "core:strconv"

parse_count :: proc(text: string) -> (value: int, err: Error) {
	consumed: int
	n, ok := strconv.parse_int(text, 10, &consumed)
	if !ok || consumed != len(text) {
		return 0, .Invalid_Number
	}
	if n < 0 {
		return 0, .Negative_Number
	}
	// Bound the example's public input before the caller doubles it.
	if n > 1_000_000 {
		return 0, .Count_Too_Large
	}
	return n, .None
}

// snippet: or-return
doubled_count :: proc(text: string) -> (result: int, err: Error) {
	n := parse_count(text) or_return
	return n * 2, .None
}
// endsnippet: or-return

// snippet: bool-return
increment_if_integer :: proc(text: string) -> (result: int, ok: bool) {
	n := strconv.parse_int(text) or_return
	if n == max(int) {
		return 0, false
	}
	return n + 1, true
}
// endsnippet: bool-return

// snippet: owned-array
// Success transfers the backing allocation to the caller. Failure returns nil.
parse_counts :: proc(texts: []string, allocator := context.allocator) -> (items: [dynamic]int, err: Error) {
	buffer, alloc_err := make([dynamic]int, 0, len(texts), allocator)
	if alloc_err != nil {
		return nil, .Allocation_Failed
	}
	defer if err != nil {
		delete(buffer)
	}
	for text in texts {
		n := parse_count(text) or_return
		_, append_err := append(&buffer, n)
		if append_err != nil {
			return nil, .Allocation_Failed
		}
	}
	return buffer, .None
}
// endsnippet: owned-array
