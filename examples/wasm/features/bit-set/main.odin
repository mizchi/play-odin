package main

USE_FEATURE :: #config(USE_FEATURE, true)

when USE_FEATURE {
	Permission :: enum { Read, Write, Execute, Admin }
	Permissions :: bit_set[Permission; u32]
	#assert(size_of(Permissions) == size_of(u32))

	@(export)
	update :: proc "c" (initial, grant, revoke: u32) -> u32 {
		flags := (transmute(Permissions)initial | transmute(Permissions)grant) - transmute(Permissions)revoke
		return transmute(u32)flags
	}

	@(export)
	has_execute :: proc "c" (raw: u32) -> u32 {
		flags := transmute(Permissions)raw
		return u32(.Execute in flags)
	}
} else {
	@(export)
	update :: proc "c" (initial, grant, revoke: u32) -> u32 {
		return (initial | grant) &~ revoke
	}

	@(export)
	has_execute :: proc "c" (raw: u32) -> u32 {
		return u32((raw & (1 << 2)) != 0)
	}
}
