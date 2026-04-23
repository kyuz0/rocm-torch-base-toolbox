#!/bin/bash
set -e
set -o pipefail

# Ensure we're in the correct directory
cd "$(dirname "$0")"

# Expect the architecture as the first argument, default to gfx1151
ARCH=${1:-"gfx1151"}
ROCM_VERSION="7.2.1"
TORCH_VERSION="v2.7.1"

# Automatically determine max jobs based on system processors (clamping to max CPUs if needed)
MAX_JOBS=$(nproc)

ROCM_IMAGE_NAME="fedora-toolbox-rocm:${ARCH}-${ROCM_VERSION}"
TORCH_IMAGE_NAME="fedora-toolbox-torch:${ARCH}-${ROCM_VERSION}"

echo "=================================================="
echo ">>> Building ROCm Base Toolbox..."
echo "    Architecture: ${ARCH}"
echo "    ROCm:         ${ROCM_VERSION}"
echo "    Target:       ${ROCM_IMAGE_NAME}"
echo "=================================================="

podman build -t "${ROCM_IMAGE_NAME}" \
  --build-arg ROCM_ARCH="${ARCH}" \
  -f toolbox.rocm.Dockerfile .

echo ""
echo "=================================================="
echo ">>> Building PyTorch Toolbox from Source..."
echo "    Architecture: ${ARCH}"
echo "    PyTorch:      ${TORCH_VERSION}"
echo "    ROCm:         ${ROCM_VERSION}"
echo "    Target:       ${TORCH_IMAGE_NAME}"
echo "    Threads:      ${MAX_JOBS}"
echo "=================================================="
echo "WARNING: Building PyTorch + Vision natively on Podman takes several hours."

podman build -t "${TORCH_IMAGE_NAME}" \
  --build-arg BASE_IMAGE="${ROCM_IMAGE_NAME}" \
  --build-arg ROCM_ARCH="${ARCH}" \
  --build-arg PYTORCH_BRANCH="${TORCH_VERSION}" \
  --build-arg PYTORCH_MAX_JOBS="${MAX_JOBS}" \
  -f toolbox.torch.Dockerfile .

echo "=================================================="
echo "Build complete! Your toolboxes are ready:"
echo " - Base ROCM: ${ROCM_IMAGE_NAME}"
echo " - PyTorch:   ${TORCH_IMAGE_NAME}"
echo ""
echo "You can spawn a toolbox using:"
echo "  toolbox create --image ${TORCH_IMAGE_NAME} -c pytorch-${ARCH}"
echo "  toolbox enter -c pytorch-${ARCH}"
