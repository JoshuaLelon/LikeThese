async function getImageCaption(imageUrl) {
  console.log('\n🔄 Getting image caption for', imageUrl);
  
  try {
    // Create prediction
    const prediction = await replicate.predictions.create({
      version: "2e1dddc8621f72155f24cf2e0adbde548458d3cab9f00c0139eea840d0ac4746",
      input: {
        image: imageUrl,
        task: "image_captioning",
        use_beam_search: true,
        min_length: 5,
        max_length: 50
      }
    });

    console.log('🔄 Waiting for prediction to complete...');
    console.log('Prediction ID:', prediction.id);
    
    // Wait for the prediction to complete
    let output;
    let attempts = 0;
    const maxAttempts = 30; // Maximum 30 seconds wait
    
    while (!output && attempts < maxAttempts) {
      const predictionStatus = await replicate.predictions.get(prediction.id);
      console.log('Status:', predictionStatus.status, predictionStatus.output);
      
      if (predictionStatus.status === 'succeeded') {
        output = predictionStatus.output;
        break;
      } else if (predictionStatus.status === 'failed') {
        throw new Error(`BLIP model prediction failed: ${predictionStatus.error || 'Unknown error'}`);
      }
      
      attempts++;
      await new Promise(resolve => setTimeout(resolve, 1000)); // Wait 1 second before checking again
    }
    
    if (!output) {
      throw new Error('BLIP model prediction timed out');
    }

    // BLIP returns an array with a single string
    if (!Array.isArray(output)) {
      throw new Error('Invalid response format from BLIP model');
    }

    const caption = output[0];
    if (typeof caption !== 'string' || !caption.trim()) {
      throw new Error('Invalid caption from BLIP model');
    }
    
    console.log('✅ Generated caption:', caption);
    return caption;
  } catch (error) {
    console.error('⚠️ Error generating caption:', error);
    throw error;
  }
}

async function getTextEmbedding(text) {
  if (!text || typeof text !== 'string') {
    throw new Error('Invalid input: text must be a non-empty string');
  }

  console.log('\n🔄 Getting text embedding for:', text);
  
  try {
    const response = await openai.embeddings.create({
      model: "text-embedding-3-small",
      input: text
    });

    if (!response || !response.data || response.data.length === 0) {
      throw new Error('Invalid response from OpenAI API');
    }

    const embedding = response.data[0].embedding;
    if (!Array.isArray(embedding)) {
      throw new Error('Invalid embedding format from OpenAI API');
    }

    console.log('✅ Successfully generated text embedding');
    return embedding;
  } catch (error) {
    if (error.error?.message) {
      console.error('⚠️ OpenAI API Error:', error.error.message);
    }
    console.error('⚠️ Error generating text embedding:', error);
    throw error;
  }
}

async function checkDocument(basename) {
  console.log(`\n🔍 Checking for existing document: ${basename}`);
  const doc = await db.collection('videos').doc(basename).get();
  if (doc.exists) {
    console.log(`✅ Found existing document for ${basename}`);
    return doc.data();
  } else {
    console.log(`➖ No document found for ${basename}`);
    return null;
  }
}

async function migrateDocument(basename) {
  console.log('\n🔄 Migrating document for:', basename);
  
  try {
    // Check if document exists and has text embedding
    const doc = await checkDocument(basename);
    if (!doc) {
      throw new Error(`Document ${basename} not found`);
    }

    console.log('\n🔍 Checking for text embedding:', basename);
    if (doc.textEmbedding) {
      console.log('✅ Text embedding already exists for', basename);
      return;
    } else {
      console.log('➖ No text embedding found for', basename);
    }

    // Get signed URL for thumbnail
    console.log('\n🔑 Getting signed URL for:', doc.thumbnailPath);
    const signedUrl = await getSignedUrl(doc.thumbnailPath);
    console.log('✅ Successfully generated signed URL for', doc.thumbnailPath);

    // Generate caption
    console.log('\n🔄 Generating caption for', basename);
    const caption = await getImageCaption(signedUrl);
    if (!caption) {
      throw new Error('Failed to generate caption');
    }

    // Get text embedding
    console.log('\n🔄 Computing text embedding for', basename);
    const textEmbedding = await getTextEmbedding(caption);
    if (!textEmbedding) {
      throw new Error('Failed to generate text embedding');
    }

    // Update document
    await db.collection('videos').doc(basename).update({
      textEmbedding,
      caption
    });

    console.log('✅ Successfully migrated document:', basename);
  } catch (error) {
    console.error('⚠️ Error migrating document:', error);
    throw error;
  }
} 