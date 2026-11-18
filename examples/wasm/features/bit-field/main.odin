package main

USE_FEATURE :: #config(USE_FEATURE, true)

when USE_FEATURE {
	Header :: bit_field u32 {
		kind:         u32  | 3,
		compressed:   bool | 1,
		payload_size: u32  | 12,
		delta:        i32  | 8,
		reserved:     u32  | 8,
	}
	#assert(size_of(Header) == size_of(u32))

	@(export)
	pack :: proc "c" (kind, compressed, length: u32, delta: i32) -> u32 {
		header := Header{kind = kind, compressed = compressed != 0, payload_size = length, delta = delta}
		return transmute(u32)header
	}

	@(export)
	payload :: proc "c" (raw: u32) -> u32 {
		header := transmute(Header)raw
		return header.payload_size
	}

	@(export)
	delta :: proc "c" (raw: u32) -> i32 {
		header := transmute(Header)raw
		return header.delta
	}
} else {
	@(export)
	pack :: proc "c" (kind, compressed, length: u32, delta: i32) -> u32 {
		return (kind & 7) | (u32(compressed != 0) << 3) | ((length & 4095) << 4) | ((u32(delta) & 255) << 16)
	}

	@(export)
	payload :: proc "c" (raw: u32) -> u32 {
		return (raw >> 4) & 4095
	}

	@(export)
	delta :: proc "c" (raw: u32) -> i32 {
		return i32(raw << 8) >> 24
	}
}
