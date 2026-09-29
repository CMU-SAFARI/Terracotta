# Base pinned to Ubuntu 22.04 (Jammy) to mirror the reference host: apt's
# build-essential + cmake install the SAME toolchain the bare-metal host build
# uses (gcc 11.4.0, cmake 3.22.1), so the in-container ramulator2 build matches
# the host build. (Ramulator2 output is deterministic regardless of compiler, but
# matching the host toolchain removes any doubt about reproducibility.)
FROM ubuntu:22.04
ARG DEBIAN_FRONTEND=noninteractive

# Build-only toolchain + deps. git + ca-certificates are required because
# ramulator2/CMakeLists.txt uses FetchContent to git-clone yaml-cpp/spdlog/
# argparse at configure time (ramulator2/ext is gitignored). No python here:
# config generation and SLURM submission run on the HOST, not in the container.
# APT::Sandbox::User "root" disables apt's drop to the unprivileged _apt uid for
# downloads, which fails under rootless podman on hosts without configured
# subuid/subgid ranges (a single-UID namespace). Harmless on properly-configured
# hosts; makes the build portable across HPC login nodes.
RUN printf 'APT::Sandbox::User "root";\n' > /etc/apt/apt.conf.d/00no-sandbox \
    && apt-get update && apt-get install -y --no-install-recommends \
        build-essential \
        cmake \
        git \
        ca-certificates \
    && rm -rf /var/lib/apt/lists/*

# Build ramulator2 IN-IMAGE so users need no local toolchain.
# Copy only the simulator source; .dockerignore drops ramulator2/build.
COPY ramulator2/ /opt/terracotta/ramulator2/
RUN cd /opt/terracotta/ramulator2 \
    && rm -rf build && mkdir -p build && cd build \
    && cmake ../ \
    && make -j"$(nproc)"

# The exe's RUNPATH is its own build tree (/opt/terracotta/ramulator2), and
# CMake writes libramulator.so into /opt/terracotta/ramulator2/, so the lib
# resolves in-image with no LD_LIBRARY_PATH and independent of the bind mount.
# Expose the binary on PATH as `ramulator2` (the name every per-job cmd calls).
RUN ln -s /opt/terracotta/ramulator2/build/ramulator2 /usr/local/bin/ramulator2

# Harmless default; every per-job command overrides this with `-w <wd>`.
WORKDIR /work
