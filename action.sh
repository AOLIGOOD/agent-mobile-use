#!/system/bin/sh
# KernelSU 模块「执行」按钮入口：以 root 运行。
#
# 设计目标：「装完点一下立刻生效」，不需要重启手机：
#   1. 把 modules_update 里的新文件同步到现行模块目录
#   2. 杀掉旧的 vd_server / DaemonMain
#   3. 以 HOST=0.0.0.0 重新拉起 vd_server
#   4. 现场信息与 daemon 日志写到 /sdcard/Download/amu_action.txt
MODDIR=${0%/*}
OUT=/sdcard/Download/amu_action.txt
STAGE=/data/adb/modules_update/agent_mobile_use

{
  echo "== action @ $(date)"
  echo "MODDIR=$MODDIR"

  echo
  echo "-- 1. 同步暂存目录 --"
  if [ -d "$STAGE" ]; then
      cp -rf "$STAGE"/. "$MODDIR"/ 2>/dev/null
      echo "已从 $STAGE 同步"
  else
      echo "无暂存目录（无需同步）"
  fi
  chmod 755 "$MODDIR/bin/vd_server" "$MODDIR/bin/run_daemon.sh" "$MODDIR/system/bin/vd" 2>/dev/null
  chmod 644 "$MODDIR/bin/agent_vd.dex" "$MODDIR/bin/agent_vd_orig.dex" "$MODDIR/bin/agent_tools.dex" 2>/dev/null
  cp -f "$MODDIR/bin/agent_vd.dex" /data/local/tmp/agent_vd.dex 2>/dev/null
  cp -f "$MODDIR/bin/agent_vd_orig.dex" /data/local/tmp/agent_vd_orig.dex 2>/dev/null
  cp -f "$MODDIR/bin/agent_tools.dex" /data/local/tmp/agent_tools.dex 2>/dev/null
  cp -f "$MODDIR/bin/run_daemon.sh" /data/local/tmp/run_daemon.sh 2>/dev/null
  chmod 755 /data/local/tmp/run_daemon.sh 2>/dev/null

  echo
  echo "-- 2. 模块文件 --"
  ls -l "$MODDIR/bin/" 2>&1
  echo "版本: $(grep '^version=' "$MODDIR/module.prop" 2>/dev/null | cut -d= -f2)"

  echo
  echo "-- 3. 停旧进程 --"
  # 先让服务自己优雅注销副屏，避免留下孤儿 daemon 占着 3071（否则新 daemon 会
  # bind failed: EADDRINUSE 并直接退出，状态变 failed）。
  /system/bin/curl -s --max-time 3 -X POST http://127.0.0.1:3070/api/stop >/dev/null 2>&1
  sleep 1
  pkill -f "bin/vd_server" 2>/dev/null
  # app_process 会把进程名改写成类名，按类名/类路径两种模式都要杀。
  pkill -f "com.agent.DaemonMain" 2>/dev/null
  pkill -f "DaemonMain" 2>/dev/null
  pkill -9 -f "agent_vd.dex" 2>/dev/null
  sleep 1
  pkill -9 -f "DaemonMain" 2>/dev/null
  echo "残留 DaemonMain: $(pgrep -f DaemonMain | tr '\n' ' ')"
  echo "3071 占用: $(netstat -tln 2>/dev/null | grep -c 3071)"
  rm -f /data/local/tmp/vd_status.json /data/local/tmp/vd_stop /data/local/tmp/vd_snap_req /data/local/tmp/vd_snapshot.jpg 2>/dev/null

  echo
  echo "-- 4. 启动 vd_server (HOST=0.0.0.0) --"
  export HOST=0.0.0.0
  export PORT=3070
  nohup "$MODDIR/bin/vd_server" >/data/local/tmp/vd_server.log 2>&1 &
  sleep 2
  echo "新 pid=$(pgrep -f 'bin/vd_server' | head -n 1)"
  netstat -tln 2>/dev/null | grep 3070

  echo
  echo "-- 5. daemon 日志（上一次运行的尾部）--"
  tail -n 60 /data/local/tmp/daemon.log 2>&1

  echo
  echo "-- 6. vd_server 日志 --"
  tail -n 20 /data/local/tmp/vd_server.log 2>&1

  echo
  echo "-- 7. 接口自检 --"
  /system/bin/curl -s --max-time 3 http://127.0.0.1:3070/api/status 2>&1
  echo
  echo "== done"
} > "$OUT" 2>&1
