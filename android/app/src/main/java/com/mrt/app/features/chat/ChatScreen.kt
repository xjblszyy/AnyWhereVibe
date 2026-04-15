package com.mrt.app.features.chat

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.outlined.MenuOpen
import androidx.compose.material.icons.automirrored.outlined.Send
import androidx.compose.material3.ModalNavigationDrawer
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.rememberDrawerState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.unit.dp
import com.mrt.app.designsystem.components.GHBanner
import com.mrt.app.designsystem.components.GHBannerTone
import com.mrt.app.designsystem.components.GHButton
import com.mrt.app.designsystem.components.GHButtonStyle
import com.mrt.app.designsystem.components.GHInput
import com.mrt.app.designsystem.theme.GHColors
import com.mrt.app.designsystem.theme.GHSpacing
import com.mrt.app.designsystem.theme.GHType
import com.mrt.app.features.sessions.SessionDrawer
import com.mrt.app.features.sessions.SessionViewModel
import kotlinx.coroutines.launch

@Composable
fun ChatScreen(
    viewModel: ChatViewModel,
    sessionViewModel: SessionViewModel,
    modifier: Modifier = Modifier,
) {
    val drawerState = rememberDrawerState(initialValue = androidx.compose.material3.DrawerValue.Closed)
    val coroutineScope = rememberCoroutineScope()
    val listState = rememberLazyListState()

    LaunchedEffect(sessionViewModel.activeSessionId) {
        viewModel.activeSessionId = sessionViewModel.activeSessionId
    }
    LaunchedEffect(viewModel.lastMessageSignature) {
        val lastIndex = viewModel.messages.lastIndex
        if (lastIndex >= 0) {
            listState.animateScrollToItem(lastIndex)
        }
    }

    ModalNavigationDrawer(
        drawerState = drawerState,
        drawerContent = {
            SessionDrawer(
                viewModel = sessionViewModel,
                connectionState = viewModel.connectionState,
            )
        },
    ) {
        Scaffold(
            modifier = modifier.fillMaxSize(),
            containerColor = GHColors.BgPrimary,
        ) { innerPadding ->
            Column(
                modifier = Modifier
                    .fillMaxSize()
                    .background(GHColors.BgPrimary)
                    .padding(innerPadding),
                verticalArrangement = Arrangement.spacedBy(GHSpacing.Md),
            ) {
                Row(
                    modifier = Modifier
                        .fillMaxWidth()
                        .padding(horizontal = GHSpacing.Lg, vertical = GHSpacing.Md),
                    horizontalArrangement = Arrangement.spacedBy(GHSpacing.Sm),
                ) {
                    GHButton(
                        text = "Sessions",
                        onClick = { coroutineScope.launch { drawerState.open() } },
                        style = GHButtonStyle.Secondary,
                        icon = Icons.AutoMirrored.Outlined.MenuOpen,
                    )
                    Column {
                        Text(
                            text = sessionViewModel.sessions.firstOrNull { it.id == sessionViewModel.activeSessionId }?.name ?: "Chat",
                            style = GHType.Title,
                            color = GHColors.TextPrimary,
                        )
                        Text(
                            text = "Threaded terminal chat",
                            style = GHType.Caption,
                            color = GHColors.TextSecondary,
                        )
                    }
                }

                ConnectionStatusBar(state = viewModel.connectionState)

                LazyColumn(
                    state = listState,
                    modifier = Modifier
                        .weight(1f)
                        .padding(horizontal = GHSpacing.Lg),
                    verticalArrangement = Arrangement.spacedBy(GHSpacing.Md),
                ) {
                    if (viewModel.messages.isEmpty()) {
                        item {
                            GHBanner(
                                title = "No messages yet",
                                message = "Send a prompt once your LAN settings are configured.",
                                tone = GHBannerTone.Info,
                            )
                        }
                    }

                    items(viewModel.messages, key = { it.id }) { message ->
                        ThreadMessage(message = message)
                    }
                }

                viewModel.pendingApproval?.let { approval ->
                    ApprovalBanner(
                        request = approval,
                        onApprove = { coroutineScope.launch { viewModel.respondToApproval(true) } },
                        onReject = { coroutineScope.launch { viewModel.respondToApproval(false) } },
                        modifier = Modifier.padding(horizontal = GHSpacing.Lg),
                    )
                }

                Column(
                    modifier = Modifier
                        .fillMaxWidth()
                        .padding(horizontal = GHSpacing.Lg, vertical = GHSpacing.Md),
                    verticalArrangement = Arrangement.spacedBy(GHSpacing.Xs),
                ) {
                    Row(
                        modifier = Modifier.fillMaxWidth(),
                        horizontalArrangement = Arrangement.spacedBy(GHSpacing.Sm),
                    ) {
                        GHInput(
                            value = viewModel.inputText,
                            onValueChange = { viewModel.inputText = it },
                            placeholder = viewModel.inputAssistiveMessage ?: "Send a prompt to the active session",
                            modifier = Modifier
                                .weight(1f)
                                .testTag("chatComposerInput"),
                            minLines = 2,
                        )
                        GHButton(
                            text = viewModel.sendButtonLabel,
                            onClick = { coroutineScope.launch { viewModel.sendPrompt() } },
                            style = GHButtonStyle.Primary,
                            icon = Icons.AutoMirrored.Outlined.Send,
                            enabled = viewModel.canSendPrompt,
                            modifier = Modifier
                                .padding(top = 4.dp)
                                .testTag("chatSendButton"),
                        )
                    }

                    viewModel.inputAssistiveMessage?.let { helperMessage ->
                        Text(
                            text = helperMessage,
                            style = GHType.Caption,
                            color = GHColors.TextSecondary,
                        )
                    }
                }
            }
        }
    }
}
