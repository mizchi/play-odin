package practice

// snippet: packet-pipeline
parse_packet :: proc(bytes: []u8) -> (packet: Packet, err: Error) {
	header := decode_header(bytes) or_return
	payload := take_payload(bytes[2:], int(header.payload_size)) or_return
	validate_payload(header, payload) or_return
	return Packet{header, payload}, .None
}
// endsnippet: packet-pipeline

@(private)
take_payload :: proc(bytes: []u8, size: int) -> (payload: []u8, err: Error) {
	if len(bytes) < size {
		return nil, .Too_Short
	}
	return bytes[:size], .None
}

@(private)
validate_payload :: proc(header: Header, payload: []u8) -> Error {
	if header.compressed {
		return .Unsupported_Compression
	}
	if (header.kind == .Data && len(payload) == 0) ||
	   (header.kind == .Ping && len(payload) != 0) {
		return .Invalid_Payload
	}
	return .None
}
