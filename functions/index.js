const { defineSecret } = require('firebase-functions/params');
const functions = require("firebase-functions/v2");
const { onSchedule } = require("firebase-functions/v2/scheduler");
const admin = require("firebase-admin");
const Replicate = require("replicate");
const axios = require("axios");
const { Client, RunTree } = require("langsmith");
const config = require("./config");
const { GoogleGenerativeAI } = require('@google/generative-ai');

// Define secrets
const replicateApiKey = defineSecret('REPLICATE_API_KEY_SECRET');
const langsmithApiKey = defineSecret('LANGSMITH_API_KEY_SECRET');
const geminiApiKey = defineSecret('GEMINI_API_KEY_SECRET');

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

// Helper function to compute average embedding
function computeAverageEmbedding(embeddingsArray) {
  if (!embeddingsArray || embeddingsArray.length === 0) {
    throw new Error('No embeddings provided to compute average');
  }
  
  const length = embeddingsArray[0].length;
  const sum = Array(length).fill(0);
  
  for (const emb of embeddingsArray) {
    if (emb.length !== length) {
      throw new Error('All embeddings must have the same length');
    }
    for (let i = 0; i < length; i++) {
      sum[i] += emb[i];
    }
  }
  
  return sum.map(val => val / embeddingsArray.length);
}

// Helper function to compute cosine distance
function cosineDistance(a, b) {
  if (!a || !b || !Array.isArray(a) || !Array.isArray(b)) {
    console.log('❌ Invalid embeddings:', { a: !!a, b: !!b, aIsArray: Array.isArray(a), bIsArray: Array.isArray(b) });
    return 1;
  }

  if (a.length !== b.length) {
    console.log('❌ Embedding length mismatch:', { aLength: a.length, bLength: b.length });
    return 1;
  }

  const dotProduct = a.reduce((sum, val, i) => sum + val * b[i], 0);
  const normA = Math.sqrt(a.reduce((sum, val) => sum + val * val, 0));
  const normB = Math.sqrt(b.reduce((sum, val) => sum + val * val, 0));

  if (normA === 0 || normB === 0) {
    console.log('⚠️ Zero magnitude vector detected:', { normA, normB });
    return 1;
  }

  const similarity = dotProduct / (normA * normB);
  const distance = 1 - similarity;

  // Add more detailed logging
  console.log('📐 Cosine calculation details:', {
    dotProduct: dotProduct.toFixed(6),
    normA: normA.toFixed(6),
    normB: normB.toFixed(6),
    similarity: similarity.toFixed(6),
    distance: distance.toFixed(6),
    vectorSample: {
      a: a.slice(0, 3).map(v => v.toFixed(6)),  // Show first 3 values
      b: b.slice(0, 3).map(v => v.toFixed(6))
    }
  });

  // Sanity check for identical vectors
  const areIdentical = a.every((val, i) => Math.abs(val - b[i]) < 1e-10);
  if (areIdentical && distance > 1e-10) {
    console.warn('⚠️ Warning: Non-zero distance for identical vectors:', distance);
  }

  return distance;
}

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

// Add Gemini initialization
let geminiClient = null;

async function initializeGemini() {
    if (!geminiClient) {
        try {
            const apiKey = geminiApiKey.value();
            if (!apiKey) {
                throw new Error("GEMINI_API_KEY_SECRET not found");
            }
            geminiClient = new GoogleGenerativeAI(apiKey);
            return geminiClient;
        } catch (error) {
            console.error("Failed to initialize Gemini:", error);
            throw error;
        }
    }
    return geminiClient;
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
    console.log("\n🔍 Starting getEmbeddingsWithCache for", videos.length, "videos");
    const results = [];
    const missingEmbeddings = [];
    let replicateInstance = null;
    
    // Check cache first
    console.log("🔍 Checking cache for", videos.length, "videos");
    for (const video of videos) {
        const cached = textEmbeddingCache.get(video.id);
        if (cached) {
            console.log("✅ Cache hit for video", video.id);
            results.push({ videoId: video.id, embedding: cached, source: 'cache' });
        } else {
            console.log("❌ Cache miss for video", video.id);
            missingEmbeddings.push(video);
        }
    }
    
    if (missingEmbeddings.length > 0) {
        console.log("\n🔄 Processing", missingEmbeddings.length, "videos with missing embeddings");
        // Batch fetch from Firestore
        const videoIds = missingEmbeddings.map(v => v.id);
        console.log("🔍 Attempting Firestore batch fetch for", videoIds.length, "videos");
        const firestoreEmbeddings = await batchFetchEmbeddings(videoIds);
        
        // Process missing embeddings
        for (const video of missingEmbeddings) {
            const embedding = firestoreEmbeddings.get(video.id);
            if (embedding) {
                console.log("✅ Found embedding in Firestore for video", video.id);
                results.push({ videoId: video.id, embedding, source: 'firestore' });
            } else {
                console.log("\n🔄 Need to generate new embedding for video", video.id);
                // Initialize Replicate only when we need it
                if (!replicateInstance) {
                    console.log("🔄 Initializing Replicate for caption generation");
                    replicateInstance = await initializeReplicate();
                }
                
                const frameUrl = video.frameUrl;
                if (!frameUrl) {
                    console.log("⚠️ No frameUrl found for video", video.id, ", extracting frame...");
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
        if (!url) {
            console.error("❌ URL validation error: URL is null or undefined");
            return false;
        }

        // Handle both signed and unsigned URLs
        if (url.includes('?')) {
            // For signed URLs, validate before the query parameters
            url = url.split('?')[0];
        }

        const urlObj = new URL(url);
        
        // Accept Firebase Storage URLs
        const isValidHost = urlObj.hostname === 'firebasestorage.googleapis.com';
        
        // Check for our bucket and valid paths
        const isValidPath = url.includes('/b/likethese-fc23d.firebasestorage.app/o/') && 
            (url.includes('/thumbnails%2F') || url.includes('/frames%2F') || url.includes('/videos%2F'));
        
        const result = isValidHost && isValidPath;
        console.log(`🔍 URL Validation for ${url.substring(0, 50)}...:\n  Host valid: ${isValidHost}\n  Path valid: ${isValidPath}\n  Result: ${result}`);
        
        return result;
    } catch (e) {
        console.error("❌ URL validation error:", e.message, "for URL:", url?.substring(0, 50));
        return false;
    }
}

// Get signed URL with proper expiration
async function getSignedUrl(bucket, filePath) {
  try {
    const file = bucket.file(filePath);
    const [url] = await file.getSignedUrl({
      version: 'v4',
      action: 'read',
      expires: Date.now() + 14 * 24 * 60 * 60 * 1000, // 14 days
    });
    return url;
  } catch (error) {
    console.error(`Failed to get signed URL for ${filePath}:`, error);
    throw error;
  }
}

// Update video document with signed URLs
async function updateVideoWithSignedUrls(videoId) {
  const bucket = admin.storage().bucket();
  const videoRef = admin.firestore().collection('videos').doc(videoId);
  const doc = await videoRef.get();
  
  if (!doc.exists) {
    throw new Error(`Video document ${videoId} not found`);
  }
  
  const data = doc.data();
  const videoPath = data.videoPath || `videos/${videoId}.mp4`;
  const thumbnailPath = data.thumbnailPath || `thumbnails/${videoId}.jpg`;
  const framePath = data.framePath || `frames/${videoId}.jpg`;
  
  const [signedVideoUrl, signedThumbnailUrl, signedFrameUrl] = await Promise.all([
    getSignedUrl(bucket, videoPath),
    getSignedUrl(bucket, thumbnailPath),
    data.framePath ? getSignedUrl(bucket, framePath) : null
  ]);
  
  const updateData = {
    signedVideoUrl,
    signedThumbnailUrl,
    lastUrlUpdate: admin.firestore.FieldValue.serverTimestamp()
  };

  if (signedFrameUrl) {
    updateData.signedFrameUrl = signedFrameUrl;
  }
  
  await videoRef.update(updateData);
  
  return { signedVideoUrl, signedThumbnailUrl, signedFrameUrl };
}

// Function to refresh signed URLs
exports.refreshSignedUrls = onSchedule({
  schedule: "every 24 hours",
  timeZone: "UTC",
  memory: "1GiB",
  timeoutSeconds: 540,
  invoker: "public"
}, async (event) => {
  console.log("🔄 Starting URL refresh job");
  const videosRef = admin.firestore().collection('videos');
  const snapshot = await videosRef.get();
  
  const updates = snapshot.docs.map(doc => 
    updateVideoWithSignedUrls(doc.id)
      .catch(error => {
        console.error(`Failed to update URLs for video ${doc.id}:`, error);
        return null;
      })
  );
  
  await Promise.all(updates);
  console.log(`✅ Updated signed URLs for ${snapshot.size} videos`);
});

// Add a manual URL refresh endpoint
exports.manualUrlRefresh = functions.https.onCall({
  timeoutSeconds: 540,
  memory: "1GiB",
}, async (data, context) => {
  console.log("🔄 Starting manual URL refresh");
  const videosRef = admin.firestore().collection('videos');
  const snapshot = await videosRef.get();
  
  const updates = snapshot.docs.map(doc => 
    updateVideoWithSignedUrls(doc.id)
      .catch(error => {
        console.error(`Failed to update URLs for video ${doc.id}:`, error);
        return null;
      })
  );
  
  await Promise.all(updates);
  console.log(`✅ Updated signed URLs for ${snapshot.size} videos`);
  
  return { message: `Updated URLs for ${snapshot.size} videos` };
});

// Validate input URLs
function validateInputUrls(boardVideos, candidateVideos) {
  console.log("🔍 Validating this many board videos:", boardVideos.length);
  console.log("🔍 Validating this many candidate videos:", candidateVideos.length);
  
  const invalidBoardUrls = boardVideos.filter(video => {
    const frameUrl = video.frameUrl || video.thumbnailUrl;
    const isValid = isValidFirebaseStorageUrl(frameUrl);
    if (!isValid) {
      console.error("❌ Invalid board video URL:", {
        videoId: video.id,
        frameUrl: frameUrl?.substring(0, 100),
        hasFrameUrl: !!video.frameUrl,
        hasThumbnailUrl: !!video.thumbnailUrl
      });
    }
    return !isValid;
  });

  const invalidCandidateUrls = candidateVideos.filter(video => {
    const frameUrl = video.frameUrl || video.thumbnailUrl;
    const isValid = isValidFirebaseStorageUrl(frameUrl);
    if (!isValid) {
      console.error("❌ Invalid candidate video URL:", {
        videoId: video.id,
        frameUrl: frameUrl?.substring(0, 100),
        hasFrameUrl: !!video.frameUrl,
        hasThumbnailUrl: !!video.thumbnailUrl
      });
    }
    return !isValid;
  });

  if (invalidBoardUrls.length > 0 || invalidCandidateUrls.length > 0) {
    console.error("❌ Invalid URLs found:", {
      invalidBoardCount: invalidBoardUrls.length,
      invalidCandidateCount: invalidCandidateUrls.length,
      sampleBoardUrl: invalidBoardUrls[0]?.frameUrl || invalidBoardUrls[0]?.thumbnailUrl,
      sampleCandidateUrl: invalidCandidateUrls[0]?.frameUrl || invalidCandidateUrls[0]?.thumbnailUrl
    });
    
    throw new functions.https.HttpsError(
      'invalid-argument',
      'Invalid Firebase Storage URLs provided',
      {
        invalidBoardUrls: invalidBoardUrls.map(v => ({
          id: v.id,
          url: v.frameUrl || v.thumbnailUrl
        })),
        invalidCandidateUrls: invalidCandidateUrls.map(v => ({
          id: v.id,
          url: v.frameUrl || v.thumbnailUrl
        }))
      }
    );
  }
}

// Generate caption using BLIP
async function generateCaption(imageUrl, replicateInstance = null) {
    console.log("\n🔄 Starting caption generation for image URL:", imageUrl);
    
    if (!isValidFirebaseStorageUrl(imageUrl)) {
        console.error("❌ Invalid image URL for caption generation:", imageUrl);
        throw new functions.https.HttpsError(
            'invalid-argument',
            `Invalid Firebase Storage URL: ${imageUrl}`
        );
    }
    
    let lastError;
    for (let attempt = 0; attempt < 2; attempt++) {
        try {
            if (!replicateInstance) {
                console.log("🔄 No Replicate instance provided, initializing new one");
                replicateInstance = await initializeReplicate();
            }
            
            console.log(`🔄 Calling BLIP model for caption (attempt ${attempt + 1})`);
            const output = await replicateInstance.run(
                "salesforce/blip:2e1dddc8621f72155f24cf2e0adbde548458d3cab9f00c0139eea840d0ac4746",
                {
                    input: {
                        task: "image_captioning",
                        image: imageUrl
                    }
                }
            );
            
            const caption = output[0].text.replace("Caption: ", "");
            console.log("✅ Successfully generated caption:", caption);
            return caption;
            
        } catch (error) {
            lastError = error;
            console.error(`❌ BLIP caption generation error (attempt ${attempt + 1}):`, {
                name: error.name,
                message: error.message,
                response: error.response?.data || 'No response data'
            });
            
            if (attempt === 0) {
                console.log("🔄 Retrying caption generation after error");
                await new Promise(resolve => setTimeout(resolve, 1000));
                replicateInstance = null;
            }
        }
    }
    throw new functions.https.HttpsError('internal', ERROR_MESSAGES.CAPTION, lastError);
}

// Generate text embedding using OpenAI
async function generateTextEmbedding(text) {
    console.log("\n🔄 Starting text embedding generation for text:", text);
    
    try {
        console.log("🔄 Calling OpenAI embeddings API");
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
        
        console.log("✅ Successfully generated text embedding");
        return response.data.data[0].embedding;
    } catch (error) {
        console.error('❌ OpenAI text embedding error:', {
            name: error.name,
            message: error.message,
            response: error.response?.data || 'No response data'
        });
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
    
    console.log(`📥 Validating URLs for ${boardVideos?.length || 0} board videos and ${candidateVideos?.length || 0} candidates`);
    
    // Validate input arrays
    if (!Array.isArray(boardVideos) || !Array.isArray(candidateVideos)) {
        throw new Error('Invalid input: boardVideos and candidateVideos must be arrays');
    }
    
    // Validate URLs in both arrays
    const invalidBoardUrls = boardVideos.filter(v => {
        const frameUrl = v.frameUrl || v.thumbnailUrl;
        return !frameUrl || !isValidFirebaseStorageUrl(frameUrl);
    });
    const invalidCandidateUrls = candidateVideos.filter(v => {
        const frameUrl = v.frameUrl || v.thumbnailUrl;
        return !frameUrl || !isValidFirebaseStorageUrl(frameUrl);
    });
    
    if (invalidBoardUrls.length > 0 || invalidCandidateUrls.length > 0) {
        console.error(`❌ Invalid URLs found:\nBoard Videos: ${invalidBoardUrls.length}\nCandidate Videos: ${invalidCandidateUrls.length}`);
        
        // Log a sample of invalid URLs
        if (invalidBoardUrls.length > 0) {
            const sampleUrl = invalidBoardUrls[0].frameUrl || invalidBoardUrls[0].thumbnailUrl;
            console.error('Sample invalid board URL:', sampleUrl?.substring(0, 100));
        }
        if (invalidCandidateUrls.length > 0) {
            const sampleUrl = invalidCandidateUrls[0].frameUrl || invalidCandidateUrls[0].thumbnailUrl;
            console.error('Sample invalid candidate URL:', sampleUrl?.substring(0, 100));
        }
        
        throw new Error(`Invalid Firebase Storage URLs: ${invalidBoardUrls.length} board videos and ${invalidCandidateUrls.length} candidate videos`);
    }
    
    console.log('✅ All URLs validated successfully');

    // Create a Set of board video IDs for efficient lookup
    const boardVideoIds = new Set(boardVideos.map(v => v.id));
    
    // Filter candidates to exclude any videos that are on the board
    const filteredCandidates = candidateVideos.filter(video => !boardVideoIds.has(video.id));
    
    console.log("🔍 Board videos:", boardVideos.map(v => v.id));
    console.log("🔍 Filtered candidates:", filteredCandidates.map(v => v.id));
    
    // Continue with the rest of the function using filteredCandidates instead of candidateVideos
    totalImagesCount = boardVideos.length + filteredCandidates.length;
    
    validateInputUrls(boardVideos, filteredCandidates);

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
    const candidateEmbeddingsResults = await getEmbeddingsWithCache(filteredCandidates);
    const candidateEmbeddingsTime = Date.now() - candidateEmbeddingsStart;
    computedEmbeddingsCount += candidateEmbeddingsResults.filter(r => r.source === 'computed' || r.source === 'computed_new').length;
    totalEmbeddingTime += candidateEmbeddingsTime;

    // Sort candidates
    const sortedCandidates = candidateEmbeddingsResults.map(candidate => {
      console.log("\n📊 Computing distance for video:", candidate.videoId);
      console.log("📐 Board average embedding length:", boardAverageEmbedding.length);
      console.log("📐 Candidate embedding length:", candidate.embedding.length);
      
      const distance = cosineDistance(candidate.embedding, boardAverageEmbedding);
      console.log("📏 Computed distance:", distance);
      
      return {
        videoId: candidate.videoId,
        distance
      };
    }).sort((a, b) => {
      console.log(`🔄 Comparing distances: ${a.videoId}(${a.distance}) vs ${b.videoId}(${b.distance})`);
      return a.distance - b.distance;
    });

    console.log("\n📊 Final sorted order:");
    sortedCandidates.forEach((candidate, index) => {
      console.log(`${index + 1}. Video ${candidate.videoId}: distance ${candidate.distance}`);
    });

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
    // Initialize ffmpeg here
    const ffmpeg = require('fluent-ffmpeg');
    const ffmpegPath = require('@ffmpeg-installer/ffmpeg').path;
    ffmpeg.setFfmpegPath(ffmpegPath);

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
    
    // Get signed URL with 14-day expiration
    const [file] = await bucket.file(destination).getSignedUrl({
      action: 'read',
      expires: Date.now() + 14 * 24 * 60 * 60 * 1000 // 14 days
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

// Change healthCheck to v2
exports.healthCheck = functions.https.onRequest((req, res) => {
    res.status(200).send('OK');
}); 