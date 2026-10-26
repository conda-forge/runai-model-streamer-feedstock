#!/bin/bash
set -euxo pipefail

# The upstream build (see cpp/Makefile) is tailored to a devcontainer that ships a
# custom Bazel crosstool (expecting /usr/bin/<arch>-linux-gnu-gcc), pre-built
# AWS/Azure/GCP SDKs under /opt, and vendored liburing/libaio/CUDA headers. The
# 0001-... patch strips the custom toolchain registration and the object-storage
# repositories from cpp/WORKSPACE because the core libstreamer.so -- the only
# artifact bundled by this wheel -- does not build them: the s3/gcs/azure
# backends are separate .so files, shipped in their own wheels, that are
# dlopen'd at runtime. Bazel therefore auto-detects the conda-forge compiler
# through CC/CXX.

export PACKAGE_VERSION="${PKG_VERSION}"

cd cpp

# Plain Bazel (not Bazelisk) ignores .bazelversion; remove it so nothing can
# enforce the upstream-pinned 7.6.1 against the conda-forge bazel.
rm -f .bazelversion

# Upstream takes the liburing, libaio and CUDA driver headers from the
# devcontainer image. Expose the conda host environment at the repository paths
# the patched WORKSPACE points at instead; the third_party BUILD files then work
# unmodified.
cuda_include_dir="$(dirname "$(find "${PREFIX}/targets" -maxdepth 3 -name cuda.h -print -quit)")"

mkdir -p .bazel-deps/cuda .bazel-deps/uring .bazel-deps/aio
ln -s "${cuda_include_dir}" .bazel-deps/cuda/include
ln -s "${PREFIX}/include" .bazel-deps/uring/include
ln -s "${PREFIX}/include" .bazel-deps/aio/include

# Build only the core shared library.
bazel build streamer:libstreamer.so \
    --verbose_failures \
    --linkopt="-L${PREFIX}/lib"

# setup.py packages runai_model_streamer/libstreamer/lib/libstreamer.so, which
# is a symlink (created by the repo) to cpp/bazel-bin/streamer/libstreamer.so.
cd ../py/runai_model_streamer
"${PYTHON}" -m pip install . -vv --no-deps --no-build-isolation
