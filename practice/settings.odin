package practice

import "core:encoding/json"
import "core:os"
import vmem "core:mem/virtual"

// snippet: settings-pipeline
load_settings :: proc(path: string) -> (settings: Settings, err: Load_Error) {
	arena: vmem.Arena
	vmem.arena_init_growing(&arena) or_return
	defer vmem.arena_destroy(&arena)
	allocator := vmem.arena_allocator(&arena)

	bytes := os.read_entire_file(path, allocator) or_return
	candidate: Settings
	json.unmarshal(bytes, &candidate, allocator=allocator) or_return
	validate_settings(candidate) or_return
	return Settings{threads=candidate.threads, timeout_ms=candidate.timeout_ms}, nil
}
// endsnippet: settings-pipeline

@(private)
validate_settings :: proc(settings: Settings) -> Settings_Validation_Error {
	if settings.threads < 1 || settings.threads > 256 {
		return .Invalid_Threads
	}
	if settings.timeout_ms < 1 || settings.timeout_ms > 60_000 {
		return .Invalid_Timeout
	}
	return .None
}
