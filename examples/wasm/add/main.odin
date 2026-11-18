package main

// A scalar C ABI lets JavaScript call this without Odin's implicit context.
@(export)
add :: proc "c" (a, b: i32) -> i32 {
	return a + b
}
