package main

import (
	"sync"
	"time"
)

// rateLimiter 是「按客户端固定窗口计数」的限流器，用于登录/注册这类认证端点。
//
// 刻意保持单进程内存态：本后端的部署形态是「单二进制 + SQLite」，
// 不为限流引入 Redis 之类的新依赖。多实例部署时它是「每实例」限流，
// 这一点在 README 里说明。
type rateLimiter struct {
	mu     sync.Mutex
	window map[string]*windowState
}

type windowState struct {
	start time.Time
	count int
}

func newRateLimiter() *rateLimiter {
	return &rateLimiter{window: make(map[string]*windowState)}
}

// allow 判断某客户端在窗口内是否还能放行。
// limitPerMinute <= 0 表示限流关闭，恒定放行。
// 返回（是否放行，拒绝时的建议重试秒数）。
func (rl *rateLimiter) allow(key string, limitPerMinute int, now time.Time) (bool, int) {
	if limitPerMinute <= 0 {
		return true, 0
	}
	rl.mu.Lock()
	defer rl.mu.Unlock()

	st, ok := rl.window[key]
	if !ok || now.Sub(st.start) >= time.Minute {
		rl.window[key] = &windowState{start: now, count: 1}
		return true, 0
	}
	if st.count >= limitPerMinute {
		retry := int((time.Minute - now.Sub(st.start)).Seconds())
		if retry < 1 {
			retry = 1
		}
		return false, retry
	}
	st.count++
	return true, 0
}

// cleanup 丢弃已过期的窗口，防止 map 随客户端数量无界增长。
func (rl *rateLimiter) cleanup(now time.Time) {
	rl.mu.Lock()
	defer rl.mu.Unlock()
	for k, st := range rl.window {
		if now.Sub(st.start) >= time.Minute {
			delete(rl.window, k)
		}
	}
}
