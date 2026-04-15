package com.mrt.app.features.sessions

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import com.mrt.app.core.network.ConnectionState
import com.mrt.app.designsystem.components.GHBanner
import com.mrt.app.designsystem.components.GHBannerTone
import com.mrt.app.designsystem.components.GHButton
import com.mrt.app.designsystem.components.GHButtonStyle
import com.mrt.app.designsystem.components.GHCard
import com.mrt.app.designsystem.components.GHInput
import com.mrt.app.designsystem.theme.GHColors
import com.mrt.app.designsystem.theme.GHSpacing
import com.mrt.app.designsystem.theme.GHType

@Composable
fun SessionsScreen(
    viewModel: SessionViewModel,
    connectionState: ConnectionState,
    modifier: Modifier = Modifier,
) {
    var draftName by rememberSaveable { mutableStateOf("") }

    Column(
        modifier = modifier
            .fillMaxSize()
            .background(GHColors.BgPrimary)
            .verticalScroll(rememberScrollState())
            .padding(GHSpacing.Xl),
        verticalArrangement = Arrangement.spacedBy(GHSpacing.Lg),
    ) {
        androidx.compose.material3.Text(
            text = "Sessions",
            style = GHType.TitleLg,
            color = GHColors.TextPrimary,
        )

        GHCard {
            Row(horizontalArrangement = Arrangement.spacedBy(GHSpacing.Sm)) {
                GHInput(
                    value = draftName,
                    onValueChange = { draftName = it },
                    placeholder = "Name",
                    singleLine = true,
                    modifier = Modifier.weight(1f),
                )
                GHButton(
                    text = "Create",
                    onClick = {
                        viewModel.createSession(named = draftName)
                        draftName = ""
                    },
                    style = GHButtonStyle.Primary,
                    enabled = draftName.trim().isNotEmpty() && viewModel.canCreateSession(connectionState),
                )
            }

            if (!viewModel.canCreateSession(connectionState)) {
                GHBanner(
                    title = "Agent required",
                    message = "Connect to the agent before creating a remote session.",
                    tone = GHBannerTone.Info,
                    modifier = Modifier.padding(top = GHSpacing.Md),
                )
            }
        }

        GHCard {
            androidx.compose.material3.Text(
                text = "Available",
                style = GHType.Title,
                color = GHColors.TextPrimary,
                modifier = Modifier.padding(bottom = GHSpacing.Md),
            )
            Column(verticalArrangement = Arrangement.spacedBy(GHSpacing.Sm)) {
                viewModel.sessions.forEach { session ->
                    SessionRow(
                        session = session,
                        isActive = session.id == viewModel.activeSessionId,
                        onSelect = { viewModel.selectSession(session.id) },
                        onClose = { viewModel.closeSession(session.id) },
                    )
                }
            }
        }
    }
}
