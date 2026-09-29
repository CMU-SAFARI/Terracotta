"""Figure 16 (paper §8.7): Terracotta-CGRA vs Terracotta-Tables vs Custom. Styled to PPT
chart23-26: grayscale (CGRA lightest, Custom darkest), per-panel y-axis + ticks, GMean-only bars.
"""
import matplotlib.pyplot as plt

from plot_setup import (setup_style, load_figure_csv, grouped_bar, style_axes,
                        add_legend, panel_title, save_figure, guard_run, panels_in_order)

FIG_ID = 16
COLORS = {"Terracotta-CGRA": "#D1D1D1", "Terracotta-Tables": "#747474", "Custom": "#262626"}
SERIES_ORDER = ["Terracotta-CGRA", "Terracotta-Tables", "Custom"]
AXIS = {"PRADA": (0.0, 125.0, 50.0), "MoPAC-C": (0.92, 1.0, 0.02), "MASA": (1.0, 1.08, 0.02),
        "ChargeCache": (1.0, 1.08, 0.02), "ChargeCacheMASA": (1.0, 1.08, 0.02)}
BASELINE = {"PRADA": None, "MoPAC-C": 1.0, "MASA": 1.0,
            "ChargeCache": 1.0, "ChargeCacheMASA": 1.0}
PANEL_TITLE = {"PRADA": "(a) PRADA", "MoPAC-C": "(b) MoPAC-C\n($T_{RH}$=250)", "MASA": "(c) MASA",
                "ChargeCache": "(d) ChargeCache", "ChargeCacheMASA": "(e) ChargeCache\nMASA"}
YLABEL_PANEL = {"PRADA": "System Performance\nNormalized to Baseline"}
# Four-core CPU panels carry a single "4-core" cluster; PRADA is the 32-bank PuM run.
XLABELS_CPU = {"GMean": "4-core"}


def plot():
    setup_style()
    df = load_figure_csv(FIG_ID)
    panels = panels_in_order(df)
    fig, axes = plt.subplots(1, len(panels), figsize=(1.12 * len(panels) + 0.7, 1.34),
                             squeeze=False, sharey=False)
    for ax, panel in zip(axes[0], panels):
        sub = df[df["panel"] == panel]
        base = BASELINE.get(panel, 1.0)
        grouped_bar(ax, sub, colors=COLORS, hatch=False, baseline=base,
                    series_order=SERIES_ORDER,
                    xlabels=(None if panel == "PRADA" else XLABELS_CPU))
        ymin, ymax, major = AXIS.get(panel, (None, None, None))
        style_axes(ax, ylabel=YLABEL_PANEL.get(panel, ""), baseline=base,
                   ymin=ymin, ymax=ymax, major=major, box=True)
        panel_title(ax, PANEL_TITLE.get(panel, panel), fontsize=4.5)
    fig.subplots_adjust(top=0.68, bottom=0.14, wspace=0.74)
    add_legend(fig, list(axes[0]), ncol=3, colors=COLORS, hatch=False,
               series_order=SERIES_ORDER, bbox_y=0.90)
    save_figure(fig, FIG_ID)


if __name__ == "__main__":
    guard_run(FIG_ID, plot)
