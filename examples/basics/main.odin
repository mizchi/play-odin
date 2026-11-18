// snippet: basics
package main

import "core:fmt"

sum :: proc(values: []int) -> int {
	result := 0
	for value in values {
		result += value
	}
	return result
}

main :: proc() {
	values := [3]int{2, 4, 8}
	fmt.println(sum(values[:]))
}
// endsnippet: basics
