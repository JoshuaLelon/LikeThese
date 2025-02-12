const admin = require('firebase-admin');
const path = require('path');
const { GoogleGenerativeAI } = require("@google/generative-ai");
const serviceAccount = require(path.join(__dirname, '..', 'service-account.json'));
const axios = require('axios');
const ffmpeg = require('fluent-ffmpeg');
const fs = require('fs').promises;
const os = require('os');
require('dotenv').config({ path: path.join(__dirname, '..', '.env') });

// Initialize Firebase Admin
if (!admin.apps.length) {
    admin.initializeApp({
        credential: admin.credential.cert(serviceAccount)
    });
}

const db = admin.firestore();
const bucket = admin.storage().bucket('likethese-fc23d.firebasestorage.app');

// Initialize Gemini
const genAI = new GoogleGenerativeAI(process.env.GEMINI_API_KEY);

// Command can be 'check', 'process', or 'list'
const command = process.argv[2];
const basename = process.argv[3];

// Extract frames from video
async function extractFrames(videoUrl, numFrames = 3) {
    console.log(`\n🎬 Extracting ${numFrames} frames from video...`);
    
    try {
        // Download video to temp file
        const videoResponse = await axios.get(videoUrl, { responseType: 'arraybuffer' });
        const tempVideoPath = path.join(os.tmpdir(), 'temp_video.mp4');
        await fs.writeFile(tempVideoPath, Buffer.from(videoResponse.data));
        
        // Create temp directory for frames
        const tempFramesDir = path.join(os.tmpdir(), 'frames');
        await fs.mkdir(tempFramesDir, { recursive: true });
        
        // Extract frames using ffmpeg
        return new Promise((resolve, reject) => {
            const frames = [];
            ffmpeg(tempVideoPath)
                .on('end', async () => {
                    console.log('✅ Frame extraction complete');
                    // Read frames
                    for (let i = 1; i <= numFrames; i++) {
                        const framePath = path.join(tempFramesDir, `frame${i}.jpg`);
                        try {
                            const frameData = await fs.readFile(framePath);
                            frames.push(frameData.toString('base64'));
                            await fs.unlink(framePath); // Clean up frame file
                        } catch (error) {
                            console.warn(`⚠️ Could not read frame ${i}:`, error);
                        }
                    }
                    // Clean up
                    await fs.unlink(tempVideoPath);
                    await fs.rmdir(tempFramesDir, { recursive: true });
                    resolve(frames);
                })
                .on('error', (err) => {
                    console.error('❌ Error extracting frames:', err);
                    reject(err);
                })
                .screenshots({
                    count: numFrames,
                    folder: tempFramesDir,
                    filename: 'frame%i.jpg',
                    size: '1280x720'
                });
        });
    } catch (error) {
        console.error('❌ Error in frame extraction:', error);
        throw error;
    }
}

// Get video description using Gemini Flash
async function generateVideoDescription(videoUrl) {
    console.log(`\n🔄 Getting video description for ${videoUrl}`);
    
    try {
        // Download video data
        console.log('📥 Downloading video data...');
        const videoResponse = await axios.get(videoUrl, { responseType: 'arraybuffer' });
        const videoData = Buffer.from(videoResponse.data);
        console.log('✅ Video data downloaded');

        // Check file size (accounting for base64 overhead)
        const fileSizeInMB = videoData.length / (1024 * 1024);
        const base64SizeInMB = (videoData.length * 1.37) / (1024 * 1024); // 1.37 is approximate base64 overhead
        console.log(`📊 Video size: ${fileSizeInMB.toFixed(2)}MB (${base64SizeInMB.toFixed(2)}MB as base64)`);

        if (base64SizeInMB >= 20) {
            console.log('⚠️ Video size would exceed 20MB when encoded as base64, using frame extraction approach...');
            // Extract frames instead of processing whole video
            const frames = await extractFrames(videoUrl);
            console.log(`✅ Extracted ${frames.length} frames from video`);

            const model = genAI.getGenerativeModel({ model: "gemini-1.5-flash" });

            const prompt = `Analyze these frames from a video in detail. Include:
                - Key actions and movements shown in the frames
                - Visual composition and style
                - Objects and their relationships
                - Temporal aspects (changes between frames)
                - Distinctive features and notable elements
                Format as a detailed, structured description.`;

            // Process each frame with Gemini
            const frameDescriptions = await Promise.all(frames.map(async (frameData, index) => {
                console.log(`\n🔄 Processing frame ${index + 1}/${frames.length}`);
                const result = await model.generateContent({
                    contents: [{
                        role: "user",
                        parts: [{
                            text: prompt
                        }, {
                            inline_data: {
                                mime_type: "image/jpeg",
                                data: frameData
                            }
                        }]
                    }]
                });
                
                const response = await result.response;
                return response.text();
            }));

            // Combine frame descriptions
            const description = `Video Analysis (based on ${frames.length} key frames):

${frameDescriptions.join('\n\n')}`;
            
            if (!description || description.length < 100) {
                throw new Error('Failed to get valid description');
            }
            console.log(`✅ Generated description preview: "${description.slice(0, 100)}..."`);
            return description;
        } else {
            console.log('✅ Video size under 20MB, processing entire video...');
            const model = genAI.getGenerativeModel({ model: "gemini-1.5-flash" });

            const prompt = `Analyze this video in detail. Include:
                - Key actions and movements throughout the video
                - Visual composition and style
                - Objects and their relationships
                - Temporal aspects (changes over time)
                - Distinctive features and notable elements
                Format as a detailed, structured description.`;

            const result = await model.generateContent({
                contents: [{
                    role: "user",
                    parts: [{
                        text: prompt
                    }, {
                        inline_data: {
                            mime_type: "video/mp4",
                            data: videoData.toString('base64')
                        }
                    }]
                }]
            });
                
            const geminiResponse = await result.response;
            const description = geminiResponse.text();
            
            if (!description || description.length < 100) {
                throw new Error('Failed to get valid description');
            }
            console.log(`✅ Generated description preview: "${description.slice(0, 100)}..."`);
            return description;
        }
    } catch (error) {
        console.error('❌ Error generating description:', error);
        throw error;
    }
}

// Get text embedding using Gemini
async function generateGeminiEmbedding(text) {
    console.log(`\n🔄 Getting Gemini embedding for text`);
    
    try {
        const model = genAI.getGenerativeModel({ model: "embedding-001" });
        const result = await model.embedContent(text);
        const embedding = result.embedding;
        console.log(`✅ Successfully got Gemini embedding`);
        return embedding;
    } catch (error) {
        console.error('❌ Gemini embedding error:', error);
        throw error;
    }
}

async function checkDocument(basename) {
    console.log(`\n🔍 Checking for Gemini data: ${basename}`);
    const doc = await db.collection('videos').doc(basename).get();
    if (doc.exists && doc.data().geminiDescription && doc.data().geminiEmbedding) {
        console.log(`✅ Found existing Gemini data for ${basename}`);
        return true;
    }
    console.log(`➖ No Gemini data found for ${basename}`);
    return false;
}

async function getSignedUrl(filePath) {
    try {
        console.log(`\n🔑 Getting signed URL for: ${filePath}`);
        const file = bucket.file(filePath);
        // Get a signed URL that expires in 7 days
        const [url] = await file.getSignedUrl({
            action: 'read',
            expires: Date.now() + 7 * 24 * 60 * 60 * 1000, // 7 days
        });
        console.log(`✅ Successfully generated signed URL for ${filePath}`);
        return url;
    } catch (error) {
        console.error(`⚠️ Error getting signed URL for ${filePath}:`, error);
        return null;
    }
}

// Process a single video with Gemini
async function processVideo(basename) {
    console.log(`\n🔄 Processing video with Gemini: ${basename}`);
    const startTime = Date.now();
    
    try {
        // Check if document already has Gemini data
        const doc = await db.collection('videos').doc(basename).get();
        const data = doc.data();
        
        let description = data.geminiDescription;
        if (!description) {
            // Only get video URL and generate description if we don't have one
            const signedUrl = await getSignedUrl(`videos/${basename}.mp4`);
            if (!signedUrl) {
                throw new Error(`Failed to get signed URL for video: ${basename}`);
            }

            try {
                description = await retryWithBackoff(
                    () => generateVideoDescription(signedUrl),
                    3,
                    1000
                );
            } catch (error) {
                // If content is prohibited, use a fallback description
                if (error.toString().includes('PROHIBITED_CONTENT')) {
                    console.log('⚠️ Content was flagged as prohibited, using fallback description');
                    description = `Video ID: ${basename}\n\nThis video's content has been reviewed but a detailed description cannot be generated due to content guidelines. The video may contain exercise, fitness, or similar content that requires careful consideration.`;
                } else {
                    throw error;
                }
            }
        } else {
            console.log('✅ Using existing Gemini description');
        }

        // Generate embedding
        const embedding = await generateGeminiEmbedding(description);

        // Update document
        await db.collection('videos').doc(basename).update({
            geminiDescription: description,
            geminiEmbedding: embedding,
            geminiMetadata: {
                processedAt: admin.firestore.Timestamp.now(),
                processingTime: Date.now() - startTime,
                isProhibited: description.includes('content guidelines')
            }
        });

        console.log(`✅ Successfully processed ${basename} with Gemini`);
        return true;
    } catch (error) {
        console.error(`⚠️ Error processing ${basename} with Gemini:`, error);
        await db.collection('videos').doc(basename).update({
            geminiMetadata: {
                processedAt: admin.firestore.Timestamp.now(),
                error: error.message
            }
        });
        return false;
    }
}

// Retry function with exponential backoff
async function retryWithBackoff(fn, maxAttempts, initialDelay) {
    let attempt = 1;
    let delay = initialDelay;

    while (attempt <= maxAttempts) {
        try {
            return await fn();
        } catch (error) {
            if (attempt === maxAttempts) throw error;
            
            console.log(`Attempt ${attempt} failed, retrying in ${delay}ms...`);
            await new Promise(resolve => setTimeout(resolve, delay));
            
            attempt++;
            delay *= 2;
        }
    }
}

// List all documents with their Gemini processing status
async function listDocuments() {
    console.log('\n📋 Listing all documents with Gemini status:');
    const snapshot = await db.collection('videos').get();
    
    if (snapshot.empty) {
        console.log('No documents found');
        return;
    }

    snapshot.forEach(doc => {
        const data = doc.data();
        const status = data.geminiMetadata?.error ? '❌' :
                      (data.geminiDescription && data.geminiEmbedding) ? '✅' : '⏳';
        console.log(`${status} ${doc.id}: ${data.geminiMetadata?.error || 'OK'}`);
    });
}

// Process all videos
async function processAllVideos() {
    console.log('\n=== Processing All Videos ===');
    
    // Query for documents that need processing (missing description or embedding)
    const snapshot = await db.collection('videos')
        .where('geminiDescription', '==', null)
        .get();
    
    const snapshot2 = await db.collection('videos')
        .where('geminiEmbedding', '==', null)
        .get();
    
    // Combine the results and remove duplicates
    const needsProcessing = new Set([
        ...snapshot.docs.map(doc => doc.id),
        ...snapshot2.docs.map(doc => doc.id)
    ]);
    
    if (needsProcessing.size === 0) {
        console.log('✅ All videos have been processed');
        return;
    }

    console.log(`📊 Found ${needsProcessing.size} videos that need processing`);
    
    let processed = 0;
    let failed = 0;
    const total = needsProcessing.size;
    
    for (const basename of needsProcessing) {
        console.log(`\n=== Processing Video ${processed + failed + 1}/${total}: ${basename} ===`);
        
        try {
            const success = await processVideo(basename);
            if (success) {
                processed++;
            } else {
                failed++;
            }
        } catch (error) {
            console.error(`⚠️ Error processing ${basename}:`, error);
            failed++;
        }
    }

    console.log(`\n=== Processing Complete ===`);
    console.log(`✅ Successfully processed: ${processed}`);
    console.log(`❌ Failed to process: ${failed}`);
    console.log(`📊 Total videos needing processing: ${total}`);
}

// Main execution
async function main() {
    try {
        switch (command) {
            case 'check':
                if (!basename) {
                    console.error('⚠️ Please provide a basename to check');
                    process.exit(1);
                }
                const exists = await checkDocument(basename);
                process.exit(exists ? 0 : 1);
                break;

            case 'process':
                if (basename) {
                    // Process single video
                    const hasGeminiData = await checkDocument(basename);
                    if (hasGeminiData) {
                        console.log(`✅ Skipping ${basename} - already has Gemini data`);
                        process.exit(0);
                    }
                    const success = await processVideo(basename);
                    process.exit(success ? 0 : 1);
                } else {
                    // Process all videos
                    await processAllVideos();
                }
                break;

            case 'list':
                await listDocuments();
                break;

            default:
                console.error('⚠️ Invalid command. Use check, process, or list');
                process.exit(1);
        }
    } catch (error) {
        console.error('⚠️ Error:', error);
        process.exit(1);
    }
}

main(); 