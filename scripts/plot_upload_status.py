#!/usr/bin/env python3
# -*- coding: utf-8 -*-

import matplotlib.pyplot as plt
import os
import sys
from collections import Counter

def main(result_folder):
    # Input files (expected names)
    files = {
        "2M": os.path.join(result_folder, "sda_cli_2M.upload_status.txt"),
        "20M": os.path.join(result_folder, "sda_cli_20M.upload_status.txt"),
        "200M": os.path.join(result_folder, "sda_cli_200M.upload_status.txt"),
    }

    categories = ["SUCCESS", "413-ERROR", "500-ERROR", "503-ERROR", "OTHER-ERROR"]
    counts_by_size = {}

    for label, filepath in files.items():
        if not os.path.exists(filepath):
            print(f"Warning: {filepath} not found, skipping")
            continue
        with open(filepath) as f:
            statuses = [line.strip() for line in f if line.strip()]
        count = Counter(statuses)
        counts_by_size[label] = [count.get(cat, 0) for cat in categories]

    if not counts_by_size:
        print("No valid input files found. Exiting.")
        return

    # Plot stacked bars
    sizes = list(counts_by_size.keys())
    bottom = [0] * len(sizes)

    fig, ax = plt.subplots(figsize=(8, 6))

    bar_width = 0.6  # make bars narrower
    positions = range(len(sizes))

    for i, cat in enumerate(categories):
        values = [counts_by_size[size][i] for size in sizes]
        ax.bar(
            positions,
            values,
            bar_width,
            bottom=bottom,
            label=cat
        )
        bottom = [b + v for b, v in zip(bottom, values)]

    ax.set_xticks(positions)
    ax.set_xticklabels(sizes)

    ax.set_ylabel("Count")
    ax.set_title("Upload Status by Dataset Size (Stacked)")

    # Move legend outside the plot
    ax.legend(title="Status", bbox_to_anchor=(1.05, 1), loc="upper left")

    plt.tight_layout()

    # Save plots
    pdf_path = os.path.join(result_folder, "plot_upload_status.pdf")
    png_path = os.path.join(result_folder, "plot_upload_status.png")
    plt.savefig(pdf_path, bbox_inches="tight")
    plt.savefig(png_path, dpi=300, bbox_inches="tight")

    print(f"Plots saved to:\n  {pdf_path}\n  {png_path}")

if __name__ == "__main__":
    if len(sys.argv) != 2:
        print("Usage: python plot_upload_status.py <result_folder>")
        sys.exit(1)

    main(sys.argv[1])
