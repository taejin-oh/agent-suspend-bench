#!/usr/bin/env bash
# 부하 실행이 남긴 가상 Agent(actor)와 그 snapshot 을 지운다. 실행 사이에 돌려 결과가 섞이지 않게 한다.
# 사용: scripts/cleanup_actors.sh [atespace=benchmark]
source "$(dirname "$0")/env.sh"
sp="${1:-benchmark}"
for a in $(kubectl ate --context "$KCTX" get actors -a "$sp" -o json 2>/dev/null | python3 -c 'import json,sys
d=json.load(sys.stdin); items=d.get("actors", d.get("items", d)) if isinstance(d,dict) else d
for a in items: print((a.get("metadata") or a).get("name"))'); do
  kubectl ate --context "$KCTX" delete actor "$a" -a "$sp" 2>&1 | grep -v '^Warning'
done
kubectl ate --context "$KCTX" get actors -a "$sp" 2>&1 | grep -v '^Warning'
