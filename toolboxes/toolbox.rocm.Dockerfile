ARG BASE_IMAGE="registry.fedoraproject.org/fedora-toolbox:43"
ARG ROCM_VERSION="7.2.1"
ARG ROCM_ARCH="gfx1151"

############# Stage 0: Base Dependencies #############
FROM ${BASE_IMAGE} AS rocm_base
ARG ROCM_VERSION

# Disable dnf mirror checks and install all requisite Fedora packages for compiling LLVM and ROCm from source
RUN dnf update -y && \
    dnf install -y \
    cmake \
    ninja-build \
    git \
    gcc-c++ \
    gcc \
    ccache \
    python3-devel \
    python3-pip \
    hwloc-devel \
    libdrm-devel \
    elfutils-libelf-devel \
    numactl-devel \
    rpm-build \
    sudo \
    shadow-utils \
    libcap-devel \
    nss-myhostname \
    pkgconfig \
    zlib-devel \
    mesa-libGL-devel \
    findutils \
    make \
    vim-common \
    && dnf clean all

# Enable Toolbox labels
LABEL com.github.containers.toolbox="true" \
      usage="This image is meant to be used with the toolbox command" \
      summary="Fedora Source-Built ROCm toolbox"

RUN rm -f /etc/machine-id && touch /etc/machine-id

ENV ROCM_PATH=/opt/rocm
ENV PATH=/opt/rocm/bin:$PATH
ENV LD_LIBRARY_PATH=/opt/rocm/lib:/opt/rocm/lib64:$LD_LIBRARY_PATH
ENV CXX=g++
ENV CC=gcc

############# Stage 1: Build LLVM #############
FROM rocm_base AS build_llvm
ARG ROCM_VERSION

WORKDIR /rocm-src
RUN git clone --depth 1 -b rocm-${ROCM_VERSION} https://github.com/ROCm/llvm-project.git

WORKDIR /rocm-src/llvm-project/build
RUN cmake -G Ninja ../llvm \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_INSTALL_PREFIX=/opt/rocm/llvm \
    -DLLVM_ENABLE_PROJECTS="clang;lld" \
    -DLLVM_TARGETS_TO_BUILD="AMDGPU;X86" \
    -DLLVM_ENABLE_ASSERTIONS=1 \
    -DLLVM_ENABLE_RUNTIMES="compiler-rt;libcxx;libcxxabi;libunwind" \
    && ninja \
    && ninja install

############# Stage 2: Build Device-Libs #############
FROM build_llvm AS build_devicelibs
ARG ROCM_VERSION

# ROCm 7.x moved Device-Libs into the LLVM monorepo
WORKDIR /rocm-src/llvm-project/amd/device-libs/build
RUN cmake -G Ninja .. \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_INSTALL_PREFIX=/opt/rocm \
    -DLLVM_DIR=/opt/rocm/llvm/lib/cmake/llvm \
    -DClang_DIR=/opt/rocm/llvm/lib/cmake/clang \
    && ninja \
    && ninja install

############# Stage 3: Build ROCR-Runtime & COMGR & CLR(HIP) #############
FROM build_devicelibs AS build_hip
ARG ROCM_VERSION
ARG ROCM_ARCH

# Install Python deps for HIP build (using --break-system-packages for Fedora 40+)
RUN pip3 install CppHeaderParser --break-system-packages || pip3 install CppHeaderParser

# ROCR-Runtime
WORKDIR /rocm-src
RUN git clone --depth 1 -b rocm-${ROCM_VERSION} https://github.com/ROCm/ROCR-Runtime.git
WORKDIR /rocm-src/ROCR-Runtime/build
# Requires elfutils-libelf-devel, libdrm-devel, numactl-devel
RUN cmake -G Ninja .. \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_INSTALL_PREFIX=/opt/rocm \
    && ninja \
    && ninja install

# COMGR (ROCm 7.x moved it into llvm-project/amd/comgr)
WORKDIR /rocm-src/llvm-project/amd/comgr/build
RUN cmake -G Ninja .. \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_INSTALL_PREFIX=/opt/rocm \
    -DCMAKE_PREFIX_PATH=/opt/rocm/llvm \
    -DLLVM_DIR=/opt/rocm/llvm/lib/cmake/llvm \
    -DClang_DIR=/opt/rocm/llvm/lib/cmake/clang \
    -DLLD_DIR=/opt/rocm/llvm/lib/cmake/lld \
    && ninja \
    && ninja install

# HIPCC (ROCm 7.x moved it into llvm-project/amd/hipcc)
WORKDIR /rocm-src/llvm-project/amd/hipcc/build
RUN cmake -G Ninja .. \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_INSTALL_PREFIX=/opt/rocm \
    -DCMAKE_PREFIX_PATH=/opt/rocm/llvm \
    && ninja \
    && ninja install

# rocprofiler-register (ROCm 7.x telemetry dependency)
WORKDIR /rocm-src
RUN git clone --depth 1 -b rocm-${ROCM_VERSION} https://github.com/ROCm/rocprofiler-register.git
WORKDIR /rocm-src/rocprofiler-register/build
RUN cmake -G Ninja .. \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_INSTALL_PREFIX=/opt/rocm \
    && ninja \
    && ninja install

# CLR (HIP)
WORKDIR /rocm-src
RUN git clone --depth 1 -b rocm-${ROCM_VERSION} https://github.com/ROCm/clr.git
RUN git clone --depth 1 -b rocm-${ROCM_VERSION} https://github.com/ROCm/HIP.git
WORKDIR /rocm-src/clr/build
RUN cmake -G Ninja .. \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_INSTALL_PREFIX=/opt/rocm \
    -DCLR_BUILD_HIP=ON \
    -DHIP_COMMON_DIR=/rocm-src/HIP \
    -DHIP_PLATFORM=amd \
    -DLLVM_DIR=/opt/rocm/llvm/lib/cmake/llvm \
    -DClang_DIR=/opt/rocm/llvm/lib/cmake/clang \
    -DROCM_PATH=/opt/rocm \
    && ninja \
    && ninja install

# rocminfo
WORKDIR /rocm-src
RUN git clone --depth 1 -b rocm-${ROCM_VERSION} https://github.com/ROCm/rocminfo.git
WORKDIR /rocm-src/rocminfo/build
RUN cmake -G Ninja .. \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_INSTALL_PREFIX=/opt/rocm \
    && ninja \
    && ninja install

# Symlink hipcc properly and mass-map Fedora's lib64 binaries into /opt/rocm/lib for hipcc TryCompile bounds
RUN ln -s /opt/rocm/bin/hipcc /usr/local/bin/hipcc || true && \
    mkdir -p /opt/rocm/lib && ln -s /opt/rocm/llvm /opt/rocm/lib/llvm || true && \
    ln -s /opt/rocm/lib64/* /opt/rocm/lib/ || true

############# Stage 4: Build Math Libraries (rocBLAS, rccl, etc) #############
FROM build_hip AS build_math
ARG ROCM_VERSION
ARG ROCM_ARCH

# Switch compiler to our locally built hipcc and configure linkers for Fedora's lib64 mapping
ENV CXX=/opt/rocm/bin/hipcc
ENV CC=/opt/rocm/llvm/bin/clang
ENV LIBRARY_PATH=/opt/rocm/lib64:/opt/rocm/lib:$LIBRARY_PATH
# Install psutil for Tensile RAM estimation to prevent parallel compilation OOM
RUN pip3 install psutil --break-system-packages || pip3 install psutil

# msgpack-cxx (Required by Tensile for precomputed kernel serialization)
WORKDIR /rocm-src
RUN git clone -b cpp_master --depth 1 https://github.com/msgpack/msgpack-c.git && \
    mkdir -p /rocm-src/msgpack-c/build && cd /rocm-src/msgpack-c/build && \
    cmake -G Ninja .. -DCMAKE_INSTALL_PREFIX=/usr -DMSGPACK_CXX17=ON -DMSGPACK_BUILD_TESTS=OFF -DMSGPACK_BUILD_EXAMPLES=OFF -DMSGPACK_USE_BOOST=OFF && \
    ninja && ninja install

# Tensile
WORKDIR /rocm-src
RUN git clone --depth 1 -b rocm-${ROCM_VERSION} https://github.com/ROCm/Tensile.git


# rocBLAS
WORKDIR /rocm-src
RUN git clone --depth 1 -b rocm-${ROCM_VERSION} https://github.com/ROCm/rocBLAS.git
WORKDIR /rocm-src/rocBLAS
# Install requirements script if necessary
RUN ./install.sh --dependencies || true
# Invoke rmake natively targeting ROCM_ARCH and breaking chronological circular dependency
RUN python3 ./rmake.py \
    --build_dir $(realpath ./build) \
    --src_path $(realpath .) \
    --architecture ${ROCM_ARCH} \
    --no_hipblaslt \
    --test_local_path $(realpath ../Tensile) \
    && cd ./build/release && make install

# hipBLASLt (Built sequentially after rocBLAS to support PyTorch tensorcores)
WORKDIR /rocm-src
RUN git clone --depth 1 -b rocm-${ROCM_VERSION} https://github.com/ROCm/hipBLASLt.git
WORKDIR /rocm-src/hipBLASLt
RUN ./install.sh --dependencies || true
RUN python3 ./rmake.py \
    --architecture ${ROCM_ARCH} \
    --build_dir $(realpath ./build) \
    && cd ./build/release && make install

# RCCL
WORKDIR /rocm-src
RUN git clone --depth 1 -b rocm-${ROCM_VERSION} https://github.com/ROCm/rccl.git
WORKDIR /rocm-src/rccl
RUN ./install.sh -i --amdgpu_targets ${ROCM_ARCH} || true

# rocRAND
WORKDIR /rocm-src
RUN git clone --depth 1 -b rocm-${ROCM_VERSION} https://github.com/ROCm/rocRAND.git
WORKDIR /rocm-src/rocRAND/build
RUN cmake -G Ninja .. -DCMAKE_INSTALL_PREFIX=/opt/rocm -DAMDGPU_TARGETS=${ROCM_ARCH} && ninja install

############# Stage 5: Final Toolbox Output #############
FROM rocm_base AS final
ENV ROCM_ARCH=${ROCM_ARCH}

# Copy the globally built ROCm SDK into the final lightweight target
COPY --from=build_math /opt/rocm /opt/rocm
