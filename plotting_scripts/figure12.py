"""Figure 12: ChargeCache speedup over baseline (single- and four-core). Styled to PPT
chart3/chart4: exact hues, per-panel y-axis + ticks, no hatches.
"""
import matplotlib.pyplot as plt

from plot_setup import (setup_style, load_figure_csv, grouped_bar, style_axes,
                        add_legend, inplot_label, save_figure, guard_run,
                        panels_in_order, cluster_counts, row_figwidth, layout_row)

FIG_ID = 12
YLABEL = "Speedup over Baseline"
COLORS = {"Terracotta-ChargeCache": "#78206E", "ChargeCache": "#F2CFEE",
          "Low-Latency DRAM": "#D1D1D1"}
SERIES_ORDER = ["Terracotta-ChargeCache", "ChargeCache", "Low-Latency DRAM"]
AXIS = {"single": (1.0, 1.08, 0.01), "four": (1.0, 1.05, 0.01)}
INLABEL = {"single": "1-core", "four": "4-core"}


def plot():
    setup_style()
    df = load_figure_csv(FIG_ID)
    panels = panels_in_order(df)
    counts = cluster_counts(df, panels)
    fig, axes = plt.subplots(1, len(panels), figsize=(row_figwidth(counts), 1.02),
                             squeeze=False)
    for i, (ax, panel) in enumerate(zip(axes[0], panels)):
        sub = df[df["panel"] == panel]
        grouped_bar(ax, sub, colors=COLORS, hatch=False, baseline=1.0,
                    series_order=SERIES_ORDER, shade=["GMean"])
        ymin, ymax, major = AXIS.get(panel, (None, None, None))
        style_axes(ax, ylabel=(YLABEL if i == 0 else ""), baseline=1.0,
                   ymin=ymin, ymax=ymax, major=major, box=True)
        inplot_label(ax, INLABEL.get(panel, panel), loc="upper left")
    layout_row(fig, list(axes[0]), counts, gap_in=0.42)   # space between the two boxes
    add_legend(fig, list(axes[0]), ncol=3, colors=COLORS, hatch=False, series_order=SERIES_ORDER)
    save_figure(fig, FIG_ID)


if __name__ == "__main__":
    guard_run(FIG_ID, plot)
