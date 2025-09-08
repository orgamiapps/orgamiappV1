package com.attendus.app

import android.content.Context
import android.util.Log
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.MethodCallHandler
import io.flutter.plugin.common.MethodChannel.Result
import ai.onnxruntime.*
import java.nio.FloatBuffer
import java.nio.LongBuffer
import java.util.concurrent.Executors
import kotlinx.coroutines.*

/**
 * ONNX Runtime plugin for on-device NLP with DistilBERT
 */
class OnnxNlpPlugin : FlutterPlugin, MethodCallHandler {
    private lateinit var channel: MethodChannel
    private lateinit var context: Context
    private var ortSession: OrtSession? = null
    private var ortEnvironment: OrtEnvironment? = null
    private val executor = Executors.newSingleThreadExecutor()
    private val scope = CoroutineScope(Dispatchers.IO)

    companion object {
        private const val TAG = "OnnxNlpPlugin"
        private const val CHANNEL_NAME = "attendus/onnx_nlp"
        private const val MAX_SEQUENCE_LENGTH = 128
    }

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        context = binding.applicationContext
        channel = MethodChannel(binding.binaryMessenger, CHANNEL_NAME)
        channel.setMethodCallHandler(this)
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel.setMethodCallHandler(null)
        dispose()
    }

    override fun onMethodCall(call: MethodCall, result: Result) {
        when (call.method) {
            "initializeModel" -> {
                scope.launch {
                    try {
                        val modelPath = call.argument<String>("modelPath") 
                            ?: "assets/models/distilbert_quantized.onnx"
                        val success = initializeModel(modelPath)
                        withContext(Dispatchers.Main) {
                            result.success(success)
                        }
                    } catch (e: Exception) {
                        withContext(Dispatchers.Main) {
                            result.error("INIT_ERROR", "Failed to initialize model: ${e.message}", null)
                        }
                    }
                }
            }
            "runInference" -> {
                scope.launch {
                    try {
                        val inputIds = call.argument<List<Int>>("inputIds") ?: emptyList()
                        val attentionMask = call.argument<List<Int>>("attentionMask") ?: emptyList()
                        
                        val output = runInference(inputIds, attentionMask)
                        withContext(Dispatchers.Main) {
                            result.success(output)
                        }
                    } catch (e: Exception) {
                        withContext(Dispatchers.Main) {
                            result.error("INFERENCE_ERROR", "Inference failed: ${e.message}", null)
                        }
                    }
                }
            }
            "dispose" -> {
                dispose()
                result.success(true)
            }
            else -> {
                result.notImplemented()
            }
        }
    }

    /**
     * Initialize ONNX Runtime with DistilBERT model
     */
    private suspend fun initializeModel(modelPath: String): Boolean = withContext(Dispatchers.IO) {
        try {
            Log.d(TAG, "Initializing ONNX Runtime with model: $modelPath")
            
            // Create ONNX Runtime environment
            ortEnvironment = OrtEnvironment.getEnvironment()
            
            // Load model from Flutter assets (packaged under flutter_assets/)
            val assetPath = if (modelPath.startsWith("flutter_assets/")) modelPath else "flutter_assets/$modelPath"
            val modelBytes = context.assets.open(assetPath).use { it.readBytes() }
            
            // Create session options with optimizations
            val sessionOptions = OrtSession.SessionOptions().apply {
                setOptimizationLevel(OrtSession.SessionOptions.OptLevel.ALL_OPT)
                setExecutionMode(OrtSession.SessionOptions.ExecutionMode.SEQUENTIAL)
                
                // Enable NNAPI for Android Neural Networks API acceleration
                if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.P) {
                    addNnapi()
                }
            }
            
            // Create inference session
            ortSession = ortEnvironment?.createSession(modelBytes, sessionOptions)
            
            Log.i(TAG, "✅ ONNX model loaded successfully")
            Log.d(TAG, "Model input names: ${ortSession?.inputNames}")
            Log.d(TAG, "Model output names: ${ortSession?.outputNames}")
            
            true
        } catch (e: Exception) {
            Log.e(TAG, "Failed to initialize model", e)
            false
        }
    }

    /**
     * Run inference on tokenized input
     */
    private suspend fun runInference(
        inputIds: List<Int>, 
        attentionMask: List<Int>
    ): Map<String, Any> = withContext(Dispatchers.IO) {
        val session = ortSession ?: throw IllegalStateException("Model not initialized")
        
        try {
            // Prepare input tensors
            val batchSize = 1L
            val sequenceLength = inputIds.size.toLong()
            
            // Convert to long arrays for ONNX
            val inputIdsArray = inputIds.map { it.toLong() }.toLongArray()
            val attentionMaskArray = attentionMask.map { it.toLong() }.toLongArray()
            
            // Create ONNX tensors
            val inputIdsTensor = OnnxTensor.createTensor(
                ortEnvironment,
                LongBuffer.wrap(inputIdsArray),
                longArrayOf(batchSize, sequenceLength)
            )
            
            val attentionMaskTensor = OnnxTensor.createTensor(
                ortEnvironment,
                LongBuffer.wrap(attentionMaskArray),
                longArrayOf(batchSize, sequenceLength)
            )
            
            // Run inference
            val inputs = mapOf(
                "input_ids" to inputIdsTensor,
                "attention_mask" to attentionMaskTensor
            )
            
            val startTime = System.currentTimeMillis()
            val outputs = session.run(inputs)
            val inferenceTime = System.currentTimeMillis() - startTime
            
            Log.d(TAG, "Inference completed in ${inferenceTime}ms")
            
            // Process outputs
            val result = mutableMapOf<String, Any>()
            
            outputs.forEach { (name, tensor) ->
                when (tensor) {
                    is OnnxTensor -> {
                        val floatArray = tensor.floatBuffer.array()
                        
                        // Extract embeddings from last hidden state
                        if (name == "last_hidden_state" || name == "output") {
                            val embeddings = extractEmbeddings(floatArray, sequenceLength.toInt())
                            result["embeddings"] = embeddings
                            
                            // Calculate category logits
                            val logits = calculateCategoryLogits(embeddings)
                            result["logits"] = logits
                        }
                    }
                }
            }
            
            // Clean up tensors
            inputIdsTensor.close()
            attentionMaskTensor.close()
            outputs.close()
            
            result["inference_time_ms"] = inferenceTime
            result
            
        } catch (e: Exception) {
            Log.e(TAG, "Inference error", e)
            throw e
        }
    }

    /**
     * Extract meaningful embeddings from model output
     */
    private fun extractEmbeddings(output: FloatArray, sequenceLength: Int): List<Float> {
        // DistilBERT output shape: [batch_size, sequence_length, hidden_size]
        // hidden_size = 768 for DistilBERT base
        val hiddenSize = 768
        
        // Use [CLS] token embedding (first token) as sentence representation
        val clsEmbedding = output.slice(0 until hiddenSize)
        
        // Also compute mean pooling over all tokens (excluding padding)
        val meanEmbedding = FloatArray(hiddenSize)
        var validTokens = 0
        
        for (i in 0 until sequenceLength) {
            if (i * hiddenSize + hiddenSize <= output.size) {
                val tokenStart = i * hiddenSize
                val tokenEnd = tokenStart + hiddenSize
                val tokenEmbedding = output.slice(tokenStart until tokenEnd)
                
                // Skip padding tokens (usually have very small values)
                if (tokenEmbedding.any { kotlin.math.abs(it) > 0.01f }) {
                    validTokens++
                    for (j in 0 until hiddenSize) {
                        meanEmbedding[j] += tokenEmbedding[j]
                    }
                }
            }
        }
        
        // Average the embeddings
        if (validTokens > 0) {
            for (i in 0 until hiddenSize) {
                meanEmbedding[i] = meanEmbedding[i] / validTokens.toFloat()
            }
        }
        
        // Return first 128 dimensions for efficiency
        return meanEmbedding.slice(0 until minOf(128, hiddenSize))
    }

    /**
     * Calculate category logits from embeddings
     */
    private fun calculateCategoryLogits(embeddings: List<Float>): List<Float> {
        // Simple linear projection to category space
        // In production, this would use a trained classification head
        val categories = listOf(
            "book_club", "music", "sports", "tech", "food", "art",
            "workshop", "networking", "party", "conference", "other"
        )
        
        // Simulate logits based on keyword matching in embeddings
        // This is a simplified version - real implementation would use a trained classifier
        val logits = mutableListOf<Float>()
        
        for (category in categories) {
            // Calculate pseudo-similarity score
            var score = 0.0f
            for (i in embeddings.indices) {
                score += embeddings[i] * getCategoryWeight(category, i)
            }
            logits.add(sigmoid(score))
        }
        
        return logits
    }

    /**
     * Get category weight for classification (simplified)
     */
    private fun getCategoryWeight(category: String, index: Int): Float {
        // In production, these would be learned weights
        // Using hash-based pseudo-random weights for demo
        val hash = (category.hashCode() + index) and 0xFF
        return (hash - 128) / 128.0f
    }

    /**
     * Sigmoid activation function
     */
    private fun sigmoid(x: Float): Float {
        return 1.0f / (1.0f + kotlin.math.exp(-x))
    }

    /**
     * Clean up resources
     */
    private fun dispose() {
        try {
            ortSession?.close()
            ortSession = null
            ortEnvironment?.close()
            ortEnvironment = null
            executor.shutdown()
            scope.cancel()
            Log.d(TAG, "ONNX resources disposed")
        } catch (e: Exception) {
            Log.e(TAG, "Error disposing resources", e)
        }
    }
}
