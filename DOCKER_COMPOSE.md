Docker Compose deployment
==========================

The repository already contains a `Dockerfile` for the pool itself as well as
systemd units. The new `docker-compose.yml` stitches together all dependencies
so you can run the full stack (Zano daemon, wallet RPC, Redis, pool) with a
single command.

## Prerequisites

* Docker Engine 24+ and Docker Compose plugin 2.20+
* A compiled wallet ( `.wallet` + `.keys` ) that holds your pool funds.
  You can create it with the `simplewallet` binary that ships with Zano
  (`./simplewallet --generate-new-wallet ...`).

## One-time setup

1. 复制 `.env` 并填写你自己的参数：

   ```bash
   cp .env.example .env
   ```

   至少需要设置以下字段：

   | 变量 | 说明 |
   |------|------|
| `ZANOD_IMAGE` / `POOL_IMAGE` | 已推送到远程仓库的镜像标签 |
| `WALLET_FILE` / `WALLET_PASSWORD` | 钱包文件名及密码 |
| `POOL_ADDRESS` | 与钱包文件一致的矿池收款地址 |
| `ENV_FILE` | 提供给容器读取的 env 文件路径（默认为当前目录下 `.env`，可改成绝对路径） |
| `ZANOD_DATA_DIR` / `WALLET_DATA_DIR` | 宿主机上用于持久化区块和钱包的目录（例如 `/home/pool/zano-data`） |
   | `POOL_CONFIG_DIR` | 对应 `config.json` 与证书所在目录 |
   | `REDIS_NETWORK` | Redis 所在 Docker 网络名称（例如 `backend_default`） |
   | `POOL_REDIS_HOST` 等 | 如果 Redis 在外部网络，填写该容器的主机名/IP 和认证信息 |

2. 准备绑定目录：

   ```bash
   mkdir -p docker/config docker/zano-data docker/wallet
   cp config.json docker/config/config.json
   ```

   若要匹配 `/home/pool/...` 结构，可先创建目录再在 `.env` 中把 `ZANOD_DATA_DIR`、`WALLET_DATA_DIR` 指向对应路径，并调整这些目录的属主（例如 `sudo chown -R pool:pool /home/pool/zano-data`）。

3. 编辑 `docker/config/config.json`，让服务主机名与 Compose 内部一致：

   ```json
   "redis": { "host": "redis", ... },
   "daemon": { "host": "zanod", "port": 11211 },
   "wallet": { "host": "wallet-rpc", "port": ${WALLET_RPC_BIND_PORT} }
   ```

   Place TLS certificates (if any) in the same `docker/config` folder because
   it is mounted at `/config` inside the pool container.

4. 将钱包文件（`.wallet`、`.keys`）复制到 `docker/wallet/`，文件名必须与 `WALLET_FILE` 相同，密码也要与 `.env` 保持一致，并把该钱包的主地址填入 `POOL_ADDRESS`。

5. 如需与外部 Redis（例如 `/home/lh/qssl/backend/docker-compose.yml` 中的 `easyhash-redis`）通信，先确认 Docker 网络名称，例如：

   ```bash
    docker network ls | grep backend_default
   ```

   若名称不同，请修改 `.env` 内 `REDIS_NETWORK`。网络不存在则手动 `docker network create <name>`，或在外部 Stack 中运行 `docker compose up` 以创建网络。

## Running the stack

```bash
docker compose up -d   # build images & start containers
docker compose logs -f pool   # follow pool logs
```

The exposed ports map directly to your `config.json`:

| Service | Container port | Host port | Notes |
|---------|----------------|-----------|-------|
| `zanod` | `${ZANOD_P2P_PORT}` / `${POOL_DAEMON_PORT}`  | same      | P2P + RPC |
| `wallet-rpc` | `${WALLET_RPC_BIND_PORT}` | same | Simplewallet RPC |
| `pool` (stratum) | 3336-3338 | same | adjust to match your `poolServer.ports` |
| `pool` (API) | 2117 / 2119 | same | 2119 is optional SSL |

Stop the stack with `docker compose down`. Named volume `pool-logs` 会保留矿池日志；
区块与钱包数据存放在你在 `.env` 中指定的宿主机目录内，重启不会丢失。

## Customising

* 若已有外部 Zano 节点，可在 Compose 中移除 `zanod` 并把 `POOL_DAEMON_HOST` 指向外部 RPC。
* 如果钱包 RPC 由宿主机或其他容器提供，注释 `wallet-rpc` 服务并调整
  `POOL_WALLET_HOST` / `PORT`。
* `REDIS_NETWORK` 与 `POOL_REDIS_HOST` 允许你连接到任意已有的 Redis 集群；
  若只想本地演示，可额外添加 Redis 服务并将 `REDIS_NETWORK` 改成内部网络。
