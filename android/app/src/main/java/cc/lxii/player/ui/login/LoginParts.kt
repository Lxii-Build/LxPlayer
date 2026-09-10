package cc.lxii.player.ui.login

import androidx.compose.animation.animateColorAsState
import androidx.compose.animation.core.tween
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.interaction.collectIsFocusedAsState
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.OutlinedTextFieldDefaults
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.input.PasswordVisualTransformation
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import cc.lxii.player.ui.theme.LocalLxExtraColors

/** 登录页各元素的设计尺寸，测试直接核对这些常量。 */
object LoginMetrics {
    val fieldRadius = 16.dp
    val fieldIconTileRadius = 12.dp
    val fieldIconTileSize = 36.dp
    val focusedBorderWidth = 2.dp
    val idleBorderWidth = 1.dp
    val buttonHeight = 54.dp
    val buttonRadius = 20.dp
    val switchHeight = 44.dp
    val brandSize = 140.dp
    val brandRingSize = 120.dp
}

/**
 * 登录 / 注册分段切换。
 *
 * 用滑块式分段控件而不是两个并排按钮：分段控件明确表达「二选一」，
 * 而两个按钮会让人以为是两个动作。
 */
@Composable
fun LoginModeSwitch(
    register: Boolean,
    onChange: (Boolean) -> Unit,
    modifier: Modifier = Modifier,
) {
    val scheme = MaterialTheme.colorScheme
    Row(
        modifier = modifier
            .fillMaxWidth()
            .height(LoginMetrics.switchHeight)
            .clip(RoundedCornerShape(percent = 50))
            .background(scheme.surfaceVariant)
            .padding(4.dp),
        horizontalArrangement = Arrangement.spacedBy(4.dp),
    ) {
        SegmentTab(
            text = "登录",
            selected = !register,
            onClick = { onChange(false) },
            tag = LoginTags.MODE_LOGIN,
            modifier = Modifier.weight(1f),
        )
        SegmentTab(
            text = "注册",
            selected = register,
            onClick = { onChange(true) },
            tag = LoginTags.MODE_REGISTER,
            modifier = Modifier.weight(1f),
        )
    }
}

@Composable
private fun SegmentTab(
    text: String,
    selected: Boolean,
    onClick: () -> Unit,
    tag: String,
    modifier: Modifier = Modifier,
) {
    val scheme = MaterialTheme.colorScheme
    val background by animateColorAsState(
        targetValue = if (selected) scheme.primary else Color.Transparent,
        animationSpec = tween(220),
        label = "segment-bg",
    )
    val content by animateColorAsState(
        targetValue = if (selected) scheme.onPrimary else LocalLxExtraColors.current.muted,
        animationSpec = tween(220),
        label = "segment-fg",
    )
    Box(
        modifier = modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(percent = 50))
            .background(background)
            .clickable(onClick = onClick)
            .testTag(tag),
        contentAlignment = Alignment.Center,
    ) {
        Text(
            text = text,
            color = content,
            fontSize = 14.sp,
            fontWeight = if (selected) FontWeight.Bold else FontWeight.Medium,
        )
    }
}

/**
 * 登录输入框。
 *
 * 前置图标做成圆角色块而不是裸图标——这是参考项目里最有效的一笔，
 * 它把输入框从「一条线」变成「一个有结构的控件」。
 * focus 时边框从 1dp 加粗到 2dp 主色，给出明确的当前焦点。
 */
@Composable
fun LoginField(
    value: String,
    onValueChange: (String) -> Unit,
    label: String,
    icon: ImageVector,
    keyboardType: KeyboardType,
    tag: String,
    modifier: Modifier = Modifier,
    masked: Boolean = false,
    supporting: String? = null,
) {
    val scheme = MaterialTheme.colorScheme
    val interaction = remember { MutableInteractionSource() }
    val focused by interaction.collectIsFocusedAsState()

    Column(modifier = modifier.fillMaxWidth()) {
        OutlinedTextField(
            value = value,
            onValueChange = onValueChange,
            modifier = Modifier
                .fillMaxWidth()
                // focus 时描边加粗到 2dp——这是「当前在填哪一格」最直接的提示。
                // OutlinedTextField 不暴露描边宽度，所以自己画一层，
                // 并把它内建的描边设为透明，避免两条线叠在一起。
                .border(
                    width = if (focused) LoginMetrics.focusedBorderWidth
                    else LoginMetrics.idleBorderWidth,
                    color = if (focused) scheme.primary else scheme.outline,
                    shape = RoundedCornerShape(LoginMetrics.fieldRadius),
                )
                .testTag(tag),
            label = { Text(label) },
            singleLine = true,
            interactionSource = interaction,
            visualTransformation = if (masked) PasswordVisualTransformation()
            else androidx.compose.ui.text.input.VisualTransformation.None,
            keyboardOptions = KeyboardOptions(keyboardType = keyboardType),
            shape = RoundedCornerShape(LoginMetrics.fieldRadius),
            leadingIcon = {
                Box(
                    modifier = Modifier
                        .padding(start = 10.dp, end = 4.dp)
                        .size(LoginMetrics.fieldIconTileSize)
                        .clip(RoundedCornerShape(LoginMetrics.fieldIconTileRadius))
                        .background(scheme.secondaryContainer),
                    contentAlignment = Alignment.Center,
                ) {
                    Icon(
                        imageVector = icon,
                        contentDescription = null,
                        modifier = Modifier.size(20.dp),
                        tint = scheme.onSecondaryContainer,
                    )
                }
            },
            colors = OutlinedTextFieldDefaults.colors(
                focusedContainerColor = scheme.surfaceVariant.copy(alpha = 0.55f),
                unfocusedContainerColor = scheme.surfaceVariant.copy(alpha = 0.40f),
                // 内建描边设为透明：真正的描边由上面的 border 画，
                // 两层都画会出现双线。
                focusedBorderColor = Color.Transparent,
                unfocusedBorderColor = Color.Transparent,
                focusedLabelColor = scheme.primary,
            ),
        )
        if (supporting != null) {
            Text(
                text = supporting,
                style = MaterialTheme.typography.labelSmall,
                color = LocalLxExtraColors.current.muted,
                modifier = Modifier.padding(start = 16.dp, top = 6.dp),
            )
        }
    }
    // borderWidth 参与重组以驱动动画；OutlinedTextField 不暴露描边宽度，
    // 焦点变化的粗细感由 colors 的对比承担，这里保留读取避免被优化掉。
    @Suppress("UNUSED_EXPRESSION")
    borderWidth
}

/**
 * 主操作按钮。
 *
 * 高 54dp、圆角 20dp、带主色阴影。禁用态去掉阴影并换成低对比底色——
 * 保留阴影会让不可点的按钮看起来仍然可点。
 */
@Composable
fun LoginPrimaryButton(
    text: String,
    enabled: Boolean,
    busy: Boolean,
    onClick: () -> Unit,
    modifier: Modifier = Modifier,
) {
    val scheme = MaterialTheme.colorScheme
    val shape = RoundedCornerShape(LoginMetrics.buttonRadius)

    Box(
        modifier = modifier
            .fillMaxWidth()
            .height(LoginMetrics.buttonHeight)
            .then(
                if (enabled) {
                    Modifier.shadow(
                        elevation = 12.dp,
                        shape = shape,
                        ambientColor = scheme.primary.copy(alpha = 0.25f),
                        spotColor = scheme.primary.copy(alpha = 0.25f),
                    )
                } else {
                    Modifier
                },
            )
            .clip(shape)
            .background(if (enabled) scheme.primary else scheme.surfaceVariant)
            .clickable(enabled = enabled && !busy, onClick = onClick)
            .testTag(LoginTags.SUBMIT),
        contentAlignment = Alignment.Center,
    ) {
        if (busy) {
            CircularProgressIndicator(
                modifier = Modifier.size(22.dp),
                strokeWidth = 2.5.dp,
                color = scheme.onPrimary,
            )
        } else {
            Text(
                text = text,
                color = if (enabled) scheme.onPrimary
                else LocalLxExtraColors.current.muted,
                fontSize = 16.sp,
                fontWeight = FontWeight.Bold,
            )
        }
    }
}
