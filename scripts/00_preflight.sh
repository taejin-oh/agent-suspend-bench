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
  grep -E "MemTotal|SwapTotal" /proc/meminfo; df -h / | tail -1
  echo "in_docker_free_kb=$(df -Pk / | tail -1 | tr -s " " | cut -d" " -f4)"' 2>&1
echo "## 외부 통신 (HTTP 코드가 나오면 도달함; 000 또는 인증서 오류면 막힘)"
for u in https://ghcr.io https://registry-1.docker.io/v2/ https://storage.googleapis.com https://github.com https://go.dev https://proxy.golang.org; do
  code="$(curl -sI -m 10 -o /dev/null -w '%{http_code}' "$u" 2>/dev/null)"; printf '%s %s curl_exit=%s\n' "$u" "$code" "$?"; done
echo "proxy_env: $(env | grep -i -E '^(https?|no)_proxy=' | sed 's/=.*/=<set>/' | tr '\n' ' ')"
echo "## 도구"
for t in git docker kubectl curl python3 tar iostat pidstat aws; do printf '%s: %s\n' "$t" "$(command -v $t || echo MISSING)"; done
kubectl version --client 2>&1 | head -1
echo "## 충돌 가능성"
docker ps -a --format '{{.Names}}' | grep -E -- '-control-plane$|^kind-registry$' | sed 's/^/existing container: /'
(command -v ss >/dev/null && ss -ltn || lsof -nP -iTCP -sTCP:LISTEN) 2>/dev/null | grep -E "[:.](${KIND_REGISTRY_PORT:-5001}|${PORT:-8000}|${LOCUST_PORT:-8089})\b" | sed 's/^/port in use: /'
} 2>&1 | tee "$out"
# 판정: 위 출력을 읽어 진행할 수 있는지 한 줄로 정리한다. FAIL 이 하나라도 있으면 PREFLIGHT=FAIL.
{
echo "## 판정"
F=0; fail() { echo "FAIL: $*"; F=1; }; warn() { echo "WARN: $*"; }
has() { grep -q -- "$1" "$out"; }
docker info >/dev/null 2>&1 || fail "docker 명령이 동작하지 않는다 (데몬이 꺼져 있거나 현재 사용자에게 권한이 없음)"
has 'cgroup=v2' || fail "Docker 가 cgroup v2 가 아니다. worker 가 뜨지 않는다"
if [ "$(uname -s)" = Linux ]; then has 'cgroupfs=cgroup2fs' || fail "호스트가 cgroup v2 가 아니다 (/sys/fs/cgroup 이 cgroup2fs 가 아님)"; fi
has '^in_docker_self_cgroup=' || fail "docker 가 busybox 이미지를 받아 실행하지 못했다 (Docker 데몬의 외부 통신 또는 권한 문제)"
for u in $(sed -n 's/^\(https:[^ ]*\) 000 curl_exit=.*/\1/p' "$out"); do fail "외부 통신 불가: $u ($(grep -F "$u " "$out" | sed 's/.* //'))"; done
has 'curl_exit=60' && fail "TLS 인증서 오류(curl_exit=60): 망이 TLS 를 가로채는 프록시를 쓰는 것으로 보인다. 이 저장소에서 다루지 않은 환경이다"
for t in git docker kubectl curl python3 tar; do has "^$t: MISSING" && fail "도구 없음: $t"; done
bv="$(bash -c 'echo $(( BASH_VERSINFO[0] * 100 + BASH_VERSINFO[1] ))')"; [ "$bv" -ge 404 ] || fail "bash 가 4.4 보다 낮다 ($(bash -c 'echo $BASH_VERSION'))"
free_kb="$(sed -n 's/^in_docker_free_kb=//p' "$out")"
if [ -n "$free_kb" ]; then
  [ "$free_kb" -lt 20000000 ] && fail "Docker 데이터 디스크 여유가 20 GB 미만이다 ($(( free_kb / 1048576 )) GB)"
  [ "$free_kb" -ge 20000000 ] && [ "$free_kb" -lt 60000000 ] && warn "Docker 데이터 디스크 여유가 60 GB 미만이다 ($(( free_kb / 1048576 )) GB). 큰 단계는 자동으로 건너뛸 수 있다"
fi
has "^existing container: ${KIND_CLUSTER_NAME:-kind}-control-plane" && warn "kind 클러스터 '${KIND_CLUSTER_NAME:-kind}' 가 이미 있다. scripts/02_cluster.sh 는 멈춘다 (그 스크립트의 안내를 따를 것)"
has '^port in use' && warn "쓰려는 포트가 사용 중이다 (위 'port in use' 줄). 5001 은 이 작업의 kind-registry 면 정상. 아니면 site.env 에서 포트를 바꾼다"
has '^proxy_env: .*=<set>' && warn "프록시 환경 변수가 설정돼 있다. 프록시 환경은 이 저장소에서 확인하지 못했다"
[ -f "$ROOT/site.env" ] || warn "site.env 가 없다. 기본값으로 진행한다 (cp site.env.example site.env 권장)"
[ "$F" = 0 ] && echo "PREFLIGHT=PASS" || echo "PREFLIGHT=FAIL"
} 2>&1 | tee -a "$out"
echo; echo "saved: $out"
