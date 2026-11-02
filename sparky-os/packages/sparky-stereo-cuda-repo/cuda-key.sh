# Created by Paweł "pavroo" Pijanowski and Daniel Ramos (Capitain Jack) 2026/10/03
# Copyright 2026 under the GNU GPL3 License
# Last update 2026/11/01
# NVIDIA's key for its CUDA repository, as NVIDIA ships it: usr/share/keyrings/cuda-archive-keyring.gpg of
# https://developer.download.nvidia.com/compute/cuda/repos/debian13/x86_64/cuda-keyring_1.1-1_all.deb, retrieved
# 2026-10-03 (the package's checksum, CUDA_KEY_SHA256) and again 2026-11-01. The recipe ships cuda-archive-keyring.gpg,
# that file byte for byte (CUDA_KEYRING_SHA256, and the MD5 cuda-keyring's own md5sums lists, CUDA_KEYRING_MD5), and its
# build stops if the file differs. Moved here from sparky-stereo-hardware's share/cuda-key.sh.
# Public key fingerprint: 02182E60104FCDC26EAE1B8597A5D4CB8793F200 ("Kitmaker (Debian 13 Trixie) <kitmaker@nvidia.com>")
CUDA_KEY_SHA256=d0d4ef986a44400f9db33c600ef33a985175e7cc63d805a10e1839c7a1e78f5f
CUDA_KEYRING_SHA256=77f0992eb9dfa444422b86e9857599df03172b2b0f9cf58047bc49ff66034bbe
CUDA_KEYRING_MD5=672a16cb3b8c6e53844563ae8c441557
CUDA_KEY_FPR=02182E60104FCDC26EAE1B8597A5D4CB8793F200
