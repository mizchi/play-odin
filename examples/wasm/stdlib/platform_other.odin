#+build !wasi
#+build !js
package main

platform_checks :: proc() -> u32 { return 0 }
