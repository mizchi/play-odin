package practice

import "core:strconv"
import "core:strings"

// snippet: dimensions-pipeline
parse_dimensions :: proc(text: string) -> (width, height: int, ok: bool) {
	left, right := split_dimensions(text) or_return
	w := strconv.parse_int(left, 10) or_return
	h := strconv.parse_int(right, 10) or_return
	validate_dimensions(w, h) or_return
	return w, h, true
}
// endsnippet: dimensions-pipeline

@(private)
split_dimensions :: proc(text: string) -> (left, right: string, ok: bool) {
	index := strings.index_byte(text, 'x')
	if index <= 0 || index == len(text)-1 {
		return "", "", false
	}
	return text[:index], text[index+1:], true
}

@(private)
validate_dimensions :: proc(width, height: int) -> bool {
	return 0 < width && width <= 16_384 && 0 < height && height <= 16_384
}
