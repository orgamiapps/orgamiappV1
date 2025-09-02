package com.stormdeve.orgami

import io.flutter.embedding.android.FlutterActivity
import android.os.Bundle
// import com.facebook.FacebookSdk
// import com.facebook.appevents.AppEventsLogger

class MainActivity: FlutterActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        
        // Facebook SDK initialization disabled to prevent configuration errors
        // FacebookSdk.sdkInitialize(applicationContext)
        // AppEventsLogger.activateApp(application)
    }
}
