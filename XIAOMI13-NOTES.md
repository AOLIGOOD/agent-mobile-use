# 小米 13 / MIUI（Android 13）适配版

本目录是可直接刷入的 KernelSU 模块树，来自 [AcidGr/agent-mobile-use](https://github.com/AcidGr/agent-mobile-use)，
针对 **Xiaomi 13（nuwa, 2210132C）/ MIUI / Android 13（SDK 33）** 做了适配。

## 内容

| 路径 | 说明 |
|---|---|
| `module.prop` `customize.sh` `service.sh` `action.sh` | 模块脚本（可读源码） |
| `system/bin/vd` | 手机端命令行入口 |
| `bin/vd_server` | Go 网关（编译产物，监听 3070） |
| `bin/agent_vd.dex` `bin/agent_tools.dex` | Java daemon 与工具（编译产物） |
| `bin/run_daemon.sh` | daemon 启动脚本（可读源码） |
| `apk/agent_hook.apk` | LSPosed 辅助模块 |
| `ADAPTATION.md` | 每一处适配的原因、代码位置与验证方法 |

## 安装

1. 刷入本目录打包成的 zip（KernelSU / APatch / Magisk）
2. 重启一次（KernelSU 会把 `modules_update` 合并到 `modules`）
3. 之后更新只需「装包 → 点模块页的『执行』」，约 10 秒生效，不必重启

## 关于源码

`bin/` 下的两个编译产物（Go 网关、Java daemon）对应的**源码修改未包含在本目录**，
工作副本没有保留。`ADAPTATION.md` 逐条记录了改动位置与思路，可按其在上游源码上重放，
主要包括：

- 副屏截图：影子显示（`SurfaceControl.createDisplay` + `setDisplayLayerStack`）+ 独立 ImageReader
- `vd apps` 在 MIUI 上的 `ResolveInfo.loadLabel` 崩溃兜底
- `BOOTCLASSPATH` 从 `system_server` 继承，替代硬编码的 OPPO 列表
- LSPosed 检测放宽
- 网关鉴权：自持 32 字节随机 token，回环免密，其余 fail-closed
- `action.sh` 免重启同步

## 已知限制

- 手机锁屏时虚拟副屏会一起进入 keyguard（UI 树出现 `current_time` / `current_date`），
  `VIRTUAL_DISPLAY_FLAG_ALWAYS_UNLOCKED` 在 MIUI 上无效；此时 agent 无法操作副屏
- `vd apps` 只有包名，没有中文应用名
