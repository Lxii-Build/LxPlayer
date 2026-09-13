package main

import (
	"database/sql"
	"encoding/json"
	"errors"
	"fmt"
	"sync"
	"time"
)

// 运行时可调项：控制开关 + 参数。
//
// 它同时被管理端（读写）与用户端（只读生效）使用，因此单独成文件，
// 与 main.go 里的账号/快照逻辑解耦。默认值刻意与原硬编码行为一致，
// 保证「没人改过设置」时接口行为零变化（见 defaultSettings）。

// settings 是当前生效的运行参数集合。
type settings struct {
	// —— 功能控制（开关）——
	RegistrationEnabled bool `json:"registrationEnabled"` // 关闭后注册端点拒绝
	ReadOnly            bool `json:"readOnly"`            // 维护模式：拒绝快照写入

	// —— 参数调整 ——
	TokenTTLHours          int `json:"tokenTTLHours"`          // 新签发令牌的有效期
	SnapshotMaxBytes       int `json:"snapshotMaxBytes"`       // 单用户快照体积上限
	AuthRateLimitPerMinute int `json:"authRateLimitPerMinute"` // 每客户端每分钟的认证尝试上限，0=关闭
}

// settingsPatch 用指针区分「未提供」与「显式设为零值」。
type settingsPatch struct {
	RegistrationEnabled    *bool `json:"registrationEnabled"`
	ReadOnly               *bool `json:"readOnly"`
	TokenTTLHours          *int  `json:"tokenTTLHours"`
	SnapshotMaxBytes       *int  `json:"snapshotMaxBytes"`
	AuthRateLimitPerMinute *int  `json:"authRateLimitPerMinute"`
}

// settingSpec 描述一个可调项，供管理端 UI 渲染与范围校验。
// 前端不做任何硬编码范围，全部以这里下发的为准。
type settingSpec struct {
	Key   string `json:"key"`
	Label string `json:"label"`
	Kind  string `json:"kind"` // "bool" | "int"
	Min   int    `json:"min,omitempty"`
	Max   int    `json:"max,omitempty"`
	Unit  string `json:"unit,omitempty"`
	Help  string `json:"help,omitempty"`
}

// settingSpecs 是「可调项登记表」。新增可调项时在这里登记，
// 读取端与管理端都从同一张表取值，避免前后端各写一份范围。
var settingSpecs = []settingSpec{
	{Key: "registrationEnabled", Label: "开放注册", Kind: "bool",
		Help: "关闭后 /api/v1/auth/register 返回 403"},
	{Key: "readOnly", Label: "维护模式（只读）", Kind: "bool",
		Help: "开启后拒绝快照写入，返回 503"},
	{Key: "tokenTTLHours", Label: "令牌有效期", Kind: "int", Min: 1, Max: 8760, Unit: "小时",
		Help: "仅影响此后新签发的令牌，已发出的令牌按其签发时的有效期到期"},
	{Key: "snapshotMaxBytes", Label: "快照体积上限", Kind: "int", Min: 1024, Max: maxBodyBytes, Unit: "字节",
		Help: "单用户快照序列化后的上限，最大不超过请求体上限 1 MiB"},
	{Key: "authRateLimitPerMinute", Label: "认证频率上限", Kind: "int", Min: 0, Max: 100000, Unit: "次/分",
		Help: "按客户端统计，作用于注册与登录；0 表示关闭"},
}

// defaultSettings 保持与原硬编码行为一致：
// 注册开放、非维护、令牌 30 天、快照上限即请求体上限、限流 60 次/分。
func defaultSettings() settings {
	return settings{
		RegistrationEnabled:    true,
		ReadOnly:               false,
		TokenTTLHours:          720, // 30 天
		SnapshotMaxBytes:       maxBodyBytes,
		AuthRateLimitPerMinute: 60,
	}
}

const settingsRowKey = "runtime"

// settingsStore 是设置在内存中的缓存 + SQLite 持久化。
// 单行 JSON 存储：读取一次进内存，写入时整体覆盖，避免多条 UPDATE 的中间态。
type settingsStore struct {
	mu  sync.RWMutex
	db  *sql.DB
	cur settings
}

// newSettingsStore 打开数据库时加载已有设置；首次运行会写入默认值。
func newSettingsStore(db *sql.DB) (*settingsStore, error) {
	st := &settingsStore{db: db, cur: defaultSettings()}
	if err := st.load(); err != nil {
		return nil, err
	}
	return st, nil
}

func (st *settingsStore) load() error {
	var raw string
	err := st.db.QueryRow(`SELECT value FROM settings WHERE key = ?`, settingsRowKey).Scan(&raw)
	if errors.Is(err, sql.ErrNoRows) {
		return st.persist(st.cur)
	}
	if err != nil {
		return err
	}
	var loaded settings
	if err := json.Unmarshal([]byte(raw), &loaded); err != nil {
		// 持久化内容损坏时不静默清空：回退默认并覆盖写回，保证接口始终可用。
		loaded = defaultSettings()
	}
	loaded.clamp()
	st.mu.Lock()
	st.cur = loaded
	st.mu.Unlock()
	return nil
}

// get 返回当前设置的副本。
func (st *settingsStore) get() settings {
	st.mu.RLock()
	defer st.mu.RUnlock()
	return st.cur
}

// update 做局部更新：只改 patch 里非 nil 的字段，校验通过并落库后才切换内存值。
// 校验失败时内存值不变（返回当前值 + 错误），不会出现「改了内存没落库」的不一致。
func (st *settingsStore) update(patch settingsPatch) (settings, error) {
	st.mu.Lock()
	defer st.mu.Unlock()
	next := st.cur
	if patch.RegistrationEnabled != nil {
		next.RegistrationEnabled = *patch.RegistrationEnabled
	}
	if patch.ReadOnly != nil {
		next.ReadOnly = *patch.ReadOnly
	}
	if patch.TokenTTLHours != nil {
		next.TokenTTLHours = *patch.TokenTTLHours
	}
	if patch.SnapshotMaxBytes != nil {
		next.SnapshotMaxBytes = *patch.SnapshotMaxBytes
	}
	if patch.AuthRateLimitPerMinute != nil {
		next.AuthRateLimitPerMinute = *patch.AuthRateLimitPerMinute
	}
	if err := next.validate(); err != nil {
		return st.cur, err
	}
	if err := st.persist(next); err != nil {
		return st.cur, err
	}
	st.cur = next
	return next, nil
}

// validate 按 settingSpecs 的范围校验，错误信息面向管理员可见。
func (s settings) validate() error {
	if s.TokenTTLHours < 1 || s.TokenTTLHours > 8760 {
		return errors.New("令牌有效期需在 1–8760 小时之间")
	}
	if s.SnapshotMaxBytes < 1024 || s.SnapshotMaxBytes > maxBodyBytes {
		return fmt.Errorf("快照体积上限需在 1024–%d 字节之间", maxBodyBytes)
	}
	if s.AuthRateLimitPerMinute < 0 || s.AuthRateLimitPerMinute > 100000 {
		return errors.New("认证频率上限需在 0–100000 之间（0 表示关闭）")
	}
	return nil
}

// clamp 把越界值夹回合法范围，用于兜底「有人直接改库」的情况。
func (s *settings) clamp() {
	s.TokenTTLHours = clampInt(s.TokenTTLHours, 1, 8760)
	s.SnapshotMaxBytes = clampInt(s.SnapshotMaxBytes, 1024, maxBodyBytes)
	s.AuthRateLimitPerMinute = clampInt(s.AuthRateLimitPerMinute, 0, 100000)
}

func (st *settingsStore) persist(s settings) error {
	raw, err := json.Marshal(s)
	if err != nil {
		return err
	}
	_, err = st.db.Exec(
		`INSERT INTO settings(key, value, updated_at) VALUES(?,?,?)
         ON CONFLICT(key) DO UPDATE SET value=excluded.value, updated_at=excluded.updated_at`,
		settingsRowKey, string(raw), time.Now().Unix(),
	)
	return err
}

func clampInt(v, lo, hi int) int {
	if v < lo {
		return lo
	}
	if v > hi {
		return hi
	}
	return v
}
