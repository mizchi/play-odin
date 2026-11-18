package main

User_ID :: distinct u64
main :: proc() {
	raw := u64(42)
	id: User_ID = raw
	_ = id
}
