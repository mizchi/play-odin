package main

import "core:os"

main :: proc() {
	message :: "Hello, Odin!\n"
	n, err := os.write_string(os.stdout, message)
	if err != nil || n != len(message) {
		os.exit(1)
	}
}
