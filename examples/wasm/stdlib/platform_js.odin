#+build js
package main

import "core:time"

platform_checks :: proc() -> u32 {
	assert(time.now() != {})
	assert(time.tick_now() != {})
	return 2 // Clock, supplied by the JS host.
}
