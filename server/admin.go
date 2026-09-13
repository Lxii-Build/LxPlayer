package main

import (
	"crypto/sha256"
	"crypto/subtle"
	"database/sql"
	"encoding/json"
	"errors"
	"net/http"
	"strconv"
	"strings"
	"time"

	"github.com/golang-jwt/jwt/v5"
)

// 管理端与用户端**彻底隔离**：
//   - 口令来自环境变量 ADMIN_PASSWORD（缺失即禁用整个管理 API，安全失败）；
//   - 管理令牌使用独立签名密钥（域分隔自 JWT_SECRET，或显式 ADMIN_JWT_SECRET）
//     与独立 issuer `lxplayer-admin`，因此用户令牌与管理令牌互不通用——
//     普通用户即便拿到自己的 JWT，也无法通过管理端鉴权。

const (
	adminIssuer        = "lxplayer-admin"
	adminTokenTTLHours = 12
)

// adminClaims 是管理令牌的载荷，role 固定为 admin。
type adminClaims struct {
	Role string `json:"role"`
	jwt.RegisteredClaims
}

// deriveAdminSecret 计算管理令牌的签名密钥。
// 显式配置 ADMIN_JWT_SECRET 时直接采用；否则从 JWT_SECRET 做域分隔派生，
// 保证管理密钥与用户密钥在密码学上不同（同密钥+不同 issuer 也互为隔离的补充）。
func deriveAdminSecret(jwtSecret, explicit string) []byte {
	if explicit != "" {
		return []byte(explicit)
	}
	sum := sha256.Sum256([]byte("lxplayer-admin-v1\x00" + jwtSecret))
	return sum[:]
}

func sha256Sum(s string) []byte {
	sum := sha256.Sum256([]byte(s))
	return sum[:]
}

// handleAdminLogin 校验管理员口令并签发管理令牌。
func (s *server) handleAdminLogin(w http.ResponseWriter, r *http.Request) {
	if !s.adminEnabled {
		writeError(w, http.StatusServiceUnavailable, "管理接口未启用（未配置 ADMIN_PASSWORD）")
		return
	}
	var in struct {
		Password string `json:"password"`
	}
	if err := json.NewDecoder(r.Body).Decode(&in); err != nil {
		writeError(w, http.StatusBadRequest, "请求格式不正确")
		return
	}
	// 恒定时间比较，避免用响应时间逐字节探测口令。
	if subtle.ConstantTimeCompare(sha256Sum(in.Password), s.adminPasswordHash) != 1 {
		writeError(w, http.StatusUnauthorized, "管理员口令不正确")
		return
	}
	s.issueAdminToken(w)
}

func (s *server) issueAdminToken(w http.ResponseWriter) {
	now := time.Now()
	exp := now.Add(adminTokenTTLHours * time.Hour)
	token := jwt.NewWithClaims(jwt.SigningMethodHS256, adminClaims{
		Role: "admin",
		RegisteredClaims: jwt.RegisteredClaims{
			Issuer:    adminIssuer,
			IssuedAt:  jwt.NewNumericDate(now),
			ExpiresAt: jwt.NewNumericDate(exp),
			Subject:   "admin",
		},
	})
	signed, err := token.SignedString(s.adminSecret)
	if err != nil {
		writeError(w, http.StatusInternalServerError, "无法签发管理令牌")
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{
		"token":            signed,
		"expiresAtMs":      exp.UnixMilli(),
		"expiresInSeconds": adminTokenTTLHours * 3600,
	})
}

// withAdminAuth 是管理端的独立鉴权中间件。
func (s *server) withAdminAuth(next http.HandlerFunc) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		if !s.adminEnabled {
			writeError(w, http.StatusServiceUnavailable, "管理接口未启用（未配置 ADMIN_PASSWORD）")
			return
		}
		header := r.Header.Get("Authorization")
		if !strings.HasPrefix(header, "Bearer ") {
			writeError(w, http.StatusUnauthorized, "需要管理员登录")
			return
		}
		raw := strings.TrimSpace(strings.TrimPrefix(header, "Bearer "))
		parsed, err := jwt.ParseWithClaims(raw, &adminClaims{}, func(t *jwt.Token) (any, error) {
			if t.Method != jwt.SigningMethodHS256 {
				return nil, errors.New("unexpected alg")
			}
			return s.adminSecret, nil
		}, jwt.WithIssuer(adminIssuer), jwt.WithValidMethods([]string{jwt.SigningMethodHS256.Alg()}))
		if err != nil || !parsed.Valid {
			writeError(w, http.StatusUnauthorized, "需要管理员登录")
			return
		}
		c, ok := parsed.Claims.(*adminClaims)
		if !ok || c.Role != "admin" {
			writeError(w, http.StatusUnauthorized, "需要管理员登录")
			return
		}
		next(w, r)
	}
}

// handleAdminSession 供 UI 校验令牌是否仍然有效（打开页面时调用）。
func (s *server) handleAdminSession(w http.ResponseWriter, _ *http.Request) {
	writeJSON(w, http.StatusOK, map[string]any{"valid": true, "role": "admin"})
}

// handleAdminLogout 无服务端状态可清，仅作为对称端点存在（客户端丢令牌即可）。
func (s *server) handleAdminLogout(w http.ResponseWriter, _ *http.Request) {
	writeJSON(w, http.StatusOK, map[string]any{"ok": true})
}

// adminUser 是用户列表里的一行：账号信息 + 该用户快照规模。
type adminUser struct {
	ID                  int64  `json:"id"`
	Email               string `json:"email"`
	TokenVer            int    `json:"tokenVer"`
	CreatedAtMs         int64  `json:"createdAtMs"`
	Revision            int64  `json:"revision"`
	SnapshotBytes       int64  `json:"snapshotBytes"`
	SnapshotUpdatedAtMs int64  `json:"snapshotUpdatedAtMs"`
}

func (s *server) handleAdminUsers(w http.ResponseWriter, r *http.Request) {
	limit := clampInt(queryInt(r, "limit", 50), 1, 200)
	offset := queryInt(r, "offset", 0)
	if offset < 0 {
		offset = 0
	}

	var total int
	if err := s.db.QueryRow(`SELECT COUNT(*) FROM users`).Scan(&total); err != nil {
		writeError(w, http.StatusInternalServerError, "读取失败")
		return
	}

	rows, err := s.db.Query(
		`SELECT u.id, u.email, u.token_ver, u.created_at,
		        COALESCE(s.revision, 0), COALESCE(LENGTH(s.payload), 0), COALESCE(s.updated_at, 0)
		   FROM users u
		   LEFT JOIN snapshots s ON s.user_id = u.id
		  ORDER BY u.id DESC
		  LIMIT ? OFFSET ?`,
		limit, offset,
	)
	if err != nil {
		writeError(w, http.StatusInternalServerError, "读取失败")
		return
	}
	defer rows.Close()

	users := make([]adminUser, 0, limit)
	for rows.Next() {
		var u adminUser
		if err := rows.Scan(&u.ID, &u.Email, &u.TokenVer, &u.CreatedAtMs,
			&u.Revision, &u.SnapshotBytes, &u.SnapshotUpdatedAtMs); err != nil {
			writeError(w, http.StatusInternalServerError, "读取失败")
			return
		}
		u.CreatedAtMs *= 1000
		u.SnapshotUpdatedAtMs *= 1000
		users = append(users, u)
	}
	if err := rows.Err(); err != nil {
		writeError(w, http.StatusInternalServerError, "读取失败")
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{
		"total":  total,
		"limit":  limit,
		"offset": offset,
		"users":  users,
	})
}

// handleAdminDeleteUser 删除账号及其快照（不可逆）。
func (s *server) handleAdminDeleteUser(w http.ResponseWriter, r *http.Request) {
	id, err := strconv.ParseInt(r.PathValue("id"), 10, 64)
	if err != nil || id <= 0 {
		writeError(w, http.StatusBadRequest, "用户 ID 不正确")
		return
	}
	tx, err := s.db.Begin()
	if err != nil {
		writeError(w, http.StatusInternalServerError, "删除失败")
		return
	}
	defer func() { _ = tx.Rollback() }()

	res, err := tx.Exec(`DELETE FROM users WHERE id = ?`, id)
	if err != nil {
		writeError(w, http.StatusInternalServerError, "删除失败")
		return
	}
	if affected, _ := res.RowsAffected(); affected == 0 {
		writeError(w, http.StatusNotFound, "用户不存在")
		return
	}
	if _, err := tx.Exec(`DELETE FROM snapshots WHERE user_id = ?`, id); err != nil {
		writeError(w, http.StatusInternalServerError, "删除失败")
		return
	}
	if err := tx.Commit(); err != nil {
		writeError(w, http.StatusInternalServerError, "删除失败")
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{"deleted": id})
}

// handleAdminRevokeUser 递增 token_ver，使该用户已签发的令牌立即失效（强制下线）。
func (s *server) handleAdminRevokeUser(w http.ResponseWriter, r *http.Request) {
	id, err := strconv.ParseInt(r.PathValue("id"), 10, 64)
	if err != nil || id <= 0 {
		writeError(w, http.StatusBadRequest, "用户 ID 不正确")
		return
	}
	res, err := s.db.Exec(`UPDATE users SET token_ver = token_ver + 1 WHERE id = ?`, id)
	if err != nil {
		writeError(w, http.StatusInternalServerError, "操作失败")
		return
	}
	if affected, _ := res.RowsAffected(); affected == 0 {
		writeError(w, http.StatusNotFound, "用户不存在")
		return
	}
	var ver int
	_ = s.db.QueryRow(`SELECT token_ver FROM users WHERE id = ?`, id).Scan(&ver)
	writeJSON(w, http.StatusOK, map[string]any{"id": id, "tokenVer": ver})
}

// handleAdminGetConfig 返回当前设置与可调项登记表（前端据此渲染表单）。
func (s *server) handleAdminGetConfig(w http.ResponseWriter, _ *http.Request) {
	writeJSON(w, http.StatusOK, map[string]any{
		"settings": s.settings(),
		"specs":    settingSpecs,
	})
}

// handleAdminPutConfig 局部更新设置。参数校验失败返回 400，不落库。
func (s *server) handleAdminPutConfig(w http.ResponseWriter, r *http.Request) {
	if s.settingsStore == nil {
		writeError(w, http.StatusServiceUnavailable, "设置存储不可用")
		return
	}
	var patch settingsPatch
	if err := json.NewDecoder(r.Body).Decode(&patch); err != nil {
		writeError(w, http.StatusBadRequest, "请求格式不正确")
		return
	}
	next, err := s.settingsStore.update(patch)
	if err != nil {
		writeError(w, http.StatusBadRequest, err.Error())
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{"settings": next})
}

// handleAdminStats 汇总数据查看所需的统计。
func (s *server) handleAdminStats(w http.ResponseWriter, _ *http.Request) {
	now := time.Now().UTC()
	dayStart := now.Truncate(24 * time.Hour)
	since7 := dayStart.AddDate(0, 0, -6).Unix()
	since30 := dayStart.AddDate(0, 0, -29).Unix()

	overview := map[string]any{
		"totalUsers":           s.countInt(`SELECT COUNT(*) FROM users`),
		"registeredToday":      s.countInt(`SELECT COUNT(*) FROM users WHERE created_at >= ?`, dayStart.Unix()),
		"registeredLast7Days":  s.countInt(`SELECT COUNT(*) FROM users WHERE created_at >= ?`, since7),
		"registeredLast30Days": s.countInt(`SELECT COUNT(*) FROM users WHERE created_at >= ?`, since30),
		"activeUsers7Days":     s.countInt(`SELECT COUNT(*) FROM snapshots WHERE updated_at >= ?`, since7),
		"activeUsers30Days":    s.countInt(`SELECT COUNT(*) FROM snapshots WHERE updated_at >= ?`, since30),
	}

	var snapshotCount, snapshotBytes, snapshotBytesMax int64
	_ = s.db.QueryRow(
		`SELECT COUNT(*), COALESCE(SUM(LENGTH(payload)), 0), COALESCE(MAX(LENGTH(payload)), 0) FROM snapshots`,
	).Scan(&snapshotCount, &snapshotBytes, &snapshotBytesMax)
	storage := map[string]any{
		"snapshotCount":    snapshotCount,
		"snapshotBytes":    snapshotBytes,
		"snapshotBytesMax": snapshotBytesMax,
	}

	writeJSON(w, http.StatusOK, map[string]any{
		"overview":          overview,
		"storage":           storage,
		"registrationTrend": s.registrationTrend(dayStart, 30),
		"generatedAtMs":     time.Now().UnixMilli(),
	})
}

// registrationTrend 返回最近 days 天的每日注册数（按 UTC 日切分），
// 无注册的日期补零，保证前端画折线时 x 轴连续。
func (s *server) registrationTrend(dayStart time.Time, days int) []map[string]any {
	since := dayStart.AddDate(0, 0, -(days - 1)).Unix()
	counts := map[string]int{}
	rows, err := s.db.Query(
		`SELECT strftime('%Y-%m-%d', created_at, 'unixepoch') AS d, COUNT(*)
		   FROM users WHERE created_at >= ? GROUP BY d`,
		since,
	)
	if err == nil {
		defer rows.Close()
		for rows.Next() {
			var day string
			var n int
			if err := rows.Scan(&day, &n); err == nil {
				counts[day] = n
			}
		}
	}
	out := make([]map[string]any, 0, days)
	for i := 0; i < days; i++ {
		day := dayStart.AddDate(0, 0, i-days+1).Format("2006-01-02")
		out = append(out, map[string]any{"date": day, "count": counts[day]})
	}
	return out
}

// countInt 跑一个只返回单个整数的查询，出错时返回 0（统计页面不应因此整体失败）。
func (s *server) countInt(query string, args ...any) int {
	var n int
	if err := s.db.QueryRow(query, args...).Scan(&n); err != nil && !errors.Is(err, sql.ErrNoRows) {
		return 0
	}
	return n
}

// queryInt 读取查询参数中的整数，缺失或非法时返回默认值。
func queryInt(r *http.Request, name string, def int) int {
	raw := r.URL.Query().Get(name)
	if raw == "" {
		return def
	}
	v, err := strconv.Atoi(raw)
	if err != nil {
		return def
	}
	return v
}
