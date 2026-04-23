好的，我来整理一份包含完整逆向分析过程的 `ANALYSIS.md` 文档，可以作为 GitHub 仓库的一部分。

### ANALYSIS.md

```markdown
# 逆向分析过程：CS:GO Steam 认证绕过

本文档记录了 CS:GO 服务器 `engine.dll` 中 Steam 认证流程的完整逆向分析过程。

## 工具

- **IDA Pro 7.x**：静态反汇编与反编译
- **Cheat Engine 7.x**：动态内存修改与测试
- **SourceMod 1.11**：插件加载与 Gamedata 管理

## 目标

解决 FRP/NAT 穿透场景下，客户端连接时服务器报 `Client dropped by server` 的问题。

## 核心调用链

```
CBaseServer::RunFrame()                    [sub_101CB3C0]
    └── sub_102624A0()                     // 网络数据包接收
         └── sub_10262380()                // recvfrom 包装
         └── sub_1025FCF0()                // 创建 CNetChan
         └── sub_1025EE30()                // Steam 认证关联
    └── sub_101CA150()                     // 客户端状态巡检（踢出超时/断开的客户端）

Steam 认证回调注册                          [sub_101BD7F0]
    └── SteamAPI_RegisterCallback(0x8F)    // ValidateAuthTicketResponse_t
         └── sub_101BE8F0()                // 认证回调入口
              └── sub_101BEDD0()           // 认证失败处理
                   └── Disconnect("Client dropped by server")
```

## 阶段一：定位网络接收入口

### 目标函数：`CBaseServer::RunFrame`

**地址**：`sub_101CB3C0`

**关键调用**：
- `sub_102624A0(this + 8, this)`：网络数据包接收
- `sub_101CA150(this)`：客户端状态巡检

### 目标函数：`sub_102624A0`

**功能**：从 socket 接收 UDP 数据包，解析位流头部，分发到上层处理。

**关键调用**：
```asm
.text:1025F8B0    call    sub_10262380    ; recvfrom 包装
.text:1025FCF0    call    sub_1025F8B0    ; 查找已有连接
.text:1025EE30    call    sub_1025EE30    ; Steam 认证关联
```

## 阶段二：定位连接创建

### 目标函数：`sub_1025FCF0`

**功能**：为新连接创建 `CNetChan` 对象（大小 16944 字节）。

**关键调用**：
```asm
.text:102505F0    call    sub_102505F0    ; CNetChan 构造函数
.text:1025EE30    call    sub_1025EE30    ; 设置 Steam 认证数据
```

## 阶段三：定位 Steam 认证关联

### 目标函数：`sub_1025EE30`

**功能**：将 Steam 认证票据关联到 `CNetChan` 对象。

**关键代码**：
```asm
.text:1025EE3F    mov     [ebx+108h], eax        ; 保存 Steam 数据标识符
.text:1025EE7F    call    dword ptr [esi+1Ch]    ; 调用 Steam API 发起认证
.text:1025EEA7    push    offset aAssociatingNet ; "Associating NetChan ... with Steam ..."
```

**关键发现**：此函数仅发起关联请求，真正的认证结果由回调处理。

## 阶段四：定位 Steam 回调注册

### 目标函数：`sub_101BD7F0`

**功能**：注册所有 Steam 服务器相关回调。

**注册的回调列表**：

| 回调 ID | 类型 | 处理函数 | 功能 |
| :--- | :--- | :--- | :--- |
| `0x65` | `SteamServersConnected_t` | `sub_101BE290` | 连接成功 |
| `0x66` | `SteamServerConnectFailure_t` | `sub_101BE640` | 连接失败 |
| `0x67` | `SteamServersDisconnected_t` | `sub_101BE7F0` | 断开连接 |
| `0x73` | `GSPolicyResponse_t` | `sub_101BE230` | 策略响应 |
| **`0x8F`** | **`ValidateAuthTicketResponse_t`** | **`sub_101BE8F0`** | **认证票据验证** |

**关键发现**：`0x8F`（143）回调正是我们要找的认证失败处理入口！

**关键代码**：
```asm
.text:101BD8E8    push    8Fh
.text:101BD8FC    mov     dword_1080C888, offset ValidateAuthTicketResponse_vftable
.text:101BD917    mov     dword_1080C898, offset sub_101BE8F0  ← 回调处理函数
.text:101BD921    call    esi ; SteamAPI_RegisterCallback
```

## 阶段五：定位认证回调入口

### 目标函数：`sub_101BE8F0`

**地址**：`0x101BE8F0`（RVA：`0x1BE8F0`）

**函数特征码**：
```
\x55\x8B\xEC\x83\xE4\xF8\x81\xEC\x24\x02\x00\x00\x53\x56\x8B\xF1\x57
```

**关键分支**（我们要修改的位置，偏移 `+0x8D`）：
```asm
.text:101BE97B    test    ecx, ecx        ; 检查认证结果码
.text:101BE97D    jz      short loc_101BE991   ; 如果为 0（成功），跳转
.text:101BE97F    push    ecx             ; 错误码
.text:101BE980    push    eax             ; pChan
.text:101BE983    call    sub_101BEDD0    ; 调用认证失败处理
```

**逻辑**：
- `ecx = 0`：认证成功 → `jz` 跳转 → 执行成功逻辑
- `ecx ≠ 0`（如 10）：认证失败 → 不跳转 → 调用 `sub_101BEDD0` → 踢出客户端

## 阶段六：定位认证失败处理

### 目标函数：`sub_101BEDD0`

**地址**：`0x101BEDD0`（RVA：`0x1BEDD0`）

**函数签名**：
```cpp
void __thiscall HandleAuthFailure(CSteam3Server* pThis, CNetChan* pChan, int errorCode)
```

**处理的各种错误码**：

| 错误码 | 枚举值 | 断开的提示信息 |
| :--- | :--- | :--- |
| 1 | `InvalidTicket` | 内部处理 |
| 2 | `DuplicateRequest` | "This Steam account does not own this game" |
| 3 | `VACBanned` | "VAC banned from secure server" |
| 4 | `LoggedInElseWhere` | "This account is being used in another location" |
| 5 | `VACCheckTimedOut` | "VAC authentication error" |
| 6-8 | `Expired`/`GameMismatch`/`VACBanned` | 内部处理 |
| **10** | **`InvalidTicket`（IP 不匹配）** | **"Client dropped by server"** |
| 其他 | default | "Client dropped by server" |

**Code 10 的处理逻辑**：
```asm
.text:101BEE38    push    offset aSteamauthClien_0  ; "STEAMAUTH: Client %s received failure code %d"
.text:101BEE3D    call    ds:Warning                ; 输出日志
; ...
.text:101BEE6B    push    offset aClientDroppedB     ; "Client dropped by server"
.text:101BEE74    call    dword ptr [eax+3Ch]       ; pChan->Disconnect()
```

## 补丁方案设计

### 方案 ：修改认证回调分支（最终采用）

将 `sub_101BE8F0` 中的条件跳转改为无条件跳转。

**地址**：`sub_101BE8F0 + 0x8D`

**原始指令**：
```asm
.text:101BE97D    jz  short loc_101BE991   ; 74 12
```

**修改后**：
```asm
.text:101BE97D    jmp short loc_101BE991   ; EB 12
```

## CE 动态验证

### 步骤

1. 附加 CE 到 `srcds.exe`
2. 计算绝对地址：`engine.dll 基址 + 0x1BE97D`
3. 将 `74` 改为 `EB`
4. 用 FRP 客户端连接测试

### 测试结果

- 修改前：`STEAMAUTH: Client ... received failure code 10` → `Client dropped by server`
- 修改后：客户端正常连接，不再被踢出

## SourceMod 插件实现

### 特征码

```
\x55\x8B\xEC\x83\xE4\xF8\x81\xEC\x24\x02\x00\x00\x53\x56\x8B\xF1\x57
```

此特征码取自 `sub_101BE8F0` 的开头 17 字节。

### 补丁

| 参数 | 值 |
| :--- | :--- |
| 偏移 | `+0x8D` |
| 原始 | `74` |
| 补丁 | `EB` |

## 内存布局参考

基于测试服务器的 `engine.dll`（基址 `0x5FB70000`）：

| 组件 | RVA | 绝对地址 |
| :--- | :--- | :--- |
| `engine.dll` 基址 | `0x00000000` | `0x5FB70000` |
| `CreateInterface` | `0x6C730` | `0x5FE6C730` |
| `sub_101BE8F0`（认证回调） | `0x1BE8F0` | `0x5FD2E8F0` |
| 补丁位置 | `0x1BE97D` | `0x5FD2E97D` |
| `sub_101BEDD0`（失败处理） | `0x1BEDD0` | `0x5FD2EDD0` |
| `sub_101CA150`（状态巡检） | `0x1CA150` | `0x5FD3A150` |

## 总结

通过 IDA Pro 静态分析 + Cheat Engine 动态验证，我们从 `CBaseServer::RunFrame` 出发，追踪了完整的 Steam 认证流程：

1. 网络数据包接收（`sub_102624A0`）
2. 连接创建（`sub_1025FCF0`）
3. Steam 认证发起（`sub_1025EE30`）
4. 回调注册（`sub_101BD7F0`）
5. 认证回调入口（`sub_101BE8F0`）
6. **认证失败处理（`sub_101BEDD0`）** ← 问题根源

最终通过 1 字节的修改（`74` → `EB`），实现了安全认证绕过。

