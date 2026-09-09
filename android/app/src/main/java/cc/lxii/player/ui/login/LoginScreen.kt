package cc.lxii.player.ui.login

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material3.Button
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.input.PasswordVisualTransformation
import androidx.compose.ui.unit.dp
import cc.lxii.player.ui.theme.LocalLxExtraColors

@Composable
fun LoginScreen(
    busy: Boolean,
    error: String?,
    onSubmit: (email: String, password: String, register: Boolean) -> Unit,
    onBack: () -> Unit,
    modifier: Modifier = Modifier,
) {
    var email by remember { mutableStateOf("") }
    var password by remember { mutableStateOf("") }
    var register by remember { mutableStateOf(false) }

    Column(
        modifier = modifier
            .fillMaxWidth()
            .statusBarsPadding()
            .padding(horizontal = 24.dp, vertical = 24.dp),
        verticalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        TextButton(onClick = onBack) { Text("返回") }
        Text(
            text = if (register) "注册 LxPlayer 账号" else "登录 LxPlayer",
            style = MaterialTheme.typography.headlineLarge,
        )
        Text(
            text = "账号只用来保存歌单、喜欢和播放历史，不会上传音频。",
            style = MaterialTheme.typography.bodyLarge,
            color = LocalLxExtraColors.current.muted,
        )
        OutlinedTextField(
            value = email,
            onValueChange = { email = it },
            modifier = Modifier.fillMaxWidth(),
            label = { Text("邮箱") },
            singleLine = true,
            keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Email),
            shape = RoundedCornerShape(14.dp),
        )
        OutlinedTextField(
            value = password,
            onValueChange = { password = it },
            modifier = Modifier.fillMaxWidth(),
            label = { Text("密码") },
            singleLine = true,
            visualTransformation = PasswordVisualTransformation(),
            keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Password),
            shape = RoundedCornerShape(14.dp),
        )
        if (error != null) {
            Text(text = error, color = MaterialTheme.colorScheme.error)
        }
        Button(
            onClick = { onSubmit(email.trim(), password, register) },
            enabled = !busy && email.isNotBlank() && password.length >= 8,
            modifier = Modifier.fillMaxWidth(),
            shape = RoundedCornerShape(percent = 50),
        ) {
            Text(if (register) "注册" else "登录")
        }
        TextButton(onClick = { register = !register }) {
            Text(if (register) "已有账号？去登录" else "没有账号？去注册")
        }
    }
}
