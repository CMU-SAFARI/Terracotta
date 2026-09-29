"""Figure 14: DRAM energy overhead (%) of Terracotta over the custom controllers. Styled to PPT
charts 11-18: one panel per technique, the bar colored in that technique's Terracotta hue,
per-panel y-axis + ticks (different scales), solid bars with std-error whiskers.
"""
import matplotlib.pyplot as plt

from plot_setup import (setup_style, load_figure_csv, grouped_bar, style_axes,
                        panel_title, save_figure, guard_run, panels_in_order)

FIG_ID = 14
YLABEL = "DRAM Energy Overhead (%)\nover Custom Implementations"
PANEL_COLOR = {"PRADA": "#636B2F", "MoPAC-C": "#0B3041", "MASA": "#C04F15",
               "ChargeCache": "#78206E", "ChargeCacheMASA": "#104862"}
# PRADA's 32-bank overhead is negative but smaller than its own std-error, so the panel floors
# it to 0 for display (plot() below). results/csv/figure14.csv keeps the true value.
AXIS = {"PRADA": (0.0, 4.0, 1.0), "MoPAC-C": (0.0, 0.8, 0.2),
        "MASA": (0.0, 0.8, 0.2), "ChargeCache": (0.0, 0.8, 0.2),
        "ChargeCacheMASA": (0.0, 0.8, 0.2)}
# Paper renders the MoPAC-C panel in its dotted (Terracotta) identity; the others are solid.
PANEL_HATCH = {"MoPAC-C": {"Terracotta": "..."}, "ChargeCacheMASA": {"Terracotta": "////"}}
PANEL_TITLE = {"PRADA": "(a) PRADA", "MoPAC-C": "(b) MoPAC-C\n($T_{RH}$=250)",
                "MASA": "(c) MASA", "ChargeCache": "(d) ChargeCache",
                "ChargeCacheMASA": "(e) ChargeCache\nMASA"}
XLABELS = {"1bank": "1 bank", "32bank": "32 banks", "single": "1-core", "four": "4-core"}


def plot():
    setup_style()
    df = load_figure_csv(FIG_ID)
    panels = panels_in_order(df)
    fig, axes = plt.subplots(1, len(panels), figsize=(1.3 * len(panels) + 0.8, 1.30),
                             squeeze=False, sharey=False)
    for i, (ax, panel) in enumerate(zip(axes[0], panels)):
        sub = df[df["panel"] == panel].copy()
        if panel == "PRADA":
            # Floor the negative-but-~0 overhead and drop its error bar: a whisker around a
            # displayed 0 would imply a precision the floored value does not have.
            floored = sub["value"] < 0
            floored_labels = list(zip(sub.loc[floored, "x_order"], sub.loc[floored, "value"]))
            sub.loc[floored, "value"] = 0.0
            sub.loc[floored, "err"] = float("nan")
        grouped_bar(ax, sub, colors={"Terracotta": PANEL_COLOR.get(panel, "#636B2F")},
                    hatch=PANEL_HATCH.get(panel, False), baseline=0.0, width=0.55,
                    xlabels=XLABELS)
        ymin, ymax, major = AXIS.get(panel, (0.0, None, None))
        style_axes(ax, ylabel=(YLABEL if i == 0 else ""), baseline=0.0,
                   ymin=ymin, ymax=ymax, major=major, box=True, ylabel_fs=5.0)
        if panel == "PRADA" and floored_labels:
            # The floored bar reads as an empty slot, so print its true value beside it.
            ticks = ax.get_xticks()
            for x_order, value in floored_labels:
                xpos = ticks[int(x_order)] if int(x_order) < len(ticks) else int(x_order)
                ax.text(xpos, (ymax - ymin) * 0.10, f"{value:.2f}%", ha="center", va="bottom",
                        fontsize=4.5, color="#262626")
        if panel == "PRADA":            # two labels in a shared-width panel -> shrink to fit
            ax.tick_params(axis="x", labelsize=5.5)
        panel_title(ax, PANEL_TITLE.get(panel, panel), fontsize=4.5)
    fig.subplots_adjust(top=0.72, bottom=0.18, wspace=0.72)
    save_figure(fig, FIG_ID)


if __name__ == "__main__":
    guard_run(FIG_ID, plot)
