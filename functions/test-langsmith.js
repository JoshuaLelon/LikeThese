const admin = require('firebase-admin');
const serviceAccount = require('./service-account.json');

admin.initializeApp({
  credential: admin.credential.cert(serviceAccount)
});

async function testLangSmith() {
  try {
    console.log('🔄 Testing LangSmith integration...');
    const result = await admin.functions().httpsCallable('testLangSmith')({});
    console.log('✅ Test successful:', result.data);
  } catch (error) {
    console.error('❌ Test failed:', error);
  } finally {
    process.exit();
  }
}

testLangSmith(); 