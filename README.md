# csgo-ip-validation-bypass
Bypass CS:GO (Legacy) IP validation for servers behind NAT/FRP using SourceMod memory patching.

# CS:GO IP Validation Bypass (IP验证绕过)

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)

## 📖 简介

当 CS:GO（Legacy 版本）服务器**没有公网 IP**，通过内网穿透（如 FRP、NPS）或 NAT 对外提供服务时，客户端连接会被拒绝，并在服务端控制台出现 `STEAM validation rejected` 错误。

这是因为 Valve 的引擎会校验客户端报告的 IP 地址与实际连接 IP 是否一致。内网穿透导致两者不一致，从而触发拒绝。

本项目通过**内存补丁**的方式，修改 `engine.dll` 中的验证函数，使其始终返回成功，从而绕过此 IP 校验。

> ⚠️ **警告**：本项目**仅适用于社区服务器**。严禁在任何受 VAC 保护的官方服务器上使用，否则可能导致封禁。

## 🔧 工作原理

通过逆向工程定位到 `engine.dll` 中的核心验证函数 `sub_101BEFA0`。该函数在执行一系列检查（包括 IP 一致性）后返回布尔值（1=成功，0=失败）。

本项目使用 SourceMod 插件，在服务器启动时动态将该函数的开头指令替换为：
```assembly
mov eax, 1    ; 直接返回 1 (成功)
retn
```
从而完全跳过其内部的 IP 检查逻辑。

## 🧠 逆向工程思路（方法论）

如果你需要在其他版本上复现此方法，或者对其他验证逻辑进行绕过，可参考以下思路：

1. **定位失败日志**：在 IDA Pro 中加载 `engine.dll`，搜索字符串 `"STEAM validation rejected"`。
2. **追溯调用链**：通过交叉引用找到引用该字符串的函数，通常是一个失败处理分发函数（如 `sub_101BEDD0`）。
3. **继续向上追溯**：对该失败处理函数进行交叉引用，找到其调用者。在调用者中寻找 `call` 到验证函数后紧跟 `test al, al` 或 `test eax, eax` 以及条件跳转的代码模式。
4. **识别核心验证函数**：在上述模式中被 `call` 的那个函数（本例中为 `sub_101BEFA0`）就是我们要 Patch 的目标。
5. **制定 Patch**：修改该函数的开头，使其直接返回成功（`mov eax, 1; retn`）。


## 🚀 安装与使用

### 要求
- SourceMod 1.10 或更高版本。
- 仅适用于 **CS:GO (Legacy 版本)**。

### 步骤

1. 将 `ip_fix.smx` 放入服务器的 `csgo/addons/sourcemod/plugins/` 目录。
2. 将 `ip_fix.games.txt` 放入服务器的 `csgo/addons/sourcemod/gamedata/` 目录。
3. 重启服务器，或在控制台执行 `sm plugins load ip_fix`。

### 验证

- 在服务器控制台输入 `sm plugins list`，应看到 `ip_fix.smx` 状态为 **Loaded**。
- 观察服务器日志，没有 `STEAM validation rejected` 相关的错误输出。
- 让内网穿透环境下的朋友尝试连接，应能成功进入服务器。

## ⚠️ 免责声明

本项目仅供学习交流使用，旨在解决社区服务器在内网穿透环境下的技术限制。**请勿在 Valve 官方服务器上使用**。使用者需自行承担因违反相关规定而导致的一切后果。

## 📄 许可证

本项目采用 [MIT 许可证](LICENSE)。

感谢以下项目提供思路
https://github.com/vanz666/NoLobbyReservation
https://github.com/eonexdev/csgo-sv-fix-engine

本项目主要使用deepseek生成。
