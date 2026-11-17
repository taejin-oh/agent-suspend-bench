#!/usr/bin/env bash
# kind 클러스터와 로컬 registry 를 지운다. 이 저장소 폴더(toolchain/, src/, gopath/ 등)와 docker 이미지는 남는다.
source "$(dirname "$0")/env.sh"
cd "$SUBSTRATE_DIR" && ./hack/delete-kind-cluster.sh
echo "남은 것: $ROOT/{toolchain,src,bin,gopath,gocache} (폴더째 삭제 가능), ~/.cache/ate-setup 또는 ~/Library/Caches/ate-setup, docker 이미지(docker images 로 확인)"
