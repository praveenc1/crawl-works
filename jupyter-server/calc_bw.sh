#!/usr/bin/env python3

import subprocess
import time
import re
from datetime import datetime

def get_network_stats(interface):
    try:
        # Run the `ip -s link show <interface>` command
        output = subprocess.check_output(f"ip -s link show {interface}", shell=True, text=True)

        # Extract RX and TX bytes from the appropriate lines
        lines = output.splitlines()
        for i, line in enumerate(lines):
            if "RX:" in line:
                rx_line = lines[i + 1].strip()
            if "TX:" in line:
                tx_line = lines[i + 1].strip()

        # Extract the first number (bytes) from the RX and TX lines
        rx_bytes = int(rx_line.split()[0])
        tx_bytes = int(tx_line.split()[0])

        return rx_bytes, tx_bytes

    except Exception as e:
        print(f"Error getting network stats: {e}")
        return None, None

def calculate_bandwidth(prev_rx, prev_tx, curr_rx, curr_tx, interval):
    # Calculate deltas for RX and TX bytes
    rx_delta = curr_rx - prev_rx
    tx_delta = curr_tx - prev_tx

    # Convert bytes to gigabits
    rx_gbps = (rx_delta * 8) / 1e9 / interval  # RX in Gbps
    tx_gbps = (tx_delta * 8) / 1e9 / interval  # TX in Gbps

    return rx_gbps, tx_gbps

def main():
    interface = "ens3"  # Replace with your network interface
    interval = 1  # Interval in seconds

    print(f"Monitoring network bandwidth on interface {interface}...")

    # Get the initial RX/TX stats
    prev_rx, prev_tx = get_network_stats(interface)

    if prev_rx is None or prev_tx is None:
        print("Failed to retrieve initial network stats. Exiting.")
        return

    while True:
        time.sleep(interval)

        # Get the current RX/TX stats
        curr_rx, curr_tx = get_network_stats(interface)

        if curr_rx is None or curr_tx is None:
            print("Failed to retrieve network stats. Skipping iteration.")
            continue

        # Debug: Log raw RX and TX bytes
        #print(f"DEBUG: Prev RX: {prev_rx}, Prev TX: {prev_tx}")
        #print(f"DEBUG: Curr RX: {curr_rx}, Curr TX: {curr_tx}")

        # Calculate bandwidth usage
        rx_gbps, tx_gbps = calculate_bandwidth(prev_rx, prev_tx, curr_rx, curr_tx, interval)

        # Print the results
        timestamp = datetime.now().strftime('%Y-%m-%d %H:%M:%S')
        print(f"{timestamp} - RX: {rx_gbps:.3f} Gbps, TX: {tx_gbps:.3f} Gbps")

        # Update previous stats
        prev_rx, prev_tx = curr_rx, curr_tx

if __name__ == "__main__":
    main()

