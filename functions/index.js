const { defineSecret } = require('firebase-functions/params');
const functions = require("firebase-functions/v2");
const admin = require("firebase-admin");
const Replicate = require("replicate");
const axios = require("axios");

admin.initializeApp();

// Define config parameters
const replicateApiKey = defineSecret('REPLICATE_API_KEY_SECRET');
const langsmithApiKey = defineSecret('LANGSMITH_API_KEY_SECRET');
const langsmithBaseUrl = defineSecret('LANGSMITH_BASE_URL_SECRET');

// Initialize Replicate with API key from Firebase config
let replicate;

// Validate Firebase Storage URL
function isValidFirebaseStorageUrl(url) {
  try {
    const urlObj = new URL(url);
    return (
      urlObj.hostname.includes('firebasestorage.googleapis.com') &&
      (url.includes('/videos/') || url.includes('/thumbnails/'))
    );
  } catch (e) {
    return false;
  }
}

// Validate input URLs
function validateInputUrls(boardVideos, candidateVideos) {
  const invalidBoardUrls = boardVideos.filter(
    video => !isValidFirebaseStorageUrl(video.thumbnailUrl)
  );
  const invalidCandidateUrls = candidateVideos.filter(
    video => !isValidFirebaseStorageUrl(video.thumbnailUrl)
  );

  if (invalidBoardUrls.length > 0 || invalidCandidateUrls.length > 0) {
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
async function getClipEmbedding(imageUrl) {
  if (!isValidFirebaseStorageUrl(imageUrl)) {
    throw new functions.https.HttpsError(
      'invalid-argument',
      `Invalid Firebase Storage URL: ${imageUrl}`
    );
  }
  const embedding = await replicate.run("andreasjansson/clip-features", {
    input: { image: imageUrl }
  });
  return embedding;
}

// Generate poster image using Imagen
async function generatePosterImage(prompt) {
  const out = await replicate.run("google/imagen-3-fast", {
    input: {
      prompt,
      width: 1080,
      height: 1920
    }
  });
  return out[0] || null;
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
  region: "us-central1",
  secrets: [replicateApiKey, langsmithApiKey, langsmithBaseUrl]
}, async (request) => {
  // Initialize Replicate with runtime config
  if (!replicate) {
    replicate = new Replicate({
      auth: replicateApiKey.value(),
    });
  }

  const startTime = Date.now();
  const metrics = {
    embeddingTimes: [],
    totalEmbeddingTime: 0,
    totalRuntime: 0
  };

  try {
    const { boardVideos, candidateVideos, textPrompt } = request.data;

    // Validate all input URLs before processing
    validateInputUrls(boardVideos, candidateVideos);

    // Compute embeddings for board videos using their thumbnails
    const boardEmbeddingsStart = Date.now();
    const boardEmbeddings = await Promise.all(
      boardVideos.map(async (video) => {
        const embedStart = Date.now();
        const thumbnailUrl = video.thumbnailUrl;
        const embedding = await getClipEmbedding(thumbnailUrl);
        const embedTime = Date.now() - embedStart;
        metrics.embeddingTimes.push({ type: 'board', id: video.id, time: embedTime });
        return embedding;
      })
    );
    metrics.totalEmbeddingTime += Date.now() - boardEmbeddingsStart;

    // Compute embeddings for candidate videos using their thumbnails
    const candidateEmbeddingsStart = Date.now();
    const candidateEmbeddings = await Promise.all(
      candidateVideos.map(async (video) => {
        const embedStart = Date.now();
        const thumbnailUrl = video.thumbnailUrl;
        const embedding = await getClipEmbedding(thumbnailUrl);
        const embedTime = Date.now() - embedStart;
        metrics.embeddingTimes.push({ type: 'candidate', id: video.id, time: embedTime });
        return { videoId: video.id, embedding };
      })
    );
    metrics.totalEmbeddingTime += Date.now() - candidateEmbeddingsStart;

    // Find the most dissimilar video
    const distanceStart = Date.now();
    let bestVideoId = null;
    let bestScore = -1;
    const distances = [];

    for (const candidate of candidateEmbeddings) {
      let totalDistance = 0;
      const candidateDistances = [];
      for (const boardEmbedding of boardEmbeddings) {
        const distance = cosineDistance(candidate.embedding, boardEmbedding);
        totalDistance += distance;
        candidateDistances.push(distance);
      }
      distances.push({ videoId: candidate.videoId, distances: candidateDistances, total: totalDistance });
      if (totalDistance > bestScore) {
        bestScore = totalDistance;
        bestVideoId = candidate.videoId;
      }
    }
    const distanceTime = Date.now() - distanceStart;

    // Generate poster image if prompt provided
    let posterImageUrl = null;
    let posterTime = 0;
    if (textPrompt) {
      const posterStart = Date.now();
      posterImageUrl = await generatePosterImage(textPrompt);
      posterTime = Date.now() - posterStart;
    }

    metrics.totalRuntime = Date.now() - startTime;

    // Log to LangSmith if configured
    const apiKey = langsmithApiKey.value();
    if (apiKey) {
      try {
        await axios.post(
          langsmithBaseUrl.value(),
          {
            name: "VideoReplacementFlow",
            inputs: {
              boardVideos: boardVideos.map(v => ({ id: v.id, thumbnailUrl: v.thumbnailUrl })),
              candidateVideos: candidateVideos.map(v => ({ id: v.id, thumbnailUrl: v.thumbnailUrl })),
              textPrompt
            },
            outputs: {
              chosenVideo: bestVideoId,
              score: bestScore,
              posterImageUrl,
              metrics: {
                ...metrics,
                distanceCalculationTime: distanceTime,
                posterGenerationTime: posterTime,
                distances
              }
            }
          },
          {
            headers: {
              "Content-Type": "application/json",
              Authorization: `Bearer ${apiKey}`
            }
          }
        );
      } catch (logError) {
        console.error("Failed to log to LangSmith:", logError);
      }
    }

    return {
      chosenVideo: bestVideoId,
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
        await axios.post(
          langsmithBaseUrl.value(),
          {
            name: "VideoReplacementFlow",
            inputs: request.data,
            outputs: {
              error: error.message,
              metrics
            }
          },
          {
            headers: {
              "Content-Type": "application/json",
              Authorization: `Bearer ${apiKey}`
            }
          }
        );
      } catch (logError) {
        console.error("Failed to log error to LangSmith:", logError);
      }
    }

    console.error("Error in findLeastSimilarVideo:", error);
    throw new functions.https.HttpsError("internal", error.message);
  }
}); 