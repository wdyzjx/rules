#!/usr/bin/env bash
# build.sh — source/*.list → dist/*.mrs 批量转换
#
# 流程：lint 先行（fail-loud）→ mihomo convert-ruleset 按文件名后缀判 behavior。
#
# 命名约定：
#   *_ip.list → ipcidr mrs
#   其他 *.list → domain mrs
#
# 用法：从仓库根跑 `bash scripts/build.sh`。
# 环境：MIHOMO_BIN 可覆盖默认 ~/.config/mihomo/mihomo-bin。

set -euo pipefail
cd "$(dirname "$0")/.."

MIHOMO_BIN="${MIHOMO_BIN:-$HOME/.config/mihomo/mihomo-bin}"
if [[ ! -x "$MIHOMO_BIN" ]]; then
  echo "FAIL: mihomo 二进制不可执行：$MIHOMO_BIN" >&2
  echo "       export MIHOMO_BIN=/path/to/mihomo 后重试" >&2
  exit 1
fi

ver=$("$MIHOMO_BIN" -v 2>&1 | head -1)
echo "==> mihomo: $ver"

# Phase 1: lint
echo "==> lint"
bash scripts/lint.sh

# Phase 2: convert
# mihomo convert-ruleset 不剥行内 # 注释（domain 静默吞进 trie，ipcidr 直接 panic）。
# 预处理：sed 剥 `[空白]*#.*` + 去 trailing 空白，纯注释/空行 mihomo 自然跳过。
# 临时文件留 .tmp 后缀，build 完成后清理。
echo "==> convert source/*.list → dist/*.mrs"
mkdir -p dist
count=0
tmpdir="$(mktemp -d)"
trap 'rm -rf "$tmpdir"' EXIT
for f in source/*.list; do
  name="$(basename "$f" .list)"
  case "$name" in
    *_ip) behavior=ipcidr ;;
    *)    behavior=domain ;;
  esac
  out="dist/${name}.mrs"
  clean="${tmpdir}/${name}.clean"
  sed -E 's/[[:space:]]*#.*$//; s/[[:space:]]+$//' "$f" > "$clean"
  echo "    [$behavior] $f → $out"
  "$MIHOMO_BIN" convert-ruleset "$behavior" text "$clean" "$out"
  count=$((count + 1))
done

# Phase 3: 报告
echo "==> done, $count mrs produced:"
ls -lh dist/ | grep '\.mrs$' | awk '{printf "    %s  %s\n", $5, $NF}'
