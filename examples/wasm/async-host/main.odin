package main

USE_CALLBACKS :: #config(USE_CALLBACKS, false)

// The host must return from request before invoking complete. This sample has
// one task slot; a new begin replaces it, and cancellation ignores later replies.
foreign import host "host"
foreign host {
	request :: proc "c" (step, ticket: u32, value: i32) ---
}

Phase :: enum u32 { Idle, First, Second, Done, Failed, Cancelled }
Task :: struct { phase: Phase, ticket: u32, value: i32 }
task: Task

when USE_CALLBACKS {
	Continuation :: #type proc "contextless" (value: i32)
	next: Continuation

	after_first :: proc "contextless" (value: i32) {
		task.phase = .Second
		next = after_second
		request(1, task.ticket, value)
	}

	after_second :: proc "contextless" (value: i32) {
		task.value = value
		task.phase = .Done
		next = nil
	}
}

@(export)
begin :: proc "c" (input: i32) -> u32 {
	task.ticket += 1
	task.phase = .First
	task.value = 0
	when USE_CALLBACKS {
		next = after_first
	}
	request(0, task.ticket, input)
	return task.ticket
}

@(export)
complete :: proc "c" (ticket, step: u32, value: i32, err: u32) {
	if ticket != task.ticket || (task.phase != .First && task.phase != .Second) {
		return
	}
	if step != u32(task.phase) - 1 {
		return
	}
	if err != 0 {
		task.phase = .Failed
		when USE_CALLBACKS {
			next = nil
		}
		return
	}
	when USE_CALLBACKS {
		next(value)
	} else {
		switch task.phase {
		case .First:
			task.phase = .Second
			request(1, task.ticket, value)
		case .Second:
			task.value = value
			task.phase = .Done
		case .Idle, .Done, .Failed, .Cancelled:
		}
	}
}

@(export)
cancel :: proc "c" () {
	if task.phase == .First || task.phase == .Second {
		task.phase = .Cancelled
		when USE_CALLBACKS {
			next = nil
		}
	}
}

@(export)
status :: proc "c" () -> u32 {
	return u32(task.phase)
}

@(export)
result :: proc "c" () -> i32 {
	return task.value
}
