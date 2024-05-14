# Use the base image with PyTorch and CUDA support
FROM pytorch/pytorch:2.0.1-cuda11.7-cudnn8-devel

# system update
RUN sudo apt update && sudo apt upgrade -y

# install other import packages
RUN sudo apt install g++ freeglut3-dev build-essential libx11-dev libxmu-dev libxi-dev libglu1-mesa libglu1-mesa-dev

# first get the PPA repository driver
RUN sudo add-apt-repository ppa:graphics-drivers/ppa
RUN sudo apt update

RUN wget https://developer.download.nvidia.com/compute/cuda/repos/ubuntu2004/arm64/cuda-ubuntu2004.pin
RUN sudo mv cuda-ubuntu2004.pin /etc/apt/preferences.d/cuda-repository-pin-600
RUN wget https://developer.download.nvidia.com/compute/cuda/11.8.0/local_installers/cuda-tegra-repo-ubuntu2004-11-8-local_11.8.0-1_arm64.deb
RUN sudo dpkg -i cuda-tegra-repo-ubuntu2004-11-8-local_11.8.0-1_arm64.deb
RUN sudo cp /var/cuda-tegra-repo-ubuntu2004-11-8-local/cuda-*-keyring.gpg /usr/share/keyrings/
RUN sudo apt-get update
RUN sudo apt-get -y install cuda-11-8

# setup your paths
RUN echo 'export PATH=/usr/local/cuda-11.8/bin:$PATH' >> ~/.bashrc
RUN echo 'export LD_LIBRARY_PATH=/usr/local/cuda-11.8/lib64:$LD_LIBRARY_PATH' >> ~/.bashrc
RUN source ~/.bashrc
RUN sudo ldconfig

# install cuDNN v11.8
# First register here: https://developer.nvidia.com/developer-program/signup

RUN CUDNN_TAR_FILE="cudnn-linux-x86_64-8.7.0.84_cuda11-archive.tar.xz"
RUN sudo wget https://developer.download.nvidia.com/compute/redist/cudnn/v8.7.0/local_installers/11.8/cudnn-linux-x86_64-8.7.0.84_cuda11-archive.tar.xz
RUN sudo tar -xvf ${CUDNN_TAR_FILE}
RUN sudo mv cudnn-linux-x86_64-8.7.0.84_cuda11-archive cuda

# copy the following files into the cuda toolkit directory.
RUN sudo cp -P cuda/include/cudnn.h /usr/local/cuda-11.8/include
RUN sudo cp -P cuda/lib/libcudnn* /usr/local/cuda-11.8/lib64/
RUN sudo chmod a+r /usr/local/cuda-11.8/lib64/libcudnn*


# NOTE:
# Building the libraries for this repository requires cuda *DURING BUILD PHASE*, therefore:
# - The default-runtime for container should be set to "nvidia" in the deamon.json file. See this: https://github.com/NVIDIA/nvidia-docker/issues/1033
# - For the above to work, the nvidia-container-runtime should be installed in your host. Tested with version 1.14.0-rc.2
# - Make sure NVIDIA's drivers are updated in the host machine. Tested with 525.125.06

ENV DEBIAN_FRONTEND=noninteractive

# Update and install tzdata separately
RUN apt update && apt install -y tzdata

# Install necessary packages
RUN apt install -y git && \
    apt install -y libglew-dev libassimp-dev libboost-all-dev libgtk-3-dev libopencv-dev libglfw3-dev libavdevice-dev libavcodec-dev libeigen3-dev libxxf86vm-dev libembree-dev && \
    apt clean && apt install wget && rm -rf /var/lib/apt/lists/*

# Create a workspace directory and clone the repository
WORKDIR /workspace
RUN git clone https://github.com/graphdeco-inria/gaussian-splatting --recursive

# Create a Conda environment and activate it
WORKDIR /workspace/gaussian-splatting

RUN conda env create --file environment.yml && conda init bash && exec bash && conda activate gaussian_splatting

# Tweak the CMake file for matching the existing OpenCV version. Fix the naming of FindEmbree.cmake
WORKDIR /workspace/gaussian-splatting/SIBR_viewers/cmake/linux
RUN sed -i 's/find_package(OpenCV 4\.5 REQUIRED)/find_package(OpenCV 4.2 REQUIRED)/g' dependencies.cmake
RUN sed -i 's/find_package(embree 3\.0 )/find_package(EMBREE)/g' dependencies.cmake
RUN mv /workspace/gaussian-splatting/SIBR_viewers/cmake/linux/Modules/FindEmbree.cmake /workspace/gaussian-splatting/SIBR_viewers/cmake/linux/Modules/FindEMBREE.cmake

# Fix the naming of the embree library in the rayscaster's cmake
RUN sed -i 's/\bembree\b/embree3/g' /workspace/gaussian-splatting/SIBR_viewers/src/core/raycaster/CMakeLists.txt

# Ready to build the viewer now.
WORKDIR /workspace/gaussian-splatting/SIBR_viewers 
RUN cmake -Bbuild . -DCMAKE_BUILD_TYPE=Release && \
    cmake --build build -j24 --target install
