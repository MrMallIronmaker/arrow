# Licensed to the Apache Software Foundation (ASF) under one
# or more contributor license agreements.  See the NOTICE file
# distributed with this work for additional information
# regarding copyright ownership.  The ASF licenses this file
# to you under the Apache License, Version 2.0 (the
# "License"); you may not use this file except in compliance
# with the License.  You may obtain a copy of the License at
#
#   http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing,
# software distributed under the License is distributed on an
# "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY
# KIND, either express or implied.  See the License for the
# specific language governing permissions and limitations
# under the License.

ARG base=amd64/ubuntu:21.04
FROM ${base}

SHELL ["/bin/bash", "-o", "pipefail", "-c"]

RUN echo "debconf debconf/frontend select Noninteractive" | \
        debconf-set-selections

# Installs LLVM toolchain, for Gandiva and testing other compilers
#
# Note that this is installed before the base packages to improve iteration
# while debugging package list with docker build.
ARG clang_tools
ARG llvm
RUN latest_system_llvm=12 && \
    if [ ${llvm} -gt ${latest_system_llvm} -o \
         ${clang_tools} -gt ${latest_system_llvm} ]; then \
      apt-get update -y -q && \
      apt-get install -y -q --no-install-recommends \
          apt-transport-https \
          ca-certificates \
          gnupg \
          lsb-release \
          wget && \
      wget -O - https://apt.llvm.org/llvm-snapshot.gpg.key | apt-key add - && \
      code_name=$(lsb_release --codename --short) && \
      if [ ${llvm} -gt 10 ]; then \
        echo "deb https://apt.llvm.org/${code_name}/ llvm-toolchain-${code_name}-${llvm} main" > \
           /etc/apt/sources.list.d/llvm.list; \
      fi && \
      if [ ${clang_tools} -ne ${llvm} -a \
           ${clang_tools} -gt ${latest_system_llvm} ]; then \
        echo "deb https://apt.llvm.org/${code_name}/ llvm-toolchain-${code_name}-${clang_tools} main" > \
           /etc/apt/sources.list.d/clang-tools.list; \
      fi; \
    fi && \
    apt-get update -y -q && \
    apt-get install -y -q --no-install-recommends \
        clang-${clang_tools} \
        clang-${llvm} \
        clang-format-${clang_tools} \
        clang-tidy-${clang_tools} \
        llvm-${llvm}-dev && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists*

# Installs C++ toolchain and dependencies
RUN apt-get update -y -q && \
    apt-get install -y -q --no-install-recommends \
        autoconf \
        ca-certificates \
        ccache \
        cmake \
        gdb \
        git \
        libbenchmark-dev \
        libboost-filesystem-dev \
        libboost-system-dev \
        libbrotli-dev \
        libbz2-dev \
        libc-ares-dev \
        libcurl4-openssl-dev \
        libgflags-dev \
        libgoogle-glog-dev \
        libgrpc++-dev \
        liblz4-dev \
        libprotobuf-dev \
        libprotoc-dev \
        libre2-dev \
        libsnappy-dev \
        libssl-dev \
        libsqlite3-dev \
        libthrift-dev \
        libutf8proc-dev \
        libzstd-dev \
        make \
        ninja-build \
        nlohmann-json3-dev \
        pkg-config \
        protobuf-compiler \
        protobuf-compiler-grpc \
        python3-pip \
        rapidjson-dev \
        rsync \
        tzdata \
        wget && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists*

COPY ci/scripts/install_minio.sh /arrow/ci/scripts/
RUN /arrow/ci/scripts/install_minio.sh latest /usr/local

COPY ci/scripts/install_gcs_testbench.sh /arrow/ci/scripts/
RUN /arrow/ci/scripts/install_gcs_testbench.sh default

# Prioritize system packages and local installation
# The following dependencies will be downloaded due to missing/invalid packages
# provided by the distribution:
# - libc-ares-dev does not install CMake config files
# - flatbuffer is not packaged
# - libgtest-dev only provide sources
# - libprotobuf-dev only provide sources
ENV ARROW_BUILD_TESTS=ON \
    ARROW_DEPENDENCY_SOURCE=SYSTEM \
    ARROW_DATASET=ON \
    ARROW_FLIGHT=ON \
    ARROW_FLIGHT_SQL=ON \
    ARROW_GANDIVA=ON \
    ARROW_HDFS=ON \
    ARROW_HOME=/usr/local \
    ARROW_INSTALL_NAME_RPATH=OFF \
    ARROW_NO_DEPRECATED_API=ON \
    ARROW_ORC=ON \
    ARROW_PARQUET=ON \
    ARROW_PLASMA=ON \
    ARROW_S3=ON \
    ARROW_USE_ASAN=OFF \
    ARROW_USE_CCACHE=ON \
    ARROW_USE_UBSAN=OFF \
    ARROW_WITH_BROTLI=ON \
    ARROW_WITH_BZ2=ON \
    ARROW_WITH_LZ4=ON \
    ARROW_WITH_OPENTELEMETRY=OFF \
    ARROW_WITH_SNAPPY=ON \
    ARROW_WITH_ZLIB=ON \
    ARROW_WITH_ZSTD=ON \
    AWSSDK_SOURCE=BUNDLED \
    GTest_SOURCE=BUNDLED \
    ORC_SOURCE=BUNDLED \
    PARQUET_BUILD_EXAMPLES=ON \
    PARQUET_BUILD_EXECUTABLES=ON \
    Protobuf_SOURCE=BUNDLED \
    PATH=/usr/lib/ccache/:$PATH \
    PYTHON=python3

ARG gcc_version=""
RUN if [ "${gcc_version}" = "" ]; then \
      apt-get update -y -q && \
      apt-get install -y -q --no-install-recommends \
          g++ \
          gcc; \
    else \
      if [ "${gcc_version}" -gt "10" ]; then \
          apt-get update -y -q && \
          apt-get install -y -q --no-install-recommends software-properties-common && \
          add-apt-repository ppa:ubuntu-toolchain-r/volatile; \
      fi; \
      apt-get update -y -q && \
      apt-get install -y -q --no-install-recommends \
          g++-${gcc_version} \
          gcc-${gcc_version} && \
      update-alternatives --install /usr/bin/gcc gcc /usr/bin/gcc-${gcc_version} 100 && \
      update-alternatives --install /usr/bin/g++ g++ /usr/bin/g++-${gcc_version} 100 && \
      update-alternatives --install /usr/bin/cc cc /usr/bin/gcc 100 && \
      update-alternatives --set cc /usr/bin/gcc && \
      update-alternatives --install /usr/bin/c++ c++ /usr/bin/g++ 100 && \
      update-alternatives --set c++ /usr/bin/g++; \
    fi
