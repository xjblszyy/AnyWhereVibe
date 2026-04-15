package com.mrt.app.features.sessions

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material3.ModalDrawerSheet
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import com.mrt.app.core.network.ConnectionState
import com.mrt.app.designsystem.components.GHBanner
import com.mrt.app.designsystem.components.GHBannerTone
import com.mrt.app.designsystem.components.GHButton
import com.mrt.app.designsystem.components.GHButtonStyle
import com.mrt.app.designsystem.components.GHInput
import com.mrt.app.designsystem.theme.GHColors
import com.mrt.app.designsystem.theme.GHSpacing
import com.mrt.app.designsystem.theme.GHType

@Composable
fun SessionDrawer(
    viewModel: SessionViewModel,
    connectionState: ConnectionState,
    modifier: Modifier = Modifier,
) {
    var draftName by rememberSaveable { mutableStateOf("") }

    ModalDrawerSheet(
        modifier = modifier.fillMaxHeight(),
        drawerContainerColor = GHColors.BgSecondary,
    ) {
        Column(
            modifier = Modifier.padding(GHSpacing.Lg),
            verticalArrangement = Arrangement.spacedBy(GHSpacing.Md),
        ) {
            Text("Sessions", style = GHType.Title, color = GHColors.TextPrimary)
            GHInput(
                value = draftName,
                onValueChange = { draftName = it },
                placeholder = "New session",
                singleLine = true,
            )
            GHButton(
                text = "New",
                onClick = {
                    viewModel.createSession(named = draftName)
                    draftName = ""
                },
                style = GHButtonStyle.Primary,
                enabled = draftName.trim().isNotEmpty() && viewModel.canCreateSession(connectionState),
            )
            if (!viewModel.canCreateSession(connectionState)) {
                GHBanner(
                    title = "Agent required",
                    message = "Session creation is available once the agent is connected.",
                    tone = GHBannerTone.Info,
                )
            }
            LazyColumn(verticalArrangement = Arrangement.spacedBy(GHSpacing.Sm)) {
                items(viewModel.sessions, key = { it.id }) { session ->
                    SessionRow(
                        session = session,
                        isActive = session.id == viewModel.activeSessionId,
                        onSelect = { viewModel.selectSession(session.id) },
                        onCancel = { viewModel.cancelTask(session.id) },
                        onClose = { viewModel.closeSession(session.id) },
                    )
                }
            }
        }
    }
}
