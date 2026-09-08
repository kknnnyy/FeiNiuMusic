package com.feiniu.music

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Intent
import android.media.MediaMetadata
import android.media.session.MediaSession
import android.media.session.PlaybackState
import android.os.Build
import android.os.IBinder
import android.util.Log

class BluetoothLyricService : Service() {

    private var mediaSession: MediaSession? = null
    private val CHANNEL_ID = "BluetoothLyricChannel"
    private val NOTIFICATION_ID = 10086

    companion object {
        private var instance: BluetoothLyricService? = null

        fun updateLyric(lyric: String, artist: String = "FeiNiuMusic") {
            instance?.updateLyrics(lyric, artist)
        }
    }

    override fun onCreate() {
        super.onCreate()
        instance = this
        createNotificationChannel()
        setupMediaSession()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val lyric = intent?.getStringExtra("lyric") ?: ""
        val artist = intent?.getStringExtra("artist") ?: "FeiNiuMusic"
        
        startForeground(NOTIFICATION_ID, createNotification(lyric))
        updateLyrics(lyric, artist)
        
        return START_STICKY
    }

    private fun setupMediaSession() {
        mediaSession = MediaSession(this, "BluetoothLyricService").apply {
            setCallback(object : MediaSession.Callback() {
                override fun onPlay() {
                    // Forward to main app if needed, but for now just keep state
                    updatePlaybackState(PlaybackState.STATE_PLAYING)
                }

                override fun onPause() {
                    updatePlaybackState(PlaybackState.STATE_PAUSED)
                }
            })
            isActive = true
        }
        updatePlaybackState(PlaybackState.STATE_PLAYING)
    }

    private fun updatePlaybackState(state: Int) {
        val playbackState = PlaybackState.Builder()
            .setActions(PlaybackState.ACTION_PLAY or PlaybackState.ACTION_PAUSE or PlaybackState.ACTION_STOP or PlaybackState.ACTION_SKIP_TO_NEXT or PlaybackState.ACTION_SKIP_TO_PREVIOUS)
            .setState(state, PlaybackState.PLAYBACK_POSITION_UNKNOWN, 1.0f)
            .build()
        mediaSession?.setPlaybackState(playbackState)
    }

    private fun updateLyrics(lyric: String, artist: String) {
        Log.d("BluetoothLyricService", "Pushing lyric: $lyric")

        val metadata = MediaMetadata.Builder()
            .putString(MediaMetadata.METADATA_KEY_TITLE, lyric.ifEmpty { " " })
            .putString(MediaMetadata.METADATA_KEY_ARTIST, artist)
            .build()
        
        mediaSession?.setMetadata(metadata)
        
        // The "nudge": update playback state to trigger AVRCP broadcast
        updatePlaybackState(PlaybackState.STATE_PLAYING)
    }

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val serviceChannel = NotificationChannel(
                CHANNEL_ID,
                "Bluetooth Lyric Service Channel",
                NotificationManager.IMPORTANCE_LOW
            )
            val manager = getSystemService(NotificationManager::class.java)
            manager.createNotificationChannel(serviceChannel)
        }
    }

    private fun createNotification(lyric: String): Notification {
        val notificationIntent = Intent(this, MainActivity::class.java)
        val pendingIntent = PendingIntent.getActivity(
            this, 0, notificationIntent,
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) PendingIntent.FLAG_IMMUTABLE else 0
        )

        val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Notification.Builder(this, CHANNEL_ID)
        } else {
            Notification.Builder(this)
        }

        return builder
            .setContentTitle("车机蓝牙歌词推送中")
            .setContentText(lyric.ifEmpty { "准备就绪" })
            .setSmallIcon(android.R.drawable.ic_media_play)
            .setContentIntent(pendingIntent)
            .build()
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onDestroy() {
        instance = null
        mediaSession?.release()
        super.onDestroy()
    }
}
