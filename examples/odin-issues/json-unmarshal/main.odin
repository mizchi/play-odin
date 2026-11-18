package main

import "core:encoding/json"
import "core:fmt"

Record :: struct { duration_ms: u32 }

main :: proc() {
	inputs := [?]string{
		`{"duration_ms":4294967295}`,
		`{"duration_ms":-1}`,
		`{"duration_ms":4294967296}`,
		`{"duration_ms":170141183460469231731687303715884105728}`,
		`{"duration_ms":1} {}`,
	}
	for input in inputs {
		value: Record
		err := json.unmarshal_string(input, &value, spec=.JSON)
		fmt.printf("%s -> value=%d success=%v\n", input, value.duration_ms, err == nil)
	}
}
