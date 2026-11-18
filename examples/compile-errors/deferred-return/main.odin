package main

broken :: proc() -> (value: int) {
	value = 1
	defer value = 2
	return
}
main :: proc() { _ = broken() }
