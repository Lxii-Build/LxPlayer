package cc.lxii.player.ui.profile

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.AccountCircle
import androidx.compose.material.icons.outlined.Bedtime
import androidx.compose.material.icons.outlined.Cloud
import androidx.compose.material.icons.outlined.DarkMode
import androidx.compose.material.icons.outlined.Speed
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.unit.dp
import cc.lxii.player.data.prefs.ThemeMode
import cc.lxii.player.ui.theme.LocalLxExtraColors
import cc.lxii.player.ui.theme.LxRadius

@Composable
fun ProfileScreen(
    account: String?,
    themeMode: ThemeMode,
    playbackSpeed: Float,
    sleepTimerRemainingMs: Long,
    onLoginClick: () -> Unit,
    onLogout: () -> Unit,
    onCycleTheme: () -> Unit,
    onCycleSpeed: () -> Unit,
    onSleepTimerClick: () -> Unit,
    onSyncNow: () -> Unit,
    contentPadding: PaddingValues,
    modifier: Modifier = Modifier,
) {
    LazyColumn(
        modifier = modifier.fillMaxWidth(),
        contentPadding = contentPadding,
        verticalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        item {
            Column(
                modifier = Modifier
                    .statusBarsPadding()
                    .padding(horizontal = 20.dp)
                    .padding(top = 24.dp),
            ) {
                Text(text = "我的", style = MaterialTheme.typography.headlineLarge)
            }
        }

        item {
            Card(
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(horizontal = 16.dp),
                shape = RoundedCornerShape(LxRadius.card),
                colors = CardDefaults.cardColors(
                    containerColor = MaterialTheme.colorScheme.surfaceVariant,
                ),
                elevation = CardDefaults.cardElevation(defaultElevation = 0.dp),
            ) {
                Row(
                    modifier = Modifier
                        .fillMaxWidth()
                        .padding(16.dp),
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    Icon(
                        Icons.Outlined.AccountCircle,
                        contentDescription = null,
                        modifier = Modifier
                            .size(48.dp)
                            .clip(CircleShape),
                        tint = MaterialTheme.colorScheme.primary,
                    )
                    Column(
                        modifier = Modifier
                            .weight(1f)
                            .padding(horizontal = 12.dp),
                    ) {
                        Text(
                            text = account ?: "未登录",
                            style = MaterialTheme.typography.titleMedium,
                        )
                        Text(
                            text = if (account != null) "数据会同步到 LxPlayer 账号"
                            else "登录后可在多设备间同步歌单与喜欢",
                            style = MaterialTheme.typography.bodySmall,
                            color = LocalLxExtraColors.current.muted,
                        )
                    }
                    if (account == null) {
                        TextButton(onClick = onLoginClick) { Text("登录") }
                    } else {
                        TextButton(onClick = onLogout) {
                            Text("退出", color = MaterialTheme.colorScheme.error)
                        }
                    }
                }
            }
        }

        item {
            SettingsGroup {
                SettingRow(
                    icon = Icons.Outlined.DarkMode,
                    title = "主题",
                    value = when (themeMode) {
                        ThemeMode.SYSTEM -> "跟随系统"
                        ThemeMode.LIGHT -> "浅色"
                        ThemeMode.DARK -> "深色"
                    },
                    onClick = onCycleTheme,
                )
                SettingRow(
                    icon = Icons.Outlined.Speed,
                    title = "播放速度",
                    value = "%.2fx".format(playbackSpeed),
                    onClick = onCycleSpeed,
                )
                SettingRow(
                    icon = Icons.Outlined.Bedtime,
                    title = "睡眠定时",
                    value = if (sleepTimerRemainingMs > 0) {
                        "${sleepTimerRemainingMs / 60_000} 分钟后停止"
                    } else {
                        "未开启"
                    },
                    onClick = onSleepTimerClick,
                )
                if (account != null) {
                    SettingRow(
                        icon = Icons.Outlined.Cloud,
                        title = "立即同步",
                        value = "",
                        onClick = onSyncNow,
                    )
                }
            }
        }
    }
}

@Composable
private fun SettingsGroup(content: @Composable () -> Unit) {
    Card(
        modifier = Modifier
            .fillMaxWidth()
            .padding(horizontal = 16.dp),
        shape = RoundedCornerShape(LxRadius.card),
        colors = CardDefaults.cardColors(
            containerColor = MaterialTheme.colorScheme.surfaceVariant,
        ),
        elevation = CardDefaults.cardElevation(defaultElevation = 0.dp),
    ) {
        Column(modifier = Modifier.padding(vertical = 4.dp)) { content() }
    }
}

@Composable
private fun SettingRow(
    icon: ImageVector,
    title: String,
    value: String,
    onClick: () -> Unit,
) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(LxRadius.listCover))
            .clickable(onClick = onClick)
            .padding(horizontal = 16.dp, vertical = 14.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Icon(
            icon,
            contentDescription = null,
            modifier = Modifier.size(20.dp),
            tint = MaterialTheme.colorScheme.primary,
        )
        Text(
            text = title,
            style = MaterialTheme.typography.bodyLarge,
            modifier = Modifier
                .weight(1f)
                .padding(start = 12.dp),
        )
        if (value.isNotEmpty()) {
            Text(
                text = value,
                style = MaterialTheme.typography.bodySmall,
                color = LocalLxExtraColors.current.muted,
            )
        }
    }
}

