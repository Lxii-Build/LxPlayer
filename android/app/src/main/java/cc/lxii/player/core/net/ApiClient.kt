package cc.lxii.player.core.net

import cc.lxii.player.data.sync.SyncSnapshot
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.Json
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.RequestBody.Companion.toRequestBody
import java.util.concurrent.TimeUnit

@Serializable
data class AuthResponse(val token: String, val user: UserDto)

@Serializable
data class UserDto(val id: Long, val email: String)

@Serializable
data class ErrorResponse(val error: String = "请求失败")

class ApiException(val status: Int, override val message: String) : RuntimeException(message)

/**
 * 后端 HTTP 客户端。
 *
 * 后端只做账号与数据同步，不解析、不代理、不存储音频。
 * 所有请求都走 HTTPS；令牌由调用方从 [cc.lxii.player.data.secure.TokenStore] 取出后传入。
 */
class ApiClient(
    private val baseUrlProvider: () -> String,
    private val tokenProvider: () -> String?,
) {
    private val json = Json { ignoreUnknownKeys = true; encodeDefaults = true }
    private val mediaType = "application/json; charset=utf-8".toMediaType()
    private val client = OkHttpClient.Builder()
        .connectTimeout(15, TimeUnit.SECONDS)
        .readTimeout(20, TimeUnit.SECONDS)
        .build()

    fun register(email: String, password: String): AuthResponse =
        post("/auth/register", """{"email":${email.json()},"password":${password.json()}}""")

    fun login(email: String, password: String): AuthResponse =
        post("/auth/login", """{"email":${email.json()},"password":${password.json()}}""")

    fun me(): UserDto = get("/me")

    fun getSnapshot(): SyncSnapshot = get("/sync/snapshot")

    fun putSnapshot(snapshot: SyncSnapshot, baseRevision: Long): SyncSnapshot {
        val body = json.encodeToString(SyncSnapshot.serializer(), snapshot)
        return put("/sync/snapshot?baseRevision=$baseRevision", body)
    }

    private inline fun <reified T> get(path: String): T = execute(Request.Builder().url(url(path)).get())

    private inline fun <reified T> post(path: String, body: String): T =
        execute(Request.Builder().url(url(path)).post(body.toRequestBody(mediaType)))

    private inline fun <reified T> put(path: String, body: String): T =
        execute(Request.Builder().url(url(path)).put(body.toRequestBody(mediaType)))

    private inline fun <reified T> execute(builder: Request.Builder): T {
        tokenProvider()?.takeIf { it.isNotBlank() }?.let {
            builder.header("Authorization", "Bearer $it")
        }
        client.newCall(builder.build()).execute().use { response ->
            val raw = response.body?.string().orEmpty()
            if (!response.isSuccessful) {
                val message = runCatching {
                    json.decodeFromString(ErrorResponse.serializer(), raw).error
                }.getOrDefault("请求失败 (${response.code})")
                throw ApiException(response.code, message)
            }
            return json.decodeFromString<T>(raw)
        }
    }

    private fun url(path: String): String {
        val base = baseUrlProvider().trimEnd('/')
        return "$base$path"
    }

    private fun String.json(): String = json.encodeToString(this)
}
