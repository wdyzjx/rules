# wdyzjx/rules

[mihomo](https://github.com/MetaCubeX/mihomo) 规则集中央仓，与 [`clash-air-full`](https://we-gt.wdyzjxchy.top/tools/clash_air_config) 主仓配套：把零散的 `DOMAIN-SUFFIX` / `DOMAIN-KEYWORD` 行从主仓 `Merge.yaml` 抽离，统一成 mrs 二进制规则集，订阅端按 `rule-providers` 直拉。

## 仓库结构

```
source/                   # 人维护的源 list（含注释 + wildcard 注解）
├── direct.list           # 公共直连：DoH 自上游 + 镜像 + 海外可达 CDN
├── airport.list          # 机场节点域名（wildcard 覆盖任意 TLD）
├── intranet_dod.list     # 阿里相关 + 内网域名
├── intranet_dod_ip.list  # 内网 IP 段（30/8、11/8）
├── proxylite_domain.list # 强制代理白名单·域名（fork qichiyu/rule）
├── proxylite_ip.list     # 强制代理白名单·IP（fork qichiyu/rule）
└── node_probe.list       # 节点测试探针补充（ping0/ippure/browserleaks）

dist/                     # mihomo convert-ruleset 产物，进 git
├── direct.mrs
├── airport.mrs
├── intranet_dod.mrs
├── intranet_dod_ip.mrs
├── proxylite_domain.mrs
├── proxylite_ip.mrs
└── node_probe.mrs

scripts/
├── lint.sh               # source/*.list fail-loud 校验
└── build.sh              # lint → mihomo convert-ruleset 批量

.gitignore                # 含 .gitconfig-inc
```

## 命名约定

| 文件 | 行为 | 内容 |
|---|---|---|
| `*_ip.list` | `ipcidr` → mrs | 一行一个 CIDR |
| 其他 `*.list` | `domain` → mrs | 一行一个 mihomo clash domain wildcard |

`build.sh` 按文件名后缀自动判 behavior，全部输出到 `dist/*.mrs`。

## 维护流程

```bash
# 1. 改 source/*.list
vim source/direct.list

# 2. 跑 lint + build（mihomo convert-ruleset）
bash scripts/build.sh

# 3. 看 dist/ 变化
git diff dist/

# 4. commit + push
git add source dist
git commit -m "<scope>: <change>"
git push origin main
```

订阅端 mihomo（含 `clash-air-full` 主仓的 `Merge.yaml`）通过 `rule-providers` URL 直拉本仓 `dist/*.mrs`，例：

```yaml
rule-providers:
  direct: { type: http, behavior: domain, format: mrs, interval: 86400,
            url: "https://gh-proxy.com/raw.githubusercontent.com/wdyzjx/rules/main/dist/direct.mrs" }
```

主仓 `clash-air-full` 改完后必须 bump Sub-Store cacheKey + `refresh-airport`，否则订阅端拿到旧产物（详见主仓 `docs/lessons/19`）。**改 `wdyzjx/rules` 本仓不需要 bump cacheKey**——mihomo rule-provider interval 到点会自动重拉。

## 关键约束（写 `source/*.list` 前必看）

### mihomo `.mrs` 只支持 domain / ipcidr，不支持 classical
- `DOMAIN-KEYWORD` / `DOMAIN-REGEX` / `PROCESS-*` / `IP-CIDR`（在 domain.list）**全部 mrs 化失败**。
- `convert-ruleset` 会**静默接受**这些行（exit 0）但 mrs 语义丢失——`lint.sh` 主动拦截。

### Clash domain wildcard 语义（mihomo `component/trie/domain.go`）
- `*` 严格匹配 **1 个 label**（不含 `.`）
- `+` 多段，只能在最左：`+.foo.com` = `foo.com` + 任意层子域
- `.` dot wildcard，多段但不含裸域名：`.foo.com` = 任意层子域（不含 `foo.com` 本身）

### "任意 TLD" 实现
KEYWORD 等价"任意位置含子串"语义在 mrs 下做不到一行覆盖。本仓约定：
```
+.X.*       # 覆盖 X.com / X.io / xxx.X.tw 等单段 TLD
+.X.*.*     # 覆盖 X.com.tw / xxx.X.com.hk 等双段 TLD（真实 ccTLD 最多 2 段）
```
两行收口覆盖 99%+ 真实场景，**比 KEYWORD 更精确**（不会误伤 label 内部含 X 子串的无关域名）。

机制级证据：mihomo `component/trie/domain_test.go` 的 `TestTrie_Wildcard`，覆盖 `+.stun.*.*` 命中 `global.stun.website.com` 等用例。

## Attribution

`proxylite_domain.list` / `proxylite_ip.list` fork 自 [qichiyuhub/rule](https://github.com/qichiyuhub/rule) `rules/proxy.list`（无 LICENSE 文件，社区 fair use；本仓仅用于个人 mihomo 配置，未重新发行）。

其余文件原创。

## License

本仓自有内容 CC0 1.0 Universal（详见 [`LICENSE`](LICENSE)）。fork 部分维持原作者权利。
