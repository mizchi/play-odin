package main

import "core:os"
import "core:fmt"
import "core:strconv"

USE_FMT :: #config(LOG_SUMMARY_USE_FMT, false)
_ :: fmt
_ :: strconv

USAGE :: "Usage: log-summary < events.jsonl\n"

main :: proc() {
	if len(os.args) == 2 && (os.args[1] == "--help" || os.args[1] == "-h") {
		if !write_all(os.stdout, USAGE) {
			os.exit(1)
		}
		return
	}
	if len(os.args) != 1 {
		_ = write_all(os.stderr, USAGE)
		os.exit(2)
	}

	summary, err := summarize(os.to_reader(os.stdin))
	if err != nil {
		_ = write_all(os.stderr, "log-summary: failed to read stdin\n")
		os.exit(1)
	}
	buffer: [256]byte
	if !write_all(os.stdout, format_summary(&buffer, summary)) {
		_ = write_all(os.stderr, "log-summary: failed to write stdout\n")
		os.exit(1)
	}
}

write_all :: proc(file: ^os.File, data: string) -> bool {
	remaining := data
	for len(remaining) > 0 {
		n, err := os.write_string(file, remaining)
		if err != nil || n <= 0 {
			return false
		}
		remaining = remaining[n:]
	}
	return true
}

// Stable output order and only fixed field names and decimal integers.
format_summary :: proc(buffer: ^[256]byte, summary: Summary) -> string {
	fields := [?]struct { prefix: string, value: u64 }{
		{`{"valid":`, summary.valid},
		{`,"invalid":`, summary.invalid},
		{`,"info":`, summary.info},
		{`,"warn":`, summary.warn},
		{`,"error":`, summary.error},
		{`,"total_ms":`, summary.total_ms},
		{`,"max_ms":`, summary.max_ms},
	}
	offset := 0
	for field in fields {
		offset += copy(buffer[offset:], field.prefix)
		when USE_FMT {
			digits := fmt.bprintf(buffer[offset:], "%d", field.value)
		} else {
			digits := strconv.write_uint(buffer[offset:], field.value, 10)
		}
		offset += len(digits)
	}
	offset += copy(buffer[offset:], "}\n")
	return string(buffer[:offset])
}
