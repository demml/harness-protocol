.PHONY: format lints test test.unit build clean

format:
	cargo fmt --all

lints:
	cargo clippy --workspace --all-targets --all-features -- -D warnings

test.unit:
	cargo test --workspace --all-features -- --nocapture --test-threads=1

test:
	$(MAKE) test.unit

build:
	cargo build --workspace --all-features --release

clean:
	cargo clean
