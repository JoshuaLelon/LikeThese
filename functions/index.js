const { defineSecret } = require('firebase-functions/params');
const functions = require("firebase-functions/v2");
const admin = require("firebase-admin");
const Replicate = require("replicate");
const axios = require("axios");
const config = require("./config");

admin.initializeApp();

// Define error messages
const ERROR_MESSAGES = {
  FRAME_EXTRACTION: "Failed to extract video frame",
  EMBEDDING: "Failed to compute video similarity",
  POSTER: "Failed to generate poster image",
  GENERAL: "Failed to process video request"
};

// Define config parameters
const replicateApiKey = defineSecret('REPLICATE_API_KEY_SECRET');
const langsmithApiKey = defineSecret('LANGSMITH_API_KEY_SECRET');
const langsmithBaseUrl = defineSecret('LANGSMITH_BASE_URL_SECRET');

// Cache for CLIP embeddings
const clipEmbeddingCache = new Map();

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
            if (data.clipEmbedding) {
                results.set(data.id, data.clipEmbedding);
                // Update cache
                clipEmbeddingCache.set(data.id, data.clipEmbedding);
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
        const cached = clipEmbeddingCache.get(video.id);
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
                // Compute new embedding
                const thumbnailUrl = video.thumbnailUrl;
                const newEmbedding = await getClipEmbedding(thumbnailUrl, replicateInstance);
                clipEmbeddingCache.set(video.id, newEmbedding);
                results.push({ videoId: video.id, embedding: newEmbedding, source: 'computed' });
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

// Get CLIP embeddings using Replicate
async function getClipEmbedding(imageUrl, replicateInstance = null) {
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
      
      console.log(`🔄 Getting CLIP embedding for ${imageUrl} (attempt ${attempt + 1})`);
      const output = await replicateInstance.run(
        "zsxkib/jina-clip-v2:5050c3108bab23981802011a3c76ee327cc0dbfdd31a2f4ef1ee8ef0d3f0b448",
        {
          input: {
            image: imageUrl,
            embedding_dim: 512,
            output_format: "array"
          }
        }
      );
      console.log("✅ Successfully got CLIP embedding");
      return output[0];
    } catch (error) {
      lastError = error;
      console.error(`❌ CLIP embedding error (attempt ${attempt + 1}):`, {
        name: error.name,
        message: error.message,
        response: error.response?.data || 'No response data',
        stack: error.stack
      });
      
      if (attempt === 0) {
        console.warn(`Retrying CLIP embedding for ${imageUrl} after error`);
        await new Promise(resolve => setTimeout(resolve, 1000));
        // Reset the Replicate instance on retry
        replicateInstance = null;
      }
    }
  }
  throw new functions.https.HttpsError('internal', ERROR_MESSAGES.EMBEDDING, lastError);
}

// Generate poster image using Imagen
async function generatePosterImage(prompt) {
  let lastError;
  for (let attempt = 0; attempt < 2; attempt++) {
    try {
      // Get a fresh Replicate instance for each attempt
      const replicateInstance = await initializeReplicate();
      
      const out = await replicateInstance.run("google/imagen-3-fast", {
        input: {
          prompt,
          width: 1080,
          height: 1920
        }
      });
      return out[0] || null;
    } catch (error) {
      lastError = error;
      if (attempt === 0) {
        console.warn(`Retrying poster generation for prompt "${prompt}" after error:`, error);
        await new Promise(resolve => setTimeout(resolve, 1000)); // Wait 1 second before retry
      }
    }
  }
  throw new functions.https.HttpsError('internal', ERROR_MESSAGES.POSTER, lastError);
}

// Compute cosine distance between two vectors
function cosineDistance(vecA, vecB) {
  const dot = vecA.reduce((sum, val, i) => sum + val * vecB[i], 0);
  const normA = Math.sqrt(vecA.reduce((sum, val) => sum + val * val, 0));
  const normB = Math.sqrt(vecB.reduce((sum, val) => sum + val * val, 0));
  return 1 - (dot / (normA * normB));
}

// Main function to handle video replacement
exports.findLeastSimilarVideo = functions.https.onCall({
  timeoutSeconds: 60,
  memory: "1GiB",
  secrets: [replicateApiKey, langsmithApiKey, langsmithBaseUrl]
}, async (request, context) => {
  const startTime = Date.now();
  const metrics = {
    totalRuntime: 0,
    totalEmbeddingTime: 0,
    embeddingTimes: [],
    error: null,
    environment: config.environment
  };

  try {
    // Log environment info
    console.log(`🌍 Running in ${config.environment} environment`);
    
    // Verify auth token if provided in request data
    if (request.data.auth?.token) {
      try {
        await admin.auth().verifyIdToken(request.data.auth.token);
        console.log("✅ Successfully verified provided auth token");
      } catch (error) {
        console.error("❌ Invalid auth token:", error);
        throw new functions.https.HttpsError('unauthenticated', 'Invalid authentication token');
      }
    }

    // Extract video data from request
    const { boardVideos, candidateVideos } = request.data;
    console.log("📥 Processing request with:", {
      boardVideosCount: boardVideos.length,
      candidateVideosCount: candidateVideos.length
    });

    // Validate all input URLs before processing
    validateInputUrls(boardVideos, candidateVideos);

    // Get board video embeddings with caching
    const boardEmbeddingsStart = Date.now();
    const boardEmbeddingsResults = await getEmbeddingsWithCache(boardVideos);
    const boardEmbeddings = boardEmbeddingsResults.map(r => r.embedding);
    
    // Track metrics
    boardEmbeddingsResults.forEach(r => {
        metrics.embeddingTimes.push({
            type: 'board',
            id: r.videoId,
            source: r.source
        });
    });
    metrics.totalEmbeddingTime += Date.now() - boardEmbeddingsStart;

    // Get candidate video embeddings with caching
    const candidateEmbeddingsStart = Date.now();
    const candidateEmbeddingsResults = await getEmbeddingsWithCache(candidateVideos);
    
    // Track metrics
    candidateEmbeddingsResults.forEach(r => {
        metrics.embeddingTimes.push({
            type: 'candidate',
            id: r.videoId,
            source: r.source
        });
    });
    metrics.totalEmbeddingTime += Date.now() - candidateEmbeddingsStart;

    // Find the most dissimilar video
    const distanceStart = Date.now();
    let bestVideoId = null;
    let bestScore = -1;
    const distances = [];

    for (const candidate of candidateEmbeddingsResults) {
        let totalDistance = 0;
        const candidateDistances = [];
        for (const boardEmbedding of boardEmbeddings) {
            const distance = cosineDistance(candidate.embedding, boardEmbedding);
            totalDistance += distance;
            candidateDistances.push(distance);
        }
        distances.push({
            videoId: candidate.videoId,
            distances: candidateDistances,
            total: totalDistance
        });
        if (totalDistance > bestScore) {
            bestScore = totalDistance;
            bestVideoId = candidate.videoId;
        }
    }
    const distanceTime = Date.now() - distanceStart;

    // Generate poster image if prompt provided
    let posterImageUrl = null;
    let posterTime = 0;
    if (request.data.textPrompt) {
      const posterStart = Date.now();
      posterImageUrl = await generatePosterImage(request.data.textPrompt);
      posterTime = Date.now() - posterStart;
    }

    metrics.totalRuntime = Date.now() - startTime;

    // Log to LangSmith if configured
    const apiKey = langsmithApiKey.value();
    if (apiKey) {
      try {
        const baseUrl = langsmithBaseUrl.value().trim();
        const payload = {
          name: "VideoReplacementFlow",
          inputs: {
            boardVideos: boardVideos.map(v => ({ id: v.id, thumbnailUrl: v.thumbnailUrl })),
            candidateVideos: candidateVideos.map(v => ({ id: v.id, thumbnailUrl: v.thumbnailUrl })),
            textPrompt: request.data.textPrompt
          },
          outputs: {
            chosen: bestVideoId,
            score: bestScore,
            posterImageUrl,
            metrics: {
              ...metrics,
              distanceCalculationTime: distanceTime,
              posterGenerationTime: posterTime,
              distances
            }
          }
        };

        await axios.post(
          baseUrl,
          payload,
          {
            headers: {
              "Content-Type": "application/json",
              "Authorization": `Bearer ${apiKey.trim()}`
            },
            timeout: 5000 // 5 second timeout
          }
        );
      } catch (logError) {
        // Don't let LangSmith errors affect the main function
        console.error("Failed to log to LangSmith:", logError.message);
      }
    }

    return {
      chosen: bestVideoId,
      score: bestScore,
      posterImageUrl
    };

  } catch (error) {
    metrics.totalRuntime = Date.now() - startTime;
    metrics.error = error.message;

    // Log error to LangSmith if configured
    const apiKey = langsmithApiKey.value();
    if (apiKey) {
      try {
        const baseUrl = langsmithBaseUrl.value().trim();
        const payload = {
          name: "VideoReplacementFlow",
          inputs: request.data,
          outputs: {
            error: error.message,
            metrics
          }
        };

        await axios.post(
          baseUrl,
          payload,
          {
            headers: {
              "Content-Type": "application/json",
              "Authorization": `Bearer ${apiKey.trim()}`
            },
            timeout: 5000 // 5 second timeout
          }
        );
      } catch (logError) {
        // Don't let LangSmith errors affect the main function
        console.error("Failed to log error to LangSmith:", logError.message);
      }
    }

    console.error("Error in findLeastSimilarVideo:", error);
    // If it's not already an HttpsError, wrap it in one
    if (!(error instanceof functions.https.HttpsError)) {
      error = new functions.https.HttpsError('internal', ERROR_MESSAGES.GENERAL, error);
    }
    throw error;
  }
}); 