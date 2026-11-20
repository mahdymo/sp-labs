# ==============================================================================
# NVIDIA Sionna — 6G PHY-Layer Simulator
# GPU-accelerated link-level simulation with TensorFlow
# ==============================================================================

FROM tensorflow/tensorflow:2.16.1-gpu-jupyter

LABEL maintainer="SP Labs Team"
LABEL description="NVIDIA Sionna 6G PHY simulator with Jupyter"

# Install system dependencies
RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential \
    cmake \
    git \
    libgl1-mesa-glx \
    && rm -rf /var/lib/apt/lists/*

# Install Sionna and scientific Python packages
RUN pip install --no-cache-dir \
    sionna==0.19.1 \
    numpy \
    scipy \
    matplotlib \
    plotly \
    ipywidgets

# Create workspace
RUN mkdir -p /workspace/notebooks

# Copy sample notebooks
COPY notebooks/ /workspace/notebooks/

WORKDIR /workspace

EXPOSE 8888

CMD ["jupyter", "notebook", "--ip=0.0.0.0", "--port=8888", \
     "--no-browser", "--allow-root", \
     "--NotebookApp.token=splabs", \
     "--NotebookApp.notebook_dir=/workspace"]
