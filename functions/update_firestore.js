const admin = require('firebase-admin');
const path = require('path');
const Replicate = require('replicate');
const { OpenAI } = require('openai');
const serviceAccount = require(path.join(__dirname, '..', 'service-account.json'));
require('dotenv').config({ path: path.join(__dirname, '..', '.env') });

// Initialize Firebase Admin
if (!admin.apps.length) {
    admin.initializeApp({
        credential: admin.credential.cert(serviceAccount)
    });
}

const db = admin.firestore();
const bucket = admin.storage().bucket('likethese-fc23d.firebasestorage.app');

// Initialize Replicate for BLIP
if (!process.env.REPLICATE_API_TOKEN) {
    console.error('⚠️ REPLICATE_API_TOKEN not found in environment');
    process.exit(1);
}

const replicate = new Replicate({
    auth: process.env.REPLICATE_API_TOKEN,
});

// Initialize OpenAI
if (!process.env.OPENAI_API_KEY) {
    console.error('⚠️ OPENAI_API_KEY not found in environment');
    process.exit(1);
}

const openai = new OpenAI({
    apiKey: process.env.OPENAI_API_KEY
});

// Command can be 'check', 'create', 'update', 'migrate', 'migrate-all', or 'list'
const command = process.argv[2];
const basename = process.argv[3];
const force = process.argv.includes('--force');

// Get image caption using BLIP
async function getImageCaption(imageUrl) {
    console.log(`\n🔄 Getting image caption for ${imageUrl}`);
    const output = await replicate.run(
        "salesforce/blip:2e1dddc8621f72155f24cf2e0adbde548458d3cab9f00c0139eea840d0ac4746",
        {
            input: {
                task: "image_captioning",
                image: imageUrl,
                use_beam_search: true,
                min_length: 20,
                max_length: 75
            }
        }
    );
    
    console.log('Raw BLIP output:', JSON.stringify(output));
    
    // BLIP returns the caption as a string
    const caption = output
        .replace(/^Caption:\s*/i, '') // Remove "Caption: " prefix
        .replace(/\s+/g, ' ')         // Replace multiple spaces/newlines with single space
        .trim();                      // Remove leading/trailing whitespace
    
    console.log('Cleaned caption:', JSON.stringify(caption));
    
    if (!caption || caption.length < 10) {
        throw new Error(`Failed to get valid caption from BLIP: ${JSON.stringify(output)}`);
    }
    console.log(`✅ Generated caption: ${caption}`);
    return caption;
}

// Get text embedding using OpenAI
async function getTextEmbedding(text) {
    console.log(`\n🔄 Getting text embedding for: "${text}"`);
    const response = await openai.embeddings.create({
        model: "text-embedding-ada-002",
        input: text,
    });
    console.log(`✅ Successfully got text embedding`);
    return response.data[0].embedding;
}

async function checkDocument(basename) {
    console.log(`\n🔍 Checking for existing document: ${basename}`);
    const doc = await db.collection('videos').doc(basename).get();
    if (doc.exists) {
        console.log(`✅ Found existing document for ${basename}`);
    } else {
        console.log(`➖ No document found for ${basename}`);
    }
    return doc.exists;
}

async function getSignedUrl(filePath) {
    try {
        console.log(`\n🔑 Getting signed URL for: ${filePath}`);
        const file = bucket.file(filePath);
        // Get a signed URL that expires in 14 days
        const [url] = await file.getSignedUrl({
            action: 'read',
            expires: Date.now() + 14 * 24 * 60 * 60 * 1000, // 14 days
        });
        console.log(`✅ Successfully generated signed URL for ${filePath}`);
        return url;
    } catch (error) {
        console.error(`⚠️ Error getting signed URL for ${filePath}:`, error);
        return null;
    }
}

// Check if text embeddings exist for a video
async function hasTextEmbedding(basename) {
    console.log(`\n🔍 Checking for text embedding: ${basename}`);
    const doc = await db.collection('videos').doc(basename).get();
    if (doc.exists && doc.data().textEmbedding) {
        console.log(`✅ Found existing text embedding for ${basename}`);
        return true;
    }
    console.log(`➖ No text embedding found for ${basename}`);
    return false;
}

// Migrate a single document to use text embeddings
async function migrateDocument(basename, force = false) {
    console.log(`\n🔄 Migrating document for: ${basename}`);
    
    // Check if document exists
    const doc = await db.collection('videos').doc(basename).get();
    if (!doc.exists) {
        console.log(`⚠️ Document doesn't exist for ${basename}, skipping migration`);
        return;
    }

    const data = doc.data();
    
    // Check if text embedding already exists
    if (!force && await hasTextEmbedding(basename)) {
        console.log(`✅ Text embedding already exists for ${basename}, skipping migration`);
        return;
    }

    // Get a fresh signed URL for the frame/thumbnail
    const signedUrl = await getSignedUrl(data.frameUrl ? `frames/${basename}.jpg` : `thumbnails/${basename}.jpg`);
    if (!signedUrl) {
        console.error(`⚠️ Failed to get signed URL for frame/thumbnail: ${basename}`);
        return;
    }

    try {
        // Get image caption using BLIP
        console.log(`🔄 Generating caption for ${basename}...`);
        const caption = await getImageCaption(signedUrl);
        console.log(`✅ Generated caption: ${caption}`);

        // Get text embedding using OpenAI
        console.log(`🔄 Computing text embedding for ${basename}...`);
        const textEmbedding = await getTextEmbedding(caption);
        console.log(`✅ Successfully computed text embedding`);

        // Update document with new fields while preserving CLIP embedding
        console.log(`\n💾 Updating document in Firestore...`);
        await doc.ref.update({
            caption: caption,
            textEmbedding: textEmbedding,
            // Keep clipEmbedding for backward compatibility
        });
        console.log(`✅ Successfully migrated document for ${basename}`);
    } catch (error) {
        console.error(`⚠️ Error migrating document ${basename}:`, error);
        throw error;
    }
}

// Migrate all documents in batches
async function migrateAllDocuments(batchSize = 5, force = false) {
    console.log(`\n📋 Starting migration of all documents...`);
    const snapshot = await db.collection('videos').get();
    
    if (snapshot.empty) {
        console.log(`➖ No documents found to migrate`);
        return;
    }

    console.log(`✅ Found ${snapshot.size} documents to process\n`);
    
    // Process in batches to avoid timeouts and rate limits
    const documents = snapshot.docs;
    for (let i = 0; i < documents.length; i += batchSize) {
        const batch = documents.slice(i, i + batchSize);
        console.log(`\n🔄 Processing batch ${Math.floor(i/batchSize) + 1} of ${Math.ceil(documents.length/batchSize)}`);
        
        // Process batch in parallel
        await Promise.all(batch.map(doc => migrateDocument(doc.id, force)))
            .catch(error => {
                console.error(`⚠️ Error processing batch:`, error);
                throw error;
            });
        
        // Add delay between batches to respect rate limits
        if (i + batchSize < documents.length) {
            console.log(`😴 Waiting 2 seconds before next batch...`);
            await new Promise(resolve => setTimeout(resolve, 2000));
        }
    }
    
    console.log(`\n✅ Successfully completed migration of all documents`);
}

async function createDocument(basename) {
    console.log(`\n📝 Creating document for: ${basename}`);
    
    // Check again to prevent race conditions
    const doc = await db.collection('videos').doc(basename).get();
    if (doc.exists) {
        console.log(`⚠️ Document already exists for ${basename}, skipping creation`);
        return;
    }

    console.log(`🔄 Generating storage URLs...`);
    const video_url = `https://storage.googleapis.com/likethese-fc23d.firebasestorage.app/videos/${basename}.mp4`;
    const thumbnail_url = `https://storage.googleapis.com/likethese-fc23d.firebasestorage.app/thumbnails/${basename}.jpg`;
    console.log(`📹 Video URL: ${video_url}`);
    console.log(`🖼️ Thumbnail URL: ${thumbnail_url}`);

    // Get signed URLs
    console.log(`\n🔄 Generating signed URLs...`);
    const signed_video_url = await getSignedUrl(`videos/${basename}.mp4`);
    const signed_thumbnail_url = await getSignedUrl(`thumbnails/${basename}.jpg`);

    if (!signed_video_url || !signed_thumbnail_url) {
        console.error(`⚠️ Failed to get signed URLs for ${basename}`);
        return;
    }

    try {
        // Get image caption using BLIP
        console.log(`🔄 Generating caption...`);
        const caption = await getImageCaption(signed_thumbnail_url);
        console.log(`✅ Generated caption: ${caption}`);

        // Get text embedding using OpenAI
        console.log(`🔄 Computing text embedding...`);
        const textEmbedding = await getTextEmbedding(caption);
        console.log(`✅ Successfully computed text embedding`);

        console.log(`\n💾 Saving document to Firestore...`);
        await db.collection('videos').doc(basename).set({
            id: basename,
            url: video_url,
            thumbnailUrl: thumbnail_url,
            frameUrl: thumbnail_url, // Use thumbnail as frame
            signedVideoUrl: signed_video_url,
            signedThumbnailUrl: signed_thumbnail_url,
            timestamp: admin.firestore.FieldValue.serverTimestamp(),
            // Store paths for easy re-signing
            videoPath: `videos/${basename}.mp4`,
            thumbnailPath: `thumbnails/${basename}.jpg`,
            // Store caption and text embedding
            caption: caption,
            textEmbedding: textEmbedding
        });
        console.log(`✅ Successfully created document for ${basename}`);
    } catch (error) {
        console.error(`⚠️ Error creating document for ${basename}:`, error);
        throw error;
    }
}

async function updateDocument(basename) {
    console.log(`\n📝 Updating document for: ${basename}`);
    
    // Check if document exists
    const doc = await db.collection('videos').doc(basename).get();
    if (!doc.exists) {
        console.log(`⚠️ Document doesn't exist for ${basename}, creating instead...`);
        return createDocument(basename);
    }

    const data = doc.data();
    
    // If document exists but doesn't have frameUrl, add it
    if (!data.frameUrl && data.thumbnailUrl) {
        console.log(`🔄 Adding frameUrl using existing thumbnailUrl for ${basename}`);
        await doc.ref.update({
            frameUrl: data.thumbnailUrl
        });
    }

    // Check if text embedding already exists
    if (await hasTextEmbedding(basename)) {
        console.log(`✅ Text embedding already exists for ${basename}`);
        return;
    }

    // Get a fresh signed URL for the thumbnail/frame
    const signedUrl = await getSignedUrl(data.frameUrl ? `frames/${basename}.jpg` : `thumbnails/${basename}.jpg`);
    if (!signedUrl) {
        console.error(`⚠️ Failed to get signed URL for thumbnail/frame: ${basename}`);
        return;
    }

    try {
        // Get image caption using BLIP
        console.log(`🔄 Generating caption...`);
        const caption = await getImageCaption(signedUrl);
        console.log(`✅ Generated caption: ${caption}`);

        // Get text embedding using OpenAI
        console.log(`🔄 Computing text embedding...`);
        const textEmbedding = await getTextEmbedding(caption);
        console.log(`✅ Successfully computed text embedding`);

        console.log(`\n💾 Updating document in Firestore...`);
        await doc.ref.update({
            caption: caption,
            textEmbedding: textEmbedding
        });
        console.log(`✅ Successfully updated document for ${basename}`);
    } catch (error) {
        console.error(`⚠️ Error updating document for ${basename}:`, error);
        throw error;
    }
}

async function listDocuments() {
    console.log(`\n📋 Listing all video documents...`);
    const snapshot = await db.collection('videos').get();
    if (snapshot.empty) {
        console.log(`➖ No documents found in collection`);
        return;
    }
    console.log(`✅ Found ${snapshot.size} documents\n`);
    snapshot.forEach(doc => {
        const data = doc.data();
        console.log(`\n📄 Document ${doc.id}:`);
        // Don't log the full signed URLs for security
        console.log(JSON.stringify({
            ...data,
            signedVideoUrl: data.signedVideoUrl ? '(signed url)' : null,
            signedThumbnailUrl: data.signedThumbnailUrl ? '(signed url)' : null,
            textEmbedding: data.textEmbedding ? '(embedding array)' : null,
            clipEmbedding: data.clipEmbedding ? '(embedding array)' : null
        }, null, 2));
    });
}

// Handle commands
if (command === 'check') {
    if (!basename) {
        console.error('⚠️ Please provide a video name to check');
        process.exit(1);
    }
    checkDocument(basename)
        .then(exists => {
            process.exit(exists ? 0 : 1);
        })
        .catch(error => {
            console.error('⚠️ Error checking document:', error);
            process.exit(1);
        });
} else if (command === 'create') {
    if (!basename) {
        console.error('⚠️ Please provide a video name to create');
        process.exit(1);
    }
    createDocument(basename)
        .then(() => process.exit(0))
        .catch(error => {
            console.error('⚠️ Error creating document:', error);
            process.exit(1);
        });
} else if (command === 'update') {
    if (!basename) {
        console.error('⚠️ Please provide a video name to update');
        process.exit(1);
    }
    updateDocument(basename)
        .then(() => process.exit(0))
        .catch(error => {
            console.error('⚠️ Error updating document:', error);
            process.exit(1);
        });
} else if (command === 'migrate') {
    if (!basename) {
        console.error('⚠️ Please provide a video name to migrate');
        process.exit(1);
    }
    migrateDocument(basename, force)
        .then(() => process.exit(0))
        .catch(error => {
            console.error('⚠️ Error migrating document:', error);
            process.exit(1);
        });
} else if (command === 'migrate-all') {
    const batchSize = parseInt(process.argv[3]) || 5;
    migrateAllDocuments(batchSize, force)
        .then(() => process.exit(0))
        .catch(error => {
            console.error('⚠️ Error migrating all documents:', error);
            process.exit(1);
        });
} else if (command === 'list') {
    listDocuments()
        .then(() => process.exit(0))
        .catch(error => {
            console.error('⚠️ Error listing documents:', error);
            process.exit(1);
        });
} else {
    console.error('⚠️ Please provide a valid command: check, create, update, migrate, migrate-all, or list');
    process.exit(1);
} 