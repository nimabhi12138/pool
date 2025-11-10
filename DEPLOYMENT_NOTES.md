# 矿池部署注意事项

以下流程基于当前项目仓库 `/home/lh/home/pool` 与 Redis Docker Compose 文件 `/home/lh/qssl/backend/docker-compose.yml` 的实际配置。按顺序执行可快速在新机器上复现环境。

## 1. 系统准备
- 建议使用 Ubuntu 20.04/22.04，具备 sudo 权限。
- 安装基础工具链（供 `node-gyp` 编译原生模块）：
  ```bash
  sudo apt update
  sudo apt install build-essential python3.10 python3.10-dev make g++
  npm config set python /usr/bin/python3.10
  ```
- 如果系统默认 Node 版本过新，使用 nvm 安装兼容版本（项目支持 Node.js 12.22.6~14.15.2）：
  ```bash
  curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.39.7/install.sh | bash
  source ~/.bashrc
  nvm install 14.15.0
  nvm use 14.15.0
  nvm alias default 14.15.0
  ```

## 2. Redis 容器部署
1. 在 `/home/lh/qssl/backend/docker-compose.yml` 已配置 `redis` 服务（镜像 `redis:7-alpine`），包含 backlog、nofile 调优以及 `restart: unless-stopped`。
2. 启动或重启 Redis：
   ```bash
   cd /home/lh/qssl/backend
   docker compose up -d redis
   ```
3. 若从零搭建，记得准备持久化目录 `/xp/www/qssl/redis`，并确保宿主机对该目录拥有写权限。

## 3. 宿主机内核调优
项目需要关闭透明大页并设置 `somaxconn = 1024`。仓库已提供脚本：
```bash
sudo /home/lh/home/pool/setup-redis-tuning.sh
```
脚本会立即生效并创建 `disable-thp.service` 与 `/etc/sysctl.d/99-redis-tuning.conf`，重启后仍保持设置。

## 4. 安全运行账户
- 为避免以 root 运行，可创建专用用户：
  ```bash
  sudo adduser --disabled-password --disabled-login pool
  # 若需要切换到该用户运行命令:
  sudo -u pool -H bash
  ```
- 该用户默认 shell 不可交互；若确实需要 `su - pool` 进入交互环境，可在保持禁用密码前提下执行 `sudo chsh -s /bin/bash pool`。
- 赋予 `pool` 访问 `/home/lh`、`/home/lh/home/zano`、`/home/lh/home/pool/logs` 等目录的权限，常用做法：
  ```bash
  sudo setfacl -m u:pool:rx /home/lh /home/lh/home
  sudo setfacl -R -m u:pool:rx /home/lh/home/zano
  sudo chown -R pool:pool /home/lh/home/pool/logs /home/pool/zano-data /home/pool/zano-wallet
  ```
- Node.js 安装在 `lh` 用户的 nvm 目录，`pool` 用户需在 `~/.bashrc` 添加：
  ```bash
  export PATH="/home/lh/.nvm/versions/node/v14.15.0/bin:$PATH"
  ```
  这样每次登录即可直接运行 `node`/`npm`；或显式调用 `/home/lh/.nvm/.../node`。

## 5. 项目依赖安装
1. 切换到仓库目录：`cd /home/lh/home/pool`
2. 安装依赖时请使用 `npm install`（不要 `npm update` 避免升级到不兼容版本）。
3. 如遇 `bignum` 等模块编译失败，确认步骤 1 的编译工具和 Python 版本设置正确，再执行：
   ```bash
  rm -rf node_modules package-lock.json
  npm install
  ```

## 6. 运行矿池后端
- Redis 在 Docker 网络内主机名为 `easyhash-redis`；若在宿主机直接运行，需要覆盖主机名：
  ```bash
  cd /home/lh/home/pool
  POOL_REDIS_HOST=127.0.0.1 node init.js
  ```
- `lib/configReader.js` 支持以下环境变量覆盖配置：
  - `POOL_REDIS_HOST`, `POOL_REDIS_PORT`, `POOL_REDIS_AUTH`, `POOL_REDIS_DB`
  - `POOL_DAEMON_HOST`, `POOL_DAEMON_PORT`
  - `POOL_WALLET_HOST`, `POOL_WALLET_PORT`
- 如需覆盖区块链 Daemon / 钱包 RPC，可追加自定义变量（建议在 `configReader.js` 中按需扩展），或直接编辑 `config.json`：
  - `daemon.host` / `daemon.port`（默认 `127.0.0.1:11211`）
  - `wallet.host` / `wallet.port`（默认 `127.0.0.1:39996`）
- 运行后端后，API 会监听 `0.0.0.0:2117`，矿池端口默认为 3336/3337/3338。
- 如果日志中持续出现 `Zano error from daemon`，说明 Daemon 未启动或地址配置错误；需先部署并开放对应 RPC。

## 7. 区块链守护进程与钱包 RPC
1. **时间同步必需**：`zanod` 会在系统时间漂移超过 300 秒时直接退出。建议改用 `chrony` 并立即对齐时间：
   ```bash
   sudo apt install chrony -y
   sudo systemctl enable --now chrony
   sudo chronyc makestep
   chronyc tracking
   timedatectl status   # System clock synchronized 应为 yes
   ```
2. **准备数据目录**：
   ```bash
   sudo mkdir -p /home/pool/zano-data /home/pool/zano-wallet
   sudo chown -R pool:pool /home/pool/zano-data /home/pool/zano-wallet
   ```
3. **启动守护进程**（使用 `pool` 用户）：
   ```bash
   /home/lh/home/zano/build/src/zanod \
     --data-dir=/home/pool/zano-data \
     --log-dir=/home/pool/zano-data/logs \
     --rpc-bind-ip=0.0.0.0 --rpc-bind-port=11211 \
     --p2p-bind-ip=0.0.0.0 --p2p-bind-port=34444 \
     --hide-my-port &
   ```
   - 初次运行会自动预下载区块数据库（约 10 GB），期间日志会显示下载进度与 “SYNCHRONIZATION started”。可用 `./build/src/zanod --command "status"` 查看高度。
4. **启动钱包 RPC**：
   ```bash
   /home/lh/home/zano/build/src/simplewallet \
     --wallet-file /home/pool/zano-wallet/pool_wallet \
     --password "<钱包密码>" \
     --daemon-address 127.0.0.1:11211 \
     --rpc-bind-ip 0.0.0.0 \
     --rpc-bind-port 39996 \
     --log-file /home/pool/zano-wallet/simplewallet.log &
   ```
   - 此版本不支持 `--rpc-login`/`--trusted-daemon`，如需限制访问请在防火墙层面控制来源。
5. **确认端口**：`ss -tlnp | grep -E '11211|34444|39996'`，确保 RPC、P2P 监听正常后再启动矿池。

## 8. 前端访问
1. 修改 `website_example/config.js` 中的 `api` 变量，使其指向后端 API，例如：
   ```js
   var api = "http://<服务器IP或域名>:2117";
   ```
2. 临时预览可使用静态服务器：
   ```bash
   npx serve website_example -l 8081
   # 或 python3 -m http.server 8081 -d website_example
   ```
   在浏览器访问 `http://<服务器IP>:8081`。
3. 正式部署时，将 `website_example/` 静态文件复制到 Nginx/Apache 等 Web 服务器目录即可。

## 9. 常见问题
- **EAI_AGAIN easyhash-redis**：说明程序在宿主机运行但仍使用容器内主机名，设置 `POOL_REDIS_HOST=127.0.0.1` 即可。
- **ECONNREFUSED 11211 / 39996**：区块链守护进程或钱包 RPC 未就绪，确保服务运行并允许网络访问。
- **node-gyp “invalid mode: 'rU'”**：Python 版本过新（3.12+）。安装 Python 3.10 并通过 `npm config set python` 指定。
- **端口被占用**：静态服务器提示“端口已被使用”时可更换端口（如 8081），或停止占用 8080 的服务。
- **Core is busy / bad response from daemon**：Zano 节点仍在同步或尚未连接成功，检查 `zanod` 日志高度以及系统时间是否同步。
- **Failed to bind server / Address already in use**：说明 `34444` P2P 或 `11211` RPC 端口已有残留进程，检查 `pgrep zanod` 和 `ss -tlnp | grep 34444`，先停止旧进程或更换端口再启动。
- **时间同步导致守护进程退出**：使用 `chronyc makestep` 立即对齐，并确保 `timedatectl status` 的 `System clock synchronized` 为 `yes`。
- **矿机被封禁无法连接**：若日志出现 `Duplicate share ... Banned`，进入 Redis 容器 `docker exec -it easyhash-redis redis-cli`，用 `SCAN 0 MATCH Zano:bans:* COUNT 50` 查看封禁列表，`DEL Zano:bans::ffff:<IP>` 删除特定 IP。
- **前端 Worker Stats 不加载 `/stats_address`**：`common.js` 默认给 cookies 加 `Secure`，在 HTTP 环境下浏览器会直接丢弃，导致 `getCurrentAddress` 取不到地址。若使用纯 HTTP 预览页面，需要修改 `docCookies.setItem`（或合并最新代码）让 `Secure` 属性只在 HTTPS 时添加，否则查找按钮不会发出 `stats_address` 请求。

按照以上说明准备环境，即可在任意新机器上快速部署矿池、Redis 容器以及前端页面。需要自动化部署时，可将这些步骤编入脚本或 Ansible 任务。
