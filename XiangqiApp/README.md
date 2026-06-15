# XiangqiApp — Pikafish iOS 集成说明

本工程把 [Pikafish](https://github.com/official-pikafish/Pikafish)（最强中国象棋 UCI 引擎，
基于 Stockfish）以纯本地方式嵌入 iOS App，无需任何服务器后端。第一阶段目标：**验证引擎能在
iOS 上启动、握手并返回 bestmove**。

## 一、目录结构

```
XiangqiApp/
├── XiangqiApp.swift              # App 入口
├── EngineTestView.swift         # 最简测试界面（启动引擎 / 让 AI 走一步）
├── XiangqiApp-Bridging-Header.h # Swift <-> ObjC++ 桥接头
└── Engine/
    ├── PikafishBridge.h         # 桥接层接口
    ├── PikafishBridge.mm        # 桥接层实现（管道重定向 std::cin/cout，后台跑 UCI loop）
    ├── PikafishEngine.swift     # Swift 引擎管理器（异步 UCI 接口）
    └── pikafish/                # Pikafish C++ 源码（已去掉 main.cpp）
```

> 注意：`Engine/pikafish/` 内已删除 `main.cpp`，因为 App 自己提供入口，引擎主循环由
> `PikafishBridge.mm` 调用 `UCIEngine::loop()` 启动。

## 二、在 Xcode 中创建工程并集成（一次性配置）

1. **新建工程**：Xcode → File → New → Project → iOS → App
   - Interface: **SwiftUI**，Language: **Swift**
   - 产品名建议 `XiangqiApp`

2. **加入源文件**：把本目录下的 `.swift` / `.h` / `.mm` 以及整个 `Engine/pikafish/`
   文件夹拖入工程（勾选 "Copy items if needed"，Target 勾选你的 App）。
   - `Engine/pikafish/Makefile` 不要加入编译（它只是参考，不参与 Xcode 构建）。

3. **配置桥接头**：Target → Build Settings → 搜索 `Bridging Header` →
   `Objective-C Bridging Header` 设为：
   ```
   XiangqiApp/XiangqiApp-Bridging-Header.h
   ```
   （或工程内对应的相对路径）

4. **头文件搜索路径**：Build Settings → `Header Search Paths` 添加（递归）：
   ```
   $(SRCROOT)/XiangqiApp/Engine/pikafish
   $(SRCROOT)/XiangqiApp/Engine/pikafish/nnue
   $(SRCROOT)/XiangqiApp/Engine/pikafish/external
   ```
   建议直接加一行 `$(SRCROOT)/XiangqiApp/Engine/pikafish` 并设为 **recursive**。

5. **C++ 编译设置**：Build Settings →
   - `C++ Language Dialect` → **C++17**
   - `C++ and Objective-C Interoperability`（或保证 .mm 以 ObjC++ 编译）
   - `Enable C++ Exceptions` → 引擎用 `-fno-exceptions`，可保持默认；若报错把它设为 No。

6. **预处理宏（关键）**：Build Settings → `Preprocessor Macros`（Debug/Release 都加）：
   ```
   NDEBUG=1
   USE_PTHREADS=1
   IS_64BIT=1
   USE_POPCNT=1
   USE_NEON=8
   USE_NEON_DOTPROD=1
   ```
   这些对应 Makefile 里 `ARCH=apple-silicon` 的定义。iPhone 是 ARM64+NEON，
   真机用上面这组；**模拟器**若运行在 Apple Silicon Mac 上也可用同一组（arm64 模拟器）。

7. **架构**：iPhone 真机为 arm64。若需在 Intel Mac 的模拟器上跑，需另配 x86_64 宏
   （去掉 NEON 宏、改用 `USE_SSE41`/`USE_POPCNT`），一般直接用真机或 Apple Silicon 即可。

## 三、NNUE 权重文件

Pikafish 评估依赖一个 `.nnue` 神经网络文件（仓库不含，需单独下载）：

1. 从 Pikafish releases 或官网下载对应版本的 `pikafish.nnue`。
2. 重命名为 `pikafish.nnue`，拖入 Xcode 工程（Target 勾选，作为资源打包进 App bundle）。
3. App 启动后由 `PikafishEngine.setNetwork(path:)` 通过
   `setoption name EvalFile value <path>` 告诉引擎。
   `EngineTestView.loadNetworkIfAvailable()` 已实现该逻辑（按文件名 `pikafish.nnue` 查找）。

> 没有 .nnue 文件时引擎仍能启动握手，但无法正常评估/对弈。

## 四、运行验证（第一阶段验收标准）

启动 App → 点「启动引擎」→ 日志应出现 `uciok` / `readyok`，状态变绿。
点「让 AI 走一步」→ 数百毫秒后 `最佳着法` 出现一个合法着法（如 `h2e2`）。

命令行侧已验证（macOS 上编译运行）：
```
id name Pikafish dev-...
uciok
readyok
```
说明源码完整、UCI 协议封装正确，桥接逻辑可直接用于 iOS。

## 五、常见问题

- **编译报找不到头文件**：检查第 4 步 Header Search Paths 是否 recursive 覆盖
  `pikafish/`、`nnue/`、`external/` 三处。
- **链接报重复 main**：确认 `Engine/pikafish/main.cpp` 已删除（本工程已删）。
- **运行无输出**：桥接用管道重定向了进程级 stdin/stdout，确保只创建一个
  `PikafishBridge` 实例并只 `start()` 一次。
- **bestmove 不返回**：通常是没加载 .nnue；先放好权重文件再测对弈。

## 六、下一阶段

引擎桥接跑通后，下一步做：棋盘 UI（9×10 格）、走子规则与 FEN 生成、把玩家走子
转成 UCI 着法喂给引擎、解析引擎 bestmove 落子，形成完整人机对弈。
