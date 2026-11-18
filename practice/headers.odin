package practice

// snippet: make-header
make_header :: proc(kind: Message_Kind, compressed: bool, payload_size: int) -> (h: Header, err: Error) {
	if kind != .Data && kind != .Ping {
		return {}, .Unknown_Kind
	}
	if payload_size < 0 || payload_size > 4095 {
		return {}, .Payload_Too_Large
	}
	h = Header{kind = kind, compressed = compressed, payload_size = u16(payload_size)}
	return
}
// endsnippet: make-header

// snippet: wire
encode_header :: proc(h: Header) -> [2]u8 {
	word := transmute(u16)h
	return {u8(word & 0xff), u8(word >> 8)}
}

decode_header :: proc(bytes: []u8) -> (h: Header, err: Error) {
	if len(bytes) < 2 {
		return {}, .Too_Short
	}
	word := u16(bytes[0]) | (u16(bytes[1]) << 8)
	h = transmute(Header)word
	if h.kind != .Data && h.kind != .Ping {
		return {}, .Unknown_Kind
	}
	return
}
// endsnippet: wire
