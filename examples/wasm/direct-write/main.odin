package main

import wasi "core:sys/wasm/wasi"

// No formatting, allocation, or implicit context is needed for this write.
write_message :: proc "contextless" () {
	message := "Hello, Odin!\n"
	remaining := transmute([]u8)message
	for len(remaining) > 0 {
		written, err := wasi.fd_write(1, {remaining})
		if err != .SUCCESS || written == 0 {
			wasi.proc_exit(1)
		}
		remaining = remaining[int(written):]
	}
}

// Build the same write routine with and without Odin's normal startup.
when ODIN_NO_ENTRY_POINT {
	@(export, link_name="_start")
	start :: proc "c" () {
		write_message()
	}
} else {
	main :: proc() {
		write_message()
	}
}
