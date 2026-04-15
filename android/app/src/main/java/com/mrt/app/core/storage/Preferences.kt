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
    val nodeUrl: String = "",
    val authToken: String = "",
    val managedTargetDeviceId: String = "",
    val managedTargetDeviceName: String = "",
) {
    val connectionConfigurationSignature: String
        get() = "${connectionMode.name}|$directHost|$directPort|$nodeUrl|$authToken|$managedTargetDeviceId|$managedTargetDeviceName"
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
        val NodeUrl = stringPreferencesKey("node.url")
        val AuthToken = stringPreferencesKey("node.auth_token")
        val ManagedTargetDeviceId = stringPreferencesKey("node.target_device_id")
        val ManagedTargetDeviceName = stringPreferencesKey("node.target_device_name")
    }

    val snapshot: Flow<PreferenceSnapshot> = dataStore.data.map { preferences ->
        PreferenceSnapshot(
            directHost = preferences[Keys.DirectHost] ?: "127.0.0.1",
            directPort = preferences[Keys.DirectPort] ?: 9876,
            connectionMode = preferences[Keys.ConnectionMode]
                ?.let(ConnectionMode::valueOf)
                ?: ConnectionMode.DIRECT,
            nodeUrl = preferences[Keys.NodeUrl] ?: "",
            authToken = preferences[Keys.AuthToken] ?: "",
            managedTargetDeviceId = preferences[Keys.ManagedTargetDeviceId] ?: "",
            managedTargetDeviceName = preferences[Keys.ManagedTargetDeviceName] ?: "",
        )
    }

    val directHost: Flow<String> = snapshot.map { it.directHost }.distinctUntilChanged()
    val directPort: Flow<Int> = snapshot.map { it.directPort }.distinctUntilChanged()
    val connectionMode: Flow<ConnectionMode> =
        snapshot.map { it.connectionMode }.distinctUntilChanged()
    val nodeUrl: Flow<String> = snapshot.map { it.nodeUrl }.distinctUntilChanged()
    val authToken: Flow<String> = snapshot.map { it.authToken }.distinctUntilChanged()
    val managedTargetDeviceId: Flow<String> =
        snapshot.map { it.managedTargetDeviceId }.distinctUntilChanged()
    val managedTargetDeviceName: Flow<String> =
        snapshot.map { it.managedTargetDeviceName }.distinctUntilChanged()

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

    suspend fun setNodeUrl(value: String) {
        dataStore.edit { preferences ->
            preferences[Keys.NodeUrl] = value
        }
    }

    suspend fun setAuthToken(value: String) {
        dataStore.edit { preferences ->
            preferences[Keys.AuthToken] = value
        }
    }

    suspend fun setManagedTargetDevice(deviceId: String, deviceName: String) {
        dataStore.edit { preferences ->
            preferences[Keys.ManagedTargetDeviceId] = deviceId
            preferences[Keys.ManagedTargetDeviceName] = deviceName
        }
    }
}
