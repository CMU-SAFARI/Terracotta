"""Shared plot style (paper/PowerPoint-matched, colorblind-safe + hatch redundancy,
grayscale-legible) and reusable chart builders for the Terracotta figures.

Import from a ``figureN.py`` with ``from plot_setup import *`` (the scripts live in
``plotting_scripts/`` which matplotlib puts on ``sys.path[0]`` when run directly).

Design policy (per CLAUDE.md figure-style policy):
  * Okabe-Ito colorblind-safe palette, keyed by *display* series name so a technique's
    colour is stable across every figure it appears in.
  * Hatch is a *redundant* channel (not decorative): bars still separate in grayscale/B&W.
  * Terracotta family = warm (orange/pink); base technique / "custom" = blue; ideal = green.
  * Every figure emits BOTH a vector PDF (fonttype 42) and a 300-dpi PNG.

A figure whose CSV is not on disk yet, or is present but has only a header row, is
*skipped* with an actionable message rather than crashing the whole batch (see
``FigureDataMissing`` / ``load_figure_csv`` / ``guard_run``).
"""
import os
import re

import pandas as pd
import matplotlib as mpl

mpl.use("Agg")  # headless: no display needed on the cluster
import matplotlib.pyplot as plt  # noqa: E402
from matplotlib.patches import Patch  # noqa: E402
from matplotlib.legend_handler import HandlerTuple  # noqa: E402
from matplotlib.ticker import MultipleLocator  # noqa: E402
import math  # noqa: E402

CSV_DIR = os.environ.get("TC_CSV_DIR", "results/csv")
FIG_DIR = os.environ.get("TC_FIG_DIR", "figures")

# ---------------------------------------------------------------------------
# Palette + hatches
# ---------------------------------------------------------------------------
# Okabe-Ito colorblind-safe hexes. Series keyed by display name so colour is stable
# across figures. Base technique variants share blue; every Terracotta-* variant shares
# warm orange (pink reserved for the CGRA variant so Tables vs CGRA separate in Fig 16).
PALETTE = {
    "Baseline": "#999999",
    "Custom": "#0072B2", "PRADA": "#0072B2", "MoPAC-C": "#0072B2",
    "MASA": "#0072B2", "ChargeCache": "#0072B2", "ChargeCacheMASA": "#0072B2",
    "Terracotta": "#D55E00",
    "Terracotta-Tables": "#D55E00", "Terracotta-CGRA": "#CC79A7",
    "Terracotta-PRADA": "#D55E00", "Terracotta-MoPAC-C": "#D55E00",
    "Terracotta-MASA": "#D55E00", "Terracotta-ChargeCache": "#D55E00",
    "Terracotta-ChargeCacheMASA": "#D55E00",
    "Ideal": "#009E73", "Low-Latency DRAM": "#009E73",
    "PRAC": "#E69F00",
}

HATCHES = {
    "Baseline": "",
    "Custom": "", "PRADA": "", "MoPAC-C": "", "MASA": "", "ChargeCache": "",
    "ChargeCacheMASA": "",
    "Terracotta": "//",
    "Terracotta-Tables": "//", "Terracotta-CGRA": "xx",
    "Terracotta-PRADA": "//", "Terracotta-MoPAC-C": "//",
    "Terracotta-MASA": "//", "Terracotta-ChargeCache": "//",
    "Terracotta-ChargeCacheMASA": "//",
    "Ideal": "..", "Low-Latency DRAM": "..",
    "PRAC": "\\\\",
}

# Marker / linestyle cycles for sweep_line (redundant channels for grayscale).
_MARKERS = ["o", "s", "^", "D", "v", "P", "X", "*"]
_LINESTYLES = ["-", "--", "-.", ":"]

# Pale warm band drawn behind the GMean/Average summary cluster (and Fig 14's nominal
# latency-overhead point) to match the paper's highlight of the summary column.
SUMMARY_SHADE = "#F7EFE3"

# strip a trailing " (250)" / " (nRH=..)" parenthetical so nRH-split series (Fig 10)
# fall back to their base technique colour/hatch.
_PAREN = re.compile(r"\s*\([^)]*\)\s*$")


class FigureDataMissing(Exception):
    """Raised when a figure's CSV is absent or has no data rows yet."""


def _base_name(series):
    return _PAREN.sub("", str(series)).strip()


def color_for(series):
    if series in PALETTE:
        return PALETTE[series]
    return PALETTE.get(_base_name(series), "#444444")


def hatch_for(series):
    if series in HATCHES:
        return HATCHES[series]
    return HATCHES.get(_base_name(series), "")


# ---------------------------------------------------------------------------
# Style + IO
# ---------------------------------------------------------------------------
def setup_style():
    """Apply the paper rcParams once. Idempotent.

    Fonts/sizes are tuned so a figure generated at ~column width (~3.3in) drops into the paper
    at \\columnwidth looking like the original (paper uses ~6-7pt type in a short, wide panel).
    """
    mpl.rcParams.update({
        "figure.figsize": (3.4, 1.3),
        "font.family": "sans-serif",
        "font.size": 6.5, "axes.titlesize": 6.5, "axes.labelsize": 6.5,
        "legend.fontsize": 6, "xtick.labelsize": 6, "ytick.labelsize": 6,
        "pdf.fonttype": 42, "ps.fonttype": 42,
        "axes.axisbelow": True, "axes.linewidth": 0.6,
        # White hatch on the coloured fill (PPT pct80 / dkVert look): the pattern is drawn in
        # white while the bar keeps its black edge. hatch.color is independent of edgecolor.
        "hatch.color": "white", "hatch.linewidth": 0.6,
        "savefig.bbox": "tight", "savefig.dpi": 300,
        "figure.dpi": 120,
    })


def load_figure_csv(fig_id):
    """The ONLY input a ``figureN.py`` may read: ``results/csv/figureN.csv``.

    Raises ``FigureDataMissing`` (a skip signal, not a crash) when the file is not on
    disk or contains only a header row.
    """
    path = os.path.join(CSV_DIR, f"figure{fig_id}.csv")
    if not os.path.exists(path):
        raise FigureDataMissing(
            f"{path} not found. Generate it with:  ./parse_results.sh   "
            f"(or:  python3 -m common.figure_csv --figures {fig_id})")
    df = pd.read_csv(path)
    if df.empty:
        raise FigureDataMissing(
            f"{path} has a header but no data rows yet -- the underlying runs for "
            f"figure {fig_id} are not complete. Skipping this figure.")
    # normalise dtypes: panel/series may be read as NaN when blank -> "".
    for col in ("panel", "series"):
        if col in df.columns:
            df[col] = df[col].fillna("").astype(str)
    return df


# ---------------------------------------------------------------------------
# Ordering helpers
# ---------------------------------------------------------------------------
def _ordered(df, key, order_col, explicit):
    """Return unique values of ``key`` in plot order.

    Priority: explicit list arg > integer ``order_col`` column > first-seen order.
    """
    if explicit is not None:
        return list(explicit)
    if order_col in df.columns:
        pairs = {}
        for v, o in zip(df[key], df[order_col]):
            if v not in pairs:
                try:
                    pairs[v] = float(o)
                except (TypeError, ValueError):
                    pairs[v] = float("inf")
        return sorted(pairs, key=lambda v: (pairs[v], str(v)))
    seen = []
    for v in df[key]:
        if v not in seen:
            seen.append(v)
    return seen


# ---------------------------------------------------------------------------
# Chart builders
# ---------------------------------------------------------------------------
def grouped_bar(ax, df, *, x="x", series="series", value="value", err="err",
                x_order=None, series_order=None, baseline=1.0, width=0.8,
                colors=None, hatch=True, xlabels=None, shade=None):
    """Grouped bars: one cluster per ``x``, one bar per ``series``.

    ``colors`` (per-figure {display: hex}) overrides PALETTE; ``hatch=False`` renders solid
    bars (paper style); ``xlabels`` ({csv_x: display}) relabels the tick text; ``shade`` is a
    list/set of x-categories (e.g. ``["GMean"]``) whose cluster gets the pale ``SUMMARY_SHADE``
    background band (matching the paper's highlighted summary column). Adds a thin black edge,
    error bars from ``err`` when present, and a baseline axhline. Returns the ordered series
    display names.
    """
    xs = _ordered(df, x, "x_order", x_order)
    ss = _ordered(df, series, "series_order", series_order)
    n = max(len(ss), 1)
    bar_w = width / n
    xpos = {xv: i for i, xv in enumerate(xs)}

    # Summary-column shading (behind grid + bars). axisbelow keeps the grid readable on top.
    if shade:
        want = set(shade)
        for xv in xs:
            if xv in want:
                ax.axvspan(xpos[xv] - 0.5, xpos[xv] + 0.5, color=SUMMARY_SHADE, zorder=-5)

    for j, sname in enumerate(ss):
        sub = df[df[series] == sname]
        vals = {r[x]: r[value] for _, r in sub.iterrows()}
        errs = {}
        if err in sub.columns:
            for _, r in sub.iterrows():
                e = r[err]
                if pd.notna(e) and str(e) != "":
                    errs[r[x]] = float(e)
        offset = (j - (n - 1) / 2.0) * bar_w
        heights, positions, yerr, has_err = [], [], [], False
        for xv in xs:
            if xv in vals:
                heights.append(float(vals[xv]))
                positions.append(xpos[xv] + offset)
                if xv in errs:
                    yerr.append(errs[xv]); has_err = True
                else:
                    # NaN (not 0.0): a 0.0 error draws a zero-length whisker/cap on that bar
                    # (e.g. the GMean bar). NaN makes matplotlib skip it entirely.
                    yerr.append(float("nan"))
        if not positions:
            continue
        col = (colors or {}).get(sname) or color_for(sname)
        if isinstance(hatch, dict):        # per-series hatch (e.g. Fig 10/15 same-color pairs)
            htch = hatch.get(sname, "")
        elif hatch:
            htch = hatch_for(sname)
        else:
            htch = ""
        # Base bar: solid fill + black edge + (thin) error bars. matplotlib draws hatches in the
        # edge colour, so a white hatch on a black-edged bar needs a second, edge-only overlay.
        bars = ax.bar(positions, heights, bar_w * 0.92,
                      label=sname, color=col, edgecolor="black", linewidth=0.5,
                      yerr=(yerr if has_err else None),
                      error_kw={"elinewidth": 0.5, "capsize": 1.6, "capthick": 0.5,
                                "ecolor": "black"})
        if htch:
            z = bars[0].get_zorder() + 0.2 if len(bars) else 3
            ax.bar(positions, heights, bar_w * 0.92, color="none",
                   edgecolor="white", linewidth=0.0, hatch=htch, zorder=z)

    ax.set_xticks(range(len(xs)))
    ax.set_xticklabels([(xlabels or {}).get(xv, xv) for xv in xs])
    ax.set_xlim(-0.5, len(xs) - 0.5)
    if baseline is not None:
        ax.axhline(baseline, color="black", linewidth=0.7, zorder=0.5)
    return ss


def sweep_line(ax, df, *, x="x", series="series", value="value", err="err",
               x_order=None, series_order=None, baseline=1.0, markers=True, colors=None,
               shade=None):
    """Line-per-series sweep (e.g. Fig 14 latency-overhead sweep).

    Marker + colour + linestyle are all varied per series for grayscale legibility.
    x categories are placed on a numeric axis when they parse as numbers, else evenly.
    ``shade`` is a list of x-categories (e.g. ``["2"]``) whose column gets the pale
    ``SUMMARY_SHADE`` band -- the paper highlights the nominal 2-cycle operating point.
    Returns the ordered series list.
    """
    xs = _ordered(df, x, "x_order", x_order)
    ss = _ordered(df, series, "series_order", series_order)

    def _numeric(v):
        try:
            return float(v)
        except (TypeError, ValueError):
            return None
    numeric_xs = [_numeric(v) for v in xs]
    use_numeric = all(v is not None for v in numeric_xs) and len(xs) > 0
    xcoord = {xv: (numeric_xs[i] if use_numeric else i) for i, xv in enumerate(xs)}

    # Nominal-point shading (behind the lines). Half-step band around each shaded x.
    if shade:
        coords = sorted(xcoord.values())
        half = (coords[1] - coords[0]) / 2.0 if len(coords) > 1 else 0.5
        for xv in xs:
            if str(xv) in {str(s) for s in shade}:
                ax.axvspan(xcoord[xv] - half, xcoord[xv] + half,
                           color=SUMMARY_SHADE, zorder=-5)

    for j, sname in enumerate(ss):
        sub = df[df[series] == sname]
        pts = {r[x]: float(r[value]) for _, r in sub.iterrows()}
        errs = {}
        if err in sub.columns:
            for _, r in sub.iterrows():
                e = r[err]
                if pd.notna(e) and str(e) != "":
                    errs[r[x]] = float(e)
        xv_present = [xv for xv in xs if xv in pts]
        if not xv_present:
            continue
        X = [xcoord[xv] for xv in xv_present]
        Y = [pts[xv] for xv in xv_present]
        E = [errs.get(xv, 0.0) for xv in xv_present]
        has_err = any(v > 0 for v in E)
        ax.plot(X, Y, label=sname, color=((colors or {}).get(sname) or color_for(sname)),
                marker=(_MARKERS[j % len(_MARKERS)] if markers else None),
                markersize=4, markeredgecolor="black", markeredgewidth=0.9,
                linestyle=_LINESTYLES[j % len(_LINESTYLES)], linewidth=1.2)
        if has_err:
            ax.errorbar(X, Y, yerr=E, fmt="none", ecolor="black",
                        elinewidth=0.6, capsize=1.5)

    if use_numeric:
        ax.set_xticks([xcoord[xv] for xv in xs])
        ax.set_xticklabels(xs)
    else:
        ax.set_xticks(range(len(xs)))
        ax.set_xticklabels(xs)
    if baseline is not None:
        ax.axhline(baseline, color="black", linewidth=0.7, zorder=0.5)
    return ss


def gmean_bar(ax, df, **kw):
    """Thin wrapper over :func:`grouped_bar` for single-cluster GMean-only panels.

    Filters to the ``GMean`` x-category if present, otherwise plots the frame as given.
    """
    sub = df[df["x"] == "GMean"] if (df["x"] == "GMean").any() else df
    return grouped_bar(ax, sub, **kw)


def style_axes(ax, *, ylabel, baseline=1.0, ygrid=True, ymin=None, ymax=None, major=None,
               box=True, ylabel_fs=None):
    """Dashed grey y-grid, black baseline axhline, spines, y label.

    ``major`` sets the y-axis major-tick spacing (the paper's dedicated per-figure ticks).
    ``box=True`` (paper style) keeps all four spines so each subplot is a full frame of the
    same weight as the axes; ``box=False`` hides the top/right spines. ``ylabel_fs`` overrides
    the y-label font size (needed for long multi-line labels in short panels).
    """
    if ygrid:
        ax.grid(axis="y", linestyle="--", linewidth=0.4, color="0.7", zorder=0)
    if baseline is not None:
        ax.axhline(baseline, color="black", linewidth=0.7, zorder=0.6)
    ax.set_ylabel(ylabel, **({"fontsize": ylabel_fs} if ylabel_fs else {}))
    if box:
        for sp in ax.spines.values():
            sp.set_visible(True)
    else:
        ax.spines["top"].set_visible(False)
        ax.spines["right"].set_visible(False)
    if ymin is not None or ymax is not None:
        cur = ax.get_ylim()
        ax.set_ylim(cur[0] if ymin is None else ymin,
                    cur[1] if ymax is None else ymax)
    if major is not None:
        ax.yaxis.set_major_locator(MultipleLocator(major))


def set_hatch_linewidth(w):
    """Per-figure override of the white-hatch stroke width (dots default thin at 0.6; a figure
    with line hatches, e.g. Fig 15's vertical lines, can bump it up)."""
    mpl.rcParams["hatch.linewidth"] = w


def inplot_label(ax, text, loc="upper left"):
    """Place a small panel label INSIDE the axes (paper puts '1 Bank'/'1-core' inside the box,
    not as a title). ``loc`` in {upper left, upper right, lower left, lower right}."""
    left = "left" in loc
    top = "upper" in loc
    ax.text(0.04 if left else 0.96, 0.94 if top else 0.06, text,
            transform=ax.transAxes, ha=("left" if left else "right"),
            va=("top" if top else "bottom"), fontsize=7, zorder=6)


def border_title(ax, text, fontsize=6.5):
    """Render a technique title ON the top border of the panel (Figs 13/14/16): the white
    background of the label interrupts the top spine line, exactly as in the paper."""
    ax.set_title("")
    ax.text(0.5, 1.0, text, transform=ax.transAxes, ha="center", va="center",
            fontsize=fontsize, zorder=6,
            bbox=dict(facecolor="white", edgecolor="none", pad=1.0))


def _colmajor_order(items, ncol):
    """Reorder ``items`` (given in row-major reading order) so matplotlib's column-major
    legend fill renders them row-major (left-to-right, top-to-bottom) -- i.e. the paper's
    reading order. Returns the reordered list."""
    n = len(items)
    nrow = max(1, math.ceil(n / ncol))
    grid = list(items) + [None] * (nrow * ncol - n)
    out = []
    for c in range(ncol):
        for r in range(nrow):
            v = grid[r * ncol + c]
            if v is not None:
                out.append(v)
    return out


def add_legend(fig, ax, *, ncol=3, above=True, series_order=None, colors=None, hatch=True,
               bbox_y=1.0, row_major=False):
    """Legend pinned above the axes, deduplicated by label.

    ``ax`` may be a single Axes or a list of Axes; handles are gathered across all of them so
    multi-panel figures get one shared legend. ``bbox_y`` sets the vertical anchor (figure
    fraction) of the legend's bottom edge. ``row_major`` lays entries out left-to-right then
    top-to-bottom (paper reading order) instead of matplotlib's default column-major.

    A hatched series' swatch is a two-layer handle (solid colour + black edge, then a white
    hatch overlay) so the legend matches the bars: white pattern on the colour, black frame.
    """
    axes = ax if isinstance(ax, (list, tuple)) else [ax]
    seen = {}
    for a in axes:
        h, l = a.get_legend_handles_labels()
        for handle, label in zip(h, l):
            if label not in seen:
                seen[label] = handle
    if not seen:
        return
    labels = list(seen)
    if series_order is not None:
        rank = {s: i for i, s in enumerate(series_order)}
        labels.sort(key=lambda s: rank.get(s, len(rank)))

    def _lh(lab):
        if isinstance(hatch, dict):
            return hatch.get(lab, "")
        return hatch_for(lab) if hatch else ""

    def _handle(lab):
        col = (colors or {}).get(lab) or color_for(lab)
        base = Patch(facecolor=col, edgecolor="black", linewidth=0.5)
        h = _lh(lab)
        if h:  # white hatch overlay on top of the colour (edge-only, no fill)
            return (base, Patch(facecolor="none", edgecolor="white", linewidth=0.0, hatch=h))
        return base

    handles = [_handle(lab) for lab in labels]
    ncol_eff = min(ncol, len(labels))
    if row_major:
        handles = _colmajor_order(handles, ncol_eff)
        labels = _colmajor_order(labels, ncol_eff)
    kw = dict(ncol=ncol_eff, frameon=False, columnspacing=1.0, handlelength=1.4,
              handletextpad=0.5, borderaxespad=0.0,
              handler_map={tuple: HandlerTuple(ndivide=1, pad=0.0)})
    if above:
        fig.legend(handles, labels, loc="lower center",
                   bbox_to_anchor=(0.5, bbox_y), **kw)
    else:
        fig.legend(handles, labels, loc="upper right", **kw)


def save_figure(fig, fig_id):
    """Emit BOTH figures/figureN.pdf and figures/figureN.png (300 dpi)."""
    os.makedirs(FIG_DIR, exist_ok=True)
    for ext in ("pdf", "png"):
        out = os.path.join(FIG_DIR, f"figure{fig_id}.{ext}")
        fig.savefig(out, dpi=300, bbox_inches="tight")
    plt.close(fig)
    print(f"[figure{fig_id}] wrote {FIG_DIR}/figure{fig_id}.pdf + .png")


def guard_run(fig_id, plot_fn):
    """Run ``plot_fn`` for a figure, turning a not-ready CSV into a clean skip.

    Keeps ``plot_all_figures.sh`` (set -euo pipefail) alive when a figure's data is not
    on disk yet: the missing-data case exits 0 with an actionable message.
    """
    try:
        plot_fn()
    except FigureDataMissing as e:
        print(f"[figure{fig_id}] SKIP: {e}")


def panels_in_order(df):
    """Ordered list of panel keys via the ``panel_order`` column."""
    return _ordered(df, "panel", "panel_order", None)


def cluster_counts(df, panels, x="x"):
    """Number of distinct x-clusters in each panel (for equal per-cluster bar width)."""
    return [int(df[df["panel"] == p][x].nunique()) for p in panels]


def row_figwidth(counts, *, per_cluster=0.30, left_in=0.44, right_in=0.06, gap_in=0.27):
    """Figure width (inches) for a row of panels whose plot boxes are ``per_cluster`` wide each,
    plus fixed inch margins for the y-title/ticks (left), inter-panel y-ticks (gap), right edge.
    """
    n = len(counts)
    return left_in + right_in + gap_in * (n - 1) + per_cluster * sum(counts)


def layout_row(fig, axes, counts, *, left_in=0.44, right_in=0.06, gap_in=0.27,
               bottom=0.18, top=0.92):
    """Position a row of panels so every x-cluster gets the SAME physical width (requirement #2).

    Plot-box widths are made exactly proportional to ``counts`` by reserving fixed inch margins
    (``left_in`` for the y-axis title+ticks, ``gap_in`` between panels for the inner panels'
    y-tick labels, ``right_in`` at the edge) and splitting the remainder in proportion to the
    cluster counts. Robust to differing figure widths (unlike GridSpec ``width_ratios``, whose
    split interacts with the fixed layout margins). Call AFTER drawing the bars/axes.
    """
    W = fig.get_figwidth()
    left = left_in / W
    right = 1.0 - right_in / W
    gap = gap_in / W
    avail = (right - left) - gap * (len(counts) - 1)
    unit = avail / sum(counts)
    x = left
    for ax, c in zip(axes, counts):
        w = unit * c
        ax.set_position([x, bottom, w, top - bottom])
        x += w + gap
