#!/bin/bash
# Build the release ramulator2 binary. CWD-independent: always builds under the
# directory this script lives in (ramulator2/), producing ramulator2/build/ramulator2.
set -euo pipefail
cd "$(dirname "$0")"

mkdir -p build
cd build
cmake ../
make -j
cd ..