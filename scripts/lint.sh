#!/usr/bin/env bash
# lint.sh — source/*.list 静态校验，fail-loud
#
# mihomo convert-ruleset 对 KEYWORD/PROCESS/REGEX 在 domain.list 里**静默接受**但 mrs
# 语义丢失（被当成裸域名编进 trie），运行时规则失效不报错。本脚本主动拦截。
#
# 命名约定：
#   *_ip.list  → ipcidr behavior，只允许 CIDR
#   其他 *.list → domain behavior，只允许 DOMAIN / DOMAIN-SUFFIX / wildcard
#
# 用法：从仓库根跑 `bash scripts/lint.sh`。出错全部列完再非零退出。

set -uo pipefail
cd "$(dirname "$0")/.."

ec=0
fail() { echo "FAIL: $*" >&2; ec=1; }

shopt -s nullglob

# === 规则 1：domain list（除 _ip 外）禁含 KEYWORD/PROCESS/REGEX/IP 关键字行 ===
for f in source/*.list; do
  name="$(basename "$f" .list)"
  case "$name" in *_ip) continue ;; esac

  bad=$(grep -nE '^[[:space:]]*(DOMAIN-KEYWORD|DOMAIN-REGEX|PROCESS-|IP-CIDR|IP-CIDR6|GEOIP|GEOSITE|SRC-|DST-|RULE-SET|MATCH|AND|OR|NOT|SUB-RULE)' "$f" || true)
  if [[ -n "$bad" ]]; then
    fail "$f domain list 含禁用规则类型行（mrs 不支持，会静默失效）:"
    echo "$bad" | sed 's/^/    /' >&2
  fi

  # 裸 IP 行（无任何 wildcard/字母）
  ip_bad=$(grep -nE '^[[:space:]]*[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+(/[0-9]+)?[[:space:]]*(#.*)?$' "$f" || true)
  if [[ -n "$ip_bad" ]]; then
    fail "$f domain list 含裸 IP 行（应放 _ip.list）:"
    echo "$ip_bad" | sed 's/^/    /' >&2
  fi
done

# === 规则 2：_ip list 只能含 CIDR 表达式 ===
for f in source/*_ip.list; do
  # 提取非空非注释行
  bad=$(awk '/^[[:space:]]*#/ || /^[[:space:]]*$/ {next} \
             !/^[[:space:]]*[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+\/[0-9]+[[:space:]]*(#.*)?$/ && \
             !/^[[:space:]]*[0-9a-fA-F:]+\/[0-9]+[[:space:]]*(#.*)?$/ \
             {print FILENAME":"NR": "$0}' "$f" || true)
  if [[ -n "$bad" ]]; then
    fail "$f ipcidr list 含非 CIDR 行:"
    echo "$bad" | sed 's/^/    /' >&2
  fi
done

# === 规则 3：domain list 行内 wildcard 语法初步校验 ===
# clash domain wildcard 合法形态:
#   bare.domain.com               (DOMAIN 精确)
#   +.foo.com / +.foo.*           (SUFFIX/多段 + 单段)
#   .foo.com                      (dot wildcard)
#   *.foo.com / sub.*.foo.com     (单段 wildcard)
# 拦截：行内空格、明显非法字符
for f in source/*.list; do
  name="$(basename "$f" .list)"
  case "$name" in *_ip) continue ;; esac

  bad=$(awk '/^[[:space:]]*#/ || /^[[:space:]]*$/ {next} \
             /[[:space:]]/ && $0 !~ /^[^[:space:]]+[[:space:]]+#/ \
             {print FILENAME":"NR": "$0}' "$f" || true)
  if [[ -n "$bad" ]]; then
    fail "$f 含行内空格（域名内不应有空格；行尾 # 注释要紧贴域名后单空格）:"
    echo "$bad" | sed 's/^/    /' >&2
  fi
done

if [[ "$ec" -eq 0 ]]; then
  echo "lint OK: $(ls source/*.list 2>/dev/null | wc -l | tr -d ' ') file(s) clean"
fi
exit "$ec"
