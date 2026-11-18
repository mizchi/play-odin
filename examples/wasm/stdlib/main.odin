package main

import "base:runtime"
import "core:mem"
import "core:strings"
import "core:container/queue"
import "core:math/linalg"
import "core:encoding/json"
import "core:encoding/cbor"
import "core:compress/lz4"
import "core:text/regex"

completed, platform_result: u32
probe_seed: i32

@(export)
get_result :: proc "c" () -> u32 { return completed }

@(export)
get_platform_result :: proc "c" () -> u32 { return platform_result }

main :: proc() { _ = run_checks(3) }

@(export)
run_checks :: proc "c" (seed: i32) -> u32 {
	context = runtime.default_context()
	when ODIN_OS == .Freestanding {
		// The host calls this export directly; there is no automatic _start.
		context.allocator = runtime.default_wasm_allocator()
		runtime._startup_runtime()
		defer runtime._cleanup_runtime()
		scratch := make([]byte, 4 * 1024 * 1024)
		defer delete(scratch)
		temporary: mem.Arena
		mem.arena_init(&temporary, scratch)
		context.temp_allocator = mem.arena_allocator(&temporary)
	}
	assert(seed != 0)
	probe_seed = seed
	completed = 0
	check_memory()
	completed |= 1
	check_containers()
	completed |= 2
	check_math()
	completed |= 4
	check_json()
	completed |= 8
	check_cbor()
	completed |= 16
	check_lz4()
	completed |= 32
	check_regex()
	completed |= 64
	check_strings()
	completed |= 128
	platform_result = platform_checks()
	return completed
}

check_memory :: proc() {
	buffer: [1024]byte
	arena: mem.Arena
	mem.arena_init(&arena, buffer[:])
	items := make([]u32, 4, allocator=mem.arena_allocator(&arena))
	items[3] = 42
	assert(items[3] == 42)
	values := make([dynamic]int)
	defer delete(values)
	append(&values, 20, 22)
	assert(values[0] + values[1] == 42)
}

check_containers :: proc() {
	values := make(map[string]int)
	defer delete(values)
	values["answer"] = 42
	assert(values["answer"] == 42)
	q: queue.Queue(int)
	assert(queue.init(&q, 4) == nil)
	defer queue.destroy(&q)
	ok, err := queue.push_back(&q, 42)
	assert(ok && err == nil)
	assert(queue.pop_front(&q) == 42)
}

check_math :: proc() {
	x := f32(probe_seed)
	v := linalg.normalize([3]f32{x, 0, 4})
	assert(abs(linalg.length(v) - 1) < 0.000001)
	m := matrix[2, 2]f32{x, 0, 0, 4}
	inverse := linalg.inverse(m)
	assert(abs(inverse[0, 0] - 1/x) < 0.000001 && inverse[1, 1] == 0.25)
}

Config :: struct { count: i32 }

check_json :: proc() {
	encoded, err := json.marshal(Config{42})
	assert(err == nil)
	defer delete(encoded)
	decoded: Config
	assert(json.unmarshal(encoded, &decoded) == nil)
	assert(decoded.count == 42)
}

check_cbor :: proc() {
	encoded, err := cbor.marshal(Config{42})
	assert(err == nil)
	defer delete(encoded)
	decoded: Config
	assert(cbor.unmarshal(encoded, &decoded) == nil)
	assert(decoded.count == 42)
}

check_lz4 :: proc() {
	text := "Odin Odin Odin Odin Odin Odin Odin Odin Odin Odin Odin Odin"
	input := transmute([]u8)text
	packed := make([dynamic]u8)
	defer delete(packed)
	assert(lz4.compress_block(&packed, input) == nil)
	output := make([]u8, len(input))
	defer delete(output)
	written, err := lz4.decompress_block(output, packed[:])
	assert(err == nil && written == len(input) && string(output) == text)
}

check_regex :: proc() {
	r, err := regex.create("^[a-z]+[0-9]+$")
	assert(err == nil)
	defer regex.destroy(r)
	capture, matched := regex.match(r, "odin42")
	defer regex.destroy(capture)
	assert(matched)
}

check_strings :: proc() {
	text := strings.clone("Odin")
	defer delete(text)
	assert(text == "Odin" && strings.contains(text, "di"))
}
