package com.mrt.app.navigation

import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.outlined.ViewList
import androidx.compose.material.icons.outlined.ChatBubbleOutline
import androidx.compose.material.icons.outlined.FolderOpen
import androidx.compose.material.icons.outlined.Settings
import androidx.compose.material.icons.outlined.Source
import androidx.compose.material3.Scaffold
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.runtime.collectAsState
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import com.mrt.app.designsystem.components.GHTabBar
import com.mrt.app.designsystem.components.GHTabItem
import com.mrt.app.designsystem.theme.GHColors
import com.mrt.app.core.network.ConnectionManager
import com.mrt.app.core.storage.PreferenceSnapshot
import com.mrt.app.core.storage.Preferences
import com.mrt.app.features.chat.ChatScreen
import com.mrt.app.features.chat.ChatViewModel
import com.mrt.app.features.placeholders.FilesPlaceholderScreen
import com.mrt.app.features.placeholders.GitPlaceholderScreen
import com.mrt.app.features.sessions.SessionsScreen
import com.mrt.app.features.sessions.SessionViewModel
import com.mrt.app.features.settings.SettingsScreen

private enum class AppDestination(
    val item: GHTabItem,
) {
    Chat(
        item = GHTabItem("chat", "Chat", Icons.Outlined.ChatBubbleOutline),
    ),
    Sessions(
        item = GHTabItem("sessions", "Sessions", Icons.AutoMirrored.Outlined.ViewList),
    ),
    Git(
        item = GHTabItem("git", "Git", Icons.Outlined.Source),
    ),
    Files(
        item = GHTabItem("files", "Files", Icons.Outlined.FolderOpen),
    ),
    Settings(
        item = GHTabItem("settings", "Settings", Icons.Outlined.Settings),
    ),
}

@Composable
fun AppNavigation() {
    val context = LocalContext.current
    val connectionManager = remember { ConnectionManager() }
    val preferences = remember { Preferences.create(context.applicationContext) }
    val chatViewModel = remember { ChatViewModel(connectionManager = connectionManager) }
    val sessionViewModel = remember { SessionViewModel(connectionManager = connectionManager) }
    val preferenceSnapshot by preferences.snapshot.collectAsState(initial = PreferenceSnapshot())

    var selectedDestination by rememberSaveable { mutableStateOf(AppDestination.Chat.name) }
    val destination = AppDestination.valueOf(selectedDestination)

    LaunchedEffect(preferenceSnapshot.connectionConfigurationSignature) {
        chatViewModel.connectIfNeeded(
            host = preferenceSnapshot.directHost,
            port = preferenceSnapshot.directPort,
            mode = preferenceSnapshot.connectionMode,
        )
    }

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
        Box(modifier = Modifier.fillMaxSize()) {
            when (destination) {
                AppDestination.Chat -> ChatScreen(
                    viewModel = chatViewModel,
                    sessionViewModel = sessionViewModel,
                    modifier = Modifier.padding(innerPadding),
                )

                AppDestination.Sessions -> SessionsScreen(
                    viewModel = sessionViewModel,
                    connectionState = chatViewModel.connectionState,
                    modifier = Modifier.padding(innerPadding),
                )

                AppDestination.Git -> GitPlaceholderScreen(modifier = Modifier.padding(innerPadding))
                AppDestination.Files -> FilesPlaceholderScreen(modifier = Modifier.padding(innerPadding))
                AppDestination.Settings -> SettingsScreen(
                    preferences = preferences,
                    modifier = Modifier.padding(innerPadding),
                )
            }
        }
    }
}
