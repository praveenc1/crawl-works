#!/bin/bash
RUST_LOG=debug cargo run --release -- -s $(find ../data -name 'CC*.gz' | head -n 1)