#!/bin/bash
# tcpr - 交互式管理 TCP-preconnection-relay
# Version: 0.0.1
# 依赖：已安装 tcp-pool-parse 和 tcp-pool@.service（即原 install 脚本跑过）
#
# 一键安装（任意机器，root）：
#   bash <(curl -fsSL https://raw.githubusercontent.com/chnnic/TCPR/refs/heads/main/tcpr.sh) --install
# 之后任意位置输入 tcpr 进入菜单。

set -uo pipefail

VERSION="0.0.1"

CONF="/etc/tcp_pool/relays.conf"
CONF_DIR="/etc/tcp_pool"
INSTALL_PATH="/usr/local/bin/tcpr"
REMOTE_URL="https://raw.githubusercontent.com/chnnic/TCPR/refs/heads/main/tcpr.sh"
UPSTREAM_INSTALL_URL="https://raw.githubusercontent.com/chnnic/TCPR/refs/heads/main/install.sh"

# ---------- 通用工具 ----------
need_root() {
    if [ "$(id -u)" -ne 0 ]; then
        echo "需要 root 权限，请用 sudo 或 root 运行" >&2
        exit 1
    fi
}

ensure_files() {
    if [ ! -f "$CONF" ]; then
        echo "找不到 $CONF，请先跑上游 TCP-preconnection-relay 的 install.sh：" >&2
        echo "  bash <(curl -L $UPSTREAM_INSTALL_URL)" >&2
        exit 1
    fi
    if [ ! -x /usr/local/bin/tcp-pool-parse ]; then
        echo "找不到 tcp-pool-parse，请先跑上游 install.sh。" >&2
        exit 1
    fi
}

# 同样的检测但只返回布尔，给菜单用
upstream_installed() {
    [ -f "$CONF" ] && [ -x /usr/local/bin/tcp-pool-parse ]
}

# 一键安装上游 TCP-preconnection-relay
action_install_upstream() {
    if upstream_installed; then
        echo "上游 TCP-preconnection-relay 已经安装。"
        read -r -p "是否仍要重新跑一遍上游 install.sh？ [y/N]: " a
        case "$a" in
            y|Y) ;;
            *) echo "已取消"; return ;;
        esac
    fi

    if ! command -v curl >/dev/null 2>&1; then
        echo "需要 curl，请先 apt install curl" >&2
        return 1
    fi

    echo "即将执行上游安装脚本："
    echo "  $UPSTREAM_INSTALL_URL"
    read -r -p "继续吗？ [Y/n]: " a
    case "$a" in
        n|N) echo "已取消"; return ;;
    esac

    bash <(curl -L "$UPSTREAM_INSTALL_URL")
    echo
    echo "上游安装流程结束。"
    if upstream_installed; then
        echo "检测到上游已安装成功，回车回到 tcpr 菜单..."
    else
        echo "看起来上游安装没完成，请检查报错。"
    fi
}

pause() {
    read -r -p "回车继续..." _
}

is_valid_port() {
    local p="$1"
    [[ "$p" =~ ^[0-9]+$ ]] || return 1
    (( p >= 1 && p <= 65535 ))
}

is_valid_tag() {
    [[ "$1" =~ ^[A-Za-z0-9_-]+$ ]]
}

# ---------- 一键安装/更新 ----------
# 从 GitHub 拉最新脚本到 INSTALL_PATH，并赋可执行权限。
# 既可作为命令行参数 --install 使用，也可从菜单调用。
remote_install() {
    need_root
    if ! command -v curl >/dev/null 2>&1; then
        echo "需要 curl，请先 apt install curl" >&2
        return 1
    fi

    local tmp
    tmp="$(mktemp)" || return 1

    echo "正在从 GitHub 下载最新 tcpr ..."
    if ! curl -fsSL "$REMOTE_URL" -o "$tmp"; then
        echo "下载失败：$REMOTE_URL" >&2
        rm -f "$tmp"
        return 1
    fi

    # 简单完整性检查
    if ! head -1 "$tmp" | grep -q '^#!/bin/bash'; then
        echo "下载内容不像合法的 bash 脚本，已取消" >&2
        rm -f "$tmp"
        return 1
    fi

    mv "$tmp" "$INSTALL_PATH"
    chmod +x "$INSTALL_PATH"
    echo "已安装到 $INSTALL_PATH"
    echo "现在可在任意位置输入：tcpr"
}

# 非交互全卸载（命令行用）
# 不询问、不交互，直接清理；保留 sysctl 配置文件由 --purge-sysctl 控制
action_uninstall_all_noninteractive() {
    local purge_sysctl="${1:-no}"

    echo "[tcpr] 非交互全卸载开始..."

    mapfile -t units < <(
        {
            systemctl list-units --full --all --no-legend 'tcp-pool@*.service' 2>/dev/null | awk '{print $1}'
            systemctl list-unit-files --full --no-legend 'tcp-pool@*.service' 2>/dev/null | awk '{print $1}'
        } | sort -u
    )
    for unit in "${units[@]}"; do
        [ -n "$unit" ] || continue
        systemctl stop "$unit" 2>/dev/null || true
        systemctl disable "$unit" 2>/dev/null || true
    done

    rm -f /etc/systemd/system/tcp-pool@.service
    systemctl daemon-reload || true

    rm -f /usr/local/bin/tcp-pool-parse
    rm -f /usr/local/bin/tcp-pool-start
    rm -rf /etc/tcp_pool
    rm -f /root/tcp_pool /root/tcp_pool.c

    if [ "$purge_sysctl" = "yes" ]; then
        rm -f /etc/sysctl.d/99-custom-network-tuning.conf
        echo "[tcpr] 已删除 sysctl 调优配置（已运行的内核参数需重启才完全恢复）"
    fi

    rm -f "$INSTALL_PATH"

    echo "[tcpr] 全卸载完成"
}

# ---------- 快捷键安装/卸载（从本地脚本复制） ----------
script_self_path() {
    local src="${BASH_SOURCE[0]}"
    while [ -L "$src" ]; do
        local dir
        dir="$(cd -P "$(dirname "$src")" && pwd)"
        src="$(readlink "$src")"
        [[ "$src" != /* ]] && src="$dir/$src"
    done
    cd -P "$(dirname "$src")" && echo "$(pwd)/$(basename "$src")"
}

is_shortcut_installed() {
    [ -x "$INSTALL_PATH" ]
}

action_install_shortcut_local() {
    local self
    self="$(script_self_path)"

    if [ "$self" = "$INSTALL_PATH" ]; then
        echo "当前就是从 $INSTALL_PATH 运行的，无需重复安装。"
        return
    fi

    if [ -e "$INSTALL_PATH" ]; then
        read -r -p "$INSTALL_PATH 已存在，是否覆盖？ [y/N]: " a
        case "$a" in
            y|Y) ;;
            *) echo "已取消"; return ;;
        esac
    fi

    cp -f "$self" "$INSTALL_PATH"
    chmod +x "$INSTALL_PATH"
    echo "已安装：现在可以在任何位置输入 tcpr 进入此菜单"
}

action_install_shortcut_remote() {
    if [ -e "$INSTALL_PATH" ]; then
        read -r -p "$INSTALL_PATH 已存在，是否用 GitHub 最新版覆盖？ [y/N]: " a
        case "$a" in
            y|Y) ;;
            *) echo "已取消"; return ;;
        esac
    fi
    remote_install
}

action_uninstall_shortcut() {
    if [ ! -e "$INSTALL_PATH" ]; then
        echo "$INSTALL_PATH 不存在，无需卸载"
        return
    fi

    read -r -p "确认从 $INSTALL_PATH 卸载快捷键？ [y/N]: " a
    case "$a" in
        y|Y) ;;
        *) echo "已取消"; return ;;
    esac

    rm -f "$INSTALL_PATH"
    echo "快捷键已卸载"
}

# ---------- 全卸载 ----------
# 卸载 tcpr 本身 + 上游 TCP-preconnection-relay 的全部痕迹
action_uninstall_all() {
    echo "============================================================"
    echo "即将卸载以下内容："
    echo "  - tcpr 快捷键          $INSTALL_PATH"
    echo "  - 全部转发实例 systemd  tcp-pool@*.service (stop + disable)"
    echo "  - systemd 模板         /etc/systemd/system/tcp-pool@.service"
    echo "  - 上游辅助脚本         /usr/local/bin/tcp-pool-parse"
    echo "                       /usr/local/bin/tcp-pool-start"
    echo "  - 配置目录             /etc/tcp_pool/  (包含 relays.conf)"
    echo "  - 核心二进制和源码     /root/tcp_pool  /root/tcp_pool.c"
    echo "  - sysctl 调优配置      /etc/sysctl.d/99-custom-network-tuning.conf"
    echo "============================================================"
    echo "！ 这是不可逆操作，会删除所有配置。"
    echo

    read -r -p "确认全部卸载？请输入大写 YES 继续: " a
    if [ "$a" != "YES" ]; then
        echo "已取消"
        return
    fi

    echo
    echo "正在停止并禁用所有 tcp-pool@* 实例..."
    mapfile -t units < <(
        {
            systemctl list-units --full --all --no-legend 'tcp-pool@*.service' 2>/dev/null | awk '{print $1}'
            systemctl list-unit-files --full --no-legend 'tcp-pool@*.service' 2>/dev/null | awk '{print $1}'
        } | sort -u
    )
    for unit in "${units[@]}"; do
        [ -n "$unit" ] || continue
        systemctl stop "$unit" 2>/dev/null || true
        systemctl disable "$unit" 2>/dev/null || true
        echo "  - 已处理 $unit"
    done

    echo "删除 systemd 模板..."
    rm -f /etc/systemd/system/tcp-pool@.service
    systemctl daemon-reload || true

    echo "删除上游辅助脚本..."
    rm -f /usr/local/bin/tcp-pool-parse
    rm -f /usr/local/bin/tcp-pool-start

    echo "删除配置目录..."
    rm -rf /etc/tcp_pool

    echo "删除核心二进制和源码..."
    rm -f /root/tcp_pool /root/tcp_pool.c

    echo "处理 sysctl 调优配置..."
    if [ -f /etc/sysctl.d/99-custom-network-tuning.conf ]; then
        read -r -p "是否一并删除 99-custom-network-tuning.conf（不会回滚已生效的内核参数，需重启才完全恢复）？ [y/N]: " sa
        case "$sa" in
            y|Y)
                rm -f /etc/sysctl.d/99-custom-network-tuning.conf
                echo "已删除。注意：当前已生效的 sysctl 参数仍在运行内核中，重启后会回到系统默认。"
                ;;
            *)
                echo "已保留 sysctl 配置"
                ;;
        esac
    fi

    echo "删除 tcpr 快捷键..."
    if [ -e "$INSTALL_PATH" ]; then
        rm -f "$INSTALL_PATH"
    fi

    echo
    echo "============================================================"
    echo "全部卸载完成。"
    echo "============================================================"

    # 如果当前脚本正是从 INSTALL_PATH 跑的，提示一下退出
    local self
    self="$(script_self_path)"
    if [ "$self" = "$INSTALL_PATH" ] || [ ! -e "$self" ]; then
        echo "tcpr 自身已被删除，本次会话结束后即不可再用。"
    else
        echo "本地脚本 $self 仍保留，可手动 rm 删除。"
    fi
    echo "按回车后退出 tcpr..."
    read -r _
    exit 0
}

# ---------- 解析 relays.conf ----------
list_tags() {
    awk '
        /^[[:space:]]*\[.*\][[:space:]]*$/ {
            tag = $0
            sub(/^[[:space:]]*\[/, "", tag)
            sub(/\][[:space:]]*$/, "", tag)
            print tag
        }
    ' "$CONF"
}

extract_section() {
    local tag="$1"
    awk -v t="$tag" '
        BEGIN { inblk = 0 }
        /^[[:space:]]*\[.*\][[:space:]]*$/ {
            cur = $0
            sub(/^[[:space:]]*\[/, "", cur)
            sub(/\][[:space:]]*$/, "", cur)
            if (cur == t) { inblk = 1; print; next }
            else if (inblk) { inblk = 0 }
        }
        inblk { print }
    ' "$CONF"
}

get_field() {
    local tag="$1" key="$2"
    extract_section "$tag" | awk -F= -v k="$key" '
        $1 ~ "^[[:space:]]*"k"[[:space:]]*$" {
            sub(/^[^=]*=/, "")
            sub(/^[[:space:]]+/, "")
            sub(/[[:space:]]+$/, "")
            print
            exit
        }'
}

# ---------- 服务状态 ----------
svc_status() {
    local tag="$1"
    if systemctl is-active --quiet "tcp-pool@$tag"; then
        echo "running"
    elif systemctl is-enabled --quiet "tcp-pool@$tag" 2>/dev/null; then
        echo "stopped(enabled)"
    else
        echo "stopped"
    fi
}

# ---------- 应用配置 ----------
apply_one() {
    local tag="$1"
    echo "正在解析并重启 tcp-pool@$tag ..."
    tcp-pool-parse || { echo "解析失败，未重启"; return 1; }
    systemctl enable "tcp-pool@$tag" >/dev/null 2>&1 || true
    systemctl restart "tcp-pool@$tag"
    echo "tcp-pool@$tag 已重启"
}

apply_all() {
    echo "执行 tcp-pool-start ..."
    tcp-pool-start
}

# ---------- 列表展示 ----------
show_list() {
    echo "============================================================"
    printf "%-3s %-12s %-20s %-6s %-22s %-6s %-6s %-16s\n" \
        "#" "TAG" "LOCAL_IP" "LPORT" "REMOTE_IP" "TCP" "UDP" "STATUS"
    echo "------------------------------------------------------------"
    local i=0
    while IFS= read -r tag; do
        i=$((i+1))
        local lip lport rip rtcp rudp st
        lip=$(get_field "$tag" LOCAL_IP)
        lport=$(get_field "$tag" LOCAL_PORT)
        rip=$(get_field "$tag" REMOTE_IP)
        rtcp=$(get_field "$tag" REMOTE_TCP_PORT)
        rudp=$(get_field "$tag" REMOTE_UDP_PORT)
        st=$(svc_status "$tag")
        printf "%-3s %-12s %-20s %-6s %-22s %-6s %-6s %-16s\n" \
            "$i" "$tag" "$lip" "$lport" "$rip" "$rtcp" "$rudp" "$st"
    done < <(list_tags)
    echo "============================================================"
}

pick_tag() {
    local prompt="${1:-请输入序号或标签名}"
    mapfile -t tags < <(list_tags)
    if [ "${#tags[@]}" -eq 0 ]; then
        echo "（当前没有任何实例）" >&2
        return 1
    fi
    read -r -p "$prompt: " sel
    [ -z "$sel" ] && return 1

    if [ "$sel" = "all" ]; then
        echo "all"
        return 0
    fi

    if [[ "$sel" =~ ^[0-9]+$ ]]; then
        local idx=$((sel-1))
        if (( idx < 0 || idx >= ${#tags[@]} )); then
            echo "序号超出范围" >&2
            return 1
        fi
        echo "${tags[$idx]}"
        return 0
    fi

    local t
    for t in "${tags[@]}"; do
        if [ "$t" = "$sel" ]; then
            echo "$t"
            return 0
        fi
    done
    echo "找不到标签 $sel" >&2
    return 1
}

# ---------- 增 ----------
action_add() {
    show_list
    echo "新增一个预连接配置（标签只能包含字母数字下划线横杠）"
    local tag lip lport rip rtcp rudp
    read -r -p "TAG (例如 SG): " tag
    is_valid_tag "$tag" || { echo "标签不合法"; return; }
    if list_tags | grep -qx "$tag"; then
        echo "标签 $tag 已存在"; return
    fi

    read -r -p "LOCAL_IP (默认 0.0.0.0，IPv6 用 ::): " lip
    lip="${lip:-0.0.0.0}"

    read -r -p "LOCAL_PORT: " lport
    is_valid_port "$lport" || { echo "端口不合法"; return; }

    read -r -p "REMOTE_IP (IP 或域名): " rip
    [ -z "$rip" ] && { echo "REMOTE_IP 不能为空"; return; }

    read -r -p "REMOTE_TCP_PORT: " rtcp
    is_valid_port "$rtcp" || { echo "TCP 端口不合法"; return; }

    read -r -p "REMOTE_UDP_PORT (默认同 TCP): " rudp
    rudp="${rudp:-$rtcp}"
    is_valid_port "$rudp" || { echo "UDP 端口不合法"; return; }

    {
        echo ""
        echo "[$tag]"
        echo "LOCAL_IP=$lip"
        echo "LOCAL_PORT=$lport"
        echo "REMOTE_IP=$rip"
        echo "REMOTE_TCP_PORT=$rtcp"
        echo "REMOTE_UDP_PORT=$rudp"
    } >> "$CONF"

    echo "已写入 [$tag]"
    apply_one "$tag"
}

# ---------- 删 ----------
action_del() {
    show_list
    local tag
    tag=$(pick_tag "选择要删除的实例") || return
    [ -z "$tag" ] && return
    [ "$tag" = "all" ] && { echo "删除不支持 all"; return; }

    read -r -p "确认删除 [$tag] ? [y/N]: " a
    case "$a" in
        y|Y) ;;
        *) echo "已取消"; return ;;
    esac

    systemctl stop "tcp-pool@$tag" 2>/dev/null || true
    systemctl disable "tcp-pool@$tag" 2>/dev/null || true

    local tmp
    tmp=$(mktemp)
    awk -v t="$tag" '
        BEGIN { skip = 0 }
        /^[[:space:]]*\[.*\][[:space:]]*$/ {
            cur = $0
            sub(/^[[:space:]]*\[/, "", cur)
            sub(/\][[:space:]]*$/, "", cur)
            if (cur == t) { skip = 1; next }
            else { skip = 0 }
        }
        skip == 0 { print }
    ' "$CONF" > "$tmp"

    mv "$tmp" "$CONF"
    chmod 644 "$CONF"

    tcp-pool-parse || echo "解析失败，请手动检查 $CONF"
    echo "已删除 [$tag] 并停止其服务"
}

# ---------- 改 ----------
action_edit() {
    show_list
    local tag
    tag=$(pick_tag "选择要修改的实例") || return
    [ -z "$tag" ] && return
    [ "$tag" = "all" ] && { echo "修改不支持 all"; return; }

    local lip lport rip rtcp rudp
    lip=$(get_field "$tag" LOCAL_IP)
    lport=$(get_field "$tag" LOCAL_PORT)
    rip=$(get_field "$tag" REMOTE_IP)
    rtcp=$(get_field "$tag" REMOTE_TCP_PORT)
    rudp=$(get_field "$tag" REMOTE_UDP_PORT)

    echo "当前 [$tag] 配置："
    echo "  LOCAL_IP=$lip"
    echo "  LOCAL_PORT=$lport"
    echo "  REMOTE_IP=$rip"
    echo "  REMOTE_TCP_PORT=$rtcp"
    echo "  REMOTE_UDP_PORT=$rudp"
    echo "（留空回车 = 保持不变）"

    local new_lip new_lport new_rip new_rtcp new_rudp
    read -r -p "新的 LOCAL_IP [$lip]: " new_lip
    read -r -p "新的 LOCAL_PORT [$lport]: " new_lport
    read -r -p "新的 REMOTE_IP [$rip]: " new_rip
    read -r -p "新的 REMOTE_TCP_PORT [$rtcp]: " new_rtcp
    read -r -p "新的 REMOTE_UDP_PORT [$rudp]: " new_rudp

    new_lip="${new_lip:-$lip}"
    new_lport="${new_lport:-$lport}"
    new_rip="${new_rip:-$rip}"
    new_rtcp="${new_rtcp:-$rtcp}"
    new_rudp="${new_rudp:-$rudp}"

    is_valid_port "$new_lport" || { echo "LOCAL_PORT 不合法"; return; }
    is_valid_port "$new_rtcp"  || { echo "REMOTE_TCP_PORT 不合法"; return; }
    is_valid_port "$new_rudp"  || { echo "REMOTE_UDP_PORT 不合法"; return; }
    [ -z "$new_rip" ] && { echo "REMOTE_IP 不能为空"; return; }

    local tmp
    tmp=$(mktemp)
    awk -v t="$tag" \
        -v lip="$new_lip" -v lport="$new_lport" \
        -v rip="$new_rip" -v rtcp="$new_rtcp" -v rudp="$new_rudp" '
        BEGIN { skip = 0 }
        /^[[:space:]]*\[.*\][[:space:]]*$/ {
            cur = $0
            sub(/^[[:space:]]*\[/, "", cur)
            sub(/\][[:space:]]*$/, "", cur)
            if (cur == t) {
                print "[" t "]"
                print "LOCAL_IP=" lip
                print "LOCAL_PORT=" lport
                print "REMOTE_IP=" rip
                print "REMOTE_TCP_PORT=" rtcp
                print "REMOTE_UDP_PORT=" rudp
                skip = 1
                next
            } else {
                skip = 0
            }
        }
        skip == 0 { print }
    ' "$CONF" > "$tmp"

    mv "$tmp" "$CONF"
    chmod 644 "$CONF"

    echo "[$tag] 已更新"
    apply_one "$tag"
}

# ---------- 启停 ----------
action_start() {
    show_list
    local tag
    tag=$(pick_tag "选择要启动的实例（输入 all 启动所有）") || return
    if [ "$tag" = "all" ]; then
        apply_all
        return
    fi
    systemctl enable "tcp-pool@$tag" >/dev/null 2>&1 || true
    systemctl restart "tcp-pool@$tag"
    echo "tcp-pool@$tag 已启动"
}

action_stop() {
    show_list
    local tag
    tag=$(pick_tag "选择要停止的实例（输入 all 停止所有）") || return
    if [ "$tag" = "all" ]; then
        mapfile -t tags < <(list_tags)
        for t in "${tags[@]}"; do
            systemctl stop "tcp-pool@$t" 2>/dev/null || true
        done
        echo "全部实例已停止"
        return
    fi
    systemctl stop "tcp-pool@$tag"
    echo "tcp-pool@$tag 已停止"
}

action_restart() {
    show_list
    local tag
    tag=$(pick_tag "选择要重启的实例（输入 all 重启所有）") || return
    if [ "$tag" = "all" ]; then
        apply_all
        return
    fi
    apply_one "$tag"
}

action_log() {
    show_list
    local tag
    tag=$(pick_tag "选择要查看日志的实例") || return
    [ "$tag" = "all" ] && { echo "日志不支持 all，请选具体实例"; return; }
    echo "Ctrl+C 退出日志查看"
    sleep 1
    journalctl -u "tcp-pool@$tag" -f
}

# ---------- 上游未安装时的简化菜单 ----------
upstream_missing_menu() {
    while true; do
        clear
        local shortcut_status
        if is_shortcut_installed; then
            shortcut_status="已安装"
        else
            shortcut_status="未安装"
        fi
        echo "===== tcpr v${VERSION} ====="
        echo "快捷键 ($INSTALL_PATH): $shortcut_status"
        echo
        echo "！ 未检测到上游 TCP-preconnection-relay"
        echo "   缺少 $CONF 和/或 /usr/local/bin/tcp-pool-parse"
        echo "   需要先安装上游才能管理预连接实例。"
        cat <<MENU

  1)  安装上游 TCP-preconnection-relay
  2)  从 GitHub 安装/更新 tcpr 到 $INSTALL_PATH
  3)  把当前本地脚本安装到 $INSTALL_PATH
  4)  卸载快捷键
  5)  全卸载（清理 tcpr + 所有上游残留）
  9)  重新检测（上游装好后选这个）
  0)  退出

MENU
        read -r -p "选择: " opt
        case "$opt" in
            1) action_install_upstream; pause
               if upstream_installed; then return 0; fi ;;
            2) action_install_shortcut_remote; pause ;;
            3) action_install_shortcut_local; pause ;;
            4) action_uninstall_shortcut; pause ;;
            5) action_uninstall_all ;;
            9) if upstream_installed; then
                   echo "已检测到上游，进入完整菜单..."; sleep 1; return 0
               else
                   echo "仍未检测到上游"; pause
               fi ;;
            0) exit 0 ;;
            *) echo "无效选项"; pause ;;
        esac
    done
}

# ---------- 主菜单 ----------
main_menu() {
    while true; do
        clear
        local shortcut_status
        if is_shortcut_installed; then
            shortcut_status="已安装"
        else
            shortcut_status="未安装"
        fi
        echo "===== tcpr - TCP-preconnection-relay 管理 v${VERSION} ====="
        echo "快捷键 ($INSTALL_PATH): $shortcut_status"
        show_list
        cat <<MENU

  1)  新增实例 (add)
  2)  修改实例 (edit IP / 端口)
  3)  删除实例 (del)
  4)  启动实例 (start)
  5)  停止实例 (stop)
  6)  重启实例 (restart)
  7)  查看实例日志 (log)
  8)  一键重启全部 (tcp-pool-start)
  9)  编辑原始 relays.conf (nano)
 10)  从 GitHub 安装/更新 tcpr 到 $INSTALL_PATH
 11)  把当前本地脚本安装到 $INSTALL_PATH
 12)  卸载快捷键
 13)  重装/更新上游 TCP-preconnection-relay
 14)  全卸载（清理 tcpr + 所有上游残留）
  0)  退出

MENU
        read -r -p "选择: " opt
        case "$opt" in
            1)  action_add; pause ;;
            2)  action_edit; pause ;;
            3)  action_del; pause ;;
            4)  action_start; pause ;;
            5)  action_stop; pause ;;
            6)  action_restart; pause ;;
            7)  action_log ;;
            8)  apply_all; pause ;;
            9)  nano "$CONF"; apply_all; pause ;;
            10) action_install_shortcut_remote; pause ;;
            11) action_install_shortcut_local; pause ;;
            12) action_uninstall_shortcut; pause ;;
            13) action_install_upstream; pause ;;
            14) action_uninstall_all ;;
            0)  exit 0 ;;
            *)  echo "无效选项"; pause ;;
        esac
    done
}

# ---------- 入口 ----------

# 命令行模式：bash <(curl ...) --install  或  tcpr --install / --update
case "${1:-}" in
    --install|--update|-i)
        remote_install
        exit $?
        ;;
    --uninstall-all)
        need_root
        purge=no
        if [ "${2:-}" = "--purge-sysctl" ]; then
            purge=yes
        fi
        action_uninstall_all_noninteractive "$purge"
        exit 0
        ;;
    --version|-v)
        echo "tcpr $VERSION"
        exit 0
        ;;
    --help|-h)
        cat <<HELP
tcpr v$VERSION - TCP-preconnection-relay 管理工具

用法：
  tcpr                       进入交互菜单
  tcpr --install             从 GitHub 拉取最新版并安装到 $INSTALL_PATH
  tcpr --update              同 --install
  tcpr --uninstall-all       非交互全卸载（保留 sysctl 调优）
  tcpr --uninstall-all --purge-sysctl
                             非交互全卸载，并删除 sysctl 调优配置
  tcpr --version             显示版本
  tcpr --help                显示本帮助

一键安装命令（无需先下载）：
  bash <(curl -fsSL $REMOTE_URL) --install

一键全卸载命令（无需先下载，需要 tcpr 已安装在 $INSTALL_PATH）：
  tcpr --uninstall-all
HELP
        exit 0
        ;;
esac

need_root

if ! upstream_installed; then
    upstream_missing_menu
fi

ensure_files
main_menu
