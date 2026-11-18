odin := env_var_or_default("ODIN", "odin")

default:
    @just --list

test:
    {{quote(odin)}} test practice -out:/tmp/play-odin-tests -define:ODIN_TEST_THREADS=1 -define:ODIN_TEST_FAIL_ON_BAD_MEMORY=true

test-negative:
    ODIN={{quote(odin)}} node scripts/check-negative.mjs

run:
    {{quote(odin)}} run examples/tour

check:
    {{quote(odin)}} check examples/tour -vet
    {{quote(odin)}} check examples/basics -vet
    node scripts/check-docs.mjs

verify: check test test-negative

wasm-size:
    ODIN={{quote(odin)}} node scripts/wasm-size.mjs

test-wasm: wasm-size
    node --test scripts/wasm.test.mjs scripts/wasm-features.test.mjs scripts/wasm-async.test.mjs

test-wasm-stdlib:
    ODIN={{quote(odin)}} node scripts/build-wasm-stdlib.mjs
    node --disable-warning=ExperimentalWarning --test scripts/wasm-stdlib.test.mjs

build-log-summary:
    ODIN={{quote(odin)}} node scripts/build-log-summary.mjs native

build-log-summary-wasi:
    ODIN={{quote(odin)}} node scripts/build-log-summary.mjs wasi

test-log-summary: build-log-summary build-log-summary-wasi
    node --test scripts/log-summary.test.mjs

bench-log-summary: build-log-summary build-log-summary-wasi
    ODIN={{quote(odin)}} node scripts/build-log-summary.mjs compare
    LOG_SUMMARY_COMPARE=1 node --test scripts/log-summary.test.mjs
    node scripts/bench-log-summary.mjs
