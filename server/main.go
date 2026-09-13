package main

import (
	"context"
	"database/sql"
	"encoding/json"
	"errors"
	"log"
	"net"
	"net/http"
	"os"
	"strconv"
	"strings"
	"time"

	"github.com/golang-jwt/jwt/v5"
	"golang.org/x/crypto/bcrypt"
	_ "modernc.org/sqlite"
)

// 后端只做账号登录和用户数据保存。不代理音频、不存储音频、不解析音源。

const (
	bcryptCost     = 12
	jwtIssuer      = "lxplayer"
	maxBodyBytes   = 1 << 20
	emailMaxLen    = 254
	passwordMinLen = 8
	passwordMaxLen = 72 // bcrypt 上限

	// serverVersion 供健康检查与公共配置端点上报。
	serverVersion = "1.1.0"

	// defaultListenAddr 是容器约定的默认端口（见 Dockerfile / docker-compose.yml）。
	defaultListenAddr = ":10044"
)

type server struct {
	db        *sql.DB
	jwtSecret []byte

	// 运行时设置（控制开关 + 参数）。为 nil 时按默认值工作，便于测试单独构造。
	settingsStore *settingsStore

	// 认证端点限流；为 nil 时不限流。
	limiter *rateLimiter

	// 管理端。adminEnabled 为 false 时整个管理 API 返回 503（安全失败）。
	// adminSecret 与 jwtSecret 相互独立，见 admin.go 的说明。
	adminEnabled      bool
	adminPasswordHash []byte
	adminSecret       []byte

	// trustProxy 为真时，限流以 X-Forwarded-For 的首个地址为客户端标识；
	// 仅在确定部署在可信反向代理之后时才启用，否则可被伪造以绕过限流。
	trustProxy bool
}

type claims struct {
	UserID   int64 `json:"uid"`
	TokenVer int   `json:"ver"`
	jwt.RegisteredClaims
}

type userRow struct {
	ID           int64
	Email        string
	PasswordHash string
	TokenVer     int
}

type snapshot struct {
	Revision  int64             `json:"revision"`
	Playlists []remotePlaylist  `json:"playlists"`
	Likes     []string          `json:"likes"`
	History   []remoteHistory   `json:"history"`
	Settings  map[string]string `json:"settings"`
}

type remotePlaylist struct {
	ID       string   `json:"id"`
	Name     string   `json:"name"`
	TrackIDs []string `json:"trackIds"`
}

type remoteHistory struct {
	TrackID    string `json:"trackId"`
	PlayedAtMs int64  `json:"playedAtMs"`
}

type ctxKey int

const ctxUserKey ctxKey = 1

func openDB(path string) (*sql.DB, error) {
	db, err := sql.Open("sqlite", path+"?_pragma=busy_timeout(5000)&_pragma=foreign_keys(1)")
	if err != nil {
		return nil, err
	}
	db.SetMaxOpenConns(1)
	if _, err := db.Exec(`
CREATE TABLE IF NOT EXISTS users (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  email TEXT NOT NULL UNIQUE,
  password_hash TEXT NOT NULL,
  token_ver INTEGER NOT NULL DEFAULT 1,
  created_at INTEGER NOT NULL
);
CREATE TABLE IF NOT EXISTS snapshots (
  user_id INTEGER PRIMARY KEY,
  revision INTEGER NOT NULL,
  payload TEXT NOT NULL,
  updated_at INTEGER NOT NULL,
  FOREIGN KEY(user_id) REFERENCES users(id)
);
CREATE TABLE IF NOT EXISTS settings (
  key TEXT PRIMARY KEY,
  value TEXT NOT NULL,
  updated_at INTEGER NOT NULL
);
`); err != nil {
		_ = db.Close()
		return nil, err
	}
	return db, nil
}

func (s *server) routes() http.Handler {
	mux := http.NewServeMux()
	// —— 用户 API（App 使用；路径与请求/响应结构保持向后兼容）——
	mux.HandleFunc("GET /api/v1/health", s.handleHealth)
	mux.HandleFunc("GET /api/v1/config", s.handleConfig)
	mux.HandleFunc("POST /api/v1/auth/register", s.handleRegister)
	mux.HandleFunc("POST /api/v1/auth/login", s.handleLogin)
	mux.HandleFunc("GET /api/v1/me", s.withAuth(s.handleMe))
	mux.HandleFunc("GET /api/v1/sync/snapshot", s.withAuth(s.handleGetSnapshot))
	mux.HandleFunc("PUT /api/v1/sync/snapshot", s.withAuth(s.handlePutSnapshot))

	// —— 管理 API（独立鉴权；走 /admin/ 前缀，与用户 API 分开挂载）——
	mux.HandleFunc("POST /admin/api/v1/login", s.handleAdminLogin)
	mux.HandleFunc("POST /admin/api/v1/logout", s.withAdminAuth(s.handleAdminLogout))
	mux.HandleFunc("GET /admin/api/v1/session", s.withAdminAuth(s.handleAdminSession))
	mux.HandleFunc("GET /admin/api/v1/stats", s.withAdminAuth(s.handleAdminStats))
	mux.HandleFunc("GET /admin/api/v1/users", s.withAdminAuth(s.handleAdminUsers))
	mux.HandleFunc("DELETE /admin/api/v1/users/{id}", s.withAdminAuth(s.handleAdminDeleteUser))
	mux.HandleFunc("POST /admin/api/v1/users/{id}/revoke", s.withAdminAuth(s.handleAdminRevokeUser))
	mux.HandleFunc("GET /admin/api/v1/config", s.withAdminAuth(s.handleAdminGetConfig))
	mux.HandleFunc("PUT /admin/api/v1/config", s.withAdminAuth(s.handleAdminPutConfig))

	// —— 管理界面静态资源 ——
	s.mountAdminUI(mux)

	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		r.Body = http.MaxBytesReader(w, r.Body, maxBodyBytes)
		w.Header().Set("X-Content-Type-Options", "nosniff")
		mux.ServeHTTP(w, r)
	})
}

func (s *server) handleHealth(w http.ResponseWriter, _ *http.Request) {
	writeJSON(w, http.StatusOK, map[string]string{"status": "ok", "version": serverVersion})
}

// handleConfig 是给 App 轮询的只读端点：暴露「能被 App 感知」的控制开关，
// 不含任何敏感参数（如令牌有效期、限流阈值）。
func (s *server) handleConfig(w http.ResponseWriter, _ *http.Request) {
	cfg := s.settings()
	writeJSON(w, http.StatusOK, map[string]any{
		"registrationEnabled": cfg.RegistrationEnabled,
		"readOnly":            cfg.ReadOnly,
		"serverVersion":       serverVersion,
	})
}

// settings 返回当前生效设置；未初始化时回退默认值（保持既有行为）。
func (s *server) settings() settings {
	if s.settingsStore == nil {
		return defaultSettings()
	}
	return s.settingsStore.get()
}

// clientKey 计算限流用的客户端标识。
func (s *server) clientKey(r *http.Request) string {
	if s.trustProxy {
		if xff := r.Header.Get("X-Forwarded-For"); xff != "" {
			first := strings.TrimSpace(strings.Split(xff, ",")[0])
			if first != "" {
				return first
			}
		}
	}
	if host, _, err := net.SplitHostPort(r.RemoteAddr); err == nil {
		return host
	}
	return r.RemoteAddr
}

// allowAuth 对认证类端点做限流，被拒时已写好 429 响应。
func (s *server) allowAuth(w http.ResponseWriter, r *http.Request) bool {
	limit := s.settings().AuthRateLimitPerMinute
	if s.limiter == nil || limit <= 0 {
		return true
	}
	ok, retry := s.limiter.allow(s.clientKey(r), limit, time.Now())
	if ok {
		return true
	}
	w.Header().Set("Retry-After", strconv.Itoa(retry))
	writeError(w, http.StatusTooManyRequests, "请求过于频繁，请稍后再试")
	return false
}

type credentials struct {
	Email    string `json:"email"`
	Password string `json:"password"`
}

func (s *server) handleRegister(w http.ResponseWriter, r *http.Request) {
	if !s.allowAuth(w, r) {
		return
	}
	if !s.settings().RegistrationEnabled {
		writeError(w, http.StatusForbidden, "当前未开放注册")
		return
	}
	var in credentials
	if err := json.NewDecoder(r.Body).Decode(&in); err != nil {
		writeError(w, http.StatusBadRequest, "请求格式不正确")
		return
	}
	email, err := normalizeEmail(in.Email)
	if err != nil {
		writeError(w, http.StatusBadRequest, err.Error())
		return
	}
	if err := validatePassword(in.Password); err != nil {
		writeError(w, http.StatusBadRequest, err.Error())
		return
	}
	hash, err := bcrypt.GenerateFromPassword([]byte(in.Password), bcryptCost)
	if err != nil {
		writeError(w, http.StatusInternalServerError, "无法创建账号")
		return
	}
	res, err := s.db.Exec(
		`INSERT INTO users(email, password_hash, token_ver, created_at) VALUES(?,?,1,?)`,
		email, string(hash), time.Now().Unix(),
	)
	if err != nil {
		// 邮箱冲突与其它写入失败对外同一句话，避免探测「这个邮箱是否已注册」。
		writeError(w, http.StatusConflict, "无法创建账号")
		return
	}
	id, _ := res.LastInsertId()
	s.issueToken(w, userRow{ID: id, Email: email, TokenVer: 1})
}

func (s *server) handleLogin(w http.ResponseWriter, r *http.Request) {
	if !s.allowAuth(w, r) {
		return
	}
	var in credentials
	if err := json.NewDecoder(r.Body).Decode(&in); err != nil {
		writeError(w, http.StatusBadRequest, "请求格式不正确")
		return
	}
	email, err := normalizeEmail(in.Email)
	if err != nil {
		writeError(w, http.StatusUnauthorized, "邮箱或密码不正确")
		return
	}
	var u userRow
	err = s.db.QueryRow(
		`SELECT id, email, password_hash, token_ver FROM users WHERE email = ?`,
		email,
	).Scan(&u.ID, &u.Email, &u.PasswordHash, &u.TokenVer)
	if err != nil {
		writeError(w, http.StatusUnauthorized, "邮箱或密码不正确")
		return
	}
	if bcrypt.CompareHashAndPassword([]byte(u.PasswordHash), []byte(in.Password)) != nil {
		writeError(w, http.StatusUnauthorized, "邮箱或密码不正确")
		return
	}
	s.issueToken(w, u)
}

func (s *server) handleMe(w http.ResponseWriter, r *http.Request) {
	u := userFrom(r)
	writeJSON(w, http.StatusOK, map[string]any{
		"id":    u.ID,
		"email": u.Email,
	})
}

func (s *server) handleGetSnapshot(w http.ResponseWriter, r *http.Request) {
	u := userFrom(r)
	snap, err := s.loadSnapshot(u.ID)
	if err != nil {
		writeError(w, http.StatusInternalServerError, "读取失败")
		return
	}
	writeJSON(w, http.StatusOK, snap)
}

func (s *server) handlePutSnapshot(w http.ResponseWriter, r *http.Request) {
	u := userFrom(r)
	cfg := s.settings()
	if cfg.ReadOnly {
		writeError(w, http.StatusServiceUnavailable, "服务处于维护模式，暂不接受写入")
		return
	}
	baseRevision, _ := strconv.ParseInt(r.URL.Query().Get("baseRevision"), 10, 64)

	var incoming snapshot
	if err := json.NewDecoder(r.Body).Decode(&incoming); err != nil {
		writeError(w, http.StatusBadRequest, "请求格式不正确")
		return
	}
	if incoming.Playlists == nil {
		incoming.Playlists = []remotePlaylist{}
	}
	if incoming.Likes == nil {
		incoming.Likes = []string{}
	}
	if incoming.History == nil {
		incoming.History = []remoteHistory{}
	}
	if incoming.Settings == nil {
		incoming.Settings = map[string]string{}
	}

	current, err := s.loadSnapshot(u.ID)
	if err != nil {
		writeError(w, http.StatusInternalServerError, "读取失败")
		return
	}
	if current.Revision != baseRevision {
		w.Header().Set("Content-Type", "application/json; charset=utf-8")
		w.WriteHeader(http.StatusConflict)
		_ = json.NewEncoder(w).Encode(current)
		return
	}
	incoming.Revision = current.Revision + 1
	payload, err := json.Marshal(incoming)
	if err != nil {
		writeError(w, http.StatusInternalServerError, "保存失败")
		return
	}
	if len(payload) > cfg.SnapshotMaxBytes {
		writeError(w, http.StatusRequestEntityTooLarge, "快照数据超过上限")
		return
	}
	_, err = s.db.Exec(
		`INSERT INTO snapshots(user_id, revision, payload, updated_at)
         VALUES(?,?,?,?)
         ON CONFLICT(user_id) DO UPDATE SET revision=excluded.revision, payload=excluded.payload, updated_at=excluded.updated_at`,
		u.ID, incoming.Revision, string(payload), time.Now().Unix(),
	)
	if err != nil {
		writeError(w, http.StatusInternalServerError, "保存失败")
		return
	}
	writeJSON(w, http.StatusOK, incoming)
}

func (s *server) loadSnapshot(userID int64) (snapshot, error) {
	var payload string
	var revision int64
	err := s.db.QueryRow(
		`SELECT revision, payload FROM snapshots WHERE user_id = ?`,
		userID,
	).Scan(&revision, &payload)
	if errors.Is(err, sql.ErrNoRows) {
		return emptySnapshot(), nil
	}
	if err != nil {
		return snapshot{}, err
	}
	var snap snapshot
	if err := json.Unmarshal([]byte(payload), &snap); err != nil {
		return snapshot{}, err
	}
	snap.Revision = revision
	return snap, nil
}

func emptySnapshot() snapshot {
	return snapshot{
		Revision:  0,
		Playlists: []remotePlaylist{},
		Likes:     []string{},
		History:   []remoteHistory{},
		Settings:  map[string]string{},
	}
}

func (s *server) issueToken(w http.ResponseWriter, u userRow) {
	now := time.Now()
	ttl := time.Duration(s.settings().TokenTTLHours) * time.Hour
	token := jwt.NewWithClaims(jwt.SigningMethodHS256, claims{
		UserID:   u.ID,
		TokenVer: u.TokenVer,
		RegisteredClaims: jwt.RegisteredClaims{
			Issuer:    jwtIssuer,
			IssuedAt:  jwt.NewNumericDate(now),
			ExpiresAt: jwt.NewNumericDate(now.Add(ttl)),
			Subject:   strconv.FormatInt(u.ID, 10),
		},
	})
	signed, err := token.SignedString(s.jwtSecret)
	if err != nil {
		writeError(w, http.StatusInternalServerError, "无法签发令牌")
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{
		"token": signed,
		"user": map[string]any{
			"id":    u.ID,
			"email": u.Email,
		},
	})
}

func (s *server) withAuth(next http.HandlerFunc) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		header := r.Header.Get("Authorization")
		if !strings.HasPrefix(header, "Bearer ") {
			writeError(w, http.StatusUnauthorized, "未登录")
			return
		}
		raw := strings.TrimSpace(strings.TrimPrefix(header, "Bearer "))
		parsed, err := jwt.ParseWithClaims(raw, &claims{}, func(t *jwt.Token) (any, error) {
			if t.Method != jwt.SigningMethodHS256 {
				return nil, errors.New("unexpected alg")
			}
			return s.jwtSecret, nil
		}, jwt.WithIssuer(jwtIssuer), jwt.WithValidMethods([]string{jwt.SigningMethodHS256.Alg()}))
		if err != nil || !parsed.Valid {
			writeError(w, http.StatusUnauthorized, "未登录")
			return
		}
		c, ok := parsed.Claims.(*claims)
		if !ok || c.UserID <= 0 {
			writeError(w, http.StatusUnauthorized, "未登录")
			return
		}
		var u userRow
		err = s.db.QueryRow(
			`SELECT id, email, password_hash, token_ver FROM users WHERE id = ?`,
			c.UserID,
		).Scan(&u.ID, &u.Email, &u.PasswordHash, &u.TokenVer)
		if err != nil || u.TokenVer != c.TokenVer {
			writeError(w, http.StatusUnauthorized, "未登录")
			return
		}
		ctx := context.WithValue(r.Context(), ctxUserKey, u)
		next(w, r.WithContext(ctx))
	}
}

func userFrom(r *http.Request) userRow {
	return r.Context().Value(ctxUserKey).(userRow)
}

func normalizeEmail(raw string) (string, error) {
	email := strings.ToLower(strings.TrimSpace(raw))
	if email == "" || len(email) > emailMaxLen || !strings.Contains(email, "@") {
		return "", errors.New("邮箱格式不正确")
	}
	at := strings.LastIndex(email, "@")
	if at <= 0 || at == len(email)-1 {
		return "", errors.New("邮箱格式不正确")
	}
	return email, nil
}

func validatePassword(password string) error {
	if len(password) < passwordMinLen {
		return errors.New("密码至少 8 位")
	}
	if len(password) > passwordMaxLen {
		return errors.New("密码过长")
	}
	return nil
}

func writeJSON(w http.ResponseWriter, status int, body any) {
	w.Header().Set("Content-Type", "application/json; charset=utf-8")
	w.WriteHeader(status)
	_ = json.NewEncoder(w).Encode(body)
}

func writeError(w http.ResponseWriter, status int, message string) {
	writeJSON(w, status, map[string]string{"error": message})
}

func main() {
	secret := os.Getenv("JWT_SECRET")
	if secret == "" {
		secret = "dev-only-change-me"
		log.Println("警告：未设置 JWT_SECRET，正在使用不安全的开发默认值")
	}
	dbPath := os.Getenv("DB_PATH")
	if dbPath == "" {
		dbPath = "lxplayer.db"
	}
	db, err := openDB(dbPath)
	if err != nil {
		panic(err)
	}
	defer db.Close()

	settingsStore, err := newSettingsStore(db)
	if err != nil {
		panic(err)
	}

	s := &server{
		db:            db,
		jwtSecret:     []byte(secret),
		settingsStore: settingsStore,
		limiter:       newRateLimiter(),
	}

	// 管理端：口令缺失时**安全失败**——禁用管理 API 而非拒绝启动，
	// 保证用户 API 不受影响，同时在 stderr 明确告警。
	if adminPassword := os.Getenv("ADMIN_PASSWORD"); adminPassword != "" {
		s.adminEnabled = true
		s.adminPasswordHash = sha256Sum(adminPassword)
		s.adminSecret = deriveAdminSecret(secret, os.Getenv("ADMIN_JWT_SECRET"))
	} else {
		s.adminEnabled = false
		log.Println("警告：未设置 ADMIN_PASSWORD，管理接口已禁用")
	}

	if os.Getenv("TRUST_PROXY_HEADERS") == "1" {
		s.trustProxy = true
	}

	// 定期清理限流窗口，避免 map 无界增长。
	go func() {
		ticker := time.NewTicker(time.Minute)
		defer ticker.Stop()
		for range ticker.C {
			s.limiter.cleanup(time.Now())
		}
	}()

	addr := os.Getenv("LISTEN_ADDR")
	if addr == "" {
		addr = defaultListenAddr
	}
	httpServer := &http.Server{
		Addr:              addr,
		Handler:           s.routes(),
		ReadHeaderTimeout: 5 * time.Second,
	}
	log.Printf("LxPlayer 后端监听 %s（管理界面 /admin/）", addr)
	if err := httpServer.ListenAndServe(); err != nil && !errors.Is(err, http.ErrServerClosed) {
		panic(err)
	}
}
