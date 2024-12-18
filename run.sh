#!/bin/bash
RUST_LOG=info cargo run --release -- -s $(find ../data -name 'CC*.gz' | head -n 1)