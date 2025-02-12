const { defineSecret } = require('firebase-functions/params');
const functions = require("firebase-functions/v2");
const functionsV1 = require("firebase-functions");
const admin = require("firebase-admin");
const Replicate = require("replicate");
const axios = require("axios");
const { Client, RunTree } = require("langsmith");
const config = require("./config");
const ffmpeg = require('fluent-ffmpeg');
const ffmpegPath = require('@ffmpeg-installer/ffmpeg').path;
ffmpeg.setFfmpegPath(ffmpegPath);

// Define secrets
const replicateApiKey = defineSecret('REPLICATE_API_KEY_SECRET');
const langsmithApiKey = defineSecret('LANGSMITH_API_KEY_SECRET');

// Set environment variables for LangSmith
process.env.LANGSMITH_TRACING_V2 = "true";
process.env.LANGSMITH_API_URL = "https://api.smith.langchain.com";
process.env.LANGSMITH_PROJECT = "LikeThese";

// Debug log environment variables (redacting sensitive info)
console.log("🔍 LangSmith Environment Variables:", {
  LANGSMITH_TRACING_V2: process.env.LANGSMITH_TRACING_V2,
  LANGSMITH_API_URL: process.env.LANGSMITH_API_URL,
  LANGSMITH_PROJECT: process.env.LANGSMITH_PROJECT,
  LANGSMITH_API_KEY_SET: !!langsmithApiKey
});

admin.initializeApp();

// Define error messages
const ERROR_MESSAGES = {
  FRAME_EXTRACTION: "Failed to extract video frame",
  EMBEDDING: "Failed to compute text embedding",
  CAPTION: "Failed to generate caption",
  GENERAL: "Failed to process video request"
};

// Cache for text embeddings
const textEmbeddingCache = new Map();

// Initialize LangSmith client
let langsmithClient = null;

async function initializeLangSmith() {
  if (!langsmithClient) {
    try {
      const apiKey = langsmithApiKey.value();
      if (!apiKey) {
        throw new Error("LANGSMITH_API_KEY_SECRET not found");
      }
      return apiKey;
    } catch (error) {
      throw error;
    }
  }
  return langsmithClient;
}

// Batch fetch embeddings from Firestore
async function batchFetchEmbeddings(videoIds) {
    console.log(`\n🔍 Batch fetching embeddings for ${videoIds.length} videos`);
    const results = new Map();
    
    // Split into chunks of 10 (Firestore limit)
    const chunkSize = 10;
    for (let i = 0; i < videoIds.length; i += chunkSize) {
        const chunk = videoIds.slice(i, i + chunkSize);
        
        // Get all documents in a single batch
        const snapshot = await admin.firestore()
            .collection('videos')
            .where('id', 'in', chunk)
            .get();
        
        snapshot.forEach(doc => {
            const data = doc.data();
            if (data.textEmbedding) {
                results.set(data.id, data.textEmbedding);
                // Update cache
                textEmbeddingCache.set(data.id, data.textEmbedding);
            }
        });
    }
    
    return results;
}

// Get embeddings with caching
async function getEmbeddingsWithCache(videos) {
    const results = [];
    const missingEmbeddings = [];
    let replicateInstance = null;
    
    // Check cache first
    for (const video of videos) {
        const cached = textEmbeddingCache.get(video.id);
        if (cached) {
            results.push({ videoId: video.id, embedding: cached, source: 'cache' });
        } else {
            missingEmbeddings.push(video);
        }
    }
    
    if (missingEmbeddings.length > 0) {
        // Batch fetch from Firestore
        const videoIds = missingEmbeddings.map(v => v.id);
        const firestoreEmbeddings = await batchFetchEmbeddings(videoIds);
        
        // Process missing embeddings
        for (const video of missingEmbeddings) {
            const embedding = firestoreEmbeddings.get(video.id);
            if (embedding) {
                results.push({ videoId: video.id, embedding, source: 'firestore' });
            } else {
                // Initialize Replicate only when we need it
                if (!replicateInstance) {
                    replicateInstance = await initializeReplicate();
                }
                // Get caption using frameUrl instead of thumbnailUrl
                const frameUrl = video.frameUrl;
                if (!frameUrl) {
                    console.warn(`⚠️ No frameUrl found for video ${video.id}, extracting frame...`);
                    const { frameUrl: newFrameUrl } = await exports.extractVideoFrame({
                        videoUrl: video.url,
                        videoId: video.id
                    });
                    const caption = await generateCaption(newFrameUrl, replicateInstance);
                    const newEmbedding = await generateTextEmbedding(caption);
                    textEmbeddingCache.set(video.id, newEmbedding);
                    results.push({ videoId: video.id, embedding: newEmbedding, source: 'computed_new' });
                    
                    // Update Firestore with new caption and embedding
                    await admin.firestore()
                        .collection('videos')
                        .doc(video.id)
                        .update({
                            caption,
                            textEmbedding: newEmbedding,
                            updatedAt: admin.firestore.FieldValue.serverTimestamp()
                        });
                } else {
                    const caption = await generateCaption(frameUrl, replicateInstance);
                    const newEmbedding = await generateTextEmbedding(caption);
                    textEmbeddingCache.set(video.id, newEmbedding);
                    results.push({ videoId: video.id, embedding: newEmbedding, source: 'computed' });
                    
                    // Update Firestore with new caption and embedding
                    await admin.firestore()
                        .collection('videos')
                        .doc(video.id)
                        .update({
                            caption,
                            textEmbedding: newEmbedding,
                            updatedAt: admin.firestore.FieldValue.serverTimestamp()
                        });
                }
            }
        }
    }
    
    return results;
}

async function initializeReplicate() {
  try {
    console.log("🔄 Starting Replicate initialization");
    const apiKey = replicateApiKey.value();
    
    if (!apiKey) {
      throw new Error("No Replicate API key found");
    }
    
    console.log("✅ Got API key, length:", apiKey.length);
    
    // Create new Replicate instance
    const replicateInstance = new Replicate({
      auth: apiKey,
    });
    
    // Test the connection by getting a specific model
    console.log("🔄 Testing Replicate connection...");
    const model = await replicateInstance.run(
      "stability-ai/sdxl:7762fd07cf82c948538e41f63f77d685e02b063e37e496e96eefd46c929f9bdc",
      {
        input: {
          prompt: "A simple test thumbnail with neutral colors",
          width: 1080,
          height: 1920,
          refine: "expert_ensemble_refiner",
          apply_watermark: false,
          num_inference_steps: 25
        }
      }
    );
    console.log("✅ Successfully connected to Replicate");
    
    return replicateInstance;
  } catch (error) {
    console.error("❌ Failed to initialize Replicate:", error);
    throw new functions.https.HttpsError('internal', 'Failed to initialize Replicate API', error);
  }
}

// Validate Firebase Storage URL
function isValidFirebaseStorageUrl(url) {
  try {
    console.log("🔍 Validating URL:", url);
    const urlObj = new URL(url);
    console.log("🏠 Hostname:", urlObj.hostname);
    
    // Accept any Google Storage or Firebase Storage URL
    const isValidHost = urlObj.hostname.includes('firebasestorage.googleapis.com') || 
                       urlObj.hostname.includes('storage.googleapis.com');
    
    // Accept any path that includes our content
    const isValidPath = url.includes('/videos/') || 
                       url.includes('/thumbnails/') ||
                       url.includes('/o/videos/') || 
                       url.includes('/o/thumbnails/');
    
    const isValid = isValidHost && isValidPath;
    console.log("✅ URL validation result:", isValid);
    return isValid;
  } catch (e) {
    console.error("❌ URL validation error:", e);
    return false;
  }
}

// Validate input URLs
function validateInputUrls(boardVideos, candidateVideos) {
  console.log("🔍 Validating board videos:", boardVideos);
  console.log("🔍 Validating candidate videos:", candidateVideos);
  
  const invalidBoardUrls = boardVideos.filter(
    video => !isValidFirebaseStorageUrl(video.thumbnailUrl)
  );
  const invalidCandidateUrls = candidateVideos.filter(
    video => !isValidFirebaseStorageUrl(video.thumbnailUrl)
  );

  if (invalidBoardUrls.length > 0 || invalidCandidateUrls.length > 0) {
    console.error("❌ Invalid URLs found:");
    console.error("Board URLs:", invalidBoardUrls);
    console.error("Candidate URLs:", invalidCandidateUrls);
    
    throw new functions.https.HttpsError(
      'invalid-argument',
      'Invalid Firebase Storage URLs provided',
      {
        invalidBoardUrls: invalidBoardUrls.map(v => v.thumbnailUrl),
        invalidCandidateUrls: invalidCandidateUrls.map(v => v.thumbnailUrl)
      }
    );
  }
}

// Generate caption using BLIP
async function generateCaption(imageUrl, replicateInstance = null) {
    if (!isValidFirebaseStorageUrl(imageUrl)) {
        throw new functions.https.HttpsError(
            'invalid-argument',
            `Invalid Firebase Storage URL: ${imageUrl}`
        );
    }
    
    let lastError;
    for (let attempt = 0; attempt < 2; attempt++) {
        try {
            // Get a fresh Replicate instance only if not provided
            if (!replicateInstance) {
                replicateInstance = await initializeReplicate();
            }
            
            console.log(`🔄 Generating caption for ${imageUrl} (attempt ${attempt + 1})`);
            const output = await replicateInstance.run(
                "salesforce/blip:2e1dddc8621f72155f24cf2e0adbde548458d3cab9f00c0139eea840d0ac4746",
                {
                    input: {
                        task: "image_captioning",
                        image: imageUrl
                    }
                }
            );
            console.log("✅ Successfully generated caption");
            return output[0].text.replace("Caption: ", "");
        } catch (error) {
            lastError = error;
            console.error(`❌ Caption generation error (attempt ${attempt + 1}):`, {
                name: error.name,
                message: error.message,
                response: error.response?.data || 'No response data',
                stack: error.stack
            });
            
            if (attempt === 0) {
                console.warn(`Retrying caption generation for ${imageUrl} after error`);
                await new Promise(resolve => setTimeout(resolve, 1000));
                // Reset the Replicate instance on retry
                replicateInstance = null;
            }
        }
    }
    throw new functions.https.HttpsError('internal', ERROR_MESSAGES.CAPTION, lastError);
}

// Generate text embedding using OpenAI
async function generateTextEmbedding(text) {
    try {
        const response = await axios.post(
            'https://api.openai.com/v1/embeddings',
            {
                input: text,
                model: "text-embedding-ada-002"
            },
            {
                headers: {
                    'Authorization': `Bearer ${process.env.OPENAI_API_KEY}`,
                    'Content-Type': 'application/json'
                }
            }
        );
        
        return response.data.data[0].embedding;
    } catch (error) {
        console.error('❌ Failed to generate text embedding:', error);
        throw new functions.https.HttpsError('internal', ERROR_MESSAGES.EMBEDDING, error);
    }
}

// Main function to handle video replacement
exports.findLeastSimilarVideo = functions.https.onCall({
  timeoutSeconds: 60,
  memory: "1GiB",
  secrets: [replicateApiKey, langsmithApiKey]
}, async (request, context) => {
  const functionStartTime = Date.now();
  let parentRun = null;
  let totalEmbeddingTime = 0;
  let computedEmbeddingsCount = 0;
  let totalImagesCount = 0;
  
  try {
    const apiKey = await initializeLangSmith();
    parentRun = new RunTree({
      name: "Video Similarity Sort",
      run_type: "chain",
      inputs: request.data,
      serialized: {},
      project_name: "LikeThese",
      apiKey: apiKey,
      apiUrl: process.env.LANGSMITH_API_URL
    });
    await parentRun.postRun();

    // Extract video data and validate URLs
    const { boardVideos, candidateVideos } = request.data;
    totalImagesCount = boardVideos.length + candidateVideos.length;
    
    validateInputUrls(boardVideos, candidateVideos);

    // Get board embeddings
    const boardEmbeddingsStart = Date.now();
    const boardEmbeddingsResults = await getEmbeddingsWithCache(boardVideos);
    const boardEmbeddingsTime = Date.now() - boardEmbeddingsStart;
    computedEmbeddingsCount += boardEmbeddingsResults.filter(r => r.source === 'computed' || r.source === 'computed_new').length;
    totalEmbeddingTime += boardEmbeddingsTime;

    // Compute board average
    const boardAverageEmbedding = computeAverageEmbedding(boardEmbeddingsResults.map(r => r.embedding));

    // Get candidate embeddings
    const candidateEmbeddingsStart = Date.now();
    const candidateEmbeddingsResults = await getEmbeddingsWithCache(candidateVideos);
    const candidateEmbeddingsTime = Date.now() - candidateEmbeddingsStart;
    computedEmbeddingsCount += candidateEmbeddingsResults.filter(r => r.source === 'computed' || r.source === 'computed_new').length;
    totalEmbeddingTime += candidateEmbeddingsTime;

    // Sort candidates
    const sortedCandidates = candidateEmbeddingsResults.map(candidate => {
      const distance = cosineDistance(candidate.embedding, boardAverageEmbedding);
      return {
        videoId: candidate.videoId,
        distance
      };
    }).sort((a, b) => a.distance - b.distance);

    // Generate poster if needed
    let posterImageUrl = null;
    if (request.data.textPrompt) {
      posterImageUrl = await generatePosterImage(request.data.textPrompt);
    }

    // Log metrics
    const metrics = {
      totalRuntime: Date.now() - functionStartTime,
      totalImagesProcessed: totalImagesCount,
      embeddingMetrics: {
        totalEmbeddingTime,
        computedEmbeddingsCount,
        cachedEmbeddingsCount: totalImagesCount - computedEmbeddingsCount
      }
    };

    await parentRun.end({
      outputs: {
        chosen: sortedCandidates[0].videoId,
        sortedCandidates,
        posterImageUrl,
        metrics
      }
    });
    await parentRun.patchRun(false);

    return {
      chosen: sortedCandidates[0].videoId,
      sortedCandidates,
      posterImageUrl,
      metrics
    };

  } catch (error) {
    console.error("❌ Error in findLeastSimilarVideo:", {
      error_name: error.name,
      error_message: error.message
    });

    const metrics = {
      totalRuntime: Date.now() - functionStartTime,
      totalImagesProcessed: totalImagesCount,
      embeddingMetrics: {
        totalEmbeddingTime,
        computedEmbeddingsCount,
        cachedEmbeddingsCount: totalImagesCount - computedEmbeddingsCount
      },
      error: error.message
    };

    if (parentRun) {
      await parentRun.end({
        error: error.message,
        outputs: { metrics }
      });
      await parentRun.patchRun(false);
    }

    if (!(error instanceof functions.https.HttpsError)) {
      error = new functions.https.HttpsError('internal', ERROR_MESSAGES.GENERAL, error);
    }
    throw error;
  }
});

// Extract first frame from video
async function extractSingleFrame(videoUrl, outputPath) {
  console.log(`🎬 Extracting first frame from ${videoUrl}`);
  
  try {
    // Download video to temp file
    const response = await axios({
      method: 'GET',
      url: videoUrl,
      responseType: 'stream'
    });

    // Create a promise to handle the ffmpeg process
    return new Promise((resolve, reject) => {
      ffmpeg()
        .input(response.data)
        .frames(1)
        .outputOptions('-q:v', '2')  // High quality JPEG
        .output(outputPath)
        .on('end', () => {
          console.log('✅ Frame extraction complete');
          resolve(outputPath);
        })
        .on('error', (err) => {
          console.error('❌ Frame extraction error:', err);
          reject(err);
        })
        .run();
    });
  } catch (error) {
    console.error('❌ Frame extraction failed:', error);
    throw new functions.https.HttpsError('internal', ERROR_MESSAGES.FRAME_EXTRACTION, error);
  }
}

// Upload frame to Firebase Storage
async function uploadFrameToStorage(localPath, videoId) {
  console.log(`📤 Uploading frame for video ${videoId}`);
  
  try {
    const bucket = admin.storage().bucket();
    const destination = `frames/${videoId}.jpg`;
    
    await bucket.upload(localPath, {
      destination,
      metadata: {
        contentType: 'image/jpeg',
      },
    });
    
    // Get the public URL
    const [file] = await bucket.file(destination).getSignedUrl({
      action: 'read',
      expires: '03-01-2500', // Far future expiration
    });
    
    console.log('✅ Frame uploaded successfully');
    return file;
  } catch (error) {
    console.error('❌ Frame upload failed:', error);
    throw new functions.https.HttpsError('internal', 'Failed to upload frame', error);
  }
}

// Function to extract and store frame
exports.extractVideoFrame = functions.https.onCall({
  timeoutSeconds: 120,
  memory: "2GiB",
}, async (data, context) => {
  const { videoUrl, videoId } = data;
  
  if (!videoUrl || !videoId) {
    throw new functions.https.HttpsError(
      'invalid-argument',
      'Missing required fields: videoUrl and videoId'
    );
  }

  try {
    // First check if the video document already has a thumbnail
    const videoDoc = await admin.firestore()
      .collection('videos')
      .doc(videoId)
      .get();

    const videoData = videoDoc.data();
    
    // If thumbnail exists, use it as the frame
    if (videoData?.thumbnailUrl) {
      console.log('✅ Using existing thumbnail as frame for video:', videoId);
      await videoDoc.ref.update({
        frameUrl: videoData.thumbnailUrl,
        updatedAt: admin.firestore.FieldValue.serverTimestamp()
      });
      return { frameUrl: videoData.thumbnailUrl };
    }

    // If no thumbnail exists, extract first frame
    console.log('🎬 No thumbnail found, extracting first frame for video:', videoId);
    const os = require('os');
    const path = require('path');
    const outputPath = path.join(os.tmpdir(), `${videoId}.jpg`);
    
    // Extract frame
    await extractSingleFrame(videoUrl, outputPath);
    
    // Upload to Firebase Storage
    const frameUrl = await uploadFrameToStorage(outputPath, videoId);
    
    // Update Firestore document with both frameUrl and thumbnailUrl
    await videoDoc.ref.update({
      frameUrl,
      thumbnailUrl: frameUrl, // Use the same URL for both fields
      updatedAt: admin.firestore.FieldValue.serverTimestamp()
    });
    
    return { frameUrl };
  } catch (error) {
    console.error('❌ Frame extraction process failed:', error);
    throw new functions.https.HttpsError('internal', ERROR_MESSAGES.FRAME_EXTRACTION, error);
  }
});

// Add health check endpoint using v1 functions
exports.healthCheck = functionsV1.https.onRequest((req, res) => {
  res.status(200).send('OK');
}); 