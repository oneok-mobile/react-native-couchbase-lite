//
//  RNCouchbaseLite.swift
//  Created by Jordan Alcott on 4/30/21
//

import Foundation
import React



@objc(RNCouchbaseLite)
class RNCouchbaseLite: RCTEventEmitter {
	
	// ---- Events -------------------------------------
	override init() {
		super.init()
		
		Events.registerEventEmitter(eventEmitter: self)
		
	}
	override func startObserving() {
		super.startObserving()
		Events.listeners += 1
	}
	override func stopObserving() {
		super.stopObserving()
		if Events.listeners > 0 {
			Events.listeners -= 1
		}
	}
	@objc open override func supportedEvents() -> [String] {
		return Events.allEvents
	}
	
	
	// ---- Open Database ------------------------------
	@objc(openDatabase:resolve:reject:)
	func openDatabase(options: NSDictionary, resolve: RCTPromiseResolveBlock, reject: RCTPromiseRejectBlock) -> Void {

		// Database
		do {

			// Get
			let metadata = try Database.getMetadata(options: options)
			return resolve(metadata)

		} catch {

			// Error
			return reject("RNCouchbaseLite-Error", "RNCouchbaseLite.openDatabase: \(error)", nil)
		}

	}


	// ---- Database Metadata --------------------------
	@objc(getDatabaseMetadata:resolve:reject:)
	func getDatabaseMetadata(options: NSDictionary, resolve: RCTPromiseResolveBlock, reject: RCTPromiseRejectBlock) -> Void {

		// Metadata
		do {

			// Get
			let metadata = try Database.getMetadata(options: options)
			return resolve(metadata)

		} catch {

			// Error
			return reject("RNCouchbaseLite-Error", "RNCouchbaseLite.getDatabaseMetadata: \(error)", nil)
		}

	}
	
	
	// ---- Close Database -----------------------------
	@objc(closeDatabase:resolve:reject:)
	func closeDatabase(options: NSDictionary, resolve: RCTPromiseResolveBlock, reject: RCTPromiseRejectBlock) -> Void {

		// Database
		do {

			// Close
			let databaseName = options["databaseName"] as? String ?? ""
			if databaseName.count > 0 {
				try Database.close(databaseName: databaseName)
			}
			return resolve(nil)

		} catch {

			// Error
			return reject("RNCouchbaseLite-Error", "RNCouchbaseLite.closeDatabase: \(error)", nil)
		}

	}
	
	
	// ---- Delete Database ----------------------------
	@objc(deleteDatabase:resolve:reject:)
	func deleteDatabase(options: NSDictionary, resolve: RCTPromiseResolveBlock, reject: RCTPromiseRejectBlock) -> Void {

		// Database
		do {

			// Delete
			let databaseName = options["databaseName"] as? String ?? ""
			try Database.close(databaseName: databaseName, delete: true)
			return resolve(nil)

		} catch {

			// Error
			return reject("RNCouchbaseLite-Error", "RNCouchbaseLite.deleteDatabase: \(error)", nil)
		}

	}
	
	
	// ---- Database Exists ----------------------------
	@objc(databaseExists:resolve:reject:)
	func databaseExists(options: NSDictionary, resolve: RCTPromiseResolveBlock, reject: RCTPromiseRejectBlock) -> Void {

		// Delete
		let exists = Database.exists(databaseName: options["databaseName"] as? String)
		return resolve(exists)

	}
	
	
	// ---- Set Encryption Key -------------------------
	@objc(setDefaultEncryptionKey:resolve:reject:)
	func setDefaultEncryptionKey(options: NSDictionary, resolve: RCTPromiseResolveBlock, reject: RCTPromiseRejectBlock) -> Void {

		// Encryption Key
		do {
			let encryptionKey = options["encryptionKey"] as? String
			if encryptionKey == nil || encryptionKey!.count < 16 {
				throw Errors.invalidParameter("RNCouchbaseLite.setDefaultEncryptionKey: 'encryptionKey' must contain at least 16 characters.")
			}

			// Set
			try Database.setDefaultEncryptionKey(encryptionKey: options["encryptionKey"] as! String)
			return resolve(nil)

		} catch {

			// Error
			return reject("RNCouchbaseLite-Error", "RNCouchbaseLite.setDefaultEncryptionKey: \(error)", nil)
		}

	}
	
	
	// ---- Get Connections ----------------------------
	@objc(getConnections:resolve:reject:)
	func getConnections(options: NSDictionary, resolve: RCTPromiseResolveBlock, reject: RCTPromiseRejectBlock) -> Void {

		// Connections
		do {

			// Get
			let connectionData = try Database.getConnections()
			return resolve(connectionData)

		} catch {

			// Error
			return reject("RNCouchbaseLite-Error", "RNCouchbaseLite.getConnections: \(error)", nil)
		}

	}
	
	
	// ---- Suspend Connections ------------------------
	@objc(suspendConnections:resolve:reject:)
	func suspendConnections(options: NSDictionary, resolve: RCTPromiseResolveBlock, reject: RCTPromiseRejectBlock) -> Void {

		// Connections
		do {

			// Suspend
			try Database.suspendConnections()
			return resolve(nil)

		} catch {

			// Error
			return reject("RNCouchbaseLite-Error", "RNCouchbaseLite.suspendConnections: \(error)", nil)
		}

	}
	
	
	// ---- Resume Connections -------------------------
	@objc(resumeConnections:resolve:reject:)
	func resumeConnections(options: NSDictionary, resolve: RCTPromiseResolveBlock, reject: RCTPromiseRejectBlock) -> Void {

		// Connections
		do {

			// Resume
			try Database.resumeConnections()
			return resolve(nil)

		} catch {

			// Error
			return reject("RNCouchbaseLite-Error", "RNCouchbaseLite.resumeConnections: \(error)", nil)
		}

	}
	
	
	// ---- Create Index -------------------------------
	@objc(createIndex:resolve:reject:)
	func createIndex(options: NSDictionary, resolve: RCTPromiseResolveBlock, reject: RCTPromiseRejectBlock) -> Void {

		// Index
		do {

			// Save
			try Database.createIndex(options: options)
			return resolve(nil)

		} catch {

			// Error
			return reject("RNCouchbaseLite-Error", "RNCouchbaseLite.createIndex: \(error)", nil)
		}

	}
	
	
	// ---- Delete Index -------------------------------
	@objc(deleteIndex:resolve:reject:)
	func deleteIndex(options: NSDictionary, resolve: RCTPromiseResolveBlock, reject: RCTPromiseRejectBlock) -> Void {

		// Index
		do {

			// Delete
			try Database.deleteIndex(options: options)
			return resolve(nil)

		} catch {

			// Error
			return reject("RNCouchbaseLite-Error", "RNCouchbaseLite.deleteIndex: \(error)", nil)
		}

	}


	// ---- Get Document -------------------------------
	@objc(getDocument:resolve:reject:)
	func getDocument(options: NSDictionary, resolve: RCTPromiseResolveBlock, reject: RCTPromiseRejectBlock) -> Void {

		// Document
		do {

			// Get
			let document = try Document.get(options: options)
			return resolve(document)

		} catch {

			// Error
			return reject("RNCouchbaseLite-Error", "RNCouchbaseLite.getDocument: \(error)", nil)
		}

	}
  

	// ---- Get Documents ------------------------------
	@objc(getDocuments:resolve:reject:)
	func getDocuments(request: NSDictionary, resolve: RCTPromiseResolveBlock, reject: RCTPromiseRejectBlock) -> Void {

		// Documents
		do {

			// Get
			let data = try Query.getDocuments(request: request)
			return resolve(data)

		} catch {
			
			// Error
			return reject("RNCouchbaseLite-Error", "RNCouchbaseLite.getDocuments: \(error)", nil)
		}

	}
	
	
	// ---- Save Document ------------------------------
	@objc(saveDocument:resolve:reject:)
	func saveDocument(options: NSDictionary, resolve: RCTPromiseResolveBlock, reject: RCTPromiseRejectBlock) -> Void {

		// Document
		do {

			// Save
			let saveData = try Document.save(options: options)
			let documentId = (saveData["documentIDs"] as! NSArray)[0]
			return resolve(documentId)

		} catch {

			// Error
			return reject("RNCouchbaseLite-Error", "RNCouchbaseLite.saveDocument: \(error)", nil)
		}

	}


	// ---- Save Documents -----------------------------
	@objc(saveDocuments:resolve:reject:)
	func saveDocuments(options: NSDictionary, resolve: RCTPromiseResolveBlock, reject: RCTPromiseRejectBlock) -> Void {

		// Document
		do {

			// Save
			let saveData = try Document.save(options: options)
			return resolve(saveData)

		} catch {

			// Error
			return reject("RNCouchbaseLite-Error", "RNCouchbaseLite.saveDocuments: \(error)", nil)
		}

	}
	
	
	// ---- Delete Document ----------------------------
	@objc(deleteDocument:resolve:reject:)
	func deleteDocument(options: NSDictionary, resolve: RCTPromiseResolveBlock, reject: RCTPromiseRejectBlock) -> Void {

		// Document
		do {

			// Delete
			try Document.delete(options: options)
			return resolve(nil)

		} catch {

			// Error
			return reject("RNCouchbaseLite-Error", "RNCouchbaseLite.deleteDocument: \(error)", nil)
		}

	}
	
	
	// ---- Purge Document -----------------------------
	@objc(purgeDocument:resolve:reject:)
	func purgeDocument(options: NSDictionary, resolve: RCTPromiseResolveBlock, reject: RCTPromiseRejectBlock) -> Void {

		// Document
		do {

			// Purge
			try Document.purge(options: options)
			return resolve(nil)

		} catch {

			// Error
			return reject("RNCouchbaseLite-Error", "RNCouchbaseLite.purgeDocument: \(error)", nil)
		}

	}
	
	
	// ---- Start Replicator ---------------------------
	@objc(startReplicator:resolve:reject:)
	func startReplicator(options: NSDictionary, resolve: RCTPromiseResolveBlock, reject: RCTPromiseRejectBlock) -> Void {
		
		// Replicator
		do {

			// Start
			let replicatorInfo = try Replication.start(options: options)
			return resolve(replicatorInfo.name)

		} catch {

			// Error
			return reject("RNCouchbaseLite-Error", "RNCouchbaseLite.startReplicator: \(error)", nil)
		}

	}
	
	
	// ---- Stop Replicator ----------------------------
	@objc(stopReplicator:resolve:reject:)
	func stopReplicator(options: NSDictionary, resolve: RCTPromiseResolveBlock, reject: RCTPromiseRejectBlock) -> Void {
		
		// Replicator
		do {

			// Stop
			try Replication.stopReplicatorByName(options: options)
			return resolve(nil)

		} catch {

			// Error
			return reject("RNCouchbaseLite-Error", "RNCouchbaseLite.stopReplicator: \(error)", nil)
		}

	}
	
	
	// ---- Get Events ---------------------------------
	@objc(getEvents:resolve:reject:)
	func getEvents(options: NSDictionary, resolve: RCTPromiseResolveBlock, reject: RCTPromiseRejectBlock) -> Void {
		
		// All Events
		return resolve(Events.allEvents)

	}
	
	
	// ---- Add Document Listener ----------------------
	@objc(addDocumentChangeListener:resolve:reject:)
	func addDocumentChangeListener(options: NSDictionary, resolve: RCTPromiseResolveBlock, reject: RCTPromiseRejectBlock) -> Void {
		
		// Listener
		do {

			// Add
			try Document.addChangeListener(options: options)
			return resolve(nil)

		} catch {

			// Error
			return reject("RNCouchbaseLite-Error", "RNCouchbaseLite.addDocumentChangeListener: \(error)", nil)
		}

	}
	
	
	// ---- Remove Document Listener -------------------
	@objc(removeDocumentChangeListener:resolve:reject:)
	func removeDocumentChangeListener(options: NSDictionary, resolve: RCTPromiseResolveBlock, reject: RCTPromiseRejectBlock) -> Void {
		
		// Listener
		do {

			// Remove
			try Document.removeChangeListener(options: options)
			return resolve(nil)

		} catch {

			// Error
			return reject("RNCouchbaseLite-Error", "RNCouchbaseLite.removeDocumentChangeListener: \(error)", nil)
		}

	}
	

}
