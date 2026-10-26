# 适配说明 — Xiaomi 13 (nuwa) / MIUI, Android 13

本包在官方 `v0.8.7-alpha` 基础上针对本机做了四处修改，Java dex 与 APK 未重编译。

## 1. 虚拟副屏截图 500（`GET /api/screenshot`）

**现象**：主屏截图正常，切到副屏后恒返回 `500 Capture error`。

**原因**（实机验证，分两层）：

1. `screencap -d` 接受的是 **SurfaceFlinger display token**（如
   `4630947134992368259`），不是 WindowManager 的逻辑 id。传 `0` 或 `3` 都会失败，
   `screencap --help` 里写着 `-d: specify the display ID to capture
   (default: 4630947134992368259)`。
2. `dumpsys SurfaceFlinger --display-id` **只列出带标识数据的物理屏**，虚拟屏完全不在
   其中。本机实测该命令只输出 `Display 4630947134992368259 (HWC display 0)`。
   虚拟屏的 token 在**完整** `dumpsys SurfaceFlinger` 里：

   ```
   Display 11529215048792333846 (virtual, "AgentVirtualDisplay")
   ```

原实现的正则只认 ColorOS 那种 `Display <n> ... Agent ... VirtualDisplay` 行，本就
匹配不到，于是退回传逻辑 id，必然失败。

**修改**：
- 新增 `reSfVirtualToken`，从完整 `dumpsys SurfaceFlinger` 抓
  `Display <token> (virtual, ...)` 行。
- 新增 `resolveSfDisplayTokens()`：返回**全部**虚拟屏 token（5 秒缓存，避免每张截图
  都跑一次约 1MB 的 dumpsys）；daemon 被 kill 时可能残留旧虚拟屏，逐个尝试即可。
- `captureDisplayJPEG()`：对每个 token 依次尝试 `-p -d <token>`、`-d <token>`，
  任一成功即返回；失败时把 screencap 的真实 stderr 拼进错误信息。

## 2. `vd apps` / `GET /api/apps` 崩溃（MIUI 主题加载器）

**现象**：返回一整段 Java 堆栈而不是应用列表：

```
java.io.FileNotFoundException: /data/system/theme_config/theme_compatibility.xml
  at miui.content.res.ThemeCompatibilityLoader.getVersion(...)
```

**原因**：`ToolMain` 用 `ResolveInfo.loadLabel(pm)` 取应用名，触发 MIUI 主题兼容层，
本机没有该 xml，`app_process` 环境下直接抛出。`CombinedOutput` 把 stderr 混进 stdout，
零退出码让堆栈被当成"正常结果"返回。同一异常也出现在 `daemon.log` 里
（`ActivityThread.systemMain → Resources.getSystem → MiuiResourcesImpl`），但 daemon
会继续建屏，不影响副屏。

**修改**：
- `looksLikeToolFailure()` 识别堆栈/失败标记。
- `fallbackListApps()` 用 `cmd package query-activities --brief -a MAIN -c LAUNCHER`
  兜底列包名。没有中文应用名（那正是崩的地方），但 `vd launch` 只需要包名。

## 3. 副屏 daemon 的 BOOTCLASSPATH 是 ColorOS 专用

**原因**：`bin/run_daemon.sh` 在 `BOOTCLASSPATH` 为空时写死了一份 OPPO 的 classpath
（`oplus-framework.jar`、`QPerformance.jar`、`UxPerformance.jar`、`tcmiface.jar` …）。
非 ColorOS 机型这些 jar 不存在，而该 ROM 真正需要的也可能不在列表里。

**修改**：
- 先从 `/proc/<system_server>/environ` 继承真实 `BOOTCLASSPATH` /
  `DEX2OATBOOTCLASSPATH`；继承不到才退回原固定列表（行为不变）。
- `wm size` 解析改取最后一行，有 Override 时优先 Override
  （本机 `Physical 1440x3200` + `Override 1080x2400`）。

## 4. LSPosed 状态误报（`lsposed_active`）

**原因**：只认 `pidof lspd` + `modules_*.log`，新版/N 版 LSPosed 的文件名与进程名不同。

**修改**：进程名或 `/data/adb/lspd` 目录任一存在即认为 daemon 在跑；再遍历
`/data/adb/lspd/log/` 全部日志匹配 `AgentMobileUseHook` 或包名。

---

## 未改动 / 已知限制

- `agent_vd.dex`、`agent_tools.dex`、`agent_hook.apk` 与原版完全一致。
- `/api/apps` 兜底列表只有包名，没有中文应用名。
- `shell` 身份（uid 2000）直接 `screencap -d <虚拟屏 token>` 实测失败，疑似权限；
  `vd_server` 以 root 运行，若 root 仍失败则需改为 daemon 侧 ImageReader 抓帧。


## 5. 副屏截图：影子显示镜像（最终方案，xiaomi23）

这一项前后试了四层方案，记录完整推理过程，避免以后重复踩坑。

### 为什么 `screencap -d` 不行

`screencap -d` 要的是 **SurfaceFlinger display token**。虚拟屏的 token 形如
`0xa0000000_62f50ffe`：它是 SurfaceFlinger 进程内 BBinder 的**指针值**，最高位为 1、
超过 int64，而且**跨进程拿到一个指针毫无意义**。所以：

- 传逻辑 display id（`3`）→ 无效
- 传 dumpsys 打印的那串十进制 → 溢出/无效
- 传等价的负数（`-6917529025980854274`，位模式相同）→ 同样失败

### 为什么 `SurfaceControl.captureDisplay` 也不行

在 daemon 进程内反射调用它，用**物理屏** token 能成功出图（自检 `OK 445398 bytes`），
但用虚拟屏 token 恒返回 null。原因是 `VirtualDisplay.mToken` 是 DisplayManagerService
的 **uniqueId**，不是 SF 的 display token；真正的 token 在 system_server 内部，
客户端拿不回来。

### 最终采用：影子显示镜像

```
SurfaceControl.createDisplay("AgentMirrorDisplay", false)   ← 自己持有的令牌
  Transaction.setDisplaySurface(token, mirrorReader.getSurface())
  Transaction.setDisplayLayerStack(token, <虚拟屏的 layerStack>)
  Transaction.setDisplayProjection(token, 0, full, full)
  apply()
```

编码器继续占用虚拟屏原来的输出面，**截图从影子显示的独立 ImageReader 读**：
不抢面、不改尺寸、不闪烁，两者互不干扰。

**layerStack 的定位方式**（踩过一次坑）：`dumpsys SurfaceFlinger` 里同一个虚拟屏
token 会出现**两个块**：

```
Display <token> (virtual, "AgentVirtualDisplay")mIsScreenProjection=0,
   layerFilter={layerStack=4294967295 toInternalDisplay=true }
   layerStackSpace=... bounds=Rect(0, 0, 1080, 2400)     ← 不是它

Display <token> (virtual, "AgentVirtualDisplay")
   layerFilter={layerStack=26 toInternalDisplay=false }
   layerStackSpace=... bounds=Rect(0, 0, 1072, 2400)     ← 这个才是
```

第一版我用"谁先出帧就用谁"，结果绑到了物理屏的栈（22），截图变成手机锁屏。
正确做法是**按名字 + 尺寸双重匹配**：只有 `bounds` 等于虚拟屏实际尺寸的那块才用，
`4294967295`（0xFFFFFFFF，无效栈）直接跳过。

### 回退链

影子显示不可用时（隐藏 API 变动、栈定位失败），依次退到：

1. `SurfaceControl.captureDisplay` 直读（虚拟屏通常 null）
2. 抢回输出面 + **真实 resize 32px** 强制重绘（有闪烁，但能出图）
3. `screencap -d`（基本不可能成功，仅作探测）

### 实测

| 项 | 结果 |
|---|---|
| 截图内容 | 副屏实时画面（设置页、搜索页均正确） |
| 延迟 | 0.21–0.30s |
| 点击后画面 | 同步变化 |
| 视频流 | 不受影响，截图后仍 101 正常 |
| 视觉 | 无闪烁、无缩放 |

## 6. 局域网鉴权：Web 设置密码，磁盘只存哈希（xiaomi10）

**问题**：为了从电脑控制手机，`service.sh` 显式设了 `HOST=0.0.0.0`；而 vd_server 的所有
接口（click / type / screenshot / launch_app / stop）**没有任何鉴权**——原代码把密钥存在
`dshAuthSecret` 里却从不校验。同一热点下任何设备都能接管手机。

**设计**（经过两次修正后的最终形态）：

- **明文密码不落盘**。服务端只保存 `sha256(密码)` 到 `/data/local/tmp/.dsh_auth`（权限 600）。
- **密码通过 Web 设置**：手机控制台页面 `http://127.0.0.1:3070/` 底栏新增锁形按钮，
  弹出输入框；也可直接 `POST /api/auth/secret {"password":"..."}`。该接口只对**回环地址**
  开放，非同机调用需要先通过鉴权，等于改密码必须在手机上操作。
- **`GET /api/auth/secret` 只返回"是否已配置"**，绝不回显密码或哈希。
- **回环免密**：手机上的 `vd` CLI、DSH 插件行为不变。
- **fail closed**：未设置密码时，非回环请求一律 401，而不是放行。
- 请求方可用 `X-Auth-Token: <密码>`、`?token=<密码>` 或 HTTP Basic 传密码。

**改密码**：手机控制台页面 → 锁形按钮 → 输入新密码 → 保存。立即生效，无需重启。

**最安全配置**：不需要远程控制时，删掉 `service.sh` 里的 `export HOST=0.0.0.0`，
服务退回只监听回环，密码机制自然用不上。

## 8. 免重启生效（xiaomi16）

**问题**：KernelSU 装包只是把文件放进 `/data/adb/modules_update/<id>`，重启时才合并到
`/data/adb/modules/<id>`。于是每次改动都要「装包 + 重启手机」，一轮好几分钟。

**修改**：`action.sh`（模块页「执行」按钮，以 root 运行）现在做完整闭环：

1. `cp -rf /data/adb/modules_update/agent_mobile_use/. $MODDIR/` —— 直接把暂存同步进现行目录
2. 重新 `chmod` 并同步 dex / run_daemon.sh 到 `/data/local/tmp`
3. `pkill` 掉旧的 `vd_server` 与 `DaemonMain`
4. 以 `HOST=0.0.0.0` 重新拉起 `vd_server`
5. 把模块文件清单、版本号、daemon 日志尾部、接口自检结果写到
   `/sdcard/Download/amu_action.txt`

**效果**：装包 → 点「执行」，约 10 秒生效，不需要重启。

## 9. 收尾清理（clean1）

调试与遗留方案全部移除，只保留生产路径。

**daemon（agent_vd.dex）**
- 删除主 ImageReader 的 JPEG 缓存（它会产出陈旧画面，是"截图永远一样"的根源）
- 删除 `SurfaceControl.captureDisplay` 直读路径（虚拟屏 token 是 DMS uniqueId，恒 null）
- 删除"抢回输出面 + 强制 resize 32px"回退（会闪烁、1.5s 延迟）
- 删除启动时用物理屏 token 打的自检
- 抓帧只剩一条路径：影子显示；不可用时写 `vd_snapshot.err` 说明原因

**网关（vd_server）**
- 删除 `/api/debug/sf` 与 `/api/debug/logs` 两个调试接口
- 删除 `screencap -d` 相关全部尝试（含负数 token 变体）与 `resolveSfDisplayTokens`
- 删除为"接管输出面"服务的 StreamHub 暂停/恢复机制，流循环恢复为原始逻辑
- 删除 `readTailLines` / `fileExists` / `fileSize` 等调试助手
- 主屏截图仍用 `screencap`（唯一合法用法，不带 `-d`）

**行为变化**：副屏抓帧失败时返回 `500 Capture error: <原因>`
（如 `mirror display unavailable`），**不再返回陈旧画面**。
