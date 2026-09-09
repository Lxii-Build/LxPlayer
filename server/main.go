package main

import (
	"context"
	"database/sql"
	"encoding/json"
	"errors"
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
)

type server struct {
	db        *sql.DB
	jwtSecret []byte
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
`); err != nil {
		_ = db.Close()
		return nil, err
	}
	return db, nil
}

func (s *server) routes() http.Handler {
	mux := http.NewServeMux()
	mux.HandleFunc("GET /api/v1/health", s.handleHealth)
	mux.HandleFunc("POST /api/v1/auth/register", s.handleRegister)
	mux.HandleFunc("POST /api/v1/auth/login", s.handleLogin)
	mux.HandleFunc("GET /api/v1/me", s.withAuth(s.handleMe))
	mux.HandleFunc("GET /api/v1/sync/snapshot", s.withAuth(s.handleGetSnapshot))
	mux.HandleFunc("PUT /api/v1/sync/snapshot", s.withAuth(s.handlePutSnapshot))
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		r.Body = http.MaxBytesReader(w, r.Body, maxBodyBytes)
		w.Header().Set("X-Content-Type-Options", "nosniff")
		mux.ServeHTTP(w, r)
	})
}

func (s *server) handleHealth(w http.ResponseWriter, _ *http.Request) {
	writeJSON(w, http.StatusOK, map[string]string{"status": "ok", "version": "1.0.0"})
}

type credentials struct {
	Email    string `json:"email"`
	Password string `json:"password"`
}

func (s *server) handleRegister(w http.ResponseWriter, r *http.Request) {
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
	token := jwt.NewWithClaims(jwt.SigningMethodHS256, claims{
		UserID:   u.ID,
		TokenVer: u.TokenVer,
		RegisteredClaims: jwt.RegisteredClaims{
			Issuer:    jwtIssuer,
			IssuedAt:  jwt.NewNumericDate(now),
			ExpiresAt: jwt.NewNumericDate(now.Add(30 * 24 * time.Hour)),
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

	addr := os.Getenv("LISTEN_ADDR")
	if addr == "" {
		addr = ":8080"
	}
	s := &server{db: db, jwtSecret: []byte(secret)}
	httpServer := &http.Server{
		Addr:              addr,
		Handler:           s.routes(),
		ReadHeaderTimeout: 5 * time.Second,
	}
	if err := httpServer.ListenAndServe(); err != nil && !errors.Is(err, http.ErrServerClosed) {
		panic(err)
	}
}
