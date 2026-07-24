"""Figure 13: DRAM energy overhead (%) of Terracotta over the custom controllers. Styled to PPT
charts 11-18: one panel per technique, the bar colored in that technique's Terracotta hue,
per-panel y-axis + ticks (different scales), solid bars with std-error whiskers.
"""
import matplotlib.pyplot as plt

from plot_setup import (setup_style, load_figure_csv, grouped_bar, style_axes,
                        border_title, save_figure, guard_run, panels_in_order)

FIG_ID = 13
YLABEL = "DRAM energy overhead (%)\nover custom implementations"
PANEL_COLOR = {"PRADA": "#636B2F", "MoPAC-C": "#0B3041", "MASA": "#C04F15", "ChargeCache": "#78206E"}
# PRADA 32-bank overhead reproduces at -0.22%, which is (a) smaller than its own std-error
# (0.26%) -> statistically indistinguishable from 0, and (b) structurally impossible as a real
# energy saving: TerracottaDDR5PRADA's timing constraints are >= the custom DDR5PRADA model on
# every command, so the negative is scheduling noise, fully hidden by 32-bank bank-level
# parallelism (cf. the +3.29% 1-bank bar, where the same latency is exposed). We therefore FLOOR
# negative overheads to 0 for display (clamp in plot()) and describe the ~0 in the paper text.
# NOTE: results/csv/figure13.csv retains the true -0.2235% -- this floor is presentation-only.
AXIS = {"PRADA": (0.0, 4.0, 1.0), "MoPAC-C": (0.0, 0.6, 0.2),
        "MASA": (0.0, 0.6, 0.2), "ChargeCache": (0.0, 0.5, 0.1)}
# Paper renders the MoPAC-C panel in its dotted (Terracotta) identity; the others are solid.
PANEL_HATCH = {"MoPAC-C": {"Terracotta": "..."}}
# Title sits ON the top border (paper style), with (a)-(d) prefixes.
BORDER_TITLE = {"PRADA": "(a) PRADA", "MoPAC-C": "(b) MoPAC-C",
                "MASA": "(c) MASA", "ChargeCache": "(d) ChargeCache"}
XLABELS = {"1bank": "1 Bank", "32bank": "32 Banks", "single": "1-core", "four": "4-core"}


def plot():
    setup_style()
    df = load_figure_csv(FIG_ID)
    panels = panels_in_order(df)
    fig, axes = plt.subplots(1, len(panels), figsize=(1.0 * len(panels) + 0.7, 1.12),
                             squeeze=False, sharey=False)
    for i, (ax, panel) in enumerate(zip(axes[0], panels)):
        sub = df[df["panel"] == panel].copy()
        if panel == "PRADA":
            # Presentation floor (see AXIS comment above): clamp the negative-but-~0 32-bank
            # overhead to 0. The underlying CSV value is unchanged.
            sub.loc[sub["value"] < 0, "value"] = 0.0
        grouped_bar(ax, sub, colors={"Terracotta": PANEL_COLOR.get(panel, "#636B2F")},
                    hatch=PANEL_HATCH.get(panel, False), baseline=0.0, width=0.55,
                    xlabels=XLABELS)
        ymin, ymax, major = AXIS.get(panel, (0.0, None, None))
        style_axes(ax, ylabel=(YLABEL if i == 0 else ""), baseline=0.0,
                   ymin=ymin, ymax=ymax, major=major, box=True, ylabel_fs=5.0)
        if panel == "PRADA":            # two labels in a shared-width panel -> shrink to fit
            ax.tick_params(axis="x", labelsize=5.5)
        border_title(ax, BORDER_TITLE.get(panel, panel), fontsize=4.5)
    fig.subplots_adjust(top=0.84, bottom=0.20, wspace=0.72)
    save_figure(fig, FIG_ID)


if __name__ == "__main__":
    guard_run(FIG_ID, plot)
