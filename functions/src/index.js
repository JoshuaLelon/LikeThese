function cosineDistance(a, b) {
  if (!a || !b || !Array.isArray(a) || !Array.isArray(b)) {
    console.log('❌ Invalid embeddings:', { a: !!a, b: !!b, aIsArray: Array.isArray(a), bIsArray: Array.isArray(b) });
    return 1;
  }

  if (a.length !== b.length) {
    console.log('❌ Embedding length mismatch:', { aLength: a.length, bLength: b.length });
    return 1;
  }

  const dotProduct = a.reduce((sum, val, i) => sum + val * b[i], 0);
  const normA = Math.sqrt(a.reduce((sum, val) => sum + val * val, 0));
  const normB = Math.sqrt(b.reduce((sum, val) => sum + val * val, 0));

  if (normA === 0 || normB === 0) {
    console.log('⚠️ Zero magnitude vector detected:', { normA, normB });
    return 1;
  }

  const similarity = dotProduct / (normA * normB);
  const distance = 1 - similarity;

  console.log('📐 Cosine calculation details:', {
    dotProduct: dotProduct.toFixed(6),
    normA: normA.toFixed(6),
    normB: normB.toFixed(6),
    similarity: similarity.toFixed(6),
    distance: distance.toFixed(6)
  });

  return distance;
} 