"""Figure 10: MoPAC-C mitigation performance (single- and four-core). Styled to PPT
chart7/chart8: exact hues (one per nRH point), per-panel y-axis + ticks. Each Terracotta/custom
pair shares a color and is distinguished by a dotted (pct80) hatch on the TERRACOTTA bar, with
the custom MoPAC-C bar solid -- matching the paper/PPT.
"""
import matplotlib.pyplot as plt

from plot_setup import (setup_style, load_figure_csv, grouped_bar, style_axes,
                        add_legend, inplot_label, save_figure, guard_run,
                        panels_in_order, cluster_counts, row_figwidth, layout_row)

FIG_ID = 10
YLABEL = "Slowdown over Baseline"
# One color per nRH point; Terracotta-<nRH> and MoPAC-<nRH> share it.
COLORS = {"Terracotta-250": "#0B3041", "MoPAC-250": "#0B3041",
          "Terracotta-500": "#4E95D9", "MoPAC-500": "#4E95D9",
          "Terracotta-1000": "#0B76A0", "MoPAC-1000": "#0B76A0",
          "PRAC": "#D1D1D1"}
SERIES_ORDER = ["Terracotta-250", "MoPAC-250", "Terracotta-500", "MoPAC-500",
                "Terracotta-1000", "MoPAC-1000", "PRAC"]
# White dotted (PPT pct80) hatch on the TERRACOTTA bar of each same-color pair; custom solid.
HATCH = {"Terracotta-250": "...", "Terracotta-500": "...", "Terracotta-1000": "..."}
AXIS = {"single": (0.88, 1.0, 0.02), "four": (0.91, 1.0, 0.01)}
INLABEL = {"single": "1-core", "four": "4-core"}


def plot():
    setup_style()
    df = load_figure_csv(FIG_ID)
    df = df.copy()
    df["err"] = ""            # Fig 10 shows NO error bars (user: they looked cluttered)
    panels = panels_in_order(df)
    counts = cluster_counts(df, panels)
    fig, axes = plt.subplots(1, len(panels), figsize=(row_figwidth(counts), 1.28),
                             squeeze=False)
    for i, (ax, panel) in enumerate(zip(axes[0], panels)):
        sub = df[df["panel"] == panel]
        grouped_bar(ax, sub, colors=COLORS, hatch=HATCH, baseline=1.0,
                    series_order=SERIES_ORDER, shade=["GMean"])
        ymin, ymax, major = AXIS.get(panel, (None, None, None))
        style_axes(ax, ylabel=(YLABEL if i == 0 else ""), baseline=1.0,
                   ymin=ymin, ymax=ymax, major=major, box=True)
        inplot_label(ax, INLABEL.get(panel, panel), loc="upper left")
    # Extra inter-panel gap (avoid aliasing the two boxes); legend pulled down into the top band.
    layout_row(fig, list(axes[0]), counts, gap_in=0.42, top=0.70)
    # Row-major legend (paper layout): row1 = Terracotta-250, MoPAC-250, Terracotta-500,
    # MoPAC-500; row2 = Terracotta-1000, MoPAC-1000, PRAC -- nRH pairs adjacent.
    add_legend(fig, list(axes[0]), ncol=4, colors=COLORS, hatch=HATCH,
               series_order=SERIES_ORDER, bbox_y=0.71, row_major=True)
    save_figure(fig, FIG_ID)


if __name__ == "__main__":
    guard_run(FIG_ID, plot)
