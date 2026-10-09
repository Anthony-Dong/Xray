# Xray (VLESS + Reality) Docker 镜像

本仓库是 [233boy/Xray](https://github.com/233boy/Xray) 的 **Docker 化维护分支**：不再使用整机的 systemd 安装脚本，改为一个**自包含的 Docker 镜像**来部署和维护 233boy 风格的 **VLESS + Reality** 服务端——无需自己的域名和证书，TLS 握手直接"借用"真实大网站的证书，抗主动探测能力最强。

> 上游原脚本的使用文档见 [old_readme.md](old_readme.md)。

## 镜像特性

- Xray-core v26.3.27 静态二进制，多阶段构建 + SHA256 校验，支持 amd64 / arm64
- 复刻 233boy 脚本生成的 VLESS-REALITY 配置：`flow=xtls-rprx-vision`、屏蔽 BT / 国内 IP / 内网 IP
- UUID / x25519 密钥对首次启动自动生成并持久化到数据卷，重启 / 重建容器不变
- 内置 `info` 命令，随时查看连接信息与分享链接
- 运行时零依赖：宿主机不需要安装任何东西（104MB，全部打包在镜像里）

## 快速开始

### 方式一：直接用仓库里的镜像包（免构建）

```bash
docker load < xray-reality-image.tar.gz
docker run -d --name xray --restart unless-stopped --network host -v xray-data:/etc/xray xray-reality
```

> 仓库里的 `xray-reality-image.tar.gz` 是手工导出的快照（2026-10-09, Xray v26.3.27），可能落后于 Dockerfile；要最新请用方式二自己构建。

### 方式二：自己构建

```bash
docker build -t xray-reality .
# 国内加速:  docker build --build-arg GITHUB_MIRROR=https://ghfast.top/ -t xray-reality .
# 固定版本:  docker build --build-arg XRAY_VERSION=v26.3.27 -t xray-reality .
```

## 查看连接信息 / 分享链接

```bash
docker exec xray info     # 随时打印 地址/端口/UUID/SNI/公钥/分享链接
docker logs xray          # 启动时也会自动打印一次
```

用 v2rayN / v2rayNG / Shadowrocket / Clash.Meta 等客户端导入分享链接即可。

## 环境变量（均有默认值，可不填）

| 变量 | 默认值 | 说明 |
|---|---|---|
| `XRAY_PORT` | `443` | 监听端口 |
| `XRAY_SNI` | `www.paypal.com` | 伪装域名（233boy 候选: amazon/ebay/paypal/aws） |
| `XRAY_UUID` | 随机生成并持久化 | 用户 ID |
| `XRAY_PRIVATE_KEY` / `XRAY_PUBLIC_KEY` | 随机生成并持久化 | Reality 密钥对，只给私钥会自动推导公钥 |
| `XRAY_ADDR` | 自动探测公网 IP | 分享链接里拼的服务器地址 |
| `XRAY_LOG_LEVEL` | `warning` | 日志级别 |
| `XRAY_ACCESS_LOG` | `/dev/null` | 访问日志，改 `/dev/stdout` 可在 docker logs 看连接记录 |
| `XRAY_BAN_BT` / `XRAY_BAN_CN` / `XRAY_BAN_PRIVATE` | `true` | 屏蔽 BT / 国内 IP / 内网 IP |

## 日常维护

```bash
docker stop xray        # 停止
docker start xray       # 启动
docker restart xray     # 重启
docker rm -f xray       # 删除容器 (xray-data 卷保留, 凭据不丢)
docker logs -f xray     # 跟踪日志
```

升级 Xray 版本：改 Dockerfile 里的 `XRAY_VERSION`（或 `latest`）→ `docker build` → `docker rm -f xray` → 重新 `docker run`。数据卷不动，客户端无感知。

## 备份与迁移

镜像和凭据各导一份：

```bash
docker save xray-reality | gzip > xray-reality-image.tar.gz
tar -czf xray-data-backup.tar.gz -C /var/lib/docker/volumes/xray-data/_data .
```

新机器恢复：

```bash
docker load < xray-reality-image.tar.gz
mkdir -p /var/lib/docker/volumes/xray-data/_data
tar -xzf xray-data-backup.tar.gz -C /var/lib/docker/volumes/xray-data/_data
docker run -d --name xray --restart unless-stopped --network host -v xray-data:/etc/xray xray-reality
```

UUID / 公钥 / SNI 原样迁移，客户端零改动。**注意**：`xray-data-backup.tar.gz` 含私钥，不要提交到仓库或放到不安全的地方（已在 .gitignore 中排除）。

## 与上游脚本 (old_readme.md) 的差异

| 上游 233boy 脚本 | 本镜像 |
|---|---|
| systemd 服务管理 | Docker 容器 + `--restart unless-stopped` |
| 交互式 `xray` 管理命令 | `docker exec xray info` |
| 一键 bbr 等内核调优 | 宿主机自行执行 `sysctl` |
| 安装时随机选 SNI | 固定默认 `www.paypal.com`（环境变量可改） |
| 整机安装，重装麻烦 | 镜像零依赖，`docker save/load` 随处迁移 |

配置生成逻辑复刻自上游 `src/core.sh` 的 VLESS-REALITY 分支；上游更新后，同步成本就是改一个版本号或模板。
