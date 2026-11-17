#!/usr/bin/env bash
# 사전 조건 확인. 읽기만 하고 아무것도 바꾸지 않는다 (busybox 이미지 pull 1회 제외).
# Linux 서버와 macOS(도커 VM) 양쪽에서 돈다. 결과: results/<host>/00_preflight.txt
source "$(dirname "$0")/env.sh"
out="$RESULTS/00_preflight.txt"
{
echo "# preflight $(date -u +%FT%TZ)  host_label=$HOST_LABEL"
echo "## host"; uname -srm
if [ "$(uname -s)" = Linux ]; then
  grep -E '^(PRETTY_NAME)=' /etc/os-release; nproc; free -h | sed -n 1,3p
  echo "cgroupfs=$(stat -fc %T /sys/fs/cgroup)   # 필요: cgroup2fs"
  ls -l /dev/kvm 2>&1; echo "vmx_svm_flags=$(grep -c -E 'vmx|svm' /proc/cpuinfo)"
  echo "ipv6_disabled=$(cat /proc/sys/net/ipv6/conf/all/disable_ipv6 2>&1)   # 필요: 0"
  echo "gc_thresh3=$(sysctl -n net.ipv4.neigh.default.gc_thresh3 2>&1)"
  lsblk -d -o NAME,ROTA,SIZE,MODEL 2>&1; df -h / /var/lib/docker 2>&1
else
  sysctl -n machdep.cpu.brand_string hw.ncpu hw.memsize; df -h / | tail -1
fi
echo "## docker (kind 노드가 실제로 도는 곳)"
docker info --format 'server={{.ServerVersion}} os={{.OperatingSystem}} kernel={{.KernelVersion}} arch={{.Architecture}} cpus={{.NCPU}} mem_bytes={{.MemTotal}} cgroup=v{{.CgroupVersion}} driver={{.CgroupDriver}}' 2>&1
docker run --rm --privileged busybox sh -c '
  echo "in_docker_self_cgroup=$(cat /proc/self/cgroup)   # 필요: 0::/ 형태 (cgroup v2)"
  ls -l /dev/kvm 2>&1 | sed "s/^/in_docker_kvm: /"
  echo "in_docker_ipv6_disabled=$(cat /proc/sys/net/ipv6/conf/all/disable_ipv6)"
  grep -E "MemTotal|SwapTotal" /proc/meminfo; df -h / | tail -1' 2>&1
echo "## 외부 통신 (HTTP 코드가 나오면 도달함; 000 또는 인증서 오류면 막힘)"
for u in https://ghcr.io https://registry-1.docker.io/v2/ https://storage.googleapis.com https://github.com https://go.dev https://proxy.golang.org; do
  printf '%s %s\n' "$u" "$(curl -sI -m 10 -o /dev/null -w '%{http_code}' "$u" 2>&1)"; done
echo "proxy_env: $(env | grep -i -E '^(https?|no)_proxy=' | sed 's/=.*/=<set>/' | tr '\n' ' ')"
echo "## 도구"
for t in git docker kubectl curl python3 iostat pidstat aws; do printf '%s: %s\n' "$t" "$(command -v $t || echo MISSING)"; done
kubectl version --client 2>&1 | head -1
echo "## 충돌 가능성"
docker ps -a --format '{{.Names}}' | grep -E '^kind-' | sed 's/^/existing container: /'
(command -v ss >/dev/null && ss -ltn || lsof -nP -iTCP -sTCP:LISTEN) 2>/dev/null | grep -E '[:.](5001|8000|8089|9000)\b' | sed 's/^/port in use: /'
} 2>&1 | tee "$out"
echo; echo "saved: $out"
