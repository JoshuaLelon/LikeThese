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

// Command can be 'check', 'create', or 'list'
const command = process.argv[2];
const basename = process.argv[3];

async function checkDocument(basename) {
    const doc = await db.collection('videos').doc(basename).get();
    if (doc.exists) {
        console.log(`Found existing document for ${basename}`);
    }
    return doc.exists;
}

async function createDocument(basename) {
    // Check again to prevent race conditions
    const doc = await db.collection('videos').doc(basename).get();
    if (doc.exists) {
        console.log(`Document already exists for ${basename}, skipping creation`);
        return;
    }

    const video_url = `https://storage.googleapis.com/likethese-fc23d.firebasestorage.app/videos/${basename}.mp4`;
    const thumbnail_url = `https://storage.googleapis.com/likethese-fc23d.firebasestorage.app/thumbnails/${basename}.jpg`;

    await db.collection('videos').doc(basename).set({
        id: basename,
        url: video_url,
        thumbnailUrl: thumbnail_url,
        timestamp: admin.firestore.FieldValue.serverTimestamp()
    });
    console.log(`Created new document for ${basename}`);
}

async function listDocuments() {
    const snapshot = await db.collection('videos').get();
    snapshot.forEach(doc => {
        console.log(`\nDocument ${doc.id}:`);
        console.log(JSON.stringify(doc.data(), null, 2));
    });
}

// Handle commands
if (command === 'check') {
    if (!basename) {
        console.error('Please provide a video name to check');
        process.exit(1);
    }
    checkDocument(basename)
        .then(exists => {
            process.exit(exists ? 0 : 1);
        })
        .catch(error => {
            console.error('Error checking document:', error);
            process.exit(1);
        });
} else if (command === 'create') {
    if (!basename) {
        console.error('Please provide a video name to create');
        process.exit(1);
    }
    createDocument(basename)
        .then(() => process.exit(0))
        .catch(error => {
            console.error('Error creating document:', error);
            process.exit(1);
        });
} else if (command === 'list') {
    listDocuments()
        .then(() => process.exit(0))
        .catch(error => {
            console.error('Error listing documents:', error);
            process.exit(1);
        });
} else {
    console.error('Please provide a valid command: check, create, or list');
    process.exit(1);
} 