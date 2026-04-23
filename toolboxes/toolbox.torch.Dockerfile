# The base image must be passed via ARG when building, e.g. "fedora-toolbox-rocm:gfx1151-7.2.1"
ARG BASE_IMAGE
FROM ${BASE_IMAGE}

ARG ROCM_ARCH="gfx1151"
ARG PYTORCH_BRANCH="v2.7.1"
ARG PYTORCH_MAX_JOBS="8"

ENV PYTORCH_ROCM_ARCH="${ROCM_ARCH}"
ENV MAX_JOBS=${PYTORCH_MAX_JOBS}
ENV REL_WITH_DEB_INFO=1
ENV BUILD_TEST=0
ENV USE_ROCM=1

WORKDIR /opt/pytorch-build

# Clone PyTorch and checkout branch
RUN git clone --recursive -b ${PYTORCH_BRANCH} https://github.com/pytorch/pytorch.git

WORKDIR /opt/pytorch-build/pytorch

# Install PyTorch python build dependencies
# We use --break-system-packages because this is an isolated toolbox container, 
# and it is expected to have python packages managed system-wide for the developer.
RUN pip3 install --no-cache-dir \
    typing-extensions \
    sympy \
    networkx \
    jinja2 \
    fsspec \
    filelock \
    pyyaml \
    --break-system-packages

RUN pip3 install --no-cache-dir -r requirements.txt --break-system-packages

# Compile PyTorch (AOTriton will be automatically fetched by CMake via submodules)
RUN chmod +x tools/amd_build/build_amd.py && \
    python3 tools/amd_build/build_amd.py && \
    USE_ROCM=1 python3 setup.py bdist_wheel && \
    pip3 install dist/*.whl --break-system-packages

# Cleanup build artifacts to keep container reasonably sized
RUN rm -rf /opt/pytorch-build
