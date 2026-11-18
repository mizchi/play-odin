package main

main :: proc() {
	value := 42
	read := proc() -> int { return value }
	_ = read()
}
