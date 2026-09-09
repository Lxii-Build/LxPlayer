package main

import (
	"bytes"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"path/filepath"
	"testing"
)

func newTestServer(t *testing.T) *server {
	t.Helper()
	db, err := openDB(filepath.Join(t.TempDir(), "test.db"))
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { _ = db.Close() })
	return &server{db: db, jwtSecret: []byte("test-secret")}
}

func doJSON(t *testing.T, h http.Handler, method, path, body, token string) *httptest.ResponseRecorder {
	t.Helper()
	var reader *bytes.Reader
	if body == "" {
		reader = bytes.NewReader(nil)
	} else {
		reader = bytes.NewReader([]byte(body))
	}
	req := httptest.NewRequest(method, path, reader)
	if body != "" {
		req.Header.Set("Content-Type", "application/json")
	}
	if token != "" {
		req.Header.Set("Authorization", "Bearer "+token)
	}
	rec := httptest.NewRecorder()
	h.ServeHTTP(rec, req)
	return rec
}

func register(t *testing.T, h http.Handler, email, password string) (token string, status int, raw map[string]any) {
	t.Helper()
	payload, _ := json.Marshal(map[string]string{"email": email, "password": password})
	rec := doJSON(t, h, http.MethodPost, "/api/v1/auth/register", string(payload), "")
	var out map[string]any
	_ = json.Unmarshal(rec.Body.Bytes(), &out)
	if rec.Code == http.StatusOK {
		token, _ = out["token"].(string)
	}
	return token, rec.Code, out
}

func TestHealth(t *testing.T) {
	h := newTestServer(t).routes()
	rec := doJSON(t, h, http.MethodGet, "/api/v1/health", "", "")
	if rec.Code != http.StatusOK {
		t.Fatalf("status=%d body=%s", rec.Code, rec.Body.String())
	}
}

func TestRegisterAndLogin(t *testing.T) {
	h := newTestServer(t).routes()
	token, status, _ := register(t, h, "a@example.com", "password12")
	if status != http.StatusOK || token == "" {
		t.Fatalf("register status=%d token=%q", status, token)
	}

	payload, _ := json.Marshal(map[string]string{"email": "a@example.com", "password": "password12"})
	rec := doJSON(t, h, http.MethodPost, "/api/v1/auth/login", string(payload), "")
	if rec.Code != http.StatusOK {
		t.Fatalf("login status=%d body=%s", rec.Code, rec.Body.String())
	}
}

func TestLoginFailuresAreIndistinguishable(t *testing.T) {
	h := newTestServer(t).routes()
	_, _, _ = register(t, h, "a@example.com", "password12")

	wrongUser := doJSON(t, h, http.MethodPost, "/api/v1/auth/login",
		`{"email":"missing@example.com","password":"password12"}`, "")
	wrongPass := doJSON(t, h, http.MethodPost, "/api/v1/auth/login",
		`{"email":"a@example.com","password":"wrong-password"}`, "")

	if wrongUser.Code != http.StatusUnauthorized || wrongPass.Code != http.StatusUnauthorized {
		t.Fatalf("codes user=%d pass=%d", wrongUser.Code, wrongPass.Code)
	}
	var a, b map[string]string
	_ = json.Unmarshal(wrongUser.Body.Bytes(), &a)
	_ = json.Unmarshal(wrongPass.Body.Bytes(), &b)
	if a["error"] != b["error"] || a["error"] == "" {
		t.Fatalf("messages differ: %q vs %q", a["error"], b["error"])
	}
}

func TestDuplicateRegisterDoesNotRevealExistingEmail(t *testing.T) {
	h := newTestServer(t).routes()
	_, status, _ := register(t, h, "a@example.com", "password12")
	if status != http.StatusOK {
		t.Fatalf("first register status=%d", status)
	}
	_, status, body := register(t, h, "a@example.com", "password12")
	if status != http.StatusConflict {
		t.Fatalf("second register status=%d", status)
	}
	if body["error"] != "无法创建账号" {
		t.Fatalf("unexpected error %v", body["error"])
	}
}

func TestTokenVerBumpInvalidatesOldTokens(t *testing.T) {
	s := newTestServer(t)
	h := s.routes()
	token, status, _ := register(t, h, "a@example.com", "password12")
	if status != http.StatusOK {
		t.Fatal(status)
	}
	if rec := doJSON(t, h, http.MethodGet, "/api/v1/me", "", token); rec.Code != http.StatusOK {
		t.Fatalf("me before bump: %d %s", rec.Code, rec.Body.String())
	}
	if _, err := s.db.Exec(`UPDATE users SET token_ver = token_ver + 1 WHERE email = ?`, "a@example.com"); err != nil {
		t.Fatal(err)
	}
	if rec := doJSON(t, h, http.MethodGet, "/api/v1/me", "", token); rec.Code != http.StatusUnauthorized {
		t.Fatalf("old token should be rejected, got %d %s", rec.Code, rec.Body.String())
	}
}

func TestRejectsNonHS256Tokens(t *testing.T) {
	h := newTestServer(t).routes()
	rec := doJSON(t, h, http.MethodGet, "/api/v1/me", "", "not-a-jwt")
	if rec.Code != http.StatusUnauthorized {
		t.Fatalf("got %d", rec.Code)
	}
}

func TestSnapshotOptimisticConcurrency(t *testing.T) {
	h := newTestServer(t).routes()
	token, status, _ := register(t, h, "a@example.com", "password12")
	if status != http.StatusOK {
		t.Fatal(status)
	}

	got := doJSON(t, h, http.MethodGet, "/api/v1/sync/snapshot", "", token)
	if got.Code != http.StatusOK {
		t.Fatalf("get %d %s", got.Code, got.Body.String())
	}
	var snap snapshot
	if err := json.Unmarshal(got.Body.Bytes(), &snap); err != nil {
		t.Fatal(err)
	}
	if snap.Revision != 0 {
		t.Fatalf("fresh snapshot revision=%d", snap.Revision)
	}

	snap.Likes = []string{"local:1"}
	body, _ := json.Marshal(snap)
	put := doJSON(t, h, http.MethodPut, "/api/v1/sync/snapshot?baseRevision=0", string(body), token)
	if put.Code != http.StatusOK {
		t.Fatalf("put %d %s", put.Code, put.Body.String())
	}
	var applied snapshot
	_ = json.Unmarshal(put.Body.Bytes(), &applied)
	if applied.Revision != 1 {
		t.Fatalf("applied revision=%d", applied.Revision)
	}

	stale := doJSON(t, h, http.MethodPut, "/api/v1/sync/snapshot?baseRevision=0", string(body), token)
	if stale.Code != http.StatusConflict {
		t.Fatalf("stale put should 409, got %d %s", stale.Code, stale.Body.String())
	}
}

func TestShortPasswordRejected(t *testing.T) {
	h := newTestServer(t).routes()
	_, status, body := register(t, h, "a@example.com", "short")
	if status != http.StatusBadRequest {
		t.Fatalf("status=%d body=%v", status, body)
	}
}

func TestEmailIsNormalized(t *testing.T) {
	h := newTestServer(t).routes()
	_, status, _ := register(t, h, "  A@Example.COM  ", "password12")
	if status != http.StatusOK {
		t.Fatalf("register status=%d", status)
	}
	payload, _ := json.Marshal(map[string]string{"email": "a@example.com", "password": "password12"})
	rec := doJSON(t, h, http.MethodPost, "/api/v1/auth/login", string(payload), "")
	if rec.Code != http.StatusOK {
		t.Fatalf("login with normalized email failed: %d %s", rec.Code, rec.Body.String())
	}
}
