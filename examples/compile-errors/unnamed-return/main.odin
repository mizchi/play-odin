package main

Error :: enum { None, Failed }
read :: proc() -> (int, Error) { return 1, .None }
broken :: proc() -> (int, Error) {
	value := read() or_return
	return value, .None
}
main :: proc() { _, _ = broken() }
