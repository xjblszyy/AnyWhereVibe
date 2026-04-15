package com.mrt.app.navigation

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.ChatBubbleOutline
import androidx.compose.material.icons.outlined.FolderOpen
import androidx.compose.material.icons.outlined.Settings
import androidx.compose.material.icons.outlined.Source
import androidx.compose.material.icons.outlined.ViewList
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import com.mrt.app.designsystem.components.GHBadge
import com.mrt.app.designsystem.components.GHBanner
import com.mrt.app.designsystem.components.GHBannerTone
import com.mrt.app.designsystem.components.GHButton
import com.mrt.app.designsystem.components.GHButtonStyle
import com.mrt.app.designsystem.components.GHCard
import com.mrt.app.designsystem.components.GHCodeBlock
import com.mrt.app.designsystem.components.GHDiffKind
import com.mrt.app.designsystem.components.GHDiffLine
import com.mrt.app.designsystem.components.GHDiffView
import com.mrt.app.designsystem.components.GHInput
import com.mrt.app.designsystem.components.GHList
import com.mrt.app.designsystem.components.GHListItem
import com.mrt.app.designsystem.components.GHStatus
import com.mrt.app.designsystem.components.GHTabBar
import com.mrt.app.designsystem.components.GHTabItem
import com.mrt.app.designsystem.theme.GHColors
import com.mrt.app.designsystem.theme.GHSpacing
import com.mrt.app.designsystem.theme.GHType

private enum class AppDestination(
    val label: String,
    val item: GHTabItem,
) {
    Chat(
        label = "Chat",
        item = GHTabItem("chat", "Chat", Icons.Outlined.ChatBubbleOutline),
    ),
    Sessions(
        label = "Sessions",
        item = GHTabItem("sessions", "Sessions", Icons.Outlined.ViewList, badge = "3"),
    ),
    Git(
        label = "Git",
        item = GHTabItem("git", "Git", Icons.Outlined.Source),
    ),
    Files(
        label = "Files",
        item = GHTabItem("files", "Files", Icons.Outlined.FolderOpen),
    ),
    Settings(
        label = "Settings",
        item = GHTabItem("settings", "Settings", Icons.Outlined.Settings),
    ),
}

@Composable
fun AppNavigation() {
    var selectedDestination by rememberSaveable { mutableStateOf(AppDestination.Chat.name) }
    val destination = AppDestination.valueOf(selectedDestination)

    Scaffold(
        modifier = Modifier.fillMaxSize(),
        containerColor = GHColors.BgPrimary,
        bottomBar = {
            GHTabBar(
                items = AppDestination.entries.map { it.item },
                selectedKey = destination.item.key,
                onSelect = { key ->
                    selectedDestination = AppDestination.entries.first { it.item.key == key }.name
                },
            )
        },
    ) { innerPadding ->
        Column(
            modifier = Modifier
                .fillMaxSize()
                .background(GHColors.BgPrimary)
                .padding(innerPadding)
                .padding(horizontal = GHSpacing.Lg)
                .verticalScroll(rememberScrollState()),
            verticalArrangement = Arrangement.spacedBy(GHSpacing.Lg),
        ) {
            Spacer(modifier = Modifier.height(8.dp))
            Header(destination.label)
            when (destination) {
                AppDestination.Chat -> ChatPlaceholder()
                AppDestination.Sessions -> SessionsPlaceholder()
                AppDestination.Git -> GitPlaceholder()
                AppDestination.Files -> FilesPlaceholder()
                AppDestination.Settings -> SettingsPlaceholder()
            }
            Spacer(modifier = Modifier.height(GHSpacing.Xl))
        }
    }
}

@Composable
private fun Header(title: String) {
    Column(verticalArrangement = Arrangement.spacedBy(GHSpacing.Xs)) {
        Text(
            text = title,
            style = GHType.TitleLg,
            color = GHColors.TextPrimary,
        )
        Text(
            text = "Android shell bootstrap with a dark-first GitHub-style Compose system.",
            style = GHType.Body,
            color = GHColors.TextSecondary,
        )
    }
}

@Composable
private fun ChatPlaceholder() {
    var prompt by rememberSaveable { mutableStateOf("") }

    GHBanner(
        title = "Shell only",
        message = "Networking, protobuf transport, and feature view models are intentionally out of scope for this stage.",
        tone = GHBannerTone.Info,
    )
    GHCard {
        Text("Prompt", style = GHType.BodySm, color = GHColors.TextSecondary)
        GHInput(
            value = prompt,
            onValueChange = { prompt = it },
            placeholder = "Ask the desktop agent to explain the latest diff...",
            minLines = 4,
        )
        Row(horizontalArrangement = Arrangement.spacedBy(GHSpacing.Sm)) {
            GHButton(text = "Send", onClick = {}, style = GHButtonStyle.Primary)
            GHButton(text = "Clear", onClick = { prompt = "" }, style = GHButtonStyle.Secondary)
        }
    }
    GHCodeBlock(
        code = """
            session: preview-shell
            status: disconnected
            transport: not wired
        """.trimIndent(),
    )
}

@Composable
private fun SessionsPlaceholder() {
    GHCard {
        Text("Recent sessions", style = GHType.Title, color = GHColors.TextPrimary)
        GHList(
            items = listOf(
                GHListItem("1", "release-train", "Awaiting reconnect on office mac mini", GHStatus.Pending, "LAN"),
                GHListItem("2", "feature/android-shell", "Ready for shell review", GHStatus.Online, "LIVE"),
                GHListItem("3", "infra-audit", "Stopped after git clean check", GHStatus.Offline, "IDLE"),
            ),
        )
    }
}

@Composable
private fun GitPlaceholder() {
    GHBanner(
        title = "Git surface pending",
        message = "This shell includes a preview-safe diff component, but no repository actions yet.",
        tone = GHBannerTone.Warning,
    )
    GHDiffView(
        title = "bootstrap.patch",
        lines = listOf(
            GHDiffLine(GHDiffKind.Context, "android/app/src/main/java/com/mrt/app/MainActivity.kt"),
            GHDiffLine(GHDiffKind.Added, "setContent { MRTTheme(darkTheme = true) { AppNavigation() } }"),
            GHDiffLine(GHDiffKind.Added, "Create GitHub-style components under designsystem/components"),
            GHDiffLine(GHDiffKind.Removed, "TODO(\"Android shell missing\")"),
        ),
    )
}

@Composable
private fun FilesPlaceholder() {
    GHCard {
        Text("Workspace", style = GHType.Title, color = GHColors.TextPrimary)
        Row(horizontalArrangement = Arrangement.spacedBy(GHSpacing.Sm)) {
            GHBadge(text = "android/", color = GHColors.AccentBlue)
            GHBadge(text = "ios/", color = GHColors.AccentPurple)
            GHBadge(text = "docs/", color = GHColors.AccentOrange)
        }
        Text(
            text = "The file surface is a placeholder for browsing local agent outputs and repo artifacts.",
            style = GHType.Body,
            color = GHColors.TextSecondary,
        )
        GHCodeBlock(
            code = """
                android/
                  app/
                    src/main/java/com/mrt/app/
                    src/main/res/values/themes.xml
            """.trimIndent(),
        )
    }
}

@Composable
private fun SettingsPlaceholder() {
    var host by rememberSaveable { mutableStateOf("192.168.0.24") }
    var port by rememberSaveable { mutableStateOf("8080") }

    GHCard {
        Text("Connection defaults", style = GHType.Title, color = GHColors.TextPrimary)
        GHInput(
            value = host,
            onValueChange = { host = it },
            placeholder = "Agent host",
            singleLine = true,
        )
        GHInput(
            value = port,
            onValueChange = { port = it },
            placeholder = "Agent port",
            singleLine = true,
        )
        Row(horizontalArrangement = Arrangement.spacedBy(GHSpacing.Sm)) {
            GHButton(text = "Save", onClick = {}, style = GHButtonStyle.Primary)
            GHButton(text = "Reset", onClick = {
                host = "192.168.0.24"
                port = "8080"
            }, style = GHButtonStyle.Secondary)
        }
    }
    GHBanner(
        title = "Design token note",
        message = "Code blocks use the platform monospace family for now; a bundled JetBrains Mono asset can be swapped in once font resources are added.",
        tone = GHBannerTone.Neutral,
    )
}
