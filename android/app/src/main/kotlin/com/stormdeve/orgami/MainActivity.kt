package com.stormdeve.orgami

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import android.os.Bundle
// import com.attendus.app.OnnxNlpPlugin // Temporarily disabled
// import com.facebook.FacebookSdk
// import com.facebook.appevents.AppEventsLogger

class MainActivity: FlutterActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        
        // Facebook SDK initialization disabled to prevent configuration errors
        // FacebookSdk.sdkInitialize(applicationContext)
        // AppEventsLogger.activateApp(application)
    }
    
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        
        // ONNX NLP Plugin temporarily disabled due to missing model files
        // TODO: Re-enable after adding distilbert_quantized.onnx to assets/models/
        // flutterEngine.plugins.add(OnnxNlpPlugin())
    }
}
