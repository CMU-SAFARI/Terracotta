# Terracotta — hardware-overhead reproduction image
# =====================================================================
# Builds OpenROAD-Flow-Scripts (ORFS) from the exact pinned commit used for the
# paper's RTL overhead results, then bakes in the Terracotta RTL designs and the
# synthesis / power scripts. The image is self-contained: an evaluator needs only
# a container runtime (podman OR docker) — no OpenROAD toolchain on the host.
#
# Pinned ORFS: v3.0-4372-ge7ea5740a  (commit e7ea5740, 2025-12-22)
#   -> yosys 0.60 (+ yosys-slang plugin; every design uses SYNTH_HDL_FRONTEND=slang)
#   -> openroad v2.0-272x
# The public prebuilt image (openroad/orfs:latest) is NOT usable here: it ships no
# slang plugin and a drifted toolchain (openroad 26Q3 / yosys 0.67), so the tools
# are compiled from the pinned sources instead.
#
# Build context is this RTL/ directory. The ORFS submodule must be populated first:
#   git submodule update --init --recursive RTL/OpenROAD-flow-scripts
#
# Build (identical under both runtimes; classic builder, no buildx needed):
#   docker build -t terracotta-openroad:latest --build-arg THREADS=$(nproc) RTL/
#   podman build -t terracotta-openroad:latest --build-arg THREADS=$(nproc) RTL/
# =====================================================================
ARG BASE=ubuntu:22.04
FROM ${BASE}

ARG THREADS=8
ARG ORFS_VERSION=v3.0-4372-ge7ea5740a
ENV DEBIAN_FRONTEND=noninteractive
ENV ORFS_ROOT=/work/RTL/OpenROAD-flow-scripts

# NOTE ON RUNTIMES: this image builds under docker (rootful) and under rootless
# podman on hosts that have /etc/subuid ranges. It does NOT build under rootless
# podman WITHOUT subuid ranges (single-UID namespace): apt/dpkg fail to chown to
# system users (e.g. _apt, man-db's root:adm). On such hosts (e.g. a cluster login
# node lacking subuid), build with docker and `podman load` the saved tar instead
# -- see build_hw.sh and README.md.

# 1. Pinned ORFS sources (recursively populated by the reviewer's submodule update).
COPY OpenROAD-flow-scripts ${ORFS_ROOT}

# 2. Install ORFS build + runtime dependencies using ORFS's own installer.
#    Runs as root inside the build (installer detects uid 0 and skips sudo).
WORKDIR ${ORFS_ROOT}
RUN ./etc/DependencyInstaller.sh -base \
 && ./etc/DependencyInstaller.sh -common \
 && rm -rf /var/lib/apt/lists/*

# 3. Compile the pinned tools: openroad + yosys + the yosys-slang plugin.
#    --no_init: sources are already present (no git submodule fetch).
#    OpenROAD version is passed explicitly so the build does not depend on .git.
RUN if [ -d tools/yosys/abc ]; then echo "" > tools/yosys/abc/.gitcommit; fi \
 && ./build_openroad.sh --local --no_init --threads ${THREADS} \
      --openroad-args -DOPENROAD_VERSION=${ORFS_VERSION}

# 4. Bake in the Terracotta RTL designs and the synthesis / power scripts,
#    mirroring the repo's RTL/ layout so the scripts run unmodified.
COPY design                  /work/RTL/design
COPY design_chargecache      /work/RTL/design_chargecache
COPY design_masa             /work/RTL/design_masa
COPY design_mopac            /work/RTL/design_mopac
COPY design_prada            /work/RTL/design_prada
COPY design_terracotta       /work/RTL/design_terracotta
COPY run_synthesis.sh run_terracotta_synthesis.sh compute_overhead.py /work/RTL/

# 5. Make the ORFS tools available on PATH and land the user in RTL/.
ENV PATH=${ORFS_ROOT}/tools/install/OpenROAD/bin:${ORFS_ROOT}/tools/install/yosys/bin:$PATH
ENV FLOW_HOME=${ORFS_ROOT}/flow
WORKDIR /work/RTL
CMD ["/bin/bash"]
