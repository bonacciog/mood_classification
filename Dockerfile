ARG UBUNTU_VERSION=18.04
ARG CUDA_VERSION=10.2
ARG IMAGE_DIGEST=218afa9c2002be9c4629406c07ae4daaf72a3d65eb3c5a5614d9d7110840a46e

FROM nvidia/cuda:${CUDA_VERSION}-base-ubuntu${UBUNTU_VERSION}@sha256:${IMAGE_DIGEST}

ARG MINICONDA_VERSION=4.8.3
ARG CONDA_PY_VERSION=38
ARG CONDA_CHECKSUM="d63adf39f2c220950a063e0529d4ff74"
ARG CONDA_PKG_VERSION=4.9.0
ARG PYTHON_VERSION=3.7
ARG PYARROW_VERSION=0.16.0
ARG MLIO_VERSION=0.6.0
ARG XGBOOST_VERSION=1.2.0

ENV DEBIAN_FRONTEND=noninteractive
ENV LANG=C.UTF-8
ENV LC_ALL=C.UTF-8

# Python won’t try to write .pyc or .pyo files on the import of source modules
# Force stdin, stdout and stderr to be totally unbuffered. Good for logging
ENV PYTHONDONTWRITEBYTECODE=1
ENV PYTHONUNBUFFERED=1
ENV PYTHONIOENCODING='utf-8'

RUN apt-get update && \
    apt-get -y install --no-install-recommends \
        build-essential \
        curl \
        git \
        jq \
        libatlas-base-dev \
        nginx \
        openjdk-8-jdk-headless \
        unzip \
        wget \
        && \
    # MLIO build dependencies
    # Official Ubuntu APT repositories do not contain an up-to-date version of CMake required to build MLIO.
    # Kitware contains the latest version of CMake.
    apt-get -y install --no-install-recommends \
        apt-transport-https \
        ca-certificates \
        gnupg \
        software-properties-common \
        && \
    wget -O - https://apt.kitware.com/keys/kitware-archive-latest.asc 2>/dev/null | \
        gpg --dearmor - | \
        tee /etc/apt/trusted.gpg.d/kitware.gpg >/dev/null && \
    apt-add-repository 'deb https://apt.kitware.com/ubuntu/ bionic main' && \
    apt-get update && \
    apt-get install -y --no-install-recommends \
        autoconf \
        automake \
        build-essential \
        cmake=3.18.4-0kitware1 \
        cmake-data=3.18.4-0kitware1 \
        doxygen \
        libcurl4-openssl-dev \
        libssl-dev \
        libtool \
        ninja-build \
        python3-dev \
        python3-distutils \
        python3-pip \
        zlib1g-dev \
        && \
    rm -rf /var/lib/apt/lists/*

# Install conda
RUN cd /tmp && \
    curl -L --output /tmp/Miniconda3.sh https://repo.anaconda.com/miniconda/Miniconda3-py${CONDA_PY_VERSION}_${MINICONDA_VERSION}-Linux-x86_64.sh && \
    echo "${CONDA_CHECKSUM} /tmp/Miniconda3.sh" | md5sum -c - && \
    bash /tmp/Miniconda3.sh -bfp /miniconda3 && \
    rm /tmp/Miniconda3.sh

ENV PATH=/miniconda3/bin:${PATH}

# Install MLIO with Apache Arrow integration
# We could install mlio-py from conda, but it comes  with extra support such as image reader that increases image size
# which increases training time. We build from source to minimize the image size.
RUN echo "conda ${CONDA_PKG_VERSION}" >> /miniconda3/conda-meta/pinned && \
    # Conda configuration see https://conda.io/projects/conda/en/latest/configuration.html
    conda config --system --set auto_update_conda false && \
    conda config --system --set show_channel_urls true && \
    echo "python ${PYTHON_VERSION}.*" >> /miniconda3/conda-meta/pinned && \
    conda install python=${PYTHON_VERSION} && \
    conda install python=${PYTHON_VERSION} && \
    conda install conda=${CONDA_PKG_VERSION} && \
    conda update -y conda && \
    conda install -c conda-forge pyarrow=${PYARROW_VERSION} && \
    cd /tmp && \
    git clone --branch v${MLIO_VERSION} https://github.com/awslabs/ml-io.git mlio && \
    cd mlio && \
    build-tools/build-dependency build/third-party all && \
    mkdir -p build/release && \
    cd build/release && \
    cmake -GNinja -DCMAKE_BUILD_TYPE=RelWithDebInfo -DCMAKE_PREFIX_PATH="$(pwd)/../third-party" ../.. && \
    cmake --build . && \
    cmake --build . --target install && \
    cmake -DMLIO_INCLUDE_PYTHON_EXTENSION=ON -DMLIO_INCLUDE_ARROW_INTEGRATION=ON ../.. && \
    cmake --build . --target mlio-py && \
    cmake --build . --target mlio-arrow && \
    cd ../../src/mlio-py && \
    python3 setup.py bdist_wheel && \
    python3 -m pip install dist/*.whl && \
    cp -r /tmp/mlio/build/third-party/lib/intel64/gcc4.7/* /usr/local/lib/ && \
    ldconfig && \
    rm -rf /tmp/mlio

# Install latest version of XGBoost
RUN python3 -m pip install --no-cache -I xgboost==${XGBOOST_VERSION}

WORKDIR /app
ADD . /app
