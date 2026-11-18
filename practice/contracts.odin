package practice

Message_Kind :: enum u8 { Data = 1, Ping = 2 }

// snippet: header
Header :: bit_field u16 {
	kind:         Message_Kind | 3,
	compressed:   bool         | 1,
	payload_size: u16          | 12,
}
// endsnippet: header

Error :: enum {
	None,
	Too_Short,
	Unknown_Kind,
	Payload_Too_Large,
	Invalid_Number,
	Negative_Number,
	Count_Too_Large,
	Allocation_Failed,
	Invalid_Payload,
	Unsupported_Compression,
}

// snippet: permission-types
Permission :: enum { Read, Write, Execute }
Permissions :: bit_set[Permission; u8]
// endsnippet: permission-types

Packet :: struct {
	header: Header,
	payload: []u8, // Borrows the input buffer; does not own it.
}

Resize :: struct { columns: int }
Input :: struct { bytes: string }
Event :: union { Resize, Input }

Particle :: struct { x, y, z: f32 }
User_ID :: distinct u64

// These are contracts of the examples, not a production networking protocol.
#assert(size_of(Header) == 2)
#assert(User_ID != u64)
