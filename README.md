# tcpr

`tcpr` 是一个交互式菜单管理工具，用于管理 [TCP-preconnection-relay](https://github.com/Xeloan/TCP-preconnection-relay) 的预连接实例。

> **Fork notice**
> 本项目 fork 自 [Xeloan/TCP-preconnection-relay](https://github.com/Xeloan/TCP-preconnection-relay)。
> 原项目提供了 TCP 预连接转发的核心 C 程序与 systemd 服务模板；本仓库在其基础上增加了一个交互式管理脚本 `tcpr`，用于简化日常增删改查与启停操作。

---

## 功能

- 列出所有预连接实例及其运行状态
- 新增实例（IP、本地/远端端口、TCP/UDP）
- 修改某个实例的 IP 或端口
- 删除实例（带二次确认）
- 启动 / 停止 / 重启单个实例或全部实例
- 实时查看某个实例的 `journalctl` 日志
- 直接 nano 编辑 `relays.conf`
- 一键把脚本安装到 `/usr/local/bin/tcpr`，之后任意位置敲 `tcpr` 进菜单

修改 / 新增配置后会**自动重启对应实例**，不需要手动 `systemctl restart`。

---

## 前置条件

在使用 `tcpr` 之前，必须先安装上游的 TCP-preconnection-relay：

```bash
# 上游原始安装命令，参见 https://github.com/Xeloan/TCP-preconnection-relay
bash <(curl -L https://raw.githubusercontent.com/Xeloan/TCP-preconnection-relay/main/install.sh)
```

`tcpr` 依赖以下由上游安装脚本提供的组件：

- `/etc/tcp_pool/relays.conf` — 主配置文件
- `/usr/local/bin/tcp-pool-parse` — 配置解析器
- `/usr/local/bin/tcp-pool-start` — 一键启停脚本
- `/etc/systemd/system/tcp-pool@.service` — systemd 模板服务

---

## 安装

### 一键安装（推荐）

直接拉脚本到 `/usr/local/bin/tcpr` 并赋可执行权限，全程不留临时文件：

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/chnnic/TCPR/refs/heads/main/tcpr.sh) --install
```

完成后任意位置输入：

```bash
tcpr
```

即可进入管理菜单。

### 手动安装

```bash
curl -L -o /root/tcpr.sh \
  https://raw.githubusercontent.com/chnnic/TCPR/refs/heads/main/tcpr.sh
chmod +x /root/tcpr.sh
/root/tcpr.sh
```

进入菜单后选 **11) 把当前本地脚本安装到 /usr/local/bin/tcpr** 即可。

### 更新

```bash
tcpr --update
# 或在菜单里选 10) 从 GitHub 安装/更新 tcpr
```

---

## 菜单一览

```
  1)  新增实例 (add)
  2)  修改实例 (edit IP / 端口)
  3)  删除实例 (del)
  4)  启动实例 (start)
  5)  停止实例 (stop)
  6)  重启实例 (restart)
  7)  查看实例日志 (log)
  8)  一键重启全部 (tcp-pool-start)
  9)  编辑原始 relays.conf (nano)
 10)  从 GitHub 安装/更新 tcpr 到 /usr/local/bin/tcpr
 11)  把当前本地脚本安装到 /usr/local/bin/tcpr
 12)  卸载快捷键
  0)  退出
```

菜单顶部会展示当前所有实例的标签、本地监听、远端目标、TCP/UDP 端口，以及运行状态（`running` / `stopped` / `stopped(enabled)`）。

启停 / 重启操作支持输入 `all` 对所有实例批量执行。

---

## 版本

- v0.0.1 — 首个公开版本

---

## 致谢与许可

- 核心 TCP 预连接转发逻辑、`tcp_pool.c`、systemd 服务模板及配置解析器均来自上游项目 [Xeloan/TCP-preconnection-relay](https://github.com/Xeloan/TCP-preconnection-relay)，所有归属与许可遵循上游项目。
- 本仓库只新增了 `tcpr.sh` 管理脚本，未修改上游核心逻辑。

如果你只是想用核心转发功能而不需要管理菜单，建议直接使用上游项目。
