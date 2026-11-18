package main

import "core:fmt"
import "../../practice"

main :: proc() {
	h, header_err := practice.make_header(.Data, true, 512)
	assert(header_err == .None)
	wire := practice.encode_header(h)
	fmt.printf("header: %04x, bytes: %02x %02x\n", transmute(u16)h, wire[0], wire[1])
	decoded, decode_err := practice.decode_header(wire[:])
	assert(decode_err == .None)
	fmt.println("decoded:", decoded.kind, decoded.compressed, decoded.payload_size)

	for text in ([]string{"12", "bad", "-2"}) {
		result, err := practice.doubled_count(text)
		fmt.println("doubled_count:", text, result, err)
	}
	counts, err := practice.parse_counts([]string{"3", "4"})
	assert(err == .None)
	defer delete(counts)
	fmt.println("owned counts:", counts)

	result, clone_err := practice.clone_via_scratch("persistent", context.allocator)
	assert(clone_err == nil)
	defer delete(result)
	fmt.println("after scratch:", result)

	particles: #soa[2]practice.Particle
	particles[0] = {1, 2, 3}
	particles[1] = {4, 5, 6}
	particles.x[0] += 10
	fmt.println("soa x:", particles.x)

	{
		value := 10
		defer fmt.println("deferred:", value)
		value = 30
	}
	fmt.println("after defer scope")

	packet_bytes := [5]u8{0x31, 0x00, 'a', 'b', 'c'}
	packet, packet_err := practice.parse_packet(packet_bytes[:])
	assert(packet_err == .None)
	fmt.println("packet:", packet.header.kind, string(packet.payload))

	width, height, valid := practice.parse_dimensions("1280x720")
	assert(valid)
	fmt.println("dimensions:", width, height)

	settings, settings_err := practice.load_settings("examples/data/settings.json")
	assert(settings_err == nil)
	fmt.println("settings:", settings.threads, settings.timeout_ms)
}
