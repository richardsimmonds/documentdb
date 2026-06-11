SET search_path TO documentdb_core,documentdb_api,documentdb_api_catalog,documentdb_api_internal;

SET citus.next_shard_id TO 1012000;
SET documentdb.next_collection_id TO 10120;
SET documentdb.next_collection_index_id TO 10120;

SELECT documentdb_api.insert_one('db','testGroupWithPush',' { "_id" : 1, "product" : "beer", "pricingInfo" : { "msrp": 10, "retailPrice": 15 }, "stock" : 2, "year": 2020 }', NULL);
SELECT documentdb_api.insert_one('db','testGroupWithPush','{ "_id" : 2, "product" : "red wine", "pricingInfo" : { "msrp": 4, "retailPrice": 9 }, "stock" : 1, "year": 2021 }', NULL);
SELECT documentdb_api.insert_one('db','testGroupWithPush',' { "_id" : 3, "product" : "bread", "pricingInfo" : { "msrp": 3, "retailPrice": 11 }, "stock" : 5 , "year": 2020}', NULL);
SELECT documentdb_api.insert_one('db','testGroupWithPush',' { "_id" : 4, "product" : "whiskey", "pricingInfo" : { "msrp": 4, "retailPrice": 10 }, "stock" : 3 , "year": 2022}', NULL);
SELECT documentdb_api.insert_one('db','testGroupWithPush','{ "_id" : 5, "product" : "bread", "pricingInfo" : { "msrp": 75, "retailPrice": 100 }, "stock" : 1, "year": 2021 }', NULL);

/* running multiple $push accumulators with different expressions */
SELECT document FROM documentdb_api_catalog.bson_aggregation_pipeline('db', '{ "aggregate": "testGroupWithPush", "pipeline": [ { "$group": { "_id": "$year", "items": { "$push": { "wholesalePricing":  { "$sum": ["$pricingInfo.msrp", 1] }, "qty": "$stock"} } } } ] }');
SELECT document FROM documentdb_api_catalog.bson_aggregation_pipeline('db', '{ "aggregate": "testGroupWithPush", "pipeline": [ { "$group": { "_id": "$year", "items": { "$push": { "retailPricing":  { "$subtract": ["$pricingInfo.retailPrice", 1] }, "isBread": { "$in": ["$product", ["bread"]] } } } } } ] }');
SELECT document FROM documentdb_api_catalog.bson_aggregation_pipeline('db', '{ "aggregate": "testGroupWithPush", "pipeline": [ { "$group": { "_id": "$year", "items": { "$push": { "shouldBeNull":  { "$subtract": ["$invalidName", 12] } } } } } ] }');
SELECT document FROM documentdb_api_catalog.bson_aggregation_pipeline('db', '{ "aggregate": "testGroupWithPush", "pipeline": [ { "$group": { "_id": "$year", "items": { "$push": { "combinedPrice":  { "$add": ["$pricingInfo.msrp", "$pricingInfo.retailPrice"] } } } } } ] }');

/* shard collection */
SELECT documentdb_api.shard_collection('db', 'testGroupWithPush', '{ "_id": "hashed" }', false);

/* run same $push queries to ensure consistency */
SELECT document FROM documentdb_api_catalog.bson_aggregation_pipeline('db', '{ "aggregate": "testGroupWithPush", "pipeline": [ { "$group": { "_id": "$year", "items": { "$push": { "wholesalePricing":  { "$sum": ["$pricingInfo.msrp", 1] }, "qty": "$stock"} } } } ] }');
SELECT document FROM documentdb_api_catalog.bson_aggregation_pipeline('db', '{ "aggregate": "testGroupWithPush", "pipeline": [ { "$group": { "_id": "$year", "items": { "$push": { "retailPricing":  { "$subtract": ["$pricingInfo.retailPrice", 1] }, "isBread": { "$in": ["$product", ["bread"]] } } } } } ] }');
SELECT document FROM documentdb_api_catalog.bson_aggregation_pipeline('db', '{ "aggregate": "testGroupWithPush", "pipeline": [ { "$group": { "_id": "$year", "items": { "$push": { "shouldBeNull":  { "$subtract": ["$invalidName", 12] } } } } } ] }');
SELECT document FROM documentdb_api_catalog.bson_aggregation_pipeline('db', '{ "aggregate": "testGroupWithPush", "pipeline": [ { "$group": { "_id": "$year", "items": { "$push": { "combinedPrice":  { "$add": ["$pricingInfo.msrp", "$pricingInfo.retailPrice"] } } } } } ] }');

-- Test for missing values
SELECT documentdb_api.insert_one('db','testGroupWithPush','{ "_id" : 7, "product" : "bread", "pricingInfo" : { "msrp": 75, "retailPrice": 100 }, "year": 2021 }', NULL);

SELECT document FROM documentdb_api_catalog.bson_aggregation_pipeline('db', '{ "aggregate": "testGroupWithPush", "pipeline": [{"$match": {"product": "bread"}}, { "$group": { "_id": "$product", "items": { "$push": { "qty": "$stock"} } } } ] }');
SELECT document FROM documentdb_api_catalog.bson_aggregation_pipeline('db', '{ "aggregate": "testGroupWithPush", "pipeline": [{"$match": {"product": "bread"}}, { "$group": { "_id": "$product", "items": { "$push": "$stock" } } } ] }');
SELECT document FROM documentdb_api_catalog.bson_aggregation_pipeline('db', '{ "aggregate": "testGroupWithPush", "pipeline": [{"$match": {"product": "bread"}}, { "$group": { "_id": "$product", "items": { "$push": ["$stock"] } } } ] }');


-- Regression test for GitHub issue #499:
-- $group with $push should preserve the document order established by a preceding $sort stage.
SELECT documentdb_api.insert_one('db','testGroupWithPushSort','{ "_id": 1, "name": "alpha", "category": "A" }', NULL);
SELECT documentdb_api.insert_one('db','testGroupWithPushSort','{ "_id": 2, "name": "charlie", "category": "B" }', NULL);
SELECT documentdb_api.insert_one('db','testGroupWithPushSort','{ "_id": 3, "name": "foxtrot", "category": "A" }', NULL);
SELECT documentdb_api.insert_one('db','testGroupWithPushSort','{ "_id": 4, "name": "hotel", "category": "B" }', NULL);
SELECT documentdb_api.insert_one('db','testGroupWithPushSort','{ "_id": 5, "name": "kilo", "category": "A" }', NULL);
SELECT documentdb_api.insert_one('db','testGroupWithPushSort','{ "_id": 6, "name": "november", "category": "C" }', NULL);
SELECT documentdb_api.insert_one('db','testGroupWithPushSort','{ "_id": 7, "name": "romeo", "category": "A" }', NULL);
SELECT documentdb_api.insert_one('db','testGroupWithPushSort','{ "_id": 8, "name": "sierra", "category": "C" }', NULL);
SELECT documentdb_api.insert_one('db','testGroupWithPushSort','{ "_id": 9, "name": "whiskey", "category": "A" }', NULL);
SELECT documentdb_api.insert_one('db','testGroupWithPushSort','{ "_id": 10, "name": "zulu", "category": "A" }', NULL);

/* $sort ascending followed by $group with $push: arrays should be in ascending order of _id */
SELECT document FROM documentdb_api_catalog.bson_aggregation_pipeline('db', '{ "aggregate": "testGroupWithPushSort", "pipeline": [ { "$sort": { "_id": 1 } }, { "$group": { "_id": "$category", "names": { "$push": "$name" } } }, { "$sort": { "_id": 1 } } ] }');

/* $sort descending followed by $group with $push: arrays should be in descending order of _id */
SELECT document FROM documentdb_api_catalog.bson_aggregation_pipeline('db', '{ "aggregate": "testGroupWithPushSort", "pipeline": [ { "$sort": { "_id": -1 } }, { "$group": { "_id": "$category", "names": { "$push": "$name" } } }, { "$sort": { "_id": 1 } } ] }');

/* $sort on a non-_id field followed by $group with $push */
SELECT document FROM documentdb_api_catalog.bson_aggregation_pipeline('db', '{ "aggregate": "testGroupWithPushSort", "pipeline": [ { "$sort": { "name": 1 } }, { "$group": { "_id": "$category", "names": { "$push": "$name" } } }, { "$sort": { "_id": 1 } } ] }');

/* shard collection and re-run to verify behaviour across shards */
SELECT documentdb_api.shard_collection('db', 'testGroupWithPushSort', '{ "_id": "hashed" }', false);

SELECT document FROM documentdb_api_catalog.bson_aggregation_pipeline('db', '{ "aggregate": "testGroupWithPushSort", "pipeline": [ { "$sort": { "_id": 1 } }, { "$group": { "_id": "$category", "names": { "$push": "$name" } } }, { "$sort": { "_id": 1 } } ] }');
SELECT document FROM documentdb_api_catalog.bson_aggregation_pipeline('db', '{ "aggregate": "testGroupWithPushSort", "pipeline": [ { "$sort": { "_id": -1 } }, { "$group": { "_id": "$category", "names": { "$push": "$name" } } }, { "$sort": { "_id": 1 } } ] }');
