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
# Presentation floor for the PRADA panel ONLY (clamp in plot(); no other panel is clamped).
# The 32-bank overhead reproduces at -0.2235% against a std-error of 0.2585%: the uncertainty
# exceeds the value itself, so it is statistically indistinguishable from 0. The negative is
# scheduling noise, not reduced work -- both configurations issue identical operation counts
# (8 iterations, ~65,575 PuM requests, matching to within 1-2), and DRAM energy here tracks
# runtime through its time-proportional background/refresh terms. Terracotta's controller- and
# command-latency overheads perturb request scheduling; under PRADA's microbenchmark-driven
# evaluation at high bank-level parallelism (32 banks), that perturbation yields a performance
# difference of the same order as simulation noise. The same effect is visible in figure9.csv as
# a +0.84% average at 32 banks, with the per-operation signs matching this figure exactly. The
# 1-bank bar (+3.29%) is the contrast case: no parallelism absorbs the added latency there, and
# Terracotta-PRADA is 3.30% slower. We therefore FLOOR the negative to 0 for display and describe
# the ~0 in the paper text.
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
            # Presentation floor, PRADA panel only (see AXIS comment above): clamp the
            # negative-but-~0 32-bank overhead to 0 and drop its error bar -- once the value is
            # floored, a whisker around it would imply a precision the displayed 0 does not have.
            # Deliberately not applied to any other technique. results/csv/figure13.csv keeps
            # both true values (-0.2235% and its 0.2585% std-error).
            floored = sub["value"] < 0
            sub.loc[floored, "value"] = 0.0
            sub.loc[floored, "err"] = float("nan")
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
