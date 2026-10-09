# 233boy/Xray (https://github.com/233boy/Xray) 风格的 VLESS + Reality 服务端镜像
#
# 说明: 233boy 的 install.sh 是给整台 VPS 用的(systemd 服务/交互式菜单/bbr 调优),
#       不适合直接塞进容器; 本镜像复刻它生成的 VLESS-REALITY 配置:
#       flow=xtls-rprx-vision, SNI 随机取自 amazon/ebay/paypal/aws, xray x25519 密钥对,
#       sniffing routeOnly, 屏蔽 BT/国内IP/内网IP, 分享链接格式与 `xray info` 一致。
#
# 构建镜像:
#   docker build -t xray-reality .
#   国内加速: docker build --build-arg GITHUB_MIRROR=https://ghfast.top/ -t xray-reality .
#   指定版本: docker build --build-arg XRAY_VERSION=v26.3.27 -t xray-reality .
#
# 运行 (host 网络, 端口直通, 最省事):
#   docker run -d --name xray --restart unless-stopped --network host xray-reality
# 运行 (桥接网络 + 数据持久化, 重建容器后 UUID/密钥不变):
#   docker run -d --name xray --restart unless-stopped -p 443:443 -v xray-data:/etc/xray xray-reality
#
# 查看连接信息 (地址/端口/UUID/SNI/公钥/分享链接):
#   docker logs xray            (启动时自动打印)
#   docker exec xray info       (随时查看)
#
# 常用环境变量 (均有默认值, 可不填):
#   XRAY_PORT=443            监听端口
#   XRAY_UUID=               不填则随机生成并持久化到 /etc/xray/.uuid
#   XRAY_SNI=www.paypal.com 伪装域名 (233boy 候选: amazon/ebay/paypal/aws)
#   XRAY_PRIVATE_KEY=        Reality 私钥, 不填则 xray x25519 随机生成并持久化
#   XRAY_PUBLIC_KEY=         Reality 公钥, 只给私钥时会自动推导, 可不填
#   XRAY_ADDR=               分享链接里的服务器地址, 不填自动探测公网 IP
#   XRAY_LOG_LEVEL=warning   日志级别
#   XRAY_ACCESS_LOG=/dev/null  访问日志位置, 改 /dev/stdout 可在 docker logs 看到连接记录
#   XRAY_BAN_BT=true         屏蔽 BT (default: true, 与 233boy 一致)
#   XRAY_BAN_CN=true         屏蔽访问国内 IP (default: true, 与 233boy 一致)
#   XRAY_BAN_PRIVATE=true    屏蔽访问内网 IP (default: true, 与 233boy 一致)
#
# 客户端: v2rayN / v2rayNG / Shadowrocket / Clash.Meta 等, 导入 docker logs 里的分享链接即可
#
# 网络优化 (宿主机执行, 与 233boy 脚本调优等效):
#   sysctl -w net.core.default_qdisc=fq
#   sysctl -w net.ipv4.tcp_congestion_control=bbr

FROM alpine:3.20 AS builder

# 可选参数:
#   XRAY_VERSION  固定 Xray-core 版本 (默认 v26.3.27, 也可 latest)
#   GITHUB_MIRROR GitHub 下载加速前缀, 注意以 / 结尾, 如 https://ghfast.top/
ARG XRAY_VERSION=v26.3.27
ARG GITHUB_MIRROR=

RUN apk add --no-cache curl unzip

ARG TARGETARCH

RUN set -eux; \
    case "${TARGETARCH}" in \
      amd64) XRAY_ARCH=64 ;; \
      arm64) XRAY_ARCH=arm64-v8a ;; \
      *) echo "不支持的架构: ${TARGETARCH} (233boy/Xray 仅支持 64 位系统)" >&2; exit 1 ;; \
    esac; \
    case "$GITHUB_MIRROR" in \
      '' | */) ;; \
      *) GITHUB_MIRROR="$GITHUB_MIRROR/" ;; \
    esac; \
    case "$XRAY_VERSION" in \
      latest) BASE="${GITHUB_MIRROR}https://github.com/XTLS/Xray-core/releases/latest/download" ;; \
      *) BASE="${GITHUB_MIRROR}https://github.com/XTLS/Xray-core/releases/download/${XRAY_VERSION}" ;; \
    esac; \
    ZIP="Xray-linux-${XRAY_ARCH}.zip"; \
    curl -fsSL --retry 3 -o /tmp/xray.zip "${BASE}/${ZIP}"; \
    curl -fsSL --retry 3 -o /tmp/xray.zip.dgst "${BASE}/${ZIP}.dgst"; \
    EXPECTED_SHA256="$(sed -n -e 's/^SHA256= *//p' -e 's/^SHA2-256= *//p' /tmp/xray.zip.dgst | head -n1)"; \
    [ -n "$EXPECTED_SHA256" ] || { echo '无法从 dgst 文件解析 SHA256' >&2; exit 1; }; \
    printf '%s  %s\n' "$EXPECTED_SHA256" /tmp/xray.zip | sha256sum -c -; \
    mkdir -p /out; \
    unzip -q /tmp/xray.zip -d /out

FROM alpine:3.20

LABEL org.opencontainers.image.title="xray-reality" \
      org.opencontainers.image.description="233boy/Xray 风格的 VLESS + Reality 服务端 (无需域名和证书, 抗主动探测)" \
      org.opencontainers.image.source="https://github.com/233boy/Xray"

RUN apk add --no-cache jq ca-certificates \
 && mkdir -p /etc/xray /usr/local/share/xray

COPY --from=builder /out/xray /usr/local/bin/xray
COPY --from=builder /out/geoip.dat /out/geosite.dat /usr/local/share/xray/

RUN chmod +x /usr/local/bin/xray

# 233boy 脚本生成的 VLESS-REALITY 服务端配置模板 (entrypoint 以它为底稿, 用 jq 注入环境变量)
# 日志: error 输出到容器 stderr, docker logs 可见; access 默认 /dev/null 避免公网扫描刷屏
RUN cat > /usr/local/share/xray/config.default.json <<'JSON'
{
  "log": {
    "access": "/dev/null",
    "error": "/dev/stderr",
    "loglevel": "warning"
  },
  "dns": {},
  "inbounds": [
    {
      "tag": "vless-reality",
      "listen": "0.0.0.0",
      "port": 443,
      "protocol": "vless",
      "settings": {
        "clients": [
          {
            "id": "uuid",
            "flow": "xtls-rprx-vision"
          }
        ],
        "decryption": "none"
      },
      "streamSettings": {
        "network": "tcp",
        "security": "reality",
        "realitySettings": {
          "dest": "REPLACE-ME.example.com:443",
          "serverNames": ["REPLACE-ME.example.com", ""],
          "publicKey": "REPLACE-ME-PUBLIC-KEY",
          "privateKey": "REPLACE-ME-PRIVATE-KEY",
          "shortIds": [""]
        }
      },
      "sniffing": {
        "enabled": true,
        "destOverride": ["http", "tls"],
        "routeOnly": true
      }
    }
  ],
  "outbounds": [
    {
      "tag": "direct",
      "protocol": "freedom",
      "settings": {}
    },
    {
      "tag": "block",
      "protocol": "blackhole",
      "settings": {}
    }
  ],
  "routing": {
    "domainStrategy": "IPIfNonMatch",
    "rules": [
      {
        "type": "field",
        "protocol": ["bittorrent"],
        "outboundTag": "block"
      },
      {
        "type": "field",
        "ip": ["geoip:cn"],
        "outboundTag": "block"
      },
      {
        "type": "field",
        "ip": ["geoip:private"],
        "outboundTag": "block"
      }
    ]
  }
}
JSON

# 入口脚本 (启动时根据环境变量生成 config.json, 校验后打印分享链接并启动 xray)
RUN cat > /usr/local/bin/entrypoint.sh <<'ENTRYPOINT'
#!/bin/sh
# 生成 233boy 风格的 VLESS + Reality 配置并启动 xray。
# 若挂载了自己的 /etc/xray/config.json (非本脚本生成), 则直接使用它。
set -eu

CONFIG_DIR=/etc/xray
CONFIG="$CONFIG_DIR/config.json"
MARKER="$CONFIG_DIR/.generated-by-entrypoint"
TEMPLATE=/usr/local/share/xray/config.default.json

log() { printf '[entrypoint] %s\n' "$*"; }
die() { printf '[entrypoint] 错误: %s\n' "$*" >&2; exit 1; }

# 允许 docker run <镜像> <命令> 直接覆盖入口, 例如: docker run -it xray-reality sh
if [ "$#" -gt 0 ]; then
  exec "$@"
fi

if [ -f "$CONFIG" ] && [ ! -f "$MARKER" ]; then
  log "检测到挂载/自带的配置文件, 直接使用: $CONFIG (忽略 XRAY_* 环境变量)"
else
  # 挂载卷不可写时退回到 /tmp, 保证容器仍能启动
  if ! touch "$CONFIG_DIR/.write-test" 2>/dev/null; then
    log "警告: $CONFIG_DIR 不可写 (多为挂载目录属主问题), 配置改生成到 /tmp/xray/"
    CONFIG_DIR=/tmp/xray
    mkdir -p "$CONFIG_DIR"
    CONFIG="$CONFIG_DIR/config.json"
    MARKER="$CONFIG_DIR/.generated-by-entrypoint"
  else
    rm -f "$CONFIG_DIR/.write-test"
  fi

  PORT="${XRAY_PORT:-443}"
  LOGLEVEL="${XRAY_LOG_LEVEL:-warning}"
  ACCESS="${XRAY_ACCESS_LOG:-/dev/null}"
  BAN_BT="${XRAY_BAN_BT:-true}"
  BAN_CN="${XRAY_BAN_CN:-true}"
  BAN_PRIVATE="${XRAY_BAN_PRIVATE:-true}"

  case "$PORT" in
    '' | *[!0-9]*) die "XRAY_PORT 必须是数字, 当前值: $PORT" ;;
  esac
  [ "$PORT" -ge 1 ] && [ "$PORT" -le 65535 ] || die "XRAY_PORT 超出范围 (1-65535): $PORT"
  for v in BAN_BT BAN_CN BAN_PRIVATE; do
    eval "val=\${$v}"
    case "$val" in
      true | false) ;;
      *) die "$v 只能是 true 或 false, 当前值: $val" ;;
    esac
  done

  # ---- UUID: 环境变量 > 上次生成的 > 随机生成 (与 233boy 一样用 xray uuid) ----
  if [ -n "${XRAY_UUID:-}" ]; then
    UUID="$XRAY_UUID"
  elif [ -f "$CONFIG_DIR/.uuid" ]; then
    UUID="$(cat "$CONFIG_DIR/.uuid")"
    log "使用上次生成的 UUID: $UUID"
  else
    UUID="$(xray uuid)"
    printf '%s' "$UUID" > "$CONFIG_DIR/.uuid"
    chmod 600 "$CONFIG_DIR/.uuid"
    log "未设置 XRAY_UUID, 已随机生成并保存到 $CONFIG_DIR/.uuid"
  fi

  # ---- SNI: 环境变量优先, 默认 www.paypal.com (镜像 ENV 已内置) ----
  SNI="${XRAY_SNI:-www.paypal.com}"
  case "$SNI" in
    '' | *[[:space:]:/]* | *'='*) die "XRAY_SNI 格式不正确: $SNI" ;;
  esac

  # ---- Reality 密钥对: 环境变量 > 上次生成的 > xray x25519 随机 ----
  if [ -n "${XRAY_PRIVATE_KEY:-}" ]; then
    PVK="$XRAY_PRIVATE_KEY"
    if [ -n "${XRAY_PUBLIC_KEY:-}" ]; then
      PBK="$XRAY_PUBLIC_KEY"
    else
      # 兼容新旧输出格式: 旧版 "Public key: x", v25+ "Password (PublicKey): x"
      PBK="$(xray x25519 -i "$PVK" | awk '/ublic/{print $NF; exit}')"
      [ -n "$PBK" ] || die "无法从 XRAY_PRIVATE_KEY 推导公钥, 请检查私钥格式"
    fi
    log "使用环境变量提供的 Reality 密钥对"
  elif [ -f "$CONFIG_DIR/.private_key" ]; then
    PVK="$(cat "$CONFIG_DIR/.private_key")"
    PBK="$(cat "$CONFIG_DIR/.public_key")"
    log "使用上次生成的 Reality 密钥对"
  else
    KEYS="$(xray x25519)"
    # 兼容新旧输出格式: 旧版 "Private key: x / Public key: x",
    # v25+ "PrivateKey: x / Password (PublicKey): x", 取行尾字段即可
    PVK="$(printf '%s\n' "$KEYS" | awk '/Privat/{print $NF; exit}')"
    PBK="$(printf '%s\n' "$KEYS" | awk '/ublic/{print $NF; exit}')"
    [ -n "$PVK" ] && [ -n "$PBK" ] || die "xray x25519 生成密钥失败"
    printf '%s' "$PVK" > "$CONFIG_DIR/.private_key"
    printf '%s' "$PBK" > "$CONFIG_DIR/.public_key"
    chmod 600 "$CONFIG_DIR/.private_key"
    log "未设置 XRAY_PRIVATE_KEY, 已随机生成 Reality 密钥对并保存到 $CONFIG_DIR"
  fi

  # ---- 服务器地址 (仅用于拼分享链接): 环境变量 > 自动探测公网 IP ----
  ADDR="${XRAY_ADDR:-}"
  if [ -z "$ADDR" ]; then
    ADDR="$(wget -qO- -T 8 https://one.one.one.one/cdn-cgi/trace 2>/dev/null | sed -n 's/^ip=//p' | head -n1 || true)"
  fi
  if [ -z "$ADDR" ]; then
    ADDR="$(hostname -i | awk '{print $1}')"
    log "警告: 未能探测到公网 IP, 分享链接暂用容器 IP ($ADDR), 如有误请设置 XRAY_ADDR 环境变量"
  fi
  # ---- 用 jq 生成配置, 保证特殊字符被正确转义 ----
  jq --argjson port "$PORT" \
     --arg uuid "$UUID" \
     --arg sni "$SNI" \
     --arg pbk "$PBK" \
     --arg pvk "$PVK" \
     --arg access "$ACCESS" \
     --arg loglevel "$LOGLEVEL" \
     --argjson banBt "$BAN_BT" \
     --argjson banCn "$BAN_CN" \
     --argjson banPrivate "$BAN_PRIVATE" \
     '.log.access = $access
      | .log.loglevel = $loglevel
      | .inbounds[0].port = $port
      | .inbounds[0].settings.clients[0].id = $uuid
      | .inbounds[0].streamSettings.realitySettings.dest = ($sni + ":443")
      | .inbounds[0].streamSettings.realitySettings.serverNames = [$sni, ""]
      | .inbounds[0].streamSettings.realitySettings.publicKey = $pbk
      | .inbounds[0].streamSettings.realitySettings.privateKey = $pvk
      | .routing.rules = [
          (if $banBt then {"type":"field","protocol":["bittorrent"],"outboundTag":"block"} else empty end),
          (if $banCn then {"type":"field","ip":["geoip:cn"],"outboundTag":"block"} else empty end),
          (if $banPrivate then {"type":"field","ip":["geoip:private"],"outboundTag":"block"} else empty end)
        ]' \
     "$TEMPLATE" > "$CONFIG.tmp"
  mv "$CONFIG.tmp" "$CONFIG"
  touch "$MARKER"

  # ---- 打印连接信息 (info 脚本统一生成, 也可随时手动执行: docker exec xray info) ----
  XRAY_ADDR="$ADDR" info
fi

# ---- 校验配置并启动 (兼容新旧两种 CLI 形式) ----
if xray run -test -c "$CONFIG" >/dev/null 2>&1; then
  log "配置校验通过, 启动 xray"
  exec xray run -c "$CONFIG"
elif xray -test -config "$CONFIG" >/dev/null 2>&1; then
  log "配置校验通过, 启动 xray"
  exec xray -config "$CONFIG"
else
  xray run -test -c "$CONFIG" || true
  die "配置文件校验失败: $CONFIG"
fi
ENTRYPOINT

RUN chmod +x /usr/local/bin/entrypoint.sh

# 连接信息/分享链接查看脚本 (docker exec xray info; 从实际生效的 config.json 读取)
RUN cat > /usr/local/bin/info <<'INFO'
#!/bin/sh
# 打印 VLESS + Reality 连接信息与分享链接 (用法: docker exec xray info)
set -eu
die() { printf '[info] 错误: %s\n' "$*" >&2; exit 1; }

CONFIG="${XRAY_CONFIG:-/etc/xray/config.json}"
[ -f "$CONFIG" ] || die "找不到配置文件: $CONFIG (容器可能尚未完成初始化)"

PORT="$(jq -r '.inbounds[0].port' "$CONFIG")"
UUID="$(jq -r '.inbounds[0].settings.clients[0].id' "$CONFIG")"
SNI="$(jq -r '.inbounds[0].streamSettings.realitySettings.serverNames[0] // empty' "$CONFIG")"
PBK="$(jq -r '.inbounds[0].streamSettings.realitySettings.publicKey // empty' "$CONFIG")"
FLOW="$(jq -r '.inbounds[0].settings.clients[0].flow // "xtls-rprx-vision"' "$CONFIG")"

[ -n "$SNI" ] && [ -n "$PBK" ] || die "$CONFIG 不是 VLESS+Reality 配置, 无法生成分享链接"

# 服务器地址: 环境变量 > 重新探测公网 IP (仅用于拼分享链接)
ADDR="${XRAY_ADDR:-}"
if [ -z "$ADDR" ]; then
  ADDR="$(wget -qO- -T 8 https://one.one.one.one/cdn-cgi/trace 2>/dev/null | sed -n 's/^ip=//p' | head -n1 || true)"
fi
if [ -z "$ADDR" ]; then
  ADDR="$(hostname -i | awk '{print $1}')"
  printf '[info] 警告: 未能探测到公网 IP, 链接暂用 %s, 如有误请在运行容器时设置 XRAY_ADDR\n' "$ADDR" >&2
fi
# IPv6 地址放进 URL 时需要中括号
case "$ADDR" in
  *:*) ADDR_LINK="[$ADDR]" ;;
  *) ADDR_LINK="$ADDR" ;;
esac

echo
echo "================================================"
echo " Xray (VLESS + REALITY) 连接信息"
echo "------------------------------------------------"
echo " 地址 (address)      : $ADDR"
echo " 端口 (port)         : $PORT"
echo " 用户ID (uuid)       : $UUID"
echo " 流控 (flow)         : $FLOW"
echo " 加密 (encryption)   : none"
echo " 传输协议 (network)  : tcp"
echo " 伪装域名 (sni)      : $SNI"
echo " 公钥 (publicKey)    : $PBK"
echo " 指纹 (fingerprint)  : chrome"
echo "------------------------------------------------"
echo " 分享链接:"
echo " vless://$UUID@$ADDR_LINK:$PORT?encryption=none&security=reality&flow=$FLOW&type=tcp&sni=$SNI&pbk=$PBK&fp=chrome#xray-reality-$ADDR"
echo "================================================"
echo " 提示: v2rayN / v2rayNG / Shadowrocket 等客户端可直接导入以上链接"
echo
INFO

RUN chmod +x /usr/local/bin/info

# 告诉 xray 去哪里找 geoip.dat / geosite.dat
ENV XRAY_LOCATION_ASSET=/usr/local/share/xray \
    XRAY_PORT=443 \
    XRAY_SNI=www.paypal.com \
    XRAY_LOG_LEVEL=warning \
    XRAY_ACCESS_LOG=/dev/null \
    XRAY_BAN_BT=true \
    XRAY_BAN_CN=true \
    XRAY_BAN_PRIVATE=true

# Reality 只走 TCP
EXPOSE 443/tcp

# 以 root 运行以便绑定 443 等特权端口 (host 网络模式); 换高位端口后可自行改回非 root
USER root
WORKDIR /etc/xray

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
