#import <React/RCTBridgeModule.h>
#import <React/RCTEventEmitter.h>
#import "RNConsole.h"


@interface RCT_EXTERN_MODULE(RNCouchbaseLite, RCTEventEmitter)

	+ (BOOL)requiresMainQueueSetup
	{
		return YES;
	}

	// "EXTERN" Method: Link to Swift Class Method
	RCT_EXTERN_METHOD(openDatabase:(NSDictionary *)options resolve:(RCTPromiseResolveBlock)resolve reject:(RCTPromiseRejectBlock)reject)

	RCT_EXTERN_METHOD(getDatabaseMetadata:(NSDictionary *)options resolve:(RCTPromiseResolveBlock)resolve reject:(RCTPromiseRejectBlock)reject)

	RCT_EXTERN_METHOD(closeDatabase:(NSDictionary *)options resolve:(RCTPromiseResolveBlock)resolve reject:(RCTPromiseRejectBlock)reject)

	RCT_EXTERN_METHOD(deleteDatabase:(NSDictionary *)options resolve:(RCTPromiseResolveBlock)resolve reject:(RCTPromiseRejectBlock)reject)

	RCT_EXTERN_METHOD(databaseExists:(NSDictionary *)options resolve:(RCTPromiseResolveBlock)resolve reject:(RCTPromiseRejectBlock)reject)

	RCT_EXTERN_METHOD(setDefaultEncryptionKey:(NSDictionary *)options resolve:(RCTPromiseResolveBlock)resolve reject:(RCTPromiseRejectBlock)reject)

	RCT_EXTERN_METHOD(getConnections:(NSDictionary *)options resolve:(RCTPromiseResolveBlock)resolve reject:(RCTPromiseRejectBlock)reject)

	RCT_EXTERN_METHOD(suspendConnections:(NSDictionary *)options resolve:(RCTPromiseResolveBlock)resolve reject:(RCTPromiseRejectBlock)reject)

	RCT_EXTERN_METHOD(resumeConnections:(NSDictionary *)options resolve:(RCTPromiseResolveBlock)resolve reject:(RCTPromiseRejectBlock)reject)

	RCT_EXTERN_METHOD(createIndex:(NSDictionary *)options resolve:(RCTPromiseResolveBlock)resolve reject:(RCTPromiseRejectBlock)reject)

	RCT_EXTERN_METHOD(deleteIndex:(NSDictionary *)options resolve:(RCTPromiseResolveBlock)resolve reject:(RCTPromiseRejectBlock)reject)

	RCT_EXTERN_METHOD(getDocument:(NSDictionary *)options resolve:(RCTPromiseResolveBlock)resolve reject:(RCTPromiseRejectBlock)reject)

	RCT_EXTERN_METHOD(getDocuments:(NSDictionary *)request resolve:(RCTPromiseResolveBlock)resolve reject:(RCTPromiseRejectBlock)reject)

	RCT_EXTERN_METHOD(saveDocument:(NSDictionary *)options resolve:(RCTPromiseResolveBlock)resolve reject:(RCTPromiseRejectBlock)reject)

	RCT_EXTERN_METHOD(saveDocuments:(NSDictionary *)options resolve:(RCTPromiseResolveBlock)resolve reject:(RCTPromiseRejectBlock)reject)

	RCT_EXTERN_METHOD(deleteDocument:(NSDictionary *)options resolve:(RCTPromiseResolveBlock)resolve reject:(RCTPromiseRejectBlock)reject)

	RCT_EXTERN_METHOD(purgeDocument:(NSDictionary *)options resolve:(RCTPromiseResolveBlock)resolve reject:(RCTPromiseRejectBlock)reject)

	RCT_EXTERN_METHOD(startReplicator:(NSDictionary *)options resolve:(RCTPromiseResolveBlock)resolve reject:(RCTPromiseRejectBlock)reject)

	RCT_EXTERN_METHOD(stopReplicator:(NSDictionary *)options resolve:(RCTPromiseResolveBlock)resolve reject:(RCTPromiseRejectBlock)reject)

	RCT_EXTERN_METHOD(getEvents:(NSDictionary *)options resolve:(RCTPromiseResolveBlock)resolve reject:(RCTPromiseRejectBlock)reject)

	RCT_EXTERN_METHOD(addDocumentChangeListener:(NSDictionary *)options resolve:(RCTPromiseResolveBlock)resolve reject:(RCTPromiseRejectBlock)reject)

	RCT_EXTERN_METHOD(removeDocumentChangeListener:(NSDictionary *)options resolve:(RCTPromiseResolveBlock)resolve reject:(RCTPromiseRejectBlock)reject)

@end
