package practice

import "core:encoding/json"
import "core:mem"
import "core:os"

// snippet: settings-types
Settings :: struct {
	threads: int,
	timeout_ms: int,
}

Settings_Validation_Error :: enum { None, Invalid_Threads, Invalid_Timeout }

Load_Error :: union {
	mem.Allocator_Error,
	os.Error,
	json.Unmarshal_Error,
	Settings_Validation_Error,
}
// endsnippet: settings-types
