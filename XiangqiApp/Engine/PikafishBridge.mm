//
//  PikafishBridge.mm
//  XiangqiApp
//
//  Objective-C++ 实现。Pikafish 是一个通过 std::cin 读命令、std::cout 写结果的
//  UCI 引擎。为了不修改引擎源码，这里用一对管道(pipe)把引擎的标准输入输出重定向：
//    - Swift 发来的命令 -> 写入 inputPipe 写端 -> 引擎从 std::cin 读到
//    - 引擎 std::cout 输出 -> 写入 outputPipe 写端 -> 读线程逐行读出 -> 回调
//
//  引擎主循环在独立线程运行（UCIEngine::loop 是阻塞式的）。
//

#import "PikafishBridge.h"

#include <atomic>
#include <cstdio>
#include <memory>
#include <string>
#include <thread>
#include <unistd.h>

#include "bitboard.h"
#include "misc.h"
#include "position.h"
#include "tune.h"
#include "uci.h"

using namespace Stockfish;

@implementation PikafishBridge {
    int _inFd[2];   // 命令输入管道：[0]=读端给引擎, [1]=写端给我们
    int _outFd[2];  // 引擎输出管道：[0]=读端给我们, [1]=写端给引擎
    int _savedStdin;
    int _savedStdout;

    std::thread _engineThread;  // 跑 UCIEngine::loop
    std::thread _readerThread;  // 读引擎输出
    std::atomic<bool> _running;

    dispatch_queue_t _callbackQueue;
    NSMutableData *_lineBuffer;  // 累积输出，按换行切行
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _running = false;
        _callbackQueue = dispatch_queue_create("com.xiangqi.pikafish.callback", DISPATCH_QUEUE_SERIAL);
        _lineBuffer = [NSMutableData data];
    }
    return self;
}

- (void)start {
    if (_running.load()) {
        return;
    }

    // 创建管道
    if (pipe(_inFd) != 0 || pipe(_outFd) != 0) {
        NSLog(@"[PikafishBridge] pipe() 创建失败");
        return;
    }

    // 备份并重定向进程级 stdin/stdout 到管道
    _savedStdin = dup(fileno(stdin));
    _savedStdout = dup(fileno(stdout));
    dup2(_inFd[0], fileno(stdin));
    dup2(_outFd[1], fileno(stdout));

    // 重新打开 C++ 的 iostream 同步（确保 std::cin/std::cout 跟随新的 fd）
    std::ios::sync_with_stdio(true);
    setvbuf(stdout, nullptr, _IONBF, 0);  // 关闭缓冲，输出即时可读

    _running = true;

    // 启动引擎主循环线程
    _engineThread = std::thread([]() {
        Bitboards::init();
        Position::init();

        int argc = 1;
        char arg0[] = "pikafish";
        char *argv[] = {arg0, nullptr};

        auto uci = std::make_unique<UCIEngine>(argc, argv);
        Tune::init(uci->engine_options());
        uci->loop();  // 阻塞，直到收到 quit
    });

    // 启动输出读取线程
    int readFd = _outFd[0];
    _readerThread = std::thread([self, readFd]() {
        char buf[4096];
        while (self->_running.load()) {
            ssize_t n = read(readFd, buf, sizeof(buf));
            if (n <= 0) {
                break;
            }
            @autoreleasepool {
                [self appendBytes:buf length:(NSUInteger)n];
            }
        }
    });
}

// 把读到的字节累积到缓冲区，按 \n 切行并回调
- (void)appendBytes:(const char *)bytes length:(NSUInteger)length {
    [_lineBuffer appendBytes:bytes length:length];

    const char *data = (const char *)_lineBuffer.bytes;
    NSUInteger total = _lineBuffer.length;
    NSUInteger lineStart = 0;

    for (NSUInteger i = 0; i < total; i++) {
        if (data[i] == '\n') {
            NSUInteger lineLen = i - lineStart;
            NSString *line = [[NSString alloc] initWithBytes:data + lineStart
                                                      length:lineLen
                                                    encoding:NSUTF8StringEncoding];
            if (line) {
                PikafishOutputHandler handler = self.outputHandler;
                if (handler) {
                    dispatch_async(self->_callbackQueue, ^{
                        handler(line);
                    });
                }
            }
            lineStart = i + 1;
        }
    }

    // 保留未完成的最后一行
    if (lineStart > 0) {
        NSData *rest = [_lineBuffer subdataWithRange:NSMakeRange(lineStart, total - lineStart)];
        _lineBuffer = [NSMutableData dataWithData:rest];
    }
}

- (void)sendCommand:(NSString *)command {
    if (!_running.load()) {
        return;
    }
    NSString *line = [command stringByAppendingString:@"\n"];
    NSData *data = [line dataUsingEncoding:NSUTF8StringEncoding];
    write(_inFd[1], data.bytes, data.length);
}

- (void)stop {
    if (!_running.load()) {
        return;
    }
    [self sendCommand:@"quit"];
    _running = false;

    // 关闭写端，唤醒可能阻塞的读
    close(_inFd[1]);
    close(_outFd[1]);

    if (_engineThread.joinable()) {
        _engineThread.join();
    }
    if (_readerThread.joinable()) {
        _readerThread.join();
    }

    // 恢复 stdin/stdout
    dup2(_savedStdin, fileno(stdin));
    dup2(_savedStdout, fileno(stdout));
    close(_savedStdin);
    close(_savedStdout);
    close(_inFd[0]);
    close(_outFd[0]);
}

@end
