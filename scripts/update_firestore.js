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

// Get video name from command line args
const basename = process.argv[2];
if (!basename) {
    console.error('Please provide a video name');
    process.exit(1);
}

// Create URLs
const video_url = `https://storage.googleapis.com/likethese-fc23d.firebasestorage.app/videos/${basename}.mp4`;
const thumbnail_url = `https://storage.googleapis.com/likethese-fc23d.firebasestorage.app/thumbnails/${basename}.jpg`;

// Create/Update document
db.collection('videos').doc(basename).set({
    id: basename,
    url: video_url,
    thumbnailUrl: thumbnail_url,
    timestamp: admin.firestore.FieldValue.serverTimestamp()
}).then(() => {
    console.log('Document created successfully');
    process.exit(0);
}).catch((error) => {
    console.error('Error creating document:', error);
    process.exit(1);
}); 