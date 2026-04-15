package com.mrt.app.core.storage

import android.content.Context
import androidx.datastore.core.DataStore
import androidx.datastore.preferences.core.Preferences as DataStorePreferences
import androidx.datastore.preferences.core.edit
import androidx.datastore.preferences.core.intPreferencesKey
import androidx.datastore.preferences.core.stringPreferencesKey
import androidx.datastore.preferences.preferencesDataStore
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.distinctUntilChanged
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.flow.map

enum class ConnectionMode {
    DIRECT,
    MANAGED,
}

data class PreferenceSnapshot(
    val directHost: String = "127.0.0.1",
    val directPort: Int = 9876,
    val connectionMode: ConnectionMode = ConnectionMode.DIRECT,
) {
    val connectionConfigurationSignature: String
        get() = "${connectionMode.name}|$directHost|$directPort"
}

private val Context.preferencesDataStore by preferencesDataStore(name = "anywherevibe_preferences")

class Preferences(
    private val dataStore: DataStore<DataStorePreferences>,
) {
    companion object {
        fun create(context: Context): Preferences = Preferences(context.preferencesDataStore)
    }

    private object Keys {
        val DirectHost = stringPreferencesKey("direct.host")
        val DirectPort = intPreferencesKey("direct.port")
        val ConnectionMode = stringPreferencesKey("connection.mode")
    }

    val snapshot: Flow<PreferenceSnapshot> = dataStore.data.map { preferences ->
        PreferenceSnapshot(
            directHost = preferences[Keys.DirectHost] ?: "127.0.0.1",
            directPort = preferences[Keys.DirectPort] ?: 9876,
            connectionMode = preferences[Keys.ConnectionMode]
                ?.let(ConnectionMode::valueOf)
                ?: ConnectionMode.DIRECT,
        )
    }

    val directHost: Flow<String> = snapshot.map { it.directHost }.distinctUntilChanged()
    val directPort: Flow<Int> = snapshot.map { it.directPort }.distinctUntilChanged()
    val connectionMode: Flow<ConnectionMode> =
        snapshot.map { it.connectionMode }.distinctUntilChanged()

    suspend fun current(): PreferenceSnapshot = snapshot.first()

    suspend fun setDirectHost(value: String) {
        dataStore.edit { preferences ->
            preferences[Keys.DirectHost] = value
        }
    }

    suspend fun setDirectPort(value: Int) {
        dataStore.edit { preferences ->
            preferences[Keys.DirectPort] = value
        }
    }

    suspend fun setConnectionMode(value: ConnectionMode) {
        dataStore.edit { preferences ->
            preferences[Keys.ConnectionMode] = value.name
        }
    }
}
