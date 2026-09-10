package cc.lxii.player.ui.login

import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.core.tween
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.outlined.ArrowBack
import androidx.compose.material.icons.outlined.ErrorOutline
import androidx.compose.material.icons.outlined.Lock
import androidx.compose.material.icons.outlined.MailOutline
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import cc.lxii.player.ui.theme.LocalLxExtraColors

/**
 * 登录 / 注册。
 *
 * 布局不再是从上到下堆控件：品牌区 → 分段切换 → 输入区 → 主按钮，
 * 每段之间留出呼吸空间，右上角一团主色径向光把视线引向品牌区。
 *
 * 输入框与按钮参数取自参考项目：圆角 16 输入框配圆角图标色块、
 * focus 时边框加粗到 2dp 主色、按钮高 54dp 圆角 20dp 带主色阴影。
 * 彩色阴影（而非黑色投影）是这套观感的关键——黑影会显脏。
 */
@Composable
fun LoginScreen(
    busy: Boolean,
    error: String?,
    onSubmit: (email: String, password: String, register: Boolean) -> Unit,
    onBack: () -> Unit,
    modifier: Modifier = Modifier,
    animateBrand: Boolean = true,
) {
    var email by remember { mutableStateOf("") }
    var password by remember { mutableStateOf("") }
    var register by remember { mutableStateOf(false) }

    val scheme = MaterialTheme.colorScheme
    val canSubmit = !busy && email.isNotBlank() && password.length >= MIN_PASSWORD_LENGTH

    Box(
        modifier = modifier
            .fillMaxSize()
            .background(scheme.background)
            // 右上角一团主色光：把视线拉向品牌区，也让纯色背景不至于死板。
            .background(
                Brush.radialGradient(
                    colors = listOf(
                        scheme.primary.copy(alpha = 0.12f),
                        scheme.background.copy(alpha = 0f),
                    ),
                    center = Offset(x = 1f, y = 0f),
                    radius = 1400f,
                ),
            ),
    ) {
        Column(
            modifier = Modifier
                .fillMaxSize()
                .verticalScroll(rememberScrollState())
                .statusBarsPadding()
                .navigationBarsPadding()
                .padding(horizontal = 28.dp),
            horizontalAlignment = Alignment.CenterHorizontally,
        ) {
            Spacer(Modifier.height(48.dp))

            LoginBrandMark(animate = animateBrand)

            Spacer(Modifier.height(28.dp))

            Text(
                text = if (register) "创建账号" else "登录 LxPlayer",
                style = MaterialTheme.typography.headlineLarge,
                color = scheme.onBackground,
                textAlign = TextAlign.Center,
            )
            Spacer(Modifier.height(8.dp))
            Text(
                text = "账号只保存歌单、喜欢和播放历史，音频始终留在本机。",
                style = MaterialTheme.typography.bodyLarge,
                color = LocalLxExtraColors.current.muted,
                textAlign = TextAlign.Center,
                modifier = Modifier.padding(horizontal = 12.dp),
            )

            Spacer(Modifier.height(28.dp))

            LoginModeSwitch(
                register = register,
                onChange = { register = it },
                enabled = !busy,
            )

            Spacer(Modifier.height(24.dp))

            LoginField(
                value = email,
                onValueChange = { email = it },
                label = "邮箱",
                icon = Icons.Outlined.MailOutline,
                keyboardType = KeyboardType.Email,
                tag = LoginTags.EMAIL,
                // 请求进行中锁住输入：此时改邮箱不影响已发出的请求，
                // 却会让人以为改了就生效。
                enabled = !busy,
            )

            Spacer(Modifier.height(16.dp))

            LoginField(
                value = password,
                onValueChange = { password = it },
                label = "密码",
                icon = Icons.Outlined.Lock,
                keyboardType = KeyboardType.Password,
                masked = true,
                supporting = if (register) "至少 $MIN_PASSWORD_LENGTH 位" else null,
                tag = LoginTags.PASSWORD,
                enabled = !busy,
            )

            // 错误用淡红底卡片承载，而不是一行裸红字——
            // 裸字容易被当成说明文字忽略掉。
            AnimatedVisibility(
                visible = error != null,
                enter = fadeIn(tween(180)),
                exit = fadeOut(tween(120)),
            ) {
                Row(
                    modifier = Modifier
                        .fillMaxWidth()
                        .padding(top = 16.dp)
                        .background(
                            scheme.error.copy(alpha = 0.12f),
                            RoundedCornerShape(14.dp),
                        )
                        .padding(horizontal = 14.dp, vertical = 12.dp)
                        .testTag(LoginTags.ERROR),
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.spacedBy(10.dp),
                ) {
                    Icon(
                        Icons.Outlined.ErrorOutline,
                        contentDescription = null,
                        modifier = Modifier.size(18.dp),
                        tint = scheme.error,
                    )
                    Text(
                        text = error.orEmpty(),
                        style = MaterialTheme.typography.bodyMedium,
                        color = scheme.error,
                    )
                }
            }

            Spacer(Modifier.height(28.dp))

            LoginPrimaryButton(
                text = if (register) "注册" else "登录",
                enabled = canSubmit,
                busy = busy,
                onClick = { onSubmit(email.trim(), password, register) },
            )

            Spacer(Modifier.height(16.dp))

            // 底部这行必须可点：上面的分段控件是主入口，
            // 但用户读完这句话时手已经在屏幕下方了。
            Text(
                text = if (register) "已有账号？返回登录" else "还没有账号？立即注册",
                style = MaterialTheme.typography.bodyLarge,
                color = scheme.primary,
                fontWeight = FontWeight.SemiBold,
                fontSize = 14.sp,
                modifier = Modifier
                    .clip(RoundedCornerShape(percent = 50))
                    .clickable { register = !register }
                    .padding(horizontal = 16.dp, vertical = 10.dp)
                    .testTag(LoginTags.TOGGLE_HINT),
            )

            Spacer(Modifier.height(32.dp))
        }

        IconButton(
            onClick = onBack,
            modifier = Modifier
                .statusBarsPadding()
                .padding(8.dp)
                .testTag(LoginTags.BACK),
        ) {
            Icon(
                Icons.AutoMirrored.Outlined.ArrowBack,
                contentDescription = "返回",
                tint = scheme.onBackground,
            )
        }
    }
}

const val MIN_PASSWORD_LENGTH = 8

object LoginTags {
    const val BACK = "login-back"
    const val EMAIL = "login-email"
    const val PASSWORD = "login-password"
    const val ERROR = "login-error"
    const val SUBMIT = "login-submit"
    const val TOGGLE_HINT = "login-toggle-hint"
    const val MODE_LOGIN = "login-mode-login"
    const val MODE_REGISTER = "login-mode-register"
}
