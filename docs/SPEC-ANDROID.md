# SPEC-ANDROID — Android App

> Language: Kotlin / Jetpack Compose (Native)  
> Design: GitHub style (same tokens as iOS, see Master SPEC §2)  
> Interaction reference: Same as iOS — Remodex-style thread, inline approval  
> Dependency: SPEC-PROTO  
> Location: `android/app/`  
> Phase: P1 (parallel with Connection Node)  
> Duration: 2-3 weeks

---

## Overview

Native Kotlin/Compose Android app. Identical design language to iOS (GitHub style), same interaction patterns. Shares Protobuf protocol. All GH design tokens ported to Compose `MaterialTheme` extension.

---

## File Structure

```
android/app/src/main/
├── java/com/mrt/app/
│   ├── MRTApplication.kt
│   ├── MainActivity.kt
│   │
│   ├── designsystem/                       # GitHub-style component library
│   │   ├── theme/
│   │   │   ├── GHColors.kt                 # Color tokens (same hex as iOS)
│   │   │   ├── GHTypography.kt
│   │   │   ├── GHSpacing.kt
│   │   │   └── MRTTheme.kt                 # MaterialTheme wrapper
│   │   └── components/
│   │       ├── GHCard.kt
│   │       ├── GHButton.kt
│   │       ├── GHBadge.kt
│   │       ├── GHInput.kt
│   │       ├── GHBanner.kt
│   │       ├── GHCodeBlock.kt
│   │       ├── GHList.kt
│   │       ├── GHDiffView.kt
│   │       ├── GHStatusDot.kt
│   │       └── GHTabBar.kt
│   │
│   ├── core/
│   │   ├── network/
│   │   │   ├── WebSocketClient.kt
│   │   │   ├── ProtobufCodec.kt
│   │   │   ├── ConnectionManager.kt
│   │   │   └── MessageDispatcher.kt
│   │   ├── crypto/                          # P3
│   │   │   ├── NoiseSession.kt
│   │   │   └── KeyManager.kt
│   │   ├── models/
│   │   │   ├── ChatMessage.kt
│   │   │   ├── SessionModel.kt
│   │   │   └── DeviceModel.kt
│   │   └── storage/
│   │       └── Preferences.kt              # DataStore
│   │
│   ├── features/
│   │   ├── chat/
│   │   │   ├── ChatScreen.kt               # Thread-based (mirrors iOS ChatView)
│   │   │   ├── ChatViewModel.kt
│   │   │   ├── ThreadMessage.kt
│   │   │   ├── StreamingText.kt
│   │   │   ├── ApprovalBanner.kt
│   │   │   └── ConnectionStatusBar.kt
│   │   ├── sessions/
│   │   │   ├── SessionDrawer.kt            # Drawer instead of swipe sidebar
│   │   │   ├── SessionRow.kt
│   │   │   └── SessionViewModel.kt
│   │   ├── devices/                         # P1
│   │   ├── git/                             # P4
│   │   ├── files/                           # P4
│   │   └── settings/
│   │       ├── SettingsScreen.kt
│   │       ├── ConnectionSettings.kt
│   │       └── PairDeviceScreen.kt          # P3
│   │
│   └── navigation/
│       └── AppNavigation.kt
│
├── proto/
│   └── mrt/                                 # Generated Kotlin Protobuf
└── res/
    ├── values/
    │   └── themes.xml
    └── font/
        └── jetbrains_mono.ttf               # Monospace font for code
```

Dependencies: see previous SPEC-ANDROID `build.gradle.kts`. Add `JetBrains Mono` font for code blocks.

---

## Design System Implementation

### ANDROID-DS01: Color Tokens

```kotlin
// designsystem/theme/GHColors.kt
object GHColors {
    // Dark mode (primary)
    val bgPrimary = Color(0xFF0D1117)
    val bgSecondary = Color(0xFF161B22)
    val bgTertiary = Color(0xFF21262D)
    val bgOverlay = Color(0xFF30363D)

    val borderDefault = Color(0xFF30363D)
    val borderMuted = Color(0xFF21262D)

    val textPrimary = Color(0xFFE6EDF3)
    val textSecondary = Color(0xFF8B949E)
    val textTertiary = Color(0xFF6E7681)

    val accentBlue = Color(0xFF58A6FF)
    val accentGreen = Color(0xFF3FB950)
    val accentRed = Color(0xFFF85149)
    val accentYellow = Color(0xFFD29922)
    val accentPurple = Color(0xFFBC8CFF)
    val accentOrange = Color(0xFFF0883E)

    // Light mode
    val lightBgPrimary = Color(0xFFFFFFFF)
    val lightBgSecondary = Color(0xFFF6F8FA)
    val lightBgTertiary = Color(0xFFEAEEF2)
    val lightBorderDefault = Color(0xFFD0D7DE)
    val lightTextPrimary = Color(0xFF1F2328)
    val lightTextSecondary = Color(0xFF656D76)
    val lightAccentBlue = Color(0xFF0969DA)
    val lightAccentGreen = Color(0xFF1A7F37)
    val lightAccentRed = Color(0xFFCF222E)
    val lightAccentYellow = Color(0xFF9A6700)
}
```

### ANDROID-DS02: Typography

```kotlin
// designsystem/theme/GHTypography.kt
val JetBrainsMono = FontFamily(Font(R.font.jetbrains_mono))

object GHType {
    val titleLg = TextStyle(fontSize = 20.sp, fontWeight = FontWeight.Bold)
    val title = TextStyle(fontSize = 17.sp, fontWeight = FontWeight.SemiBold)
    val body = TextStyle(fontSize = 15.sp)
    val bodySm = TextStyle(fontSize = 13.sp)
    val caption = TextStyle(fontSize = 12.sp)
    val code = TextStyle(fontSize = 13.sp, fontFamily = JetBrainsMono)
    val codeSm = TextStyle(fontSize = 11.sp, fontFamily = JetBrainsMono)
}
```

### ANDROID-DS03: Core Components

All GH components follow the same visual spec as iOS. Key difference: use Compose idioms.

```kotlin
// designsystem/components/GHCard.kt
@Composable
fun GHCard(modifier: Modifier = Modifier, content: @Composable ColumnScope.() -> Unit) {
    Column(
        modifier = modifier
            .fillMaxWidth()
            .background(GHColors.bgSecondary, RoundedCornerShape(12.dp))
            .border(1.dp, GHColors.borderDefault, RoundedCornerShape(12.dp))
            .padding(16.dp),
        content = content
    )
}

// designsystem/components/GHButton.kt
enum class GHButtonStyle { Primary, Secondary, Danger }

@Composable
fun GHButton(
    text: String,
    style: GHButtonStyle = GHButtonStyle.Primary,
    icon: ImageVector? = null,
    onClick: () -> Unit,
) {
    val bg = when (style) {
        GHButtonStyle.Primary -> GHColors.accentBlue.copy(alpha = 0.15f)
        GHButtonStyle.Secondary -> Color.Transparent
        GHButtonStyle.Danger -> GHColors.accentRed.copy(alpha = 0.15f)
    }
    val fg = when (style) {
        GHButtonStyle.Primary -> GHColors.accentBlue
        GHButtonStyle.Secondary -> GHColors.textSecondary
        GHButtonStyle.Danger -> GHColors.accentRed
    }
    Button(
        onClick = onClick,
        colors = ButtonDefaults.buttonColors(containerColor = bg, contentColor = fg),
        shape = RoundedCornerShape(6.dp),
        border = if (style == GHButtonStyle.Secondary) BorderStroke(1.dp, GHColors.borderDefault) else null,
        contentPadding = PaddingValues(horizontal = 12.dp, vertical = 8.dp),
    ) {
        icon?.let { Icon(it, null, modifier = Modifier.size(14.dp)) }
        if (icon != null) Spacer(Modifier.width(8.dp))
        Text(text, style = GHType.bodySm.copy(fontWeight = FontWeight.Medium))
    }
}

// designsystem/components/GHBadge.kt
@Composable
fun GHBadge(text: String, color: Color) {
    Text(
        text = text,
        style = GHType.caption.copy(fontWeight = FontWeight.Medium, color = color),
        modifier = Modifier
            .background(color.copy(alpha = 0.15f), RoundedCornerShape(10.dp))
            .padding(horizontal = 8.dp, vertical = 2.dp)
    )
}

// designsystem/components/GHCodeBlock.kt
@Composable
fun GHCodeBlock(code: String, modifier: Modifier = Modifier) {
    Box(
        modifier = modifier
            .fillMaxWidth()
            .background(GHColors.bgTertiary, RoundedCornerShape(6.dp))
            .border(1.dp, GHColors.borderDefault, RoundedCornerShape(6.dp))
            .padding(12.dp)
            .horizontalScroll(rememberScrollState())
    ) {
        Text(text = code, style = GHType.code, color = GHColors.textPrimary)
    }
}

// designsystem/components/GHStatusDot.kt
@Composable
fun GHStatusDot(status: DeviceStatus) {
    val color = when (status) {
        DeviceStatus.Online -> GHColors.accentGreen
        DeviceStatus.Pending -> GHColors.accentYellow
        DeviceStatus.Error -> GHColors.accentRed
        DeviceStatus.Offline -> GHColors.textTertiary
    }
    Box(modifier = Modifier.size(8.dp).background(color, CircleShape))
}
```

Implement remaining components (GHBanner, GHInput, GHDiffView, GHList, GHTabBar) following the same pattern.

---

## P1 Tasks (Feature Parity with iOS P0)

### ANDROID-T01: Project Setup

1. Create project, min SDK 29, Compose.
2. Add dependencies (OkHttp, protobuf-kotlin-lite, JetBrains Mono font).
3. Generate Kotlin Protobuf classes.
4. Implement full `designsystem/` package with all GH components.
5. Bottom navigation: Chat, Sessions, Git, Files, Settings.

**Acceptance**: App launches in dark mode with GH-style UI matching iOS.

### ANDROID-T02: Network Layer

WebSocketClient, ProtobufCodec, ConnectionManager, MessageDispatcher — same protocol as iOS. Use OkHttp WebSocket.

### ANDROID-T03: Chat Screen (Thread-based)

Same layout as iOS `ChatView`. Key difference: use Compose `ModalNavigationDrawer` for session sidebar instead of custom swipe gesture.

```kotlin
@Composable
fun ChatScreen(vm: ChatViewModel) {
    val drawerState = rememberDrawerState(DrawerValue.Closed)

    ModalNavigationDrawer(
        drawerState = drawerState,
        drawerContent = { SessionDrawer(vm.sessions, vm.activeSessionId, onSelect = { ... }) }
    ) {
        Column(modifier = Modifier.fillMaxSize().background(GHColors.bgPrimary)) {
            ConnectionStatusBar(state = vm.connectionState)

            // Thread messages
            LazyColumn(modifier = Modifier.weight(1f)) {
                items(vm.messages) { msg ->
                    ThreadMessage(message = msg)
                    Divider(color = GHColors.borderMuted)
                }
            }

            // Approval banner
            vm.pendingApproval?.let {
                ApprovalBanner(request = it, onApprove = { vm.respondApproval(true) }, onReject = { vm.respondApproval(false) })
            }

            // Input bar
            PromptInputBar(text = vm.inputText, isLoading = vm.isLoading, onSend = vm::sendPrompt)
        }
    }
}
```

### ANDROID-T04: Approval Banner

Same visual spec as iOS `ApprovalBannerView`. Yellow left border, shield icon, command preview in `GHCodeBlock`, Approve/Reject buttons.

### ANDROID-T05: Session Management

`ModalNavigationDrawer` with session list. Create, switch, close sessions.

### ANDROID-T06: Settings

Same structure as iOS: connection mode picker, direct/node address fields, auth token.

### ANDROID-T07: Device List (Connection Node)

Same as iOS: list online agents, tap to connect.

**Acceptance**: Android app has visual and functional parity with iOS P0. Same dark GitHub theme, same thread interaction, same approval flow.

---

## P3+ Tasks

Same as iOS equivalents, ported to Kotlin/Compose:
- **ANDROID-T08**: QR Code Pairing (CameraX + ML Kit)
- **ANDROID-T09**: Noise Protocol E2E (Noise-Java)
- **ANDROID-T10**: Push Notifications (FCM)
- **ANDROID-T11**: Extended Keyboard (Compose custom bar)
- **ANDROID-T12**: Git Feature
- **ANDROID-T13**: File Browser

---

## Cross-Platform Design Consistency Checklist

| Token/Component | iOS | Android | Must match |
|----------------|-----|---------|-----------|
| Color hex values | `GHColors` struct | `GHColors` object | Exact same hex codes |
| Font sizes | `GHTypography` | `GHType` | Same pt/sp values |
| Corner radii | 12dp cards, 6dp buttons | Same | Exact |
| Border widths | 1px everywhere | Same | Exact |
| Status dot size | 8pt | 8dp | Same |
| Badge padding | 8h x 2v | Same | Same |
| Dark mode default | Yes | Yes | Yes |
| Thread message layout | Role icon → name → timestamp | Same | Pixel-close |
| Approval banner | Yellow left border, inline | Same | Same |
| Code blocks | bg-tertiary, monospace, 1px border | Same | Same |
