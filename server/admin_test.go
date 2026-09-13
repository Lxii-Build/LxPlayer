package main

import (
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"path/filepath"
	"strconv"
	"strings"
	"testing"
	"time"

	"github.com/golang-jwt/jwt/v5"
)

// newAdminTestServer 在默认测试服务器上启用管理端（口令 admin-secret）。
func newAdminTestServer(t *testing.T) *server {
	t.Helper()
	s := newTestServer(t)
	s.adminEnabled = true
	s.adminPasswordHash = sha256Sum("admin-secret")
	s.adminSecret = deriveAdminSecret("test-secret", "")
	return s
}

func adminLogin(t *testing.T, h http.Handler, password string) (string, int) {
	t.Helper()
	body, _ := json.Marshal(map[string]string{"password": password})
	rec := doJSON(t, h, http.MethodPost, "/admin/api/v1/login", string(body), "")
	var out map[string]any
	_ = json.Unmarshal(rec.Body.Bytes(), &out)
	token, _ := out["token"].(string)
	return token, rec.Code
}

func putConfig(t *testing.T, h http.Handler, token, body string) *httptest.ResponseRecorder {
	t.Helper()
	return doJSON(t, h, http.MethodPut, "/admin/api/v1/config", body, token)
}

func intPtr(v int) *int { return &v }

func TestAdminLoginRejectsWrongPassword(t *testing.T) {
	s := newAdminTestServer(t)
	h := s.routes()

	if _, code := adminLogin(t, h, "wrong-password"); code != http.StatusUnauthorized {
		t.Fatalf("wrong password status=%d", code)
	}
	token, code := adminLogin(t, h, "admin-secret")
	if code != http.StatusOK || token == "" {
		t.Fatalf("correct password status=%d token=%q", code, token)
	}
}

func TestAdminEndpointsRejectWithoutToken(t *testing.T) {
	s := newAdminTestServer(t)
	h := s.routes()
	for _, path := range []string{"/admin/api/v1/stats", "/admin/api/v1/users", "/admin/api/v1/config"} {
		if rec := doJSON(t, h, http.MethodGet, path, "", ""); rec.Code != http.StatusUnauthorized {
			t.Fatalf("%s want 401 got %d", path, rec.Code)
		}
	}
}

// 管理端与用户端隔离的核心断言：普通用户的 JWT 不能当作管理员令牌。
func TestUserTokenCannotAccessAdmin(t *testing.T) {
	s := newAdminTestServer(t)
	h := s.routes()
	userToken, status, _ := register(t, h, "u@example.com", "password12")
	if status != http.StatusOK {
		t.Fatal(status)
	}
	if rec := doJSON(t, h, http.MethodGet, "/admin/api/v1/stats", "", userToken); rec.Code != http.StatusUnauthorized {
		t.Fatalf("user token must not pass admin auth, got %d", rec.Code)
	}
}

// 未配置 ADMIN_PASSWORD 时整个管理 API 安全失败（503），用户 API 不受影响。
func TestAdminDisabledWithoutPassword(t *testing.T) {
	h := newTestServer(t).routes()
	if rec := doJSON(t, h, http.MethodPost, "/admin/api/v1/login", `{"password":"x"}`, ""); rec.Code != http.StatusServiceUnavailable {
		t.Fatalf("login want 503 got %d", rec.Code)
	}
	if rec := doJSON(t, h, http.MethodGet, "/admin/api/v1/stats", "", "whatever"); rec.Code != http.StatusServiceUnavailable {
		t.Fatalf("stats want 503 got %d", rec.Code)
	}
	// 用户 API 仍正常
	if rec := doJSON(t, h, http.MethodGet, "/api/v1/health", "", ""); rec.Code != http.StatusOK {
		t.Fatalf("health want 200 got %d", rec.Code)
	}
}

// 注册开关：关闭后注册 403，公共只读端点能感知，重新开启后恢复。
func TestRegistrationToggleTakesEffect(t *testing.T) {
	s := newAdminTestServer(t)
	h := s.routes()
	token, _ := adminLogin(t, h, "admin-secret")

	if rec := putConfig(t, h, token, `{"registrationEnabled":false}`); rec.Code != http.StatusOK {
		t.Fatalf("disable status=%d body=%s", rec.Code, rec.Body.String())
	}
	if _, status, _ := register(t, h, "blocked@example.com", "password12"); status != http.StatusForbidden {
		t.Fatalf("register should be 403, got %d", status)
	}
	pub := doJSON(t, h, http.MethodGet, "/api/v1/config", "", "")
	var cfg map[string]any
	_ = json.Unmarshal(pub.Body.Bytes(), &cfg)
	if cfg["registrationEnabled"] != false {
		t.Fatalf("public config not reflecting disable: %v", cfg)
	}

	if rec := putConfig(t, h, token, `{"registrationEnabled":true}`); rec.Code != http.StatusOK {
		t.Fatalf("enable status=%d", rec.Code)
	}
	if _, status, _ := register(t, h, "allowed@example.com", "password12"); status != http.StatusOK {
		t.Fatalf("register should recover, got %d", status)
	}
}

// 维护模式：只读时拒绝快照写入，但读取仍可用；关闭后恢复写入。
func TestReadOnlyBlocksSnapshotWrite(t *testing.T) {
	s := newAdminTestServer(t)
	h := s.routes()
	token, _ := adminLogin(t, h, "admin-secret")
	userToken, status, _ := register(t, h, "ro@example.com", "password12")
	if status != http.StatusOK {
		t.Fatal(status)
	}

	if rec := putConfig(t, h, token, `{"readOnly":true}`); rec.Code != http.StatusOK {
		t.Fatalf("enable read-only status=%d", rec.Code)
	}
	if rec := doJSON(t, h, http.MethodGet, "/api/v1/sync/snapshot", "", userToken); rec.Code != http.StatusOK {
		t.Fatalf("read must still work in read-only, got %d", rec.Code)
	}
	body := `{"revision":0,"playlists":[],"likes":["x"],"history":[],"settings":{}}`
	if rec := doJSON(t, h, http.MethodPut, "/api/v1/sync/snapshot?baseRevision=0", body, userToken); rec.Code != http.StatusServiceUnavailable {
		t.Fatalf("write must be blocked, got %d %s", rec.Code, rec.Body.String())
	}

	if rec := putConfig(t, h, token, `{"readOnly":false}`); rec.Code != http.StatusOK {
		t.Fatalf("disable read-only status=%d", rec.Code)
	}
	if rec := doJSON(t, h, http.MethodPut, "/api/v1/sync/snapshot?baseRevision=0", body, userToken); rec.Code != http.StatusOK {
		t.Fatalf("write should recover, got %d %s", rec.Code, rec.Body.String())
	}
}

// 参数校验：越界值被拒且不改变当前设置。
func TestConfigValidationRejectsOutOfRange(t *testing.T) {
	s := newAdminTestServer(t)
	h := s.routes()
	token, _ := adminLogin(t, h, "admin-secret")
	before := s.settingsStore.get()

	for _, body := range []string{
		`{"tokenTTLHours":0}`,
		`{"snapshotMaxBytes":10}`,
		`{"authRateLimitPerMinute":-1}`,
	} {
		if rec := putConfig(t, h, token, body); rec.Code != http.StatusBadRequest {
			t.Fatalf("body %s want 400 got %d", body, rec.Code)
		}
	}
	if after := s.settingsStore.get(); after != before {
		t.Fatalf("settings changed on invalid input: %+v -> %+v", before, after)
	}
}

// 令牌有效期参数对新签发的令牌生效。
func TestTokenTTLSettingAppliesToNewTokens(t *testing.T) {
	s := newAdminTestServer(t)
	h := s.routes()
	token, _ := adminLogin(t, h, "admin-secret")
	if rec := putConfig(t, h, token, `{"tokenTTLHours":1}`); rec.Code != http.StatusOK {
		t.Fatalf("set ttl status=%d %s", rec.Code, rec.Body.String())
	}

	userToken, status, _ := register(t, h, "ttl@example.com", "password12")
	if status != http.StatusOK {
		t.Fatal(status)
	}
	parsed, err := jwt.ParseWithClaims(userToken, &claims{}, func(tk *jwt.Token) (any, error) {
		return []byte("test-secret"), nil
	})
	if err != nil {
		t.Fatal(err)
	}
	c, ok := parsed.Claims.(*claims)
	if !ok || c.ExpiresAt == nil || c.IssuedAt == nil {
		t.Fatalf("missing time claims: %+v", parsed.Claims)
	}
	delta := c.ExpiresAt.Time.Sub(c.IssuedAt.Time)
	if delta < 59*time.Minute || delta > 61*time.Minute {
		t.Fatalf("token ttl = %v, want ~1h", delta)
	}
}

// 快照体积上限参数被执行。
func TestSnapshotMaxBytesEnforced(t *testing.T) {
	s := newAdminTestServer(t)
	h := s.routes()
	token, _ := adminLogin(t, h, "admin-secret")
	if rec := putConfig(t, h, token, `{"snapshotMaxBytes":1024}`); rec.Code != http.StatusOK {
		t.Fatalf("set max status=%d %s", rec.Code, rec.Body.String())
	}

	userToken, status, _ := register(t, h, "big@example.com", "password12")
	if status != http.StatusOK {
		t.Fatal(status)
	}
	likes := make([]string, 0, 300)
	for i := 0; i < 300; i++ {
		likes = append(likes, "local:track-identifier-000000000000")
	}
	snap := snapshot{Revision: 0, Likes: likes, Playlists: []remotePlaylist{}, History: []remoteHistory{}, Settings: map[string]string{}}
	body, _ := json.Marshal(snap)
	rec := doJSON(t, h, http.MethodPut, "/api/v1/sync/snapshot?baseRevision=0", string(body), userToken)
	if rec.Code != http.StatusRequestEntityTooLarge {
		t.Fatalf("want 413 got %d %s", rec.Code, rec.Body.String())
	}
}

// 认证频率上限参数被执行。
func TestAuthRateLimitEnforced(t *testing.T) {
	s := newAdminTestServer(t)
	h := s.routes()
	token, _ := adminLogin(t, h, "admin-secret")
	if rec := putConfig(t, h, token, `{"authRateLimitPerMinute":2}`); rec.Code != http.StatusOK {
		t.Fatalf("set limit status=%d", rec.Code)
	}

	bad := `{"email":"rate@example.com","password":"password12"}`
	for i := 1; i <= 2; i++ {
		if rec := doJSON(t, h, http.MethodPost, "/api/v1/auth/login", bad, ""); rec.Code != http.StatusUnauthorized {
			t.Fatalf("call %d want 401 got %d", i, rec.Code)
		}
	}
	rec := doJSON(t, h, http.MethodPost, "/api/v1/auth/login", bad, "")
	if rec.Code != http.StatusTooManyRequests {
		t.Fatalf("third call want 429 got %d %s", rec.Code, rec.Body.String())
	}
	if rec.Header().Get("Retry-After") == "" {
		t.Fatal("429 should carry Retry-After")
	}
}

// 限流关闭（0）时不拦截。
func TestRateLimitDisabledWhenZero(t *testing.T) {
	s := newAdminTestServer(t)
	h := s.routes()
	token, _ := adminLogin(t, h, "admin-secret")
	if rec := putConfig(t, h, token, `{"authRateLimitPerMinute":0}`); rec.Code != http.StatusOK {
		t.Fatalf("disable limit status=%d", rec.Code)
	}
	bad := `{"email":"a@example.com","password":"password12"}`
	for i := 0; i < 8; i++ {
		if rec := doJSON(t, h, http.MethodPost, "/api/v1/auth/login", bad, ""); rec.Code != http.StatusUnauthorized {
			t.Fatalf("call %d want 401 got %d", i, rec.Code)
		}
	}
}

// 数据查看：统计与用户列表。
func TestAdminStatsAndUsers(t *testing.T) {
	s := newAdminTestServer(t)
	h := s.routes()
	token, _ := adminLogin(t, h, "admin-secret")

	userToken, status, _ := register(t, h, "s1@example.com", "password12")
	if status != http.StatusOK {
		t.Fatal(status)
	}
	register(t, h, "s2@example.com", "password12")
	body := `{"revision":0,"playlists":[],"likes":["a","b"],"history":[],"settings":{}}`
	if rec := doJSON(t, h, http.MethodPut, "/api/v1/sync/snapshot?baseRevision=0", body, userToken); rec.Code != http.StatusOK {
		t.Fatalf("seed snapshot status=%d", rec.Code)
	}

	stats := doJSON(t, h, http.MethodGet, "/admin/api/v1/stats", "", token)
	if stats.Code != http.StatusOK {
		t.Fatalf("stats status=%d %s", stats.Code, stats.Body.String())
	}
	var sd struct {
		Overview          map[string]any   `json:"overview"`
		Storage           map[string]any   `json:"storage"`
		RegistrationTrend []map[string]any `json:"registrationTrend"`
	}
	_ = json.Unmarshal(stats.Body.Bytes(), &sd)
	if sd.Overview["totalUsers"].(float64) != 2 {
		t.Fatalf("totalUsers=%v", sd.Overview["totalUsers"])
	}
	if sd.Storage["snapshotCount"].(float64) != 1 {
		t.Fatalf("snapshotCount=%v", sd.Storage["snapshotCount"])
	}
	if len(sd.RegistrationTrend) != 30 {
		t.Fatalf("registrationTrend len=%d, want 30", len(sd.RegistrationTrend))
	}

	users := doJSON(t, h, http.MethodGet, "/admin/api/v1/users?limit=10&offset=0", "", token)
	if users.Code != http.StatusOK {
		t.Fatalf("users status=%d", users.Code)
	}
	var ud struct {
		Total int         `json:"total"`
		Users []adminUser `json:"users"`
	}
	_ = json.Unmarshal(users.Body.Bytes(), &ud)
	if ud.Total != 2 || len(ud.Users) != 2 {
		t.Fatalf("users total=%d len=%d", ud.Total, len(ud.Users))
	}
}

// 强制下线：递增令牌版本使已签发令牌立即失效。
func TestAdminRevokeInvalidatesUserTokens(t *testing.T) {
	s := newAdminTestServer(t)
	h := s.routes()
	token, _ := adminLogin(t, h, "admin-secret")

	userToken, status, _ := register(t, h, "rev@example.com", "password12")
	if status != http.StatusOK {
		t.Fatal(status)
	}
	if rec := doJSON(t, h, http.MethodGet, "/api/v1/me", "", userToken); rec.Code != http.StatusOK {
		t.Fatalf("token should work before revoke, got %d", rec.Code)
	}

	var id int64
	if err := s.db.QueryRow(`SELECT id FROM users WHERE email = ?`, "rev@example.com").Scan(&id); err != nil {
		t.Fatal(err)
	}
	rec := doJSON(t, h, http.MethodPost, "/admin/api/v1/users/"+strconv.FormatInt(id, 10)+"/revoke", "", token)
	if rec.Code != http.StatusOK {
		t.Fatalf("revoke status=%d %s", rec.Code, rec.Body.String())
	}
	if rec := doJSON(t, h, http.MethodGet, "/api/v1/me", "", userToken); rec.Code != http.StatusUnauthorized {
		t.Fatalf("old token must be invalid after revoke, got %d", rec.Code)
	}
}

// 删除用户：账号与其数据被移除；删除不存在的用户返回 404。
func TestAdminDeleteRemovesUser(t *testing.T) {
	s := newAdminTestServer(t)
	h := s.routes()
	token, _ := adminLogin(t, h, "admin-secret")
	register(t, h, "del@example.com", "password12")

	var id int64
	if err := s.db.QueryRow(`SELECT id FROM users WHERE email = ?`, "del@example.com").Scan(&id); err != nil {
		t.Fatal(err)
	}
	rec := doJSON(t, h, http.MethodDelete, "/admin/api/v1/users/"+strconv.FormatInt(id, 10), "", token)
	if rec.Code != http.StatusOK {
		t.Fatalf("delete status=%d %s", rec.Code, rec.Body.String())
	}
	login := doJSON(t, h, http.MethodPost, "/api/v1/auth/login", `{"email":"del@example.com","password":"password12"}`, "")
	if login.Code != http.StatusUnauthorized {
		t.Fatalf("deleted user should not log in, got %d", login.Code)
	}
	if rec := doJSON(t, h, http.MethodDelete, "/admin/api/v1/users/999999", "", token); rec.Code != http.StatusNotFound {
		t.Fatalf("delete missing user want 404 got %d", rec.Code)
	}
}

// 设置跨重启持久化。
func TestSettingsPersistAcrossReload(t *testing.T) {
	path := filepath.Join(t.TempDir(), "persist.db")

	db, err := openDB(path)
	if err != nil {
		t.Fatal(err)
	}
	store, err := newSettingsStore(db)
	if err != nil {
		t.Fatal(err)
	}
	off := false
	if _, err := store.update(settingsPatch{RegistrationEnabled: &off, TokenTTLHours: intPtr(48)}); err != nil {
		t.Fatal(err)
	}
	_ = db.Close()

	db2, err := openDB(path)
	if err != nil {
		t.Fatal(err)
	}
	defer db2.Close()
	store2, err := newSettingsStore(db2)
	if err != nil {
		t.Fatal(err)
	}
	got := store2.get()
	if got.RegistrationEnabled {
		t.Fatal("registrationEnabled should persist as false")
	}
	if got.TokenTTLHours != 48 {
		t.Fatalf("tokenTTLHours=%d, want 48", got.TokenTTLHours)
	}
}

// 公共只读配置端点：无需鉴权，默认值与既有行为一致。
func TestPublicConfigEndpoint(t *testing.T) {
	h := newTestServer(t).routes()
	rec := doJSON(t, h, http.MethodGet, "/api/v1/config", "", "")
	if rec.Code != http.StatusOK {
		t.Fatalf("config status=%d", rec.Code)
	}
	var cfg map[string]any
	_ = json.Unmarshal(rec.Body.Bytes(), &cfg)
	if cfg["registrationEnabled"] != true {
		t.Fatalf("registrationEnabled=%v", cfg["registrationEnabled"])
	}
	if cfg["readOnly"] != false {
		t.Fatalf("readOnly=%v", cfg["readOnly"])
	}
	if cfg["serverVersion"] == nil {
		t.Fatal("missing serverVersion")
	}
}

// 管理界面由二进制内嵌托管，根路径重定向到 /admin/。
func TestAdminUIServed(t *testing.T) {
	h := newTestServer(t).routes()
	rec := doJSON(t, h, http.MethodGet, "/admin/", "", "")
	if rec.Code != http.StatusOK {
		t.Fatalf("admin ui status=%d", rec.Code)
	}
	if !strings.Contains(rec.Body.String(), "LxPlayer") {
		t.Fatalf("unexpected admin index body: %.80s", rec.Body.String())
	}
	if root := doJSON(t, h, http.MethodGet, "/", "", ""); root.Code != http.StatusFound {
		t.Fatalf("root should redirect, got %d", root.Code)
	}
}
