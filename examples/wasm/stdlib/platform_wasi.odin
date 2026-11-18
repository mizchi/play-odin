#+build wasi
package main

import "core:os"
import "core:time"

platform_checks :: proc() -> u32 {
	path :: "/sandbox/probe.txt"
	assert(os.write_entire_file(path, "WASI file") == nil)
	defer os.remove(path)
	bytes, err := os.read_entire_file(path, context.allocator)
	assert(err == nil)
	defer delete(bytes)
	assert(string(bytes) == "WASI file")
	assert(time.now() != {})
	return 3 // File I/O and clock.
}
