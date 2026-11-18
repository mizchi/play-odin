package main

USE_FEATURE :: #config(USE_FEATURE, true)
state: i32

record :: proc "contextless" (value: i32) {
	state = state * 10 + value
}

@(export)
read_state :: proc "c" () -> i32 {
	return state
}

when USE_FEATURE {
	@(export)
	evaluate :: proc "c" (input: i32, stop: u32) -> i32 {
		state = 0
		defer record(input)
		{
			marker := i32(2)
			defer record(marker)
			if stop != 0 {
				return input + 10
			}
			marker = 4
			record(3)
		}
		return input + 20
	}
} else {
	@(export)
	evaluate :: proc "c" (input: i32, stop: u32) -> i32 {
		state = 0
		if stop != 0 {
			record(2)
			record(input)
			return input + 10
		}
		record(3)
		record(4)
		record(input)
		return input + 20
	}
}
