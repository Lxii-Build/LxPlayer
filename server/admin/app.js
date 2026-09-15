/* LxPlayer 后端管理 UI —— 原生 JS，无构建步骤。
 * 只与 /admin/api/v1/* 通信；令牌存于 localStorage（管理端与用户端令牌完全隔离）。 */
(function () {
  "use strict";

  var TOKEN_KEY = "lxplayer_admin_token";
  var USERS_PAGE_SIZE = 20;

  var state = {
    token: localStorage.getItem(TOKEN_KEY) || "",
    view: "overview",
    specs: [],
    settings: null,
    dirty: {},          // 待保存的局部修改
    usersOffset: 0,
    usersTotal: 0,
  };

  // ---------- DOM 快捷 ----------
  function $(id) { return document.getElementById(id); }

  function escapeHtml(s) {
    return String(s == null ? "" : s)
      .replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;")
      .replace(/"/g, "&quot;").replace(/'/g, "&#39;");
  }

  function formatBytes(n) {
    n = Number(n) || 0;
    if (n < 1024) return n + " B";
    var units = ["KB", "MB", "GB"];
    var v = n / 1024, i = 0;
    while (v >= 1024 && i < units.length - 1) { v /= 1024; i++; }
    return v.toFixed(v >= 10 ? 0 : 1) + " " + units[i];
  }

  function formatTime(ms) {
    if (!ms) return "—";
    var d = new Date(Number(ms));
    if (isNaN(d.getTime())) return "—";
    var p = function (x) { return (x < 10 ? "0" : "") + x; };
    return d.getFullYear() + "-" + p(d.getMonth() + 1) + "-" + p(d.getDate()) +
      " " + p(d.getHours()) + ":" + p(d.getMinutes());
  }

  // ---------- Toast ----------
  function toast(message, type) {
    var host = $("toast-host");
    var el = document.createElement("div");
    el.className = "toast toast-" + (type || "info");
    el.textContent = message;
    host.appendChild(el);
    setTimeout(function () { el.remove(); }, 3200);
  }

  // ---------- API ----------
  function api(path, options) {
    options = options || {};
    var headers = options.headers || {};
    headers["Content-Type"] = "application/json";
    if (state.token) headers["Authorization"] = "Bearer " + state.token;
    return fetch(path, {
      method: options.method || "GET",
      headers: headers,
      body: options.body,
    }).then(function (res) {
      return res.json().catch(function () { return {}; })
        .then(function (data) { return { status: res.status, data: data }; });
    });
  }

  function errorText(result, fallback) {
    if (result && result.data && typeof result.data.error === "string" && result.data.error) {
      return result.data.error;
    }
    return fallback;
  }

  function handleFatal(result) {
    // 令牌失效 → 回登录页；管理接口未启用 → 明确提示。
    if (result.status === 401) { doLogout(false); toast("登录已失效，请重新登录", "error"); return true; }
    if (result.status === 503) { toast("管理接口未启用（未配置 ADMIN_PASSWORD）", "error"); return true; }
    return false;
  }

  // ---------- 登录 / 登出 ----------
  function showLogin() { $("login-view").hidden = false; $("app-view").hidden = true; }
  function showApp() { $("login-view").hidden = true; $("app-view").hidden = false; }

  function doLogout(callServer) {
    if (callServer && state.token) { api("/admin/api/v1/logout", { method: "POST" }).catch(function () {}); }
    state.token = "";
    state.settings = null;
    state.dirty = {};
    localStorage.removeItem(TOKEN_KEY);
    showLogin();
  }

  function login(password) {
    var button = $("login-button");
    var errorEl = $("login-error");
    errorEl.hidden = true;
    button.disabled = true;
    button.textContent = "登录中…";

    api("/admin/api/v1/login", { method: "POST", body: JSON.stringify({ password: password }) })
      .then(function (result) {
        if (result.status === 200 && result.data.token) {
          state.token = result.data.token;
          localStorage.setItem(TOKEN_KEY, state.token);
          showApp();
          toast("登录成功", "success");
          refreshCurrentView();
        } else if (result.status === 503) {
          errorEl.textContent = "管理接口未启用（未配置 ADMIN_PASSWORD）";
          errorEl.hidden = false;
        } else {
          errorEl.textContent = errorText(result, "登录失败");
          errorEl.hidden = false;
        }
      })
      .catch(function (e) { errorEl.textContent = "网络错误：" + e; errorEl.hidden = false; })
      .then(function () { button.disabled = false; button.textContent = "登录"; });
  }

  // ---------- 视图切换 ----------
  var VIEW_TITLES = { overview: "数据概览", users: "用户", config: "控制与参数" };

  function switchView(view) {
    state.view = view;
    var views = document.querySelectorAll(".view");
    for (var i = 0; i < views.length; i++) views[i].hidden = true;
    $("view-" + view).hidden = false;
    var navItems = document.querySelectorAll(".nav-item[data-view]");
    for (var j = 0; j < navItems.length; j++) {
      navItems[j].classList.toggle("active", navItems[j].getAttribute("data-view") === view);
    }
    $("view-title").textContent = VIEW_TITLES[view] || "";
    refreshCurrentView();
  }

  function refreshCurrentView() {
    if (state.view === "overview") loadOverview();
    else if (state.view === "users") loadUsers(state.usersOffset);
    else if (state.view === "config") loadConfig();
  }

  // ---------- 概览 ----------
  function loadOverview() {
    api("/admin/api/v1/stats").then(function (result) {
      if (handleFatal(result)) return;
      if (result.status !== 200) { toast(errorText(result, "读取统计失败"), "error"); return; }
      renderOverview(result.data);
    }).catch(function (e) { toast("网络错误：" + e, "error"); });

    api("/api/v1/config").then(function (result) {
      if (result.status === 200 && result.data.serverVersion) {
        $("server-version").textContent = "v" + result.data.serverVersion;
      }
    }).catch(function () {});
  }

  function renderOverview(data) {
    var ov = data.overview || {};
    var cards = [
      ["总用户数", ov.totalUsers],
      ["今日注册", ov.registeredToday],
      ["近 7 天注册", ov.registeredLast7Days],
      ["近 30 天注册", ov.registeredLast30Days],
      ["近 7 天活跃", ov.activeUsers7Days],
      ["近 30 天活跃", ov.activeUsers30Days],
    ];
    $("overview-cards").innerHTML = cards.map(function (c) {
      return '<div class="stat-card"><div class="stat-label">' + escapeHtml(c[0]) +
        '</div><div class="stat-value">' + (Number(c[1]) || 0) + "</div></div>";
    }).join("");

    renderTrend(data.registrationTrend || []);

    var st = data.storage || {};
    var rows = [
      ["快照数量", String(st.snapshotCount || 0)],
      ["快照总字节", formatBytes(st.snapshotBytes)],
      ["单快照最大字节", formatBytes(st.snapshotBytesMax)],
      ["生成时间", formatTime(data.generatedAtMs)],
    ];
    $("storage-list").innerHTML = rows.map(function (r) {
      return '<div class="kv-item"><div class="kv-key">' + escapeHtml(r[0]) +
        '</div><div class="kv-val">' + escapeHtml(r[1]) + "</div></div>";
    }).join("");
  }

  function renderTrend(trend) {
    var chart = $("trend-chart");
    if (!trend.length) { chart.innerHTML = '<p class="muted">暂无数据</p>'; return; }
    var max = 1, total = 0;
    trend.forEach(function (d) { max = Math.max(max, d.count); total += d.count; });
    $("trend-total").textContent = "合计 " + total + " 人";

    chart.innerHTML = trend.map(function (d) {
      var h = Math.max(2, Math.round((d.count / max) * 130));
      return '<div class="trend-bar" style="height:' + h + 'px" title="' +
        escapeHtml(d.date + "：" + d.count + " 人") + '"></div>';
    }).join("");
  }

  // ---------- 用户 ----------
  function loadUsers(offset) {
    if (offset < 0) offset = 0;
    api("/admin/api/v1/users?limit=" + USERS_PAGE_SIZE + "&offset=" + offset).then(function (result) {
      if (handleFatal(result)) return;
      if (result.status !== 200) { toast(errorText(result, "读取用户失败"), "error"); return; }
      state.usersOffset = result.data.offset || 0;
      state.usersTotal = result.data.total || 0;
      renderUsers(result.data.users || []);
    }).catch(function (e) { toast("网络错误：" + e, "error"); });
  }

  function renderUsers(users) {
    var body = $("users-body");
    if (!users.length) {
      body.innerHTML = '<tr><td class="empty-row" colspan="7">暂无用户</td></tr>';
    } else {
      body.innerHTML = users.map(function (u) {
        return "<tr>" +
          "<td>" + u.id + "</td>" +
          "<td>" + escapeHtml(u.email) + "</td>" +
          "<td>" + u.tokenVer + "</td>" +
          "<td>" + formatTime(u.createdAtMs) + "</td>" +
          "<td>" + u.revision + "</td>" +
          "<td>" + formatBytes(u.snapshotBytes) + "</td>" +
          '<td class="col-actions"><div class="row-actions">' +
            '<button class="btn btn-sm" data-action="revoke" data-id="' + u.id + '">强制下线</button>' +
            '<button class="btn btn-sm btn-danger" data-action="delete" data-id="' + u.id + '">删除</button>' +
          "</div></td>" +
        "</tr>";
      }).join("");
    }
    var from = state.usersTotal === 0 ? 0 : state.usersOffset + 1;
    var to = Math.min(state.usersOffset + USERS_PAGE_SIZE, state.usersTotal);
    $("users-count").textContent = "共 " + state.usersTotal + " 人";
    $("users-page").textContent = from + "–" + to + " / " + state.usersTotal;
    $("users-prev").disabled = state.usersOffset <= 0;
    $("users-next").disabled = state.usersOffset + USERS_PAGE_SIZE >= state.usersTotal;
  }

  function onUsersClick(event) {
    var btn = event.target.closest("button[data-action]");
    if (!btn) return;
    var id = btn.getAttribute("data-id");
    var action = btn.getAttribute("data-action");
    if (action === "revoke") { revokeUser(id); }
    else if (action === "delete") { deleteUser(id); }
  }

  function revokeUser(id) {
    if (!confirm("确认强制下线用户 #" + id + "？该用户已签发的令牌将立即失效。")) return;
    api("/admin/api/v1/users/" + encodeURIComponent(id) + "/revoke", { method: "POST" })
      .then(function (result) {
        if (handleFatal(result)) return;
        if (result.status === 200) { toast("已强制下线（令牌版本 " + result.data.tokenVer + "）", "success"); loadUsers(state.usersOffset); }
        else toast(errorText(result, "操作失败"), "error");
      }).catch(function (e) { toast("网络错误：" + e, "error"); });
  }

  function deleteUser(id) {
    if (!confirm("确认删除用户 #" + id + "？其账号与快照数据将被永久删除，不可恢复。")) return;
    api("/admin/api/v1/users/" + encodeURIComponent(id), { method: "DELETE" })
      .then(function (result) {
        if (handleFatal(result)) return;
        if (result.status === 200) { toast("已删除用户 #" + id, "success"); loadUsers(state.usersOffset); }
        else toast(errorText(result, "删除失败"), "error");
      }).catch(function (e) { toast("网络错误：" + e, "error"); });
  }

  // ---------- 控制与参数 ----------
  function loadConfig() {
    api("/admin/api/v1/config").then(function (result) {
      if (handleFatal(result)) return;
      if (result.status !== 200) { toast(errorText(result, "读取设置失败"), "error"); return; }
      state.specs = result.data.specs || [];
      state.settings = result.data.settings || {};
      state.dirty = {};
      renderConfig();
    }).catch(function (e) { toast("网络错误：" + e, "error"); });
  }

  function renderConfig() {
    var toggles = state.specs.filter(function (s) { return s.kind === "bool"; });
    var params = state.specs.filter(function (s) { return s.kind === "int"; });

    $("config-toggles").innerHTML = toggles.map(function (s) {
      var on = state.settings[s.key] === true;
      return '<div class="control-row">' +
        '<div class="control-text"><div class="control-label">' + escapeHtml(s.label) + "</div>" +
        '<div class="control-help">' + escapeHtml(s.help || "") + "</div></div>" +
        '<label class="switch"><input type="checkbox" data-key="' + s.key + '"' + (on ? " checked" : "") +
        '><span class="track"></span></label>' +
      "</div>";
    }).join("");

    $("config-params").innerHTML = params.map(function (s) {
      var val = state.settings[s.key];
      return '<div class="param-row">' +
        '<div class="param-text"><div class="control-label">' + escapeHtml(s.label) + "</div>" +
        '<div class="control-help">' + escapeHtml(s.help || "") + "（范围 " + s.min + "–" + s.max + "）</div></div>" +
        '<div class="param-input"><input type="number" data-key="' + s.key + '" value="' + val +
        '" min="' + s.min + '" max="' + s.max + '"><span class="param-unit">' + escapeHtml(s.unit || "") + "</span></div>" +
      "</div>";
    }).join("");
  }

  function findSpec(key) {
    for (var i = 0; i < state.specs.length; i++) if (state.specs[i].key === key) return state.specs[i];
    return null;
  }

  function onConfigChange(event) {
    var el = event.target;
    var key = el.getAttribute("data-key");
    if (!key) return;
    var spec = findSpec(key);
    if (!spec) return;

    if (spec.kind === "bool") {
      state.dirty[key] = el.checked;
    } else {
      var raw = el.value.trim();
      if (raw === "") { delete state.dirty[key]; return; }
      var n = Number(raw);
      if (isNaN(n) || Math.floor(n) !== n) { toast("请输入整数", "error"); el.value = state.settings[key]; delete state.dirty[key]; return; }
      if (n < spec.min || n > spec.max) {
        toast(spec.label + " 需在 " + spec.min + "–" + spec.max + " 之间", "error");
        el.value = state.settings[key];
        delete state.dirty[key];
        return;
      }
      state.dirty[key] = n;
    }
  }

  function saveConfig() {
    var keys = Object.keys(state.dirty);
    if (!keys.length) { toast("没有需要保存的修改", "info"); return; }
    var button = $("config-save");
    button.disabled = true;
    api("/admin/api/v1/config", { method: "PUT", body: JSON.stringify(state.dirty) })
      .then(function (result) {
        if (handleFatal(result)) return;
        if (result.status === 200) {
          state.settings = result.data.settings || state.settings;
          state.dirty = {};
          renderConfig();
          toast("已保存并生效（" + keys.length + " 项）", "success");
        } else {
          toast(errorText(result, "保存失败"), "error");
        }
      })
      .catch(function (e) { toast("网络错误：" + e, "error"); })
      .then(function () { button.disabled = false; });
  }

  // ---------- 事件绑定 ----------
  function bindEvents() {
    $("login-form").addEventListener("submit", function (e) {
      e.preventDefault();
      var pw = $("login-password").value;
      if (!pw) { return; }
      login(pw);
    });

    var navItems = document.querySelectorAll(".nav-item[data-view]");
    for (var i = 0; i < navItems.length; i++) {
      navItems[i].addEventListener("click", function () { switchView(this.getAttribute("data-view")); });
    }

    $("logout-button").addEventListener("click", function () { doLogout(true); toast("已退出登录", "info"); });
    $("refresh-button").addEventListener("click", refreshCurrentView);

    $("users-prev").addEventListener("click", function () { loadUsers(state.usersOffset - USERS_PAGE_SIZE); });
    $("users-next").addEventListener("click", function () { loadUsers(state.usersOffset + USERS_PAGE_SIZE); });
    $("users-body").addEventListener("click", onUsersClick);

    $("config-toggles").addEventListener("change", onConfigChange);
    $("config-params").addEventListener("change", onConfigChange);
    $("config-params").addEventListener("input", onConfigChange);
    $("config-save").addEventListener("click", saveConfig);
    $("config-reset").addEventListener("click", function () { state.dirty = {}; loadConfig(); });
  }

  // ---------- 启动 ----------
  function boot() {
    bindEvents();
    if (!state.token) { showLogin(); return; }
    // 有令牌时先校验是否仍然有效。
    api("/admin/api/v1/session").then(function (result) {
      if (result.status === 200) { showApp(); switchView("overview"); }
      else { handleFatal(result); showLogin(); }
    }).catch(function () { showLogin(); });
  }

  if (document.readyState === "loading") {
    document.addEventListener("DOMContentLoaded", boot);
  } else {
    boot();
  }
})();
