"""Figure 13: ChargeCacheMASA composition -- speedup over baseline. Styled to PPT chart1/chart2:
exact hues, per-panel y-axis + ticks. Each Terracotta/custom pair shares a color and is
distinguished by a vertical-line (PPT dkVert) hatch on the TERRACOTTA bar, custom solid --
matching the paper/PPT. single = L/H/GMean; four = GMean only.
"""
import matplotlib.pyplot as plt

from plot_setup import (setup_style, set_hatch_linewidth, load_figure_csv, grouped_bar,
                        style_axes, add_legend, border_title, save_figure, guard_run,
                        panels_in_order, cluster_counts, row_figwidth, layout_row)

FIG_ID = 13
YLABEL = "Speedup over Baseline"
COLORS = {"Terracotta-ChargeCache": "#F6C6AD", "ChargeCache": "#F6C6AD",
          "Terracotta-MASA": "#C04F15", "MASA": "#C04F15",
          "Terracotta-ChargeCacheMASA": "#104862", "ChargeCacheMASA": "#104862"}
SERIES_ORDER = ["Terracotta-ChargeCache", "ChargeCache", "Terracotta-MASA", "MASA",
                "Terracotta-ChargeCacheMASA", "ChargeCacheMASA"]
# Legend = 3 rows x 2 cols grouped by technique. matplotlib fills column-major, so this order
# (all Terracotta-* first, then all custom) yields rows: [Terra-CC, CC], [Terra-MASA, MASA],
# [Terra-CCMASA, CCMASA].
LEGEND_ORDER = ["Terracotta-ChargeCache", "Terracotta-MASA", "Terracotta-ChargeCacheMASA",
                "ChargeCache", "MASA", "ChargeCacheMASA"]
# White diagonal hatch on the TERRACOTTA bar of each pair; custom bars are solid.
HATCH = {"Terracotta-ChargeCache": "////", "Terracotta-MASA": "////",
         "Terracotta-ChargeCacheMASA": "////"}
# Limits leave headroom above the tallest bar incl. its error bar in each panel.
AXIS = {"single": (1.0, 1.18, 0.04), "four": (1.0, 1.08, 0.02)}
BORDER_LABEL = {"single": "(a) 1-core", "four": "(b) 4-core"}


def plot():
    setup_style()
    set_hatch_linewidth(0.9)                 # keep the vertical-line hatch bold (dots stay thin)
    df = load_figure_csv(FIG_ID)
    panels = panels_in_order(df)
    counts = cluster_counts(df, panels)
    # Same bar width as Figs 11/12 (6 bars per cluster, not 3), so the plot spans the legend.
    fig, axes = plt.subplots(1, len(panels),
                             figsize=(row_figwidth(counts, per_cluster=0.6, gap_in=0.5), 1.18),
                             squeeze=False)
    for i, (ax, panel) in enumerate(zip(axes[0], panels)):
        sub = df[df["panel"] == panel]
        grouped_bar(ax, sub, colors=COLORS, hatch=HATCH, baseline=1.0,
                    series_order=SERIES_ORDER, shade=["GMean"])
        ymin, ymax, major = AXIS.get(panel, (None, None, None))
        style_axes(ax, ylabel=(YLABEL if i == 0 else ""), baseline=1.0,
                   ymin=ymin, ymax=ymax, major=major, box=True)
        border_title(ax, BORDER_LABEL.get(panel, panel))
    layout_row(fig, list(axes[0]), counts, gap_in=0.5)   # space between 1-core and 4-core boxes
    add_legend(fig, list(axes[0]), ncol=2, colors=COLORS, hatch=HATCH,
               series_order=LEGEND_ORDER)
    save_figure(fig, FIG_ID)


if __name__ == "__main__":
    guard_run(FIG_ID, plot)
