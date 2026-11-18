package main

import "core:nbio"
import wasi "core:sys/wasm/wasi"

// The fallback's next-tick queue is exercised, not its unsupported network I/O.
#assert(ODIN_OS == .WASI)
#assert(!nbio.FULLY_SUPPORTED)
completed: i32

on_ready :: proc(_: ^nbio.Operation) {
	completed = 42
}

main :: proc() {
	if err := nbio.acquire_thread_event_loop(); err != nil {
		wasi.proc_exit(1)
	}
	defer nbio.release_thread_event_loop()
	nbio.next_tick(on_ready)
	if completed != 0 {
		wasi.proc_exit(2)
	}
	if err := nbio.run(); err != nil || completed != 42 {
		wasi.proc_exit(3)
	}
	message := "Hello, Odin!\n"
	remaining := transmute([]u8)message
	for len(remaining) > 0 {
		written, err := wasi.fd_write(1, {remaining})
		if err != .SUCCESS || written == 0 {
			wasi.proc_exit(4)
		}
		remaining = remaining[int(written):]
	}
}
