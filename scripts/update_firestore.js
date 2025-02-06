const admin = require('firebase-admin');
const path = require('path');
const serviceAccount = require(path.join(__dirname, '..', 'service-account.json'));

// Initialize Firebase Admin
if (!admin.apps.length) {
    admin.initializeApp({
        credential: admin.credential.cert(serviceAccount)
    });
}

const db = admin.firestore();
const bucket = admin.storage().bucket('likethese-fc23d.firebasestorage.app');

// Command can be 'check', 'create', or 'list'
const command = process.argv[2];
const basename = process.argv[3];

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

    if (!signed_video_url) {
        console.error(`⚠️ Failed to get signed video URL for ${basename}`);
        return;
    }

    console.log(`\n💾 Saving document to Firestore...`);
    await db.collection('videos').doc(basename).set({
        id: basename,
        url: video_url,
        thumbnailUrl: thumbnail_url,
        signedVideoUrl: signed_video_url,
        signedThumbnailUrl: signed_thumbnail_url,
        timestamp: admin.firestore.FieldValue.serverTimestamp(),
        // Store paths for easy re-signing
        videoPath: `videos/${basename}.mp4`,
        thumbnailPath: `thumbnails/${basename}.jpg`
    });
    console.log(`✅ Successfully created document for ${basename} with signed URLs`);
    console.log(`\n📄 Document contents:`);
    console.log(JSON.stringify({
        id: basename,
        url: video_url,
        thumbnailUrl: thumbnail_url,
        signedVideoUrl: '(signed url)',
        signedThumbnailUrl: signed_thumbnail_url ? '(signed url)' : null,
        videoPath: `videos/${basename}.mp4`,
        thumbnailPath: `thumbnails/${basename}.jpg`
    }, null, 2));
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
} else if (command === 'list') {
    listDocuments()
        .then(() => process.exit(0))
        .catch(error => {
            console.error('⚠️ Error listing documents:', error);
            process.exit(1);
        });
} else {
    console.error('⚠️ Please provide a valid command: check, create, or list');
    process.exit(1);
} 