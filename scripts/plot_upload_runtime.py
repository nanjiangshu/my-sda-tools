import os
import sys

import matplotlib.pyplot as plt
import numpy as np


def load_runtime_file(filepath):
    """Load runtimes from a text file (one float per line)."""
    with open(filepath, "r") as f:
        return [float(line.strip()) for line in f if line.strip()]

def main(result_folder):
    sizes = ["2M", "20M", "200M"]
    data = {}
    
    for size in sizes:
        filename = os.path.join(result_folder, f"sda_cli_{size}.runtime.txt")
        if os.path.exists(filename):
            data[size] = load_runtime_file(filename)
        else:
            print(f"Warning: {filename} not found, skipping")
            data[size] = []

    # Prepare plot
    fig, ax = plt.subplots(figsize=(8, 6))

    box_data = [data[size] for size in sizes if data[size]]
    labels = [size for size in sizes if data[size]]

    bp = ax.boxplot(box_data, tick_labels=labels, patch_artist=True, showmeans=True)

    # Set log scale
    ax.set_yscale("log")
    ax.set_ylabel("Runtime (seconds, log scale)")
    ax.set_title("Runtime Distribution by File Size")

    # Annotate above boxes
    for i, size in enumerate(labels):
        values = data[size]
        if not values:
            continue
        mean_val = np.mean(values)
        median_val = np.median(values)
        n = len(values)
        y_pos = max(values) * 1.2  # a bit above the max value
        ax.text(
            i + 1, y_pos,
            f"(mean: {mean_val:.2f}; median: {median_val:.2f}; n={n})",
            ha="center", va="bottom", fontsize=9, rotation=0
        )

    # Save plot
    out_pdf = os.path.join(result_folder, "plot_runtime_boxplot.pdf")
    out_png = os.path.join(result_folder, "plot_runtime_boxplot.png")
    plt.savefig(out_pdf)
    plt.savefig(out_png, dpi=300)
    print(f"Saved box plot to {out_pdf} and {out_png}")

if __name__ == "__main__":
    if len(sys.argv) < 2:
        print("Usage: python plot_runtime_boxplot.py <result_folder>")
        sys.exit(1)
    main(sys.argv[1])
