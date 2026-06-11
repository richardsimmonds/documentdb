# DocumentDB Search Guide

DocumentDB supports three distinct search capabilities, each backed by a dedicated index type
and query surface:

- **Vector search** — find semantically similar documents using embedding vectors (HNSW or IVF)
- **Geospatial search** — query documents by geographic location (2d or 2dsphere indexes)
- **Full-text search** — keyword and phrase matching with language-aware stemming (text index + RUM)

All three use the same `db.collection.createIndex()` / `createIndexes` command to set up an
index, and the same `find` / aggregation pipeline patterns to query.

## Table of Contents

- [Prerequisites](#prerequisites)
- [Vector Search](#vector-search)
  - [When to use it](#when-to-use-it)
  - [Index types: HNSW vs IVF](#index-types-hnsw-vs-ivf)
  - [Creating a vector index](#creating-a-vector-index)
  - [Querying with $search / cosmosSearch](#querying-with-search--cosmossearch)
  - [Querying with $vectorSearch](#querying-with-vectorsearch)
  - [Similarity score projection](#similarity-score-projection)
  - [Filtered vector search](#filtered-vector-search)
  - [Exact (brute-force) search](#exact-brute-force-search)
  - [Vector index parameter reference](#vector-index-parameter-reference)
- [Geospatial Search](#geospatial-search)
  - [When to use it](#when-to-use-it-1)
  - [Index types: 2d vs 2dsphere](#index-types-2d-vs-2dsphere)
  - [Storing geospatial data](#storing-geospatial-data)
  - [Creating a geospatial index](#creating-a-geospatial-index)
  - [Proximity search with $geoNear](#proximity-search-with-geonear)
  - [Range filter with $geoWithin](#range-filter-with-geowithin)
  - [Geospatial index parameter reference](#geospatial-index-parameter-reference)
- [Full-Text Search](#full-text-search)
  - [When to use it](#when-to-use-it-2)
  - [Creating a text index](#creating-a-text-index)
  - [Querying with $text](#querying-with-text)
  - [Search operators](#search-operators)
  - [Language support and stemming](#language-support-and-stemming)
  - [Text score projection](#text-score-projection)
  - [Text index parameter reference](#text-index-parameter-reference)
- [Combining Search Types](#combining-search-types)
- [Index Management](#index-management)

---

## Prerequisites

You need a running DocumentDB instance. The quickest path is Docker:

```bash
docker run -dt -p 10260:10260 --name documentdb documentdb \
  --username admin --password secret
```

Connect with pymongo:

```python
from pymongo import MongoClient

client = MongoClient(
    "mongodb://admin:secret@localhost:10260/?tls=true&tlsAllowInvalidCertificates=true"
)
db = client["mydb"]
```

Or connect with mongosh:

```bash
mongosh "mongodb://admin:secret@localhost:10260/?tls=true&tlsAllowInvalidCertificates=true"
```

---

## Vector Search

### When to use it

Vector search finds documents whose stored embedding vector is _closest_ to a query vector,
measured by a configurable distance metric. Use it for:

- Semantic similarity search over text, images, audio, or any encoded embedding
- Recommendation engines ("find items similar to this one")
- Retrieval-augmented generation (RAG) pipelines

You generate embeddings outside DocumentDB (e.g. with OpenAI, Sentence Transformers, or any
other embedding model), store the resulting float arrays in document fields, and then let
DocumentDB's ANN index do the fast nearest-neighbor retrieval.

### Index types: HNSW vs IVF

DocumentDB supports two approximate nearest-neighbor (ANN) algorithms, both backed by
[pgvector](https://github.com/pgvector/pgvector):

| | HNSW | IVF (IVFFlat) |
|---|---|---|
| **Kind string** | `"vector-hnsw"` | `"vector-ivf"` |
| **Build time** | Slower (graph construction) | Faster (k-means clustering) |
| **Query time** | Faster, better recall | Slightly slower, tunable |
| **Memory** | Higher | Lower |
| **Tune at query time** | `efSearch` | `nProbes` |
| **Max dimensions** | 2000 | 2000 |

HNSW is the better general-purpose default. Use IVF when memory is constrained or the
collection is very large (millions of vectors) and you need faster build times.

### Creating a vector index

The index key is the field that holds the float array. Set the key value to `"cosmosSearch"`
and provide a `cosmosSearchOptions` subdocument with the algorithm, similarity metric, and
vector dimensions.

**HNSW index (cosine similarity, 1536 dimensions):**

```javascript
db.articles.createIndex(
  { embedding: "cosmosSearch" },
  {
    name: "articles_embedding_hnsw",
    cosmosSearchOptions: {
      kind: "vector-hnsw",
      similarity: "COS",   // "COS", "L2", or "IP"
      dimensions: 1536,
      m: 16,               // optional: max connections per layer (default: 16, range: 2–100)
      efConstruction: 64   // optional: build-time search width (default: 64, must be >= 2*m)
    }
  }
)
```

**IVF index (L2 / Euclidean distance, 768 dimensions):**

```javascript
db.images.createIndex(
  { visual_embedding: "cosmosSearch" },
  {
    name: "images_visual_ivf",
    cosmosSearchOptions: {
      kind: "vector-ivf",
      similarity: "L2",
      dimensions: 768,
      numLists: 100   // number of clusters (default: 100); aim for sqrt(N) where N = doc count
    }
  }
)
```

**Similarity metrics:**

| Value | Metric | Good for |
|-------|--------|----------|
| `"COS"` | Cosine | Normalized text/image embeddings |
| `"L2"` | Euclidean (L2) | Absolute spatial distance |
| `"IP"` | Inner Product | Dot-product similarity (unnormalized vectors) |

The similarity metric you choose at index creation time is fixed — it cannot be changed
without dropping and recreating the index. Make sure your choice matches how you compute
distances at query time.

### Querying with $search / cosmosSearch

Use the `$search` aggregation stage with the `cosmosSearch` operator. The vector index must
exist on the field specified by `path`.

```javascript
// Find the 5 articles most similar to a given query embedding
const queryEmbedding = [0.12, -0.34, 0.56, /* ... 1536 floats total */];

db.articles.aggregate([
  {
    $search: {
      cosmosSearch: {
        vector: queryEmbedding,
        path: "embedding",    // field that holds the stored vectors
        k: 5                  // number of nearest neighbors to return
      }
    }
  },
  {
    $project: {
      title: 1,
      body: 1,
      _id: 0
    }
  }
])
```

**With efSearch (HNSW only) — trade recall for speed:**

```javascript
db.articles.aggregate([
  {
    $search: {
      cosmosSearch: {
        vector: queryEmbedding,
        path: "embedding",
        k: 5,
        efSearch: 40   // higher = better recall, slower (default: 2*k, min: 1)
      }
    }
  }
])
```

**With nProbes (IVF only) — how many clusters to search:**

```javascript
db.images.aggregate([
  {
    $search: {
      cosmosSearch: {
        vector: queryEmbedding,
        path: "visual_embedding",
        k: 10,
        nProbes: 20   // higher = better recall, slower (default: numLists, min: 1)
      }
    }
  }
])
```

### Querying with $vectorSearch

DocumentDB also supports the `$vectorSearch` aggregation stage (Atlas-compatible syntax):

```javascript
db.products.aggregate([
  {
    $vectorSearch: {
      queryVector: queryEmbedding,
      path: "product_embedding",
      limit: 10,           // equivalent to k
      numCandidates: 100   // candidates to consider before ranking (>= limit)
    }
  },
  {
    $project: {
      name: 1,
      category: 1,
      _id: 0
    }
  }
])
```

The `$vectorSearch` stage must be the first stage in the pipeline.

### Similarity score projection

After a vector search, DocumentDB attaches a `__cosmos_meta__.score` field to each result.
You can surface it using `$meta: "searchScore"` in a `$project` or `$addFields` stage:

```javascript
db.articles.aggregate([
  {
    $search: {
      cosmosSearch: {
        vector: queryEmbedding,
        path: "embedding",
        k: 5
      }
    }
  },
  {
    $project: {
      title: 1,
      score: { $meta: "searchScore" },
      _id: 0
    }
  }
])
```

Score semantics depend on the similarity metric:

- **COS**: score in [0, 1]; higher is more similar
- **IP**: score = inner product; higher is more similar
- **L2**: score = 1 / (1 + distance); higher is more similar (smaller distance)

### Filtered vector search

You can combine vector search with a document filter. DocumentDB applies the filter before
(pre-filtering) or after (post-filtering) the ANN search, depending on the index type and
planner decision. Pass a `filter` field inside `cosmosSearch`:

```javascript
db.articles.aggregate([
  {
    $search: {
      cosmosSearch: {
        vector: queryEmbedding,
        path: "embedding",
        k: 10,
        filter: {
          category: "technology",
          published: true
        }
      }
    }
  },
  {
    $project: { title: 1, score: { $meta: "searchScore" }, _id: 0 }
  }
])
```

For `$vectorSearch` syntax, pass a `filter` field at the stage level:

```javascript
db.products.aggregate([
  {
    $vectorSearch: {
      queryVector: queryEmbedding,
      path: "product_embedding",
      limit: 5,
      numCandidates: 50,
      filter: { inStock: true, price: { $lt: 100 } }
    }
  }
])
```

### Exact (brute-force) search

To bypass the ANN index and do an exact nearest-neighbor scan (useful for testing or small
collections), set `exact: true` in the `cosmosSearch` spec:

```javascript
db.articles.aggregate([
  {
    $search: {
      cosmosSearch: {
        vector: queryEmbedding,
        path: "embedding",
        k: 5,
        exact: true   // linear scan through all documents
      }
    }
  }
])
```

Exact search ignores the ANN index entirely, so it always returns the true nearest neighbors
but does not scale to large collections.

### Vector index parameter reference

**HNSW (`kind: "vector-hnsw"`):**

| Parameter | Required | Type | Default | Range | Description |
|-----------|----------|------|---------|-------|-------------|
| `similarity` | Yes | string | — | `"COS"`, `"L2"`, `"IP"` | Distance metric |
| `dimensions` | Yes | int | — | 1–2000 | Vector length |
| `m` | No | int | 16 | 2–100 | Max connections per HNSW layer. Higher = better recall, more memory |
| `efConstruction` | No | int | 64 | must be >= 2*m | Build-time beam width. Higher = better recall at build time |
| At query time: `efSearch` | No | int | 2*k | >= 1 | Search beam width. Higher = better recall at query time |

**IVF (`kind: "vector-ivf"`):**

| Parameter | Required | Type | Default | Range | Description |
|-----------|----------|------|---------|-------|-------------|
| `similarity` | Yes | string | — | `"COS"`, `"L2"`, `"IP"` | Distance metric |
| `dimensions` | Yes | int | — | 1–2000 | Vector length |
| `numLists` | No | int | 100 | >= 1 | Number of IVF clusters. Aim for sqrt(N) |
| At query time: `nProbes` | No | int | `numLists` | >= 1 | Clusters to probe. Higher = better recall |

---

## Geospatial Search

### When to use it

DocumentDB's geospatial support lets you query documents by physical location: finding nearby
places, filtering within a polygon, or sorting by distance from a reference point. Use it for:

- Store locators / proximity search ("find cafes within 2 km")
- Geo-fencing ("is this point inside this region?")
- Distance-sorted result sets ("sorted by distance from me")

### Index types: 2d vs 2dsphere

DocumentDB supports two geospatial index types:

| | `2d` | `2dsphere` |
|---|---|---|
| **Coordinate model** | Flat Cartesian plane | Spherical Earth (WGS 84) |
| **Data format** | Legacy `[lng, lat]` pairs or `{x, y}` objects | GeoJSON (`Point`, `Polygon`, `LineString`, etc.) or legacy pairs |
| **Distance unit** | Cartesian distance | Radians or meters |
| **Best for** | Simple games, 2D grids, non-geographic planes | Real-world lat/lng coordinates |

Use `2dsphere` for any real-world geographic data. Use `2d` for non-geographic planes or when
you need backwards compatibility with legacy coordinate pairs.

### Storing geospatial data

**Legacy coordinate pair (works with both `2d` and `2dsphere`):**

```json
{ "location": [longitude, latitude] }
```

Always put longitude first — GeoJSON convention, not latitude-first.

**GeoJSON Point (recommended for `2dsphere`):**

```json
{
  "location": {
    "type": "Point",
    "coordinates": [longitude, latitude]
  }
}
```

**Other GeoJSON types (only `2dsphere`):**

```json
// Polygon (e.g. a delivery zone)
{
  "zone": {
    "type": "Polygon",
    "coordinates": [
      [[-122.4, 37.7], [-122.3, 37.7], [-122.3, 37.8], [-122.4, 37.8], [-122.4, 37.7]]
    ]
  }
}

// MultiPoint, LineString, MultiPolygon, GeometryCollection are also supported
```

### Creating a geospatial index

**2dsphere index (for real-world coordinates):**

```javascript
db.places.createIndex({ location: "2dsphere" })
```

**2d index (for flat coordinates):**

```javascript
db.gamemap.createIndex({ position: "2d" })
```

**2d index with custom coordinate bounds:**

```javascript
// For a 1000x1000 game grid instead of the default [-180, 180] range
db.gamemap.createIndex(
  { position: "2d" },
  { name: "gamemap_pos", min: 0, max: 1000, bits: 26 }
)
```

**Note:** A collection can have at most one `2d` index and one `2dsphere` index per field.
Unlike vector indexes, geospatial indexes do not support compound keys (you cannot pair a `2d`
or `2dsphere` key with another indexed field in the same index document).

### Proximity search with $geoNear

`$geoNear` is an aggregation stage that returns documents sorted by distance from a reference
point. It must be the first stage in the pipeline.

**Find the 5 nearest coffee shops to a given location:**

```javascript
db.places.aggregate([
  {
    $geoNear: {
      near: { type: "Point", coordinates: [-122.419, 37.774] },  // [lng, lat]
      distanceField: "dist.meters",   // field to add to each result document
      maxDistance: 2000,              // meters (for 2dsphere spherical mode)
      spherical: true,                // use spherical Earth model
      key: "location",                // field that holds the coordinates
      query: { category: "coffee" }   // optional pre-filter
    }
  },
  { $limit: 5 },
  { $project: { name: 1, "dist.meters": 1, _id: 0 } }
])
```

**Legacy coordinate pairs (2d index, Cartesian distance):**

```javascript
db.gamemap.aggregate([
  {
    $geoNear: {
      near: [500, 500],
      distanceField: "dist.cartesian",
      key: "position",
      maxDistance: 50   // Cartesian units
    }
  },
  { $limit: 10 }
])
```

**$geoNear parameters:**

| Parameter | Required | Description |
|-----------|----------|-------------|
| `near` | Yes | Reference point: GeoJSON `Point` or `[lng, lat]` legacy pair |
| `distanceField` | Yes | Dotted path of the field to add to each returned document |
| `key` | Yes | The indexed field name |
| `spherical` | No | `true` to use spherical model (required for `2dsphere`); defaults to `false` |
| `maxDistance` | No | Upper bound on distance. Meters if spherical=true, radians otherwise (legacy) |
| `minDistance` | No | Lower bound on distance; same units as `maxDistance` |
| `query` | No | Additional match conditions applied before the geo filter |
| `distanceMultiplier` | No | Multiply the raw distance before storing (e.g. `0.001` to convert meters to km) |
| `includeLocs` | No | Dotted path to include the matched coordinate in results |

**Convert distance to km in the result:**

```javascript
db.places.aggregate([
  {
    $geoNear: {
      near: { type: "Point", coordinates: [-122.419, 37.774] },
      distanceField: "dist.km",
      distanceMultiplier: 0.001,   // meters * 0.001 = km
      spherical: true,
      key: "location"
    }
  },
  { $project: { name: 1, "dist.km": { $round: ["$dist.km", 2] }, _id: 0 } }
])
```

### Range filter with $geoWithin

`$geoWithin` is a query operator (used in `find` or `$match`) that filters documents whose
location falls inside a specified shape. Unlike `$geoNear`, it does not sort by distance.

**Find all stores inside a bounding box (legacy `$box`):**

```javascript
db.stores.find({
  location: {
    $geoWithin: {
      $box: [
        [-122.5, 37.7],   // bottom-left [lng, lat]
        [-122.3, 37.9]    // top-right [lng, lat]
      ]
    }
  }
})
```

**Find all places inside a polygon (GeoJSON `$geometry`):**

```javascript
db.places.find({
  location: {
    $geoWithin: {
      $geometry: {
        type: "Polygon",
        coordinates: [[
          [-122.45, 37.76],
          [-122.41, 37.76],
          [-122.41, 37.80],
          [-122.45, 37.80],
          [-122.45, 37.76]   // close the ring
        ]]
      }
    }
  }
})
```

**Find all points within a radius (legacy `$center` — Cartesian):**

```javascript
db.gamemap.find({
  position: {
    $geoWithin: {
      $center: [[500, 500], 50]   // center point, radius in Cartesian units
    }
  }
})
```

**Find within a sphere on real coordinates (`$centerSphere`):**

```javascript
// 10 km radius centered on San Francisco
const radiusInRadians = 10 / 6378.1;  // km / Earth radius in km

db.places.find({
  location: {
    $geoWithin: {
      $centerSphere: [[-122.419, 37.774], radiusInRadians]
    }
  }
})
```

### Geospatial index parameter reference

**2d index options:**

| Parameter | Default | Range | Description |
|-----------|---------|-------|-------------|
| `min` | -180 | < `max` | Lower bound for coordinate values |
| `max` | 180 | > `min` | Upper bound for coordinate values |
| `bits` | 26 | 1–32 | Precision of the geohash in bits |

**2dsphere index options:**

| Parameter | Default | Range | Description |
|-----------|---------|-------|-------------|
| `coarsestIndexedLevel` | 0 | 0–`finestIndexedLevel` | Minimum S2 cell level to index |
| `finestIndexedLevel` | 30 | `coarsestIndexedLevel`–30 | Maximum S2 cell level to index |

---

## Full-Text Search

### When to use it

DocumentDB's full-text search supports language-aware keyword matching with stemming,
stop-word filtering, and relevance scoring. Use it for:

- Blog / article search ("find posts about machine learning")
- Product catalog keyword search
- Any workload that needs fast, indexed word matching with linguistic normalization

DocumentDB's full-text search is backed by PostgreSQL's RUM index extension (`pg_documentdb_extended_rum`),
which provides better performance than standard GIN for text workloads.

### Creating a text index

Set the key value to `"text"` for any field that holds text you want to search.

**Single-field text index:**

```javascript
db.articles.createIndex({ body: "text" }, { name: "articles_body_text" })
```

**Compound text index (search across multiple fields):**

```javascript
db.articles.createIndex(
  { title: "text", body: "text", tags: "text" },
  { name: "articles_fulltext" }
)
```

A collection can have at most one text index. The compound form is how you search across
multiple fields with a single query.

**Wildcard text index (index all string fields):**

```javascript
db.articles.createIndex({ "$**": "text" }, { name: "articles_all_text" })
```

**Text index with a default language:**

```javascript
// Use Spanish stemming and stop-words by default for this collection
db.articles_es.createIndex(
  { body: "text" },
  { name: "articles_es_text", default_language: "es" }
)
```

### Querying with $text

`$text` is a query operator used inside `find` `filter` or an aggregation `$match` stage.
A text index on the collection is required.

**Basic keyword search:**

```javascript
// Find documents that contain "machine" or "learning" (OR by default)
db.articles.find({ $text: { $search: "machine learning" } })
```

**Phrase search (exact match):**

```javascript
// Quotes force exact phrase match
db.articles.find({ $text: { $search: '"machine learning"' } })
```

**Negation:**

```javascript
// Documents that contain "apple" but NOT "store"
db.articles.find({ $text: { $search: "apple -store" } })
```

**OR search:**

```javascript
// Documents that contain "apple" OR "pear"
db.articles.find({ $text: { $search: "apple pear" } })  // space = OR by default
```

In aggregation:

```javascript
db.articles.aggregate([
  { $match: { $text: { $search: "machine learning" } } },
  { $sort: { _id: 1 } },
  { $limit: 10 }
])
```

### Search operators

| Syntax | Behavior | Example |
|--------|----------|---------|
| `word` | Match documents containing this stem | `"learn"` matches "learning", "learned" |
| `word1 word2` | OR — match either word | `"cat dog"` |
| `"phrase"` | Exact phrase match | `'"New York"'` |
| `-word` | Exclude documents containing this term | `"apple -store"` |

Each word is independently stemmed before matching, so `"cats"` matches documents containing
`"cat"`, `"cats"`, or `"catlike"`, depending on the language's stemmer.

### Language support and stemming

DocumentDB uses PostgreSQL's built-in text search dictionaries. Override the language
per-query with `$language`:

```javascript
// Spanish-language query with Spanish stemming
db.articles_es.find({
  $text: { $search: "Manzana", $language: "es" }
})
```

The `$language` value in the query overrides the index's `default_language`. If you omit
`$language`, DocumentDB uses the language the index was created with (default: `"en"`).

Supported language values include: `"da"` (Danish), `"de"` (German), `"en"` (English),
`"es"` (Spanish), `"fi"` (Finnish), `"fr"` (French), `"hu"` (Hungarian), `"it"` (Italian),
`"nb"` (Norwegian), `"nl"` (Dutch), `"pt"` (Portuguese), `"ro"` (Romanian), `"ru"` (Russian),
`"sv"` (Swedish), and `"tr"` (Turkish).

Set `"none"` to disable stemming and match exact tokens only.

### Text score projection

Retrieve the relevance score for each result using `$meta: "textScore"`:

```javascript
// Return results with their relevance scores, sorted by score descending
db.articles.find(
  { $text: { $search: "machine learning" } },
  { title: 1, score: { $meta: "textScore" } }
).sort({ score: { $meta: "textScore" } })
```

In aggregation:

```javascript
db.articles.aggregate([
  { $match: { $text: { $search: "machine learning" } } },
  {
    $project: {
      title: 1,
      body: 1,
      relevance: { $meta: "textScore" }
    }
  },
  { $sort: { relevance: -1 } },
  { $limit: 10 }
])
```

The text score is a positive float. Higher values indicate stronger relevance — more
matching terms from the search query appear in the document.

### Text index parameter reference

| Parameter | Default | Description |
|-----------|---------|-------------|
| `default_language` | `"en"` | Language for stemming and stop-word filtering |
| `textIndexVersion` | 3 | Text index version. Use 3 (current) |
| `weights` | `{}` | Per-field score multipliers, e.g. `{ title: 10, body: 1 }` to boost title matches |

---

## Combining Search Types

You can use text search and geospatial search together in the same collection. Create a text
index and a geospatial index independently; `find` can apply both filter types simultaneously.

**Example: find coffee shops in an area that match a text query:**

```javascript
// Assume the collection has both a 2dsphere index on "location" and a text index on "description"
db.places.createIndex({ location: "2dsphere" })
db.places.createIndex({ description: "text" })

// Find places near a point that also mention "outdoor seating" in their description
db.places.aggregate([
  {
    $geoNear: {
      near: { type: "Point", coordinates: [-122.419, 37.774] },
      distanceField: "dist.meters",
      maxDistance: 1000,
      spherical: true,
      key: "location",
      query: { $text: { $search: "outdoor seating" } }  // pre-filter
    }
  },
  { $limit: 10 },
  { $project: { name: 1, "dist.meters": 1, description: 1, _id: 0 } }
])
```

Note: vector search, while combinable with arbitrary document filters, cannot be composed
with `$geoNear` in a single stage. Run them as separate queries and join in application code
when you need both.

---

## Index Management

**List indexes on a collection:**

```javascript
db.articles.getIndexes()
```

**Drop a specific index by name:**

```javascript
db.articles.dropIndex("articles_body_text")
```

**Drop all indexes (keeps the `_id` index):**

```javascript
db.articles.dropIndexes()
```

**Check your query used the index (explain):**

```javascript
db.articles.find({ $text: { $search: "machine learning" } }).explain("executionStats")
```

For vector search, use `explain` on the aggregation:

```javascript
db.articles.explain("executionStats").aggregate([
  { $search: { cosmosSearch: { vector: queryEmbedding, path: "embedding", k: 5 } } }
])
```

A vector search using the HNSW or IVF index will show an `Index Scan` on the vector index in
the explain output. If you see a `Seq Scan`, the index was not used — check that the vector
dimensions in the query match the dimensions the index was created with, and that the field
name in `path` matches the indexed field.
