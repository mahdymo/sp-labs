# ==============================================================================
# ns-3 Network Simulator — 5G NR Module + 6G Research Extensions
# ==============================================================================

FROM ubuntu:22.04

LABEL maintainer="SP Labs Team"
LABEL description="ns-3 network simulator with 5G NR module for 6G research"

ENV DEBIAN_FRONTEND=noninteractive
ENV NS3_VERSION=3.42

# Install build dependencies
RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential \
    cmake \
    git \
    python3 \
    python3-pip \
    python3-dev \
    python3-setuptools \
    libsqlite3-dev \
    libxml2-dev \
    libgtk-3-dev \
    qtbase5-dev \
    gdb \
    valgrind \
    tcpdump \
    wget \
    unzip \
    && rm -rf /var/lib/apt/lists/*

# Install Python analysis tools
RUN pip3 install --no-cache-dir \
    numpy \
    scipy \
    matplotlib \
    pandas

# Download and build ns-3
WORKDIR /opt
RUN wget -q https://www.nsnam.org/releases/ns-allinone-${NS3_VERSION}.tar.bz2 \
    && tar xjf ns-allinone-${NS3_VERSION}.tar.bz2 \
    && rm ns-allinone-${NS3_VERSION}.tar.bz2

WORKDIR /opt/ns-allinone-${NS3_VERSION}/ns-${NS3_VERSION}
RUN ./ns3 configure --enable-examples --enable-tests \
    && ./ns3 build

# Create results output directory
RUN mkdir -p /results

WORKDIR /opt/ns-allinone-${NS3_VERSION}/ns-${NS3_VERSION}

CMD ["./ns3", "run", "scratch/nr-simple-example", "--no-build"]
