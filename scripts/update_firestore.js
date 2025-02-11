const admin = require('firebase-admin');
const path = require('path');
const Replicate = require('replicate');
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

// Initialize Replicate
if (!process.env.REPLICATE_API_TOKEN) {
    console.error('⚠️ REPLICATE_API_TOKEN not found in environment');
    process.exit(1);
}

const replicate = new Replicate({
    auth: process.env.REPLICATE_API_TOKEN,
});

// Command can be 'check', 'create', 'update', or 'list'
const command = process.argv[2];
const basename = process.argv[3];

// Get CLIP embeddings using Replicate
async function getClipEmbedding(imageUrl) {
    console.log(`\n🔄 Getting CLIP embedding for ${imageUrl}`);
    const output = await replicate.run(
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

// Check if CLIP embeddings exist for a video
async function hasClipEmbedding(basename) {
    console.log(`\n🔍 Checking for CLIP embedding: ${basename}`);
    const doc = await db.collection('videos').doc(basename).get();
    if (doc.exists && doc.data().clipEmbedding) {
        console.log(`✅ Found existing CLIP embedding for ${basename}`);
        return true;
    }
    console.log(`➖ No CLIP embedding found for ${basename}`);
    return false;
}

async function createDocument(basename) {
    console.log(`\n📝 Creating document for: ${basename}`);
    
    // Check again to prevent race conditions
    const doc = await db.collection('videos').doc(basename).get();
    if (doc.exists) {
        console.log(`⚠️ Document already exists for ${basename}, skipping creation`);
        return;
    }

    // Check if CLIP embedding already exists
    if (await hasClipEmbedding(basename)) {
        console.log(`✅ Using existing CLIP embedding for ${basename}`);
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

    // Get CLIP embedding for the thumbnail using signed URL
    console.log(`\n🔄 Computing CLIP embedding...`);
    const clipEmbedding = await getClipEmbedding(signed_thumbnail_url);
    console.log(`✅ Successfully computed CLIP embedding`);

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
        // Store CLIP embedding
        clipEmbedding: clipEmbedding
    });
    console.log(`✅ Successfully created document for ${basename} with signed URLs and CLIP embedding`);
    console.log(`\n📄 Document contents:`);
    console.log(JSON.stringify({
        id: basename,
        url: video_url,
        thumbnailUrl: thumbnail_url,
        frameUrl: thumbnail_url,
        signedVideoUrl: '(signed url)',
        signedThumbnailUrl: '(signed url)',
        videoPath: `videos/${basename}.mp4`,
        thumbnailPath: `thumbnails/${basename}.jpg`,
        clipEmbedding: '(embedding array)'
    }, null, 2));
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

    // Check if CLIP embedding already exists
    if (await hasClipEmbedding(basename)) {
        console.log(`✅ Using existing CLIP embedding for ${basename}`);
        return;
    }

    // Get a fresh signed URL for the thumbnail/frame
    const signedUrl = await getSignedUrl(data.frameUrl ? 'frames/${basename}.jpg' : `thumbnails/${basename}.jpg`);
    if (!signedUrl) {
        console.error(`⚠️ Failed to get signed URL for thumbnail/frame: ${basename}`);
        return;
    }

    console.log(`🔄 Computing CLIP embedding for ${basename}...`);
    const clipEmbedding = await getClipEmbedding(signedUrl);
    console.log(`✅ Successfully computed CLIP embedding`);

    console.log(`\n💾 Updating document in Firestore...`);
    await doc.ref.update({
        clipEmbedding: clipEmbedding
    });
    console.log(`✅ Successfully updated document for ${basename} with CLIP embedding`);
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
            signedThumbnailUrl: data.signedThumbnailUrl ? '(signed url)' : null
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
} else if (command === 'list') {
    listDocuments()
        .then(() => process.exit(0))
        .catch(error => {
            console.error('⚠️ Error listing documents:', error);
            process.exit(1);
        });
} else {
    console.error('⚠️ Please provide a valid command: check, create, update, or list');
    process.exit(1);
} 