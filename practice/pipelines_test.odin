package practice

import "core:encoding/json"
import "core:os"
import "core:strings"
import "core:testing"

@(test)
packet_pipeline_checks_each_stage_and_borrows_payload :: proc(t: ^testing.T) {
	valid := [5]u8{0x31, 0x00, 'a', 'b', 'c'}
	packet, err := parse_packet(valid[:])
	testing.expect_value(t, err, .None)
	testing.expect_value(t, packet.header.kind, .Data)
	testing.expect_value(t, string(packet.payload), "abc")
	testing.expect(t, raw_data(packet.payload) == &valid[2])

	short := [1]u8{1}
	unknown := [2]u8{7, 0}
	missing := [3]u8{0x31, 0, 'a'}
	empty := [2]u8{1, 0}
	compressed := [3]u8{0x19, 0, 'a'}
	ping_with_payload := [3]u8{0x12, 0, 'a'}
	cases := [?]struct { bytes: []u8, err: Error }{
		{short[:], .Too_Short},
		{unknown[:], .Unknown_Kind},
		{missing[:], .Too_Short},
		{empty[:], .Invalid_Payload},
		{compressed[:], .Unsupported_Compression},
		{ping_with_payload[:], .Invalid_Payload},
	}
	for test in cases {
		failed, failure := parse_packet(test.bytes)
		testing.expect_value(t, failure, test.err)
		testing.expect_value(t, len(failed.payload), 0)
	}
}

@(test)
dimensions_chain_checks_separator_both_numbers_and_bounds :: proc(t: ^testing.T) {
	width, height, ok := parse_dimensions("1280x720")
	testing.expect(t, ok)
	testing.expect_value(t, width, 1280)
	testing.expect_value(t, height, 720)
	for text in ([]string{"1280", "ax720", "1280xb", "0x720", "1280x-1", "1x2x3", "16385x1"}) {
		w, h, valid := parse_dimensions(text)
		testing.expect_value(t, valid, false)
		testing.expect_value(t, w, 0)
		testing.expect_value(t, h, 0)
	}
}

@(test)
settings_pipeline_returns_values_after_arena_is_destroyed :: proc(t: ^testing.T) {
	path := write_settings_fixture(t, `{"threads":4,"timeout_ms":1500}`)
	defer delete(path)
	defer os.remove(path)
	settings, err := load_settings(path)
	testing.expect_value(t, err, nil)
	testing.expect_value(t, settings.threads, 4)
	testing.expect_value(t, settings.timeout_ms, 1500)
}

@(test)
settings_pipeline_preserves_os_error_type :: proc(t: ^testing.T) {
	path := write_settings_fixture(t, `{}`)
	defer delete(path)
	removed := os.remove(path)
	testing.expect_value(t, removed, nil)
	settings, err := load_settings(path)
	testing.expect(t, err != nil)
	_, is_os_error := err.(os.Error)
	testing.expect(t, is_os_error)
	testing.expect_value(t, settings.threads, 0)
}

@(test)
settings_pipeline_preserves_json_error_type :: proc(t: ^testing.T) {
	path := write_settings_fixture(t, `{"threads":`)
	defer delete(path)
	defer os.remove(path)
	settings, err := load_settings(path)
	testing.expect(t, err != nil)
	_, is_json_error := err.(json.Unmarshal_Error)
	testing.expect(t, is_json_error)
	testing.expect_value(t, settings.threads, 0)
}

@(test)
settings_pipeline_validates_after_parsing :: proc(t: ^testing.T) {
	cases := [?]struct { text: string, err: Settings_Validation_Error }{
		{`{"threads":0,"timeout_ms":1500}`, .Invalid_Threads},
		{`{"threads":257,"timeout_ms":1500}`, .Invalid_Threads},
		{`{"threads":4,"timeout_ms":0}`, .Invalid_Timeout},
		{`{"threads":4,"timeout_ms":60001}`, .Invalid_Timeout},
	}
	for test in cases {
		path := write_settings_fixture(t, test.text)
		defer delete(path)
		defer os.remove(path)
		settings, err := load_settings(path)
		validation, ok := err.(Settings_Validation_Error)
		testing.expect(t, ok)
		testing.expect_value(t, validation, test.err)
		testing.expect_value(t, settings.threads, 0)
	}
}

@(test)
bit_set_supports_subset_add_and_remove :: proc(t: ^testing.T) {
	// snippet: permissions
	granted := Permissions{.Read, .Write}
	required := Permissions{.Read}
	can_read := .Read in granted
	has_all := required <= granted
	granted -= {.Write}
	granted += {.Execute}
	// endsnippet: permissions
	testing.expect(t, can_read)
	testing.expect(t, has_all)
	testing.expect(t, .Write not_in granted)
	testing.expect(t, .Execute in granted)
	testing.expect(t, !(Permissions{.Read, .Write} <= granted))
}

@(private)
write_settings_fixture :: proc(t: ^testing.T, text: string) -> string {
	file, create_err := os.create_temp_file("", "play-odin-settings-*")
	if !testing.expect_value(t, create_err, nil) { testing.fail_now(t) }
	path := strings.clone(os.name(file))
	_, write_err := os.write_string(file, text)
	close_err := os.close(file)
	testing.expect_value(t, write_err, nil)
	testing.expect_value(t, close_err, nil)
	return path
}
