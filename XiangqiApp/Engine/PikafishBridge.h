//
//  PikafishBridge.h
//  XiangqiApp
//
//  Objective-C++ 桥接层：把 Pikafish 的 UCI 引擎封装成可供 Swift 调用的接口。
//  引擎内部通过标准输入/输出（std::cin / std::cout）通信，这里用管道重定向，
//  在后台线程运行 UCI 主循环，并把引擎输出逐行回调给 Swift。
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// 引擎输出回调：每收到一行 UCI 文本就触发一次。
typedef void (^PikafishOutputHandler)(NSString *line);

@interface PikafishBridge : NSObject

/// 引擎输出回调（在后台串行队列上调用，UI 更新需切回主线程）。
@property (nonatomic, copy, nullable) PikafishOutputHandler outputHandler;

/// 启动引擎：初始化 Bitboards/Position，并在后台线程开启 UCI 主循环。
/// 只需调用一次。
- (void)start;

/// 向引擎发送一条 UCI 命令（自动补换行）。例如：@"uci"、@"isready"、@"go movetime 1000"。
- (void)sendCommand:(NSString *)command;

/// 停止引擎并释放资源。
- (void)stop;

@end

NS_ASSUME_NONNULL_END
