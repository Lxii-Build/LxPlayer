package main

import (
	"embed"
	"io/fs"
	"net/http"
)

// 管理界面是原生 HTML/CSS/JS 单页，直接由 Go 静态托管并通过 embed 打进二进制。
// 刻意不引入 npm/vite 等前端工具链：本项目要保持「单二进制 + SQLite」的部署形态，
// 少一条工具链就少一处会在 CI 里坏掉的地方。
//
//go:embed admin
var adminFS embed.FS

// mountAdminUI 把 /admin/ 挂到内嵌文件系统上，并把根路径重定向过去。
func (s *server) mountAdminUI(mux *http.ServeMux) {
	sub, err := fs.Sub(adminFS, "admin")
	if err != nil {
		// embed 保证 admin/ 存在；此处失败属构建期问题，直接跳过挂载而非 panic。
		return
	}
	fileServer := http.FileServer(http.FS(sub))
	mux.Handle("GET /admin/", http.StripPrefix("/admin/", fileServer))
	redirectToAdmin := func(w http.ResponseWriter, r *http.Request) {
		http.Redirect(w, r, "/admin/", http.StatusFound)
	}
	mux.HandleFunc("GET /admin", redirectToAdmin)
	mux.HandleFunc("GET /{$}", redirectToAdmin)
}
