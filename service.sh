#!/system/bin/sh
MODDIR=${0%/*}

# Wait until system boot is fully completed
while [ "$(getprop sys.boot_completed)" != "1" ]; do
    sleep 2
done

# Wait extra seconds for network/system stability
sleep 3

# Clean stale status and stop files on boot
rm -f /data/local/tmp/vd_status.json 2>/dev/null
rm -f /data/local/tmp/vd_stop 2>/dev/null

# Ensure permissions and temp runtime files exist
chmod 755 "$MODDIR/bin/vd_server" 2>/dev/null
chmod 755 "$MODDIR/bin/run_daemon.sh" 2>/dev/null
chmod 755 "$MODDIR/system/bin/vd" 2>/dev/null

cp -f "$MODDIR/bin/agent_vd.dex" /data/local/tmp/agent_vd.dex 2>/dev/null
cp -f "$MODDIR/bin/agent_tools.dex" /data/local/tmp/agent_tools.dex 2>/dev/null
cp -f "$MODDIR/bin/run_daemon.sh" /data/local/tmp/run_daemon.sh 2>/dev/null
chmod 755 /data/local/tmp/run_daemon.sh 2>/dev/null

# 局域网密码：服务端只保存 sha256（/data/local/tmp/.dsh_auth, 600），明文不落盘。
# 密码通过手机上的控制台页面（127.0.0.1:3070 的锁形按钮）设置，或 POST /api/auth/secret。
# 未设置时非回环访问一律 401（fail closed），手机上的一切照常可用。

# 清理可能残留的 daemon（上次异常退出会占着 3071，导致新 daemon bind 失败）。
pkill -9 -f "DaemonMain" 2>/dev/null
sleep 1

if ! pgrep -f "vd_server" >/dev/null 2>&1; then
    chmod 755 "$MODDIR/bin/vd_server" 2>/dev/null
    # vd_server 默认绑定 127.0.0.1（源码里的安全默认）。本模块的用途是从同网段的
    # 电脑 / DSH 控制这台手机，所以这里显式对外监听；不需要远程控制时删掉此行即可。
    export HOST=0.0.0.0
    export PORT=3070
    nohup "$MODDIR/bin/vd_server" > /data/local/tmp/vd_server.log 2>&1 &
    sleep 3
fi

# 开机诊断：把二进制状态与存活情况写到 Download，任何一次开机都能事后核对。
BOOTINFO=/sdcard/Download/amu_boot.txt
{
    echo "== boot @ $(date)"
    echo "-- 二进制 --"
    ls -l "$MODDIR/bin/vd_server" 2>&1
    sha256sum "$MODDIR/bin/vd_server" 2>&1
    echo "-- 进程 --"
    pgrep -f vd_server 2>&1
    echo "-- 端口 --"
    netstat -tln 2>/dev/null | grep 3070
    echo "-- 日志末尾 --"
    tail -n 30 /data/local/tmp/vd_server.log 2>&1
} > "$BOOTINFO" 2>&1
