package practice

// snippet: tagged-union
event_amount :: proc(event: Event) -> int {
	switch e in event {
	case Resize:
		return e.columns
	case Input:
		return len(e.bytes)
	case nil:
		return 0
	}
	return 0
}
// endsnippet: tagged-union

// snippet: polymorphism
identity :: proc(value: $T) -> T {
	return value
}

twice_i32 :: proc(value: i32) -> i32 { return value * 2 }
twice_f32 :: proc(value: f32) -> f32 { return value * 2 }
twice :: proc{twice_i32, twice_f32}
// endsnippet: polymorphism
