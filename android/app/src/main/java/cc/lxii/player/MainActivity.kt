package cc.lxii.player

import android.Manifest
import android.content.Intent
import android.os.Build
import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.BackHandler
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.unit.dp
import androidx.core.content.ContextCompat
import androidx.lifecycle.viewmodel.compose.viewModel
import androidx.media3.common.util.UnstableApi
import cc.lxii.player.core.net.ApiClient
import cc.lxii.player.core.net.ApiException
import cc.lxii.player.core.player.PlaybackService
import cc.lxii.player.core.player.policy.SleepTimerMode
import cc.lxii.player.core.player.policy.SleepTimerPolicy
import cc.lxii.player.data.prefs.ThemeMode
import cc.lxii.player.data.secure.TokenStore
import cc.lxii.player.ui.LibraryViewModel
import cc.lxii.player.ui.component.GlassBottomNav
import cc.lxii.player.ui.component.LxTab
import cc.lxii.player.ui.component.MiniPlayer
import cc.lxii.player.ui.home.HomeScreen
import cc.lxii.player.ui.library.LibraryScreen
import cc.lxii.player.ui.login.LoginScreen
import cc.lxii.player.ui.nowplaying.NowPlayingScreen
import cc.lxii.player.ui.profile.ProfileScreen
import cc.lxii.player.ui.queue.QueueSheet
import cc.lxii.player.ui.search.SearchScreen
import cc.lxii.player.ui.theme.LxPlayerTheme
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

@UnstableApi
class MainActivity : ComponentActivity() {

    private val permissionLauncher = registerForActivityResult(
        ActivityResultContracts.RequestPermission(),
    ) { granted -> permissionCallback?.invoke(granted) }

    private var permissionCallback: ((Boolean) -> Unit)? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        enableEdgeToEdge()

        val app = application as LxPlayerApp
        val container = app.container
        val tokenStore = TokenStore(this)
        val api = ApiClient(
            baseUrlProvider = { BuildConfig.BASE_URL },
            tokenProvider = { tokenStore.token() },
        )

        setContent {
            val themeMode by container.settings.darkTheme.collectAsState(initial = ThemeMode.SYSTEM)
            val dark = when (themeMode) {
                ThemeMode.SYSTEM -> androidx.compose.foundation.isSystemInDarkTheme()
                ThemeMode.LIGHT -> false
                ThemeMode.DARK -> true
            }

            LxPlayerTheme(darkTheme = dark) {
                Surface(color = MaterialTheme.colorScheme.background) {
                    val player = container.playerController
                    val libraryVm: LibraryViewModel = viewModel(
                        factory = LibraryViewModel.Factory(container.localSource, player),
                    )
                    val libraryState by libraryVm.state.collectAsState()
                    val featuredIndex by libraryVm.featuredIndex.collectAsState()
                    val currentTrack by player.currentTrack.collectAsState()
                    val isPlaying by player.isPlaying.collectAsState()
                    val positionMs by player.positionMs.collectAsState()
                    val durationMs by player.durationMs.collectAsState()
                    val queue by player.queue.collectAsState()
                    val currentIndex by player.currentIndex.collectAsState()
                    val repeatMode by player.repeatMode.collectAsState()
                    val shuffle by player.shuffleEnabled.collectAsState()
                    val speed by player.playbackSpeed.collectAsState()
                    val sleepTimer by player.sleepTimer.collectAsState()

                    var tab by remember { mutableStateOf(LxTab.HOME) }
                    var nowPlayingOpen by remember { mutableStateOf(false) }
                    var queueOpen by remember { mutableStateOf(false) }
                    var loginOpen by remember { mutableStateOf(false) }
                    var loginBusy by remember { mutableStateOf(false) }
                    var loginError by remember { mutableStateOf<String?>(null) }
                    var account by remember { mutableStateOf(tokenStore.email()) }
                    var sleepPickerOpen by remember { mutableStateOf(false) }
                    val scope = rememberCoroutineScope()

                    LaunchedEffect(Unit) {
                        libraryVm.onPermissionResult(hasAudioPermission())
                    }

                    BackHandler(enabled = nowPlayingOpen || loginOpen) {
                        when {
                            loginOpen -> loginOpen = false
                            nowPlayingOpen -> nowPlayingOpen = false
                        }
                    }

                    Box(modifier = Modifier.fillMaxSize()) {
                        val bottomPad = if (currentTrack != null) 168.dp else 92.dp
                        val padding = PaddingValues(bottom = bottomPad)

                        when (tab) {
                            LxTab.HOME -> HomeScreen(
                                state = libraryState,
                                featuredIndex = featuredIndex,
                                currentTrackId = currentTrack?.id,
                                isPlaying = isPlaying,
                                onFeaturedIndexChange = libraryVm::onFeaturedIndexChange,
                                onPlayTrack = { track ->
                                    startPlaybackService()
                                    libraryVm.playFromLibrary(track)
                                },
                                onRefresh = libraryVm::refresh,
                                onRequestPermission = {
                                    permissionCallback = { libraryVm.onPermissionResult(it) }
                                    permissionLauncher.launch(audioPermission())
                                },
                                contentPadding = padding,
                            )

                            LxTab.SEARCH -> SearchScreen(
                                tracks = libraryState.tracks,
                                currentTrackId = currentTrack?.id,
                                isPlaying = isPlaying,
                                onPlayTrack = { track ->
                                    startPlaybackService()
                                    libraryVm.playFromLibrary(track)
                                },
                                contentPadding = padding,
                            )

                            LxTab.LIBRARY -> LibraryScreen(
                                state = libraryState,
                                currentTrackId = currentTrack?.id,
                                isPlaying = isPlaying,
                                onPlayTrack = { track ->
                                    startPlaybackService()
                                    libraryVm.playFromLibrary(track)
                                },
                                onRefresh = libraryVm::refresh,
                                contentPadding = padding,
                            )

                            LxTab.PROFILE -> ProfileScreen(
                                account = account,
                                themeMode = themeMode,
                                playbackSpeed = speed,
                                sleepTimerRemainingMs = SleepTimerPolicy.remainingMs(
                                    sleepTimer,
                                    System.currentTimeMillis(),
                                ),
                                onLoginClick = { loginOpen = true; loginError = null },
                                onLogout = {
                                    tokenStore.clear()
                                    account = null
                                },
                                onCycleTheme = {
                                    val next = when (themeMode) {
                                        ThemeMode.SYSTEM -> ThemeMode.DARK
                                        ThemeMode.DARK -> ThemeMode.LIGHT
                                        ThemeMode.LIGHT -> ThemeMode.SYSTEM
                                    }
                                    scope.launch { container.settings.setDarkTheme(next) }
                                },
                                onCycleSpeed = {
                                    val options = floatArrayOf(0.75f, 1f, 1.25f, 1.5f, 2f)
                                    val next = options.firstOrNull { it > speed + 0.01f } ?: options.first()
                                    player.setSpeed(next)
                                },
                                onSleepTimerClick = { sleepPickerOpen = true },
                                onSyncNow = {
                                    scope.launch {
                                        runCatching {
                                            withContext(Dispatchers.IO) { api.getSnapshot() }
                                        }
                                    }
                                },
                                contentPadding = padding,
                            )
                        }

                        MiniPlayer(
                            track = currentTrack,
                            playing = isPlaying,
                            positionMs = positionMs,
                            durationMs = durationMs,
                            onTogglePlay = player::playPause,
                            onNext = player::next,
                            onOpenNowPlaying = { nowPlayingOpen = true },
                            onOpenQueue = { queueOpen = true },
                            modifier = Modifier
                                .align(Alignment.BottomCenter)
                                .padding(bottom = 84.dp),
                        )

                        GlassBottomNav(
                            selected = tab,
                            onSelect = { tab = it },
                            modifier = Modifier.align(Alignment.BottomCenter),
                        )

                        if (nowPlayingOpen) {
                            NowPlayingScreen(
                                track = currentTrack,
                                playing = isPlaying,
                                positionMs = positionMs,
                                durationMs = durationMs,
                                repeatMode = repeatMode,
                                shuffleEnabled = shuffle,
                                liked = false,
                                accent = Color(0xFF6B7280),
                                onTogglePlay = player::playPause,
                                onNext = player::next,
                                onPrevious = player::previous,
                                onSeek = player::seekTo,
                                onCycleRepeat = player::cycleRepeat,
                                onToggleShuffle = { player.setShuffle(!shuffle) },
                                onToggleLike = {},
                                onOpenQueue = { queueOpen = true },
                                onCollapse = { nowPlayingOpen = false },
                            )
                        }

                        if (loginOpen) {
                            Surface(modifier = Modifier.fillMaxSize()) {
                                LoginScreen(
                                    busy = loginBusy,
                                    error = loginError,
                                    onSubmit = { email, password, register ->
                                        loginBusy = true
                                        loginError = null
                                        scope.launch {
                                            val result = runCatching {
                                                withContext(Dispatchers.IO) {
                                                    if (register) api.register(email, password)
                                                    else api.login(email, password)
                                                }
                                            }
                                            loginBusy = false
                                            result.fold(
                                                onSuccess = { auth ->
                                                    tokenStore.save(auth.token, auth.user.email)
                                                    account = auth.user.email
                                                    loginOpen = false
                                                },
                                                onFailure = { error ->
                                                    loginError = when (error) {
                                                        is ApiException -> error.message
                                                        else -> "网络异常，请稍后重试"
                                                    }
                                                },
                                            )
                                        }
                                    },
                                    onBack = { loginOpen = false },
                                )
                            }
                        }
                    }

                    if (queueOpen) {
                        QueueSheet(
                            queue = queue,
                            currentIndex = currentIndex,
                            isPlaying = isPlaying,
                            onPlayAt = { index ->
                                startPlaybackService()
                                player.playAt(index)
                            },
                            onRemoveAt = player::removeAt,
                            onClear = {
                                val last = queue.lastIndex
                                for (i in last downTo 0) player.removeAt(i)
                            },
                            onDismiss = { queueOpen = false },
                        )
                    }

                    if (sleepPickerOpen) {
                        AlertDialog(
                            onDismissRequest = { sleepPickerOpen = false },
                            title = { Text("睡眠定时") },
                            text = {
                                androidx.compose.foundation.layout.Column {
                                    SleepTimerPolicy.presetMinutes.forEach { minutes ->
                                        TextButton(
                                            onClick = {
                                                player.armSleepTimer(
                                                    minutes,
                                                    SleepTimerMode.COUNTDOWN_FINISH_CURRENT,
                                                )
                                                sleepPickerOpen = false
                                            },
                                        ) { Text("$minutes 分钟后停止（播完当前）") }
                                    }
                                    TextButton(
                                        onClick = {
                                            player.cancelSleepTimer()
                                            sleepPickerOpen = false
                                        },
                                    ) { Text("关闭定时") }
                                }
                            },
                            confirmButton = {},
                            dismissButton = {
                                TextButton(onClick = { sleepPickerOpen = false }) { Text("取消") }
                            },
                        )
                    }
                }
            }
        }
    }

    private fun startPlaybackService() {
        val intent = Intent(this, PlaybackService::class.java)
        ContextCompat.startForegroundService(this, intent)
    }

    private fun audioPermission(): String =
        if (Build.VERSION.SDK_INT >= 33) Manifest.permission.READ_MEDIA_AUDIO
        else Manifest.permission.READ_EXTERNAL_STORAGE

    private fun hasAudioPermission(): Boolean =
        ContextCompat.checkSelfPermission(this, audioPermission()) ==
            android.content.pm.PackageManager.PERMISSION_GRANTED
}
