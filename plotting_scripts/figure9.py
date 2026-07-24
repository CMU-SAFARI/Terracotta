"""Figure 9: PRADA PuM-primitive speedup over baseline (1 bank + 32 banks).

Reads results/csv/figure9.csv ONLY; emits figures/figure9.{pdf,png}. Styled to the paper's
PowerPoint (chart9/chart10): exact series hues, per-panel y-axis range + tick spacing, UPPERCASE
operation labels, NO hatches, series order Terracotta-PRADA (left) then PRADA (right).
"""
import matplotlib.pyplot as plt

from plot_setup import (setup_style, load_figure_csv, grouped_bar, style_axes,
                        add_legend, inplot_label, save_figure, guard_run, panels_in_order)

FIG_ID = 9
YLABEL = "Speedup over Baseline"
COLORS = {"Terracotta-PRADA": "#636B2F", "PRADA": "#98A869"}
SERIES_ORDER = ["Terracotta-PRADA", "PRADA"]           # left-to-right per PPT c:ser order
XORDER = ["copy", "not", "andor", "nandnor", "xorxnor", "Average"]
XLABELS = {"copy": "COPY", "not": "NOT", "andor": "AND/OR",
           "nandnor": "NAND/NOR", "xorxnor": "XOR/XNOR", "Average": "Average"}
AXIS = {"1bank": (0, 30, 10), "32bank": (0, 400, 100)}  # (ymin, ymax, major tick)
# Paper places the bank-count label INSIDE each panel (top-right), not as a title.
INLABEL = {"1bank": "1 Bank", "32bank": "32 Banks"}


def plot():
    setup_style()
    df = load_figure_csv(FIG_ID)
    panels = panels_in_order(df)                        # 1 Bank (left), 32 Banks (right)
    fig, axes = plt.subplots(1, len(panels), figsize=(1.95 * len(panels), 1.22), squeeze=False)
    for i, (ax, panel) in enumerate(zip(axes[0], panels)):
        sub = df[df["panel"] == panel]
        grouped_bar(ax, sub, colors=COLORS, hatch=False, baseline=None,
                    x_order=XORDER, series_order=SERIES_ORDER, xlabels=XLABELS,
                    shade=["Average"])
        ymin, ymax, major = AXIS.get(panel, (None, None, None))
        style_axes(ax, ylabel=(YLABEL if i == 0 else ""), baseline=None,
                   ymin=ymin, ymax=ymax, major=major, box=True)
        inplot_label(ax, INLABEL.get(panel, panel), loc="upper right")
        ax.tick_params(axis="x", rotation=45)
    add_legend(fig, list(axes[0]), ncol=2, colors=COLORS, hatch=False,
               series_order=SERIES_ORDER)
    save_figure(fig, FIG_ID)


if __name__ == "__main__":
    guard_run(FIG_ID, plot)
