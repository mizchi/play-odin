package main

import "core:bufio"
import "core:bytes"
import "core:encoding/json"
import "core:io"
import "core:mem"
import "core:strconv"
import "core:strings"
import "core:unicode/utf8"

MAX_LINE_BYTES :: 64 * 1024
MAX_JSON_DEPTH :: 64

Record :: struct {
	level:       Level,
	duration_ms: u32,
}

Level :: enum { Unknown, Info, Warn, Error }

Summary :: struct {
	valid, invalid, info, warn, error: u64,
	total_ms, max_ms: u64,
}

// The tokenizer bounds nesting and checks that exactly one object fills the
// record. The schema decoder then validates structure and decodes its fields.
has_object_frame :: proc(line: string) -> bool {
	tokens := json.make_tokenizer(line, .JSON, true)
	first, err := json.get_token(&tokens)
	if err != nil || first.kind != .Open_Brace {
		return false
	}

	depth := 1
	previous := first.kind
	for depth > 0 {
		token, token_err := json.get_token(&tokens)
		if token_err != nil || token.kind == .Invalid {
			return false
		}
		#partial switch token.kind {
		case .Open_Brace, .Open_Bracket:
			depth += 1
			if depth > MAX_JSON_DEPTH {
				return false
			}
		case .Close_Brace, .Close_Bracket:
			if previous == .Comma {
				return false
			}
			depth -= 1
		}
		previous = token.kind
	}

	tail, tail_err := json.get_token(&tokens)
	return tail.kind == .EOF && tail_err == .EOF
}

parse_record :: proc(line: []byte, allocator: mem.Allocator) -> (record: Record, ok: bool) {
	text := string(line)
	if bytes.index_byte(line, 0) >= 0 || bytes.index_byte(line, 0x0b) >= 0 ||
	   bytes.index_byte(line, 0x0c) >= 0 || !utf8.valid_string(text) ||
	   !has_object_frame(text) {
		return {}, false
	}
	parser := json.make_parser(line, .JSON, true, allocator)
	json.advance_token(&parser) // Leading '{' was verified above.
	has_duration := false
	for parser.curr_token.kind != .Close_Brace {
		key, key_err := json.parse_object_key(&parser, allocator)
		if key_err != nil || json.expect_token(&parser, .Colon) != nil {
			return {}, false
		}
		switch key {
		case "level":
			if record.level != .Unknown || parser.curr_token.kind != .String {
				return {}, false
			}
			value, err := json.parse_value(&parser)
			if err != nil {
				return {}, false
			}
			level, _ := value.(json.String)
			switch level {
			case "info":  record.level = .Info
			case "warn":  record.level = .Warn
			case "error": record.level = .Error
			case:         return {}, false
			}
		case "duration_ms":
			token := parser.curr_token
			if has_duration || token.kind != .Integer || len(token.text) > 10 {
				return {}, false
			}
			value, valid := strconv.parse_u64(token.text, 10)
			if !valid || value > u64(max(u32)) {
				return {}, false
			}
			record.duration_ms = u32(value)
			has_duration = true
			json.advance_token(&parser)
		case:
			if !json.validate_value(&parser) {
				return {}, false
			}
		}
		if !json.allow_token(&parser, .Comma) && parser.curr_token.kind != .Close_Brace {
			return {}, false
		}
	}
	return record, record.level != .Unknown && has_duration
}

add_record :: proc(summary: ^Summary, record: Record) {
	switch record.level {
	case .Info:    summary.info += 1
	case .Warn:    summary.warn += 1
	case .Error:   summary.error += 1
	case .Unknown: unreachable()
	}
	summary.valid += 1
	summary.total_ms += u64(record.duration_ms)
	summary.max_ms = max(summary.max_ms, u64(record.duration_ms))
}

summarize :: proc(input: io.Reader) -> (summary: Summary, err: io.Error) {
	buffer: [MAX_LINE_BYTES + 2]byte // Leave room for CRLF or an oversized byte.
	reader: bufio.Reader
	bufio.reader_init_with_buf(&reader, input, buffer[:])

	scratch: mem.Dynamic_Arena
	mem.dynamic_arena_init(&scratch, block_size=64 * 1024)
	defer mem.dynamic_arena_destroy(&scratch)
	allocator := mem.dynamic_arena_allocator(&scratch)

	discarding := false
	for {
		line, read_err := bufio.reader_read_slice(&reader, '\n')
		if read_err == .Buffer_Full {
			if !discarding {
				summary.invalid += 1
			}
			discarding = true
			continue
		}
		if read_err != nil && read_err != .EOF {
			return summary, read_err
		}
		if !discarding {
			had_lf := len(line) > 0 && line[len(line) - 1] == '\n'
			if had_lf {
				line = line[:len(line) - 1]
				if len(line) > 0 && line[len(line) - 1] == '\r' {
					line = line[:len(line) - 1]
				}
			}
			if len(line) > MAX_LINE_BYTES {
				summary.invalid += 1
			} else if len(strings.trim(string(line), " \t\r")) != 0 {
				if record, ok := parse_record(line, allocator); ok {
					add_record(&summary, record)
				} else {
					summary.invalid += 1
				}
				mem.dynamic_arena_reset(&scratch)
			}
		}
		discarding = false
		if read_err == .EOF {
			return summary, nil
		}
	}
}
