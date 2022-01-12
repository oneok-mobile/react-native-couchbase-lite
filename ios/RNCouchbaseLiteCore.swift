//
//  RNCouchbaseLiteCore.swift
//  RNCouchbaseLite
//
//  Created by Jordan Alcott on 8/17/21.
//
//

import Foundation
import CouchbaseLiteSwift


extension RNCouchbaseLite {
	
	
	// -------------------------------------------------------------------------------------------
	// ---- Database -----------------------------------------------------------------------------
	
	class Database: NSObject {
		static let metaDatabase : String = "metadb"
		static let defaultDatabase : String = "cbdb"
		static let encryptionStorageKey : String = "RNCouchbaseLite.defaultEncryptionKey"
		
		// Connection
		class Connection : NSObject {
			var database : CouchbaseLiteSwift.Database? // Optional because CouchbaseliteSwift documentation says that it can be null (sic) when resuming from background state
			var name : String
			var encryptionKey : String
			var directory : String? = nil
			var listener : ListenerToken? = nil
			var documentListeners : [String:ListenerToken] = [:]
			var replicators : [Replication.ReplicatorInfo] = []

			init(database: CouchbaseLiteSwift.Database, name: String, encryptionKey: String) {
				self.database = database
				self.name = name
				self.encryptionKey = encryptionKey
			}
		}

		// Connections Store
		static var Connections : [String:Connection] = [:]
		
		
		
		
		// ---- Database Exists ----------------------------
		static func exists(databaseName: String?) -> Bool {

			return CouchbaseLiteSwift.Database.exists(withName: databaseName ?? "")
		}
		
		
		// ---- Open Database ------------------------------
		static func open(options: NSDictionary) throws -> Void {
			let _ = try getConnection(options)
		}


		// ---- Get Database Connection --------------------
		static func getConnection(_ options: NSDictionary = [:], databaseName: String? = nil) throws -> Connection {
			
			// Existing Connection
			let _databaseName = databaseName ?? (options["databaseName"] as? String) ?? defaultDatabase
			if Connections[_databaseName] != nil {
				return Connections[_databaseName]!
			}
			
			// Config
			let config = DatabaseConfiguration()
			let directory = options["directory"] as? String ?? ""
			if directory.count > 0 { config.directory = directory; }
			var encryptionKey = ""
			#if CBLENTERPRISE
				encryptionKey = try options["encryptionKey"] as? String ?? getDefaultEncryptionKey()
				if encryptionKey.count > 0 {
					config.encryptionKey = EncryptionKey.password(encryptionKey)
				}
			#endif

			// Database
			RNConsole.log("Opening \(_databaseName)\(directory.count > 0 ? " in \(directory)" : "")")
			let database = try CouchbaseLiteSwift.Database(name: _databaseName, config: config)
			Connections[_databaseName] = Connection(database: database, name: _databaseName, encryptionKey: encryptionKey)
			if _databaseName != metaDatabase {
				let databaseListener : ListenerToken = database.addChangeListener { (change) in
					Events.publish("Database.Change", ["databaseName":_databaseName, "documentIDs":change.documentIDs])
				}
				Connections[_databaseName]?.listener = databaseListener
			}
			if directory.count > 0 { Connections[_databaseName]?.directory = directory; }
			
			return Connections[_databaseName]!
		}


		// ---- Close Database -----------------------------
		static func close(databaseName: String, delete: Bool = false) throws -> Void {

			// Connection
			if Connections[databaseName] == nil {
				if exists(databaseName: databaseName) {
					RNConsole.log("RNCouchbaseLite: The database needs to be opened before it can be \(delete ? "deleted" : "closed").")
				}
				else {
					RNConsole.log("RNCouchbaseLite: The database does not exist.")
				}
				return
			}

			// Database
			let databaseConnection : Connection = Connections[databaseName]!

			// Close Listeners
			if databaseConnection.listener != nil {
				databaseConnection.database?.removeChangeListener(withToken: databaseConnection.listener!)
			}
			databaseConnection.documentListeners.forEach { (listenerToken) in 
				databaseConnection.database?.removeChangeListener(withToken: listenerToken.value)
			}
			databaseConnection.documentListeners.removeAll()

			// Close Replicators
			try databaseConnection.replicators.forEach { (replicatorInfo) in 
				try Replication.stop(databaseConnection: databaseConnection, replicatorName: replicatorInfo.name)
			}

			// Close Database (Documentation: Before closing the database, the active replicators, listeners and live queries will be stopped.)
			if delete {
				try databaseConnection.database?.delete()
			}
			else {
				try databaseConnection.database?.close()
			}
			RNConsole.log("Database '\(databaseConnection.database?.name ?? databaseConnection.name)' \(delete ? "deleted" : "closed").")
			Connections.removeValue(forKey: databaseName)
		}
		
		
		// ---- Get Metadata -------------------------------
		static func getMetadata(options: NSDictionary) throws -> NSDictionary {

			// Database
			let databaseConection = try getConnection(options)
			var metadata : [String:Any] = [:]
			metadata["name"] = databaseConection.database!.name
			metadata["directory"] = databaseConection.directory
			metadata["path"] = databaseConection.database!.path
			metadata["count"] = databaseConection.database!.count
			metadata["indexes"] = databaseConection.database!.indexes
			metadata["documentListeners"] = databaseConection.documentListeners.map({ (documentId: String, _: ListenerToken) in return documentId; })
			metadata["replicators"] = databaseConection.replicators.map({ (replicatorInfo) -> String in return replicatorInfo.name; })
			return metadata as NSDictionary
		}
		

		// ---- Get Connections  ---------------------------
		static func getConnections() throws -> [NSDictionary] {
			
			// Filter metadata database from Connections list
			let _connections = Connections.filter { (databaseName: String, value: Connection) in
				return databaseName != metaDatabase
			}
			
			// Return generated metadata for each connection
			return try _connections.map { (databaseName: String, value: Connection) in
				return try Database.getMetadata(options: ["databaseName":databaseName])
			}
			
		}
		
		
		// ---- Suspend All Connections --------------------
		static func suspendConnections() throws -> Void {
			
			// Prepare suspension database
			try Database.open(options: ["databaseName":metaDatabase, "encryptionKey":getDefaultEncryptionKey()])
			
			// Connections
			try Connections.forEach { (key: String, connection: Connection) in
				
				// Don't store metadata database metadata in metadata database
				if key == metaDatabase {
					return
				}
				
				// Check for background replication
				let backgroundReplicationEnabled = connection.replicators.contains { (replicatorInfo) in
					return replicatorInfo.config["allowReplicatingInBackground"] as? Bool ?? false
				}
				
				// Save database metadata
				let document : NSDictionary = [
					// "id" : "suspension_\(connection.name)",
					"type" : "suspended",
					"name" : connection.name,
					"encryptionKey" : connection.encryptionKey,
					"directory" : connection.directory ?? "",
					"documentListeners" : connection.documentListeners.map({ (key: String, _) in return key; }),
					"replicators" : connection.replicators.map({ (replicatorInfo) in return replicatorInfo.config; }),
					"backgroundReplication" : backgroundReplicationEnabled
				]
				let _ = try Document.save(options: ["databaseName":metaDatabase, "document":document])
				
				// Close database without background replication
				if !backgroundReplicationEnabled {
					try Database.close(databaseName: connection.database!.name)
					return
				}

				// Don't close database with background replication.
				// Close Listeners
				connection.database!.removeChangeListener(withToken: connection.listener!)
				connection.documentListeners.forEach { (listenerToken) in 
					connection.database!.removeChangeListener(withToken: listenerToken.value)
				}
				connection.documentListeners.removeAll()
				
				// & Non-Background Replicators
				try connection.replicators.forEach { (replicatorInfo) in
					if !(replicatorInfo.config["allowReplicatingInBackground"] as? Bool ?? false) {
						try Replication.stop(databaseConnection: connection, replicatorName: replicatorInfo.name)
					}
				}
			}
		}
		
		
		// ---- Resume All Connections ---------------------
		static func resumeConnections() throws -> Void {
			
			do {
				// Prepare Metadata Database
				try Database.open(options: ["databaseName":metaDatabase, "encryptionKey":getDefaultEncryptionKey()])
			}
			catch {
				// TODO: Delete database (File system delete)
				throw Errors.invalidState("Metadata database is inaccessible.")
			}
			
			// Get Suspended Database Metadata from Metadata database
			let suspendedDatabases : [NSDictionary] = try Query.getDocuments(request: [
				"select"	: ["id","type","name","encryptionKey","directory","documentListeners","replicators"],
				"from"		: metaDatabase,
				"where"		: [["type":"suspended"]]
			])
			
			// Databases
			try suspendedDatabases.forEach { (suspendedDatabase) in
				let databaseName = suspendedDatabase["name"] as! String
				let backgroundReplication = suspendedDatabase["backgroundReplication"] as? Bool ?? false
				
				// Database w/ Background Replication
				if backgroundReplication {
					try Database.close(databaseName: databaseName) // & Stop Replicators
				}
				
				// Reconnect
				try Database.resumeConnection(suspendedDatabase: suspendedDatabase)
				
				// Remove from suspended database list
				try Document.purge(options: ["databaseName":metaDatabase, "documentId":suspendedDatabase["id"]!])
			}
			
		}
		
		
		// ---- Resume Connection --------------------------
		static func resumeConnection(suspendedDatabase: NSDictionary) throws -> Void {
			
			// Open Database
			let databaseName = suspendedDatabase["name"] as! String
			let encryptionKey = suspendedDatabase["encryptionKey"] as? String
			let directory = suspendedDatabase["directory"] as? String
			try Database.open(options: ["databaseName":databaseName, "encryptionKey":(encryptionKey as Any), "directory":(directory as Any)])

			// Create Document Listeners
			let documentListeners = suspendedDatabase["documentListeners"] as! [String]
			try documentListeners.forEach { (documentId) in
				try Document.addChangeListener(options: ["databaseName":databaseName, "documentId":documentId])
			}

			// Restart Replicators
			let replicators = suspendedDatabase["replicators"] as! [NSDictionary]
			try replicators.forEach { (replicatorConfig) in
				let _ = try Replication.start(options: replicatorConfig)
			}
		}
		
		
		// ---- Get Default Encryption Key -----------------
		static func getDefaultEncryptionKey() throws -> String {
			
			#if CBLENTERPRISE
				// Encryption Key
				var encyptionKey = try SecureStorage.getString(key: encryptionStorageKey)
				if encyptionKey == nil {
					encyptionKey = UUID().uuidString
					try SecureStorage.storeString(key: encryptionStorageKey, value: encyptionKey!)
				}
				return encyptionKey!
			#else
				// Only the enterprise edition supports encryption
				return ""
			#endif
		}
		
		
		// ---- Set Default Encryption Key -----------------
		static func setDefaultEncryptionKey(encryptionKey: String) throws -> Void {
			
			// Update Encryption Key
			let existingKey = try SecureStorage.getString(key: encryptionStorageKey)
			if existingKey == nil {
				try SecureStorage.storeString(key: encryptionStorageKey, value: encryptionKey)
			}
			else {
				try SecureStorage.updateString(key: encryptionStorageKey, value: encryptionKey)
			}
			
			// Update Metadata Database
			if Database.exists(databaseName: metaDatabase) {
				try Database.open(options: ["databaseName":metaDatabase, "encryptionKey":getDefaultEncryptionKey()])
				let allDocs = try Query.getDocuments(request: ["from":metaDatabase])
				try Database.close(databaseName: metaDatabase, delete: true)
				try Database.open(options: ["databaseName":metaDatabase, "encryptionKey":encryptionKey])
				let _ = try Document.save(options: ["databaseName":metaDatabase, "documents":allDocs])
			}
		}
		

		// ---- Create Index -------------------------------
		static func createIndex(options: NSDictionary) throws -> Void {

			// Document
			if options["indexFields"] == nil {
				throw Errors.invalidParameter("indexFields is required")
			}

			// Database
			let databaseConection = try getConnection(options)

			// Index
			var indexName = ""
			let indexFields : [ValueIndexItem] = (options["indexFields"] as! [String]).map { (fieldName) -> ValueIndexItem in
				indexName += fieldName
				return ValueIndexItem.expression(Expression.property(fieldName))
			}
			indexName += "ValueIndex"

			// Create
			let index = IndexBuilder.valueIndex(items: indexFields)
			try databaseConection.database!.createIndex(index, withName: indexName)
		}


		// ---- Delete Index -------------------------------
		static func deleteIndex(options: NSDictionary) throws -> Void {

			// Database
			let databaseConection = try getConnection(options)

			// Index
			let indexName = options["indexName"] as? String ?? ""
			if indexName.count > 0 {
				// Delete
				try databaseConection.database!.deleteIndex(forName: indexName)
			}
		}

	}
	
	
	
	// ---------------------------------------------------------------------------------------------------
	// ---- Document -------------------------------------------------------------------------------------
	
	class Document: NSObject {

		// ---- Get Document -------------------------------
		static func get(options: NSDictionary) throws -> NSDictionary? {

			// Document ID
			if options["documentId"] == nil {
				throw Errors.invalidParameter("documentId is required")
			}
			let documentId = options["documentId"] as! String

			// Database
			let databaseConection = try Database.getConnection(options)

			// Document
			if let document = databaseConection.database!.document(withID: documentId) {
				return document.toDictionary() as NSDictionary
			}
			return nil;
		}
		
		
		// ---- Save Document ------------------------------
		static func save(options: NSDictionary) throws -> NSDictionary {
			
			// Documents
			let document = options["document"] as? NSDictionary
			let documents = options["documents"] as? [NSDictionary] ?? (document != nil ? [document!] : [])
			if documents.count < 1 {
				throw Errors.invalidParameter("Either 'documents' or 'document' must be supplied")
			}

			// Database
			let databaseConection = try Database.getConnection(options)
			let database = databaseConection.database!
			
			// Documents
			var documentIDs: [String] = []
			var errors: [Dictionary<String, Any>] = []
			try database.inBatch {
				for document in documents {
					do {
						// Existing Document
						let hasId : Bool = (document["id"] != nil)
						let documentId = hasId ? document["id"] as! String : ""
						var existingDocument : CouchbaseLiteSwift.Document?
						if hasId {
							document.setValue(nil, forKey: "id") // Remove 'id' from Dictionary

							// Check for existing document
							existingDocument = database.document(withID: documentId)
							if existingDocument != nil { // Document Exists

								// Set Document
								let mutableDoc = existingDocument!.toMutable()
								mutableDoc.setData(document as? Dictionary<String, Any>) // 'setData' replaces the whole document

								// Save to Database
								try database.saveDocument(mutableDoc)
								documentIDs.append(documentId)
								continue
							}
						}

						// New Document
						var mutableDoc : MutableDocument
						if (hasId) {
							mutableDoc = MutableDocument(id: documentId, data: document as? Dictionary<String, Any>)
						}
						else {
							mutableDoc = MutableDocument(data: document as? Dictionary<String, Any>)
						}
						try database.saveDocument(mutableDoc)
						documentIDs.append(mutableDoc.id)
						continue
					}
					catch {
						errors.append((error as NSError).toDictionary())
						continue
					}
				}
			}
			
			// Return Results
			return ["documentIDs":documentIDs, "errors":errors]
		}


		// ---- Delete Document ----------------------------
		static func delete(options: NSDictionary) throws -> Void {
			let documentId = options["documentId"] as? String
			if documentId == nil {
				return;
			}

			// Database
			let databaseConection = try Database.getConnection(options)

			// Document
			let document = databaseConection.database!.document(withID: documentId!)
			if document != nil {

				// Delete
				try databaseConection.database!.deleteDocument(document!)
			}
		}


		// ---- Purge Document -----------------------------
		static func purge(options: NSDictionary) throws -> Void {

			// Database
			let databaseConection = try Database.getConnection(options)

			// Purge (Document)
			if (options["documentId"] as? String ?? "").count > 0 {
				try databaseConection.database!.purgeDocument(withID: options["documentId"] as! String)
			}
		}
		
		
		// ---- Add Document Listener ----------------------
		static func addChangeListener(options: NSDictionary) throws -> Void {
			
			// DocID
			let documentId = options["documentId"] as? String ?? ""
			if documentId.count < 1 {
				throw Errors.invalidParameter("Document.addChangeListener: documentId is required.")
			}
			
			// Database
			let databaseConection = try Database.getConnection(options)
			if databaseConection.documentListeners[documentId] != nil {
				return
			}

			// Listener
			let listenerToken = databaseConection.database!.addDocumentChangeListener(withID: documentId, listener: { (change) in
				Events.publish("Document.Change", ["databaseName":databaseConection.name, "documentID":change.documentID])
			})
			databaseConection.documentListeners[documentId] = listenerToken
		}
		
		
		// ---- Remove Document Listener -------------------
		static func removeChangeListener(options: NSDictionary) throws -> Void {
			
			// DocID
			let documentId = options["documentId"] as? String ?? ""
			if documentId.count < 1 {
				throw Errors.invalidParameter("Document.addChangeListener: documentId is required.")
			}
			
			// Database
			let databaseConection = try Database.getConnection(options)
			if databaseConection.documentListeners[documentId] == nil {
				return
			}

			// Remove
			databaseConection.database!.removeChangeListener(withToken: databaseConection.documentListeners[documentId]!)
			databaseConection.documentListeners.removeValue(forKey: documentId)
		}

	}
	
	
	
	// ---------------------------------------------------------------------------------------------------
	// ---- Replication ----------------------------------------------------------------------------------
	
	class Replication: NSObject {
		
		class ReplicatorInfo: NSObject {
			var name : String
			var config : NSDictionary
			var replicator : CouchbaseLiteSwift.Replicator?
			var listeners : [ListenerToken] = []

			init(name: String, config: NSDictionary, replicator: Replicator) {
				self.name = name
				self.config = config
				self.replicator = replicator
			}
		}
		
		

		// ---- Start Replicator ---------------------------
		static func start(options: NSDictionary) throws -> RNCouchbaseLite.Replication.ReplicatorInfo {

			// Database
			let databaseName = options["databaseName"] as? String
			let databaseConection = try RNCouchbaseLite.Database.getConnection(options)

			// Target
			let target = options["target"] as? String // Example: "wss://10.1.1.12:8092/actDb"
			if target == nil {
				throw Errors.invalidParameter("target is required")
			}
			let targetURL = URL(string: target!)!
			let targetURLEndpoint = URLEndpoint(url: targetURL)

			// Configuration Object
			let replicationConfig = ReplicatorConfiguration(database: databaseConection.database!, target: targetURLEndpoint)

			// Replicator Type
			let replicatorType = options["replicatorType"] as? String
			switch (replicatorType ?? "").lowercased() {
				case "push": replicationConfig.replicatorType = ReplicatorType.push
				case "pull": replicationConfig.replicatorType = ReplicatorType.pull
				default: replicationConfig.replicatorType = ReplicatorType.pushAndPull
			}

			// Continuous Replication
			let continuous = options["continuous"] as? Bool ?? true
			replicationConfig.continuous = continuous

			// Channels
			let channels = options["channels"] as? [String]
			if channels != nil && channels!.count > 0 {
				replicationConfig.channels = channels!
			}

			// Document IDs
			let documentIDs = options["documentIDs"] as? [String]
			if documentIDs != nil && documentIDs!.count > 0 {
				replicationConfig.documentIDs = documentIDs!
			}

			// Heartbeat
			let heartbeat = options["heartbeat"] as? Double
			if heartbeat != nil {
				replicationConfig.heartbeat = heartbeat!
			}
			
			#if CBLENTERPRISE
			// Accept Self-Signed Certificates (DEV ONLY)
			let selfSigned = options["selfSigned"] as? Bool ?? false
			replicationConfig.acceptOnlySelfSignedServerCertificate = selfSigned
			#endif

			// Pinned Certificate
			var certData : Data? = nil
			if let certificateURL = options["certificateURL"] as? String {
				certData = try Data(contentsOf: URL(string: certificateURL)!)
			}
			let encodedCertificate = options["cerificate"] as? String
			if encodedCertificate != nil {
				certData = Data(base64Encoded: encodedCertificate!)
			}
			if certData != nil {
			let certificate = SecCertificateCreateWithData(nil, certData! as CFData)
				replicationConfig.pinnedServerCertificate = certificate
			}

			// Authenticator
			let authenticationType = options["authenticationType"] as? String
			switch (authenticationType ?? "").uppercased() {

				case "BASIC":
					// Username
					let username = options["username"] as? String 
					if username == nil || username!.count < 1 {
						throw Errors.invalidParameter("username is required for basic authentication")
					}
					// Password
					let password = options["password"] as? String 
					if password == nil {
						throw Errors.invalidParameter("password is required for basic authentication")
					}
					// Authenticator
					let authenticator = BasicAuthenticator(username: username!, password: password!)
					replicationConfig.authenticator = authenticator

				default: // SESSION
					let sessionID = options["sessionID"] as? String
					if sessionID == nil {
						throw Errors.invalidParameter("sessionID is required for session authentication")
					}
					replicationConfig.authenticator = SessionAuthenticator(sessionID: sessionID!)
			}

			// Headers
			let headers = options["headers"] as? Dictionary<String, String>
			if headers != nil && headers!.count > 0 {
				replicationConfig.headers = headers!
			}

			// Background Replication // (If setting the value to [true], please [get user/device permission] properly.)
			let allowReplicatingInBackground = options["allowReplicatingInBackground"] as? Bool
			if allowReplicatingInBackground != nil {
				replicationConfig.allowReplicatingInBackground = allowReplicatingInBackground!
			}


			//	/* Optionally set custom conflict resolver call back */
			//	replicationConfig.conflictResolver = ( /* TODO: evaluate if a conflict resolver can be reasonably defined in JSON data */);
			
			
			// Verbose Events
			let verboseEvents = options["verboseEvents"] as? Bool ?? false
			
			
			// Push Filter
			let pushFilter = options["pushFilter"] as? NSDictionary
			if pushFilter != nil {
				let applyPushFilter = getDictionaryFilter(filterDefinition: pushFilter!)
				replicationConfig.pushFilter = { (document, flags) in
					return applyPushFilter(document, flags)
				}
			}
			
			// Pull Filter
			let enableAccessRemovedEvent = options["enableAccessRemovedEvent"] as? Bool ?? false
			let enablePullDeleteEvent = options["enablePullDeleteEvent"] as? Bool ?? false
			let pullFilter = options["pullFilter"] as? NSDictionary
			if (pullFilter != nil || enableAccessRemovedEvent || enablePullDeleteEvent) {
				let applyPullFilter = getDictionaryFilter(filterDefinition: pullFilter)
				replicationConfig.pullFilter = { (document, flags) in
					
					// Flags
					let eventPayload = verboseEvents ? ["databaseName":databaseConection.name, "document":document.toDictionary()] : ["docId":document.id]
					if (enablePullDeleteEvent && flags.contains(.deleted)) {
						Events.publish("Replication.Pull.Delete", eventPayload)
					}
					if (enableAccessRemovedEvent && flags.contains(.accessRemoved)) {
						Events.publish("Replication.Pull.AccessRemoved", eventPayload)
					}
					
					// Filter
					return applyPullFilter(document, flags)
				}
			}

			
			// Replicator Name
			let defaultName : String = "\(databaseName ?? "defaultDb")-\(target!)-\(replicatorType ?? "pushAndPull")-\(continuous ? "continuous" : "adhoc")-\(channels?.joined(separator: "-") ?? "allChannels")-\(documentIDs?.joined(separator: "-") ?? "allDocs")\(pushFilter == nil ? "" : "-PushFilter\(getFilterName(filterDefinition: pushFilter))")\(pullFilter == nil ? "" : "-PullFilter\(getFilterName(filterDefinition: pullFilter))")"
			let replicatorName = options["name"] as? String ?? defaultName
			let existingReplicatorInfo = getReplicatorByName(databaseConnection: databaseConection, replicatorName: replicatorName)
			if existingReplicatorInfo != nil {
				let replicator : Replicator = existingReplicatorInfo!.replicator!
				if replicator.status.activity == Replicator.ActivityLevel.stopped {
					replicator.start()
				}
				return existingReplicatorInfo!
			}
			
			// Initialize Replicator
			let replicator : Replicator = Replicator.init(config: replicationConfig)

			
			// Change Listener
			let changeListener : ListenerToken = replicator.addChangeListener({ (change) in // .split(separator: ".")[3]
				let status : [String : Any] = ["activity":String(describing: change.replicator.status.activity), "progress":["completed":change.status.progress.completed, "total":change.status.progress.total]]
				if let error = change.status.error as NSError? {
					Events.publish("Replication.Error", ["replicator":replicatorName, "status":status, "error":error.toDictionary()])
				}
				if change.status.activity == Replicator.ActivityLevel.stopped {
					Events.publish("Replication.Stopped", ["replicator":replicatorName, "status":status])
				}
				else {
					Events.publish("Replication.Change", ["replicator":replicatorName, "status":status])
				}
			})

			// Document Listener
			let documentListener = replicator.addDocumentReplicationListener { (replication) in
				
				// Event
				var eventPayload : Dictionary<String, Any> = [
					"databaseName"		: databaseConection.name,
					"replicator"		: replicatorName
				]
				if verboseEvents {
					eventPayload["documents"] = replication.documents.map({ (document) -> Dictionary<String, Any?> in
						let error = document.error as NSError?
						return [
							"id"	: document.id,
							"flags"	: ["deleted":document.flags.contains(.deleted), "accessRemoved":document.flags.contains(.accessRemoved)],
							"error"	: error == nil ? nil : "\(error!.domain), \(error!.code) - \(error!.localizedDescription)"
						]
					})
				}
				else { // Simple Reporting
					eventPayload["documents"] = replication.documents.map({ (document) -> String in return document.id; })
				}
				
				Events.publish("Replication.\(replication.isPush ? "Push" : "Pull")", eventPayload)
			}

			// Reset Checkpoint
			let resetCheckpoint = options["resetCheckpoint"] as? Bool ?? false


			// Start Replication
			replicator.start(reset: resetCheckpoint)


			// Store
			let replicatorInfo = ReplicatorInfo(name: replicatorName, config: options, replicator: replicator)
			replicatorInfo.listeners.append(changeListener)
			replicatorInfo.listeners.append(documentListener)
			databaseConection.replicators.append(replicatorInfo)
			return replicatorInfo;
		}


		// ---- Stop Replicator ----------------------------
		static func stop(databaseConnection: Database.Connection, replicatorName: String) throws -> Void {

			// Replicator
			let replicatorInfo = getReplicatorByName(databaseConnection: databaseConnection, replicatorName: replicatorName)
			if replicatorInfo == nil {
				throw Errors.invalidParameter("replicator with name, '\(replicatorName)' could not be found")
			}

			// Remove Listeners
			replicatorInfo!.listeners.forEach { (listener) in
				replicatorInfo!.replicator!.removeChangeListener(withToken: listener)
			}
			replicatorInfo!.listeners.removeAll()

			// Stop
			replicatorInfo!.replicator?.stop()
			databaseConnection.replicators.removeAll(where: { $0.name == replicatorName })
		}


		// ---- Stop Replicator By Name --------------------
		static func stopReplicatorByName(options: NSDictionary) throws -> Void {

			// Database
			let databaseConnection : Database.Connection = try Database.getConnection(options)

			// Replicator
			let replicatorName = options["replicatorName"] as? String ?? ""
			try stop(databaseConnection: databaseConnection, replicatorName: replicatorName)
		}


		// ---- Get Replicator -----------------------------
		static func getReplicatorByName(databaseConnection: Database.Connection, replicatorName: String) -> ReplicatorInfo? {

			var replicator : ReplicatorInfo? = nil
			databaseConnection.replicators.forEach { (replicatorInfo) in 
				if replicatorInfo.name == replicatorName {
					replicator = replicatorInfo
				}
			}
			return replicator
		}
		

		// ---- Get Dictionary Filter ---------------------- (Returns a function)
		static func getDictionaryFilter(filterDefinition: NSDictionary?) -> ((_ document: CouchbaseLiteSwift.Document, _ flags: DocumentFlags) -> Bool) {
			
			// Empty Filter
			if filterDefinition == nil {
				return { (document: CouchbaseLiteSwift.Document, flags: DocumentFlags) -> Bool in return true; }
			}
			
			// Filter - Prepare Type Caches
			var matchFilterArrayTypes : Dictionary<String, [String]> = [:]
			var notFilterArrayTypes : Dictionary<String, [String]> = [:]
			for index in 0...1 {
				let filter = filterDefinition![(index == 0 ? "match" : "not")] as? NSDictionary ?? [:]
				var types : Dictionary<String, [String]> = [:]
				
				filter.allKeys.forEach { (_key) in
					let key = _key as! String
					let rootType = getType(value: filter.value(forKey: key))
					if rootType != "array" { types[key] = [rootType]; }
					else {
						types[key] = []
						let list = filter.value(forKey: key) as! [Any]
						for value in list { types[key]!.append(getType(value: value)); }
					}
				}
				if index == 0 { matchFilterArrayTypes = types; }
				else { notFilterArrayTypes = types; }
			}
			
			// Filter - Function
			return { (document: CouchbaseLiteSwift.Document, flags: DocumentFlags) -> Bool in
				
				// 2-Passes: 'Match' & 'Not'
				for index in 0...1 {
					let isMatchFilter = (index == 0) // Start with 'Match'
					let filter = filterDefinition?[(isMatchFilter ? "match" : "not")] as? NSDictionary ?? [:]
					let types = (isMatchFilter ? matchFilterArrayTypes : notFilterArrayTypes)
					
					var isMatch = (isMatchFilter) // for "matches" you want to start with true, and false for "not"
					for _key in filter.allKeys {
						let key = _key as! String
						let documentValue = (key == "_deleted" ? flags.contains(.deleted) as Any? : document.value(forKey: key))
						
						//  Search For Match
						var atLeastOneMatch = false
						let list = filter.value(forKey: key) as? [Any] ?? [filter.value(forKey: key)!]
						for index in 0...(list.count - 1) {
							if valuesAreEqual(type: types[key]![index], valueA: list[index], valueB: documentValue) {
								atLeastOneMatch = true
								break
							}
						}
						if (isMatchFilter && !atLeastOneMatch) || (!isMatchFilter && atLeastOneMatch) {
							isMatch = atLeastOneMatch
							break
						}
					}
					if (isMatchFilter && !isMatch) || (!isMatchFilter && isMatch) {
						return false // Reject Document
					}
				}
				
				return true // Document Passes Filter
			}
		}
		

		// ---- Compare Values -----------------------------
		static func valuesAreEqual(type: String, valueA: Any?, valueB: Any?) -> Bool {
			
			switch (type) {
			case "string":
				let stringValueB = valueB as? String
				if stringValueB != nil && stringValueB! == (valueA as! String) {
					return true
				}
				return false;
			
			case "decimal":
				let decimalValueB = valueB as? Decimal
				if decimalValueB != nil && decimalValueB! == (valueA as! Decimal) {
					return true
				}
				return false;
				
			case "integer":
				let integerValueB = valueB as? Int64
				if integerValueB != nil && integerValueB! == (valueA as! Int64) {
					return true
				}
				return false;
				
			case "bool":
				let boolValueB = valueB as? Bool
				if boolValueB != nil && boolValueB! == (valueA as! Bool) {
					return true
				}
				return false;
				
			default: return false;
			}
		}
		

		// ---- Get Type -----------------------------------
		static func getType(value: Any?) -> String {
			
			// dictionary
			let dictionaryValue = value as? NSDictionary
			if dictionaryValue != nil {
				return "dictionary"
			}

			// array
			let arrayValue = value as? [Any]
			if arrayValue != nil {
				return "array"
			}
			
			// string
			let stringValue = value as? String
			if stringValue != nil {
				return "string"
			}
			
			// decimal
			let decimalValue = value as? Decimal
			if decimalValue != nil {
				return "decimal"
			}
			
			// integer
			let integerValue = value as? Int64
			if integerValue != nil {
				return "integer"
			}
			
			// bool
			let boolValue = value as? Bool
			if boolValue != nil {
				return "bool"
			}
			
			// nil
			return "nil";
		}
		

		// ---- Get Filter Name ----------------------------
		static func getFilterName(filterDefinition: NSDictionary?) -> String {
			
			var matchFilterName : String = ""
			var notFilterName : String = ""
			if filterDefinition != nil {
				// Match Filter - Build Types Dictionary
				let matchFilter = filterDefinition!["match"] as? NSDictionary
				if matchFilter != nil {
					matchFilter!.allKeys.forEach { (matchKey) in
						let key = matchKey as! String
						matchFilterName += (key.prefix(1).uppercased() + key.dropFirst())
					}
				}

				// Not Filter - Build Types Dictionary
				let notFilter = filterDefinition!["not"] as? NSDictionary
				if notFilter != nil {
					notFilter!.allKeys.forEach { (notKey) in
						let key = notKey as! String
						notFilterName += (key.prefix(1).uppercased() + key.dropFirst())
					}
				}
			}
			
			return (matchFilterName.count == 0 ? "" : "Match\(matchFilterName)") + (notFilterName.count == 0 ? "" : "Not\(notFilterName)")
		}
		
	}
	
	
	
	// ---------------------------------------------------------------------------------------------------
	// ---- Secure Storage ------ (https://www.advancedswift.com/secure-private-data-keychain-swift/) ----
	
	class SecureStorage: NSObject {
		static let defaultService : String = "rncouchbaselite.store"
		
		enum KeychainError: Error {
			// Attempted read for an item that does not exist.
			case itemNotFound

			// Attempted save to override an existing item.
			// Use update instead of save to update existing items
			case duplicateItem

			// A read of an item in any format other than Data
			case invalidItemFormat

			// Any operation result status than errSecSuccess
			case unexpectedStatus(OSStatus)
		}
		
		
		// ---- Store String -------------------------------
		static func storeString(key: String, value: String, service: String = defaultService) throws {

			let query: [String: AnyObject] = [
				// kSecAttrService,  kSecAttrAccount, and kSecClass uniquely identify the item to save in Keychain
				kSecAttrService as String: service as AnyObject,
				kSecAttrAccount as String: key as AnyObject,
				kSecClass as String: kSecClassGenericPassword,

				// kSecValueData is the item value to save
				kSecValueData as String: value.data(using: .utf8) as AnyObject
			]

			// SecItemAdd attempts to add the item identified by the query to keychain
			let status = SecItemAdd(query as CFDictionary, nil)

			// errSecDuplicateItem is a special case where the item identified by the query already exists.
			// Throw duplicateItem so the client can determine whether or not to handle this as an error
			if status == errSecDuplicateItem {
				throw KeychainError.duplicateItem
			}

			// Any status other than errSecSuccess indicates the save operation failed.
			guard status == errSecSuccess else {
				throw KeychainError.unexpectedStatus(status)
			}
		}


		// ---- Update String ------------------------------
		static func updateString(key: String, value: String, service: String = defaultService) throws {

			let query: [String: AnyObject] = [
				// kSecAttrService,  kSecAttrAccount, and kSecClass uniquely identify the item to update in Keychain
				kSecAttrService as String: service as AnyObject,
				kSecAttrAccount as String: key as AnyObject,
				kSecClass as String: kSecClassGenericPassword
			]

			// attributes is passed to SecItemUpdate with kSecValueData as the updated item value
			let attributes: [String: AnyObject] = [
				kSecValueData as String: value.data(using: .utf8) as AnyObject
			]

			// SecItemUpdate attempts to update the item identified by query, overriding the previous value
			let status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)

			// errSecItemNotFound is a special status indicating the item to update does not exist.
			// Throw itemNotFound so the client can determine whether or not to handle this as an error
			guard status != errSecItemNotFound else {
				throw KeychainError.itemNotFound
			}

			// Any status other than errSecSuccess indicates the update operation failed.
			guard status == errSecSuccess else {
				throw KeychainError.unexpectedStatus(status)
			}
		}


		// ---- Get String ---------------------------------
		static func getString(key: String, service: String = defaultService) throws -> String? {

			let query: [String: AnyObject] = [
				// kSecAttrService,  kSecAttrAccount, and kSecClass uniquely identify the item to read in Keychain
				kSecAttrService as String: service as AnyObject,
				kSecAttrAccount as String: key as AnyObject,
				kSecClass as String: kSecClassGenericPassword,

				// kSecMatchLimitOne indicates keychain should read only the most recent item matching this query
				kSecMatchLimit as String: kSecMatchLimitOne,

				// kSecReturnData is set to kCFBooleanTrue in order to retrieve the data for the item
				kSecReturnData as String: kCFBooleanTrue
			]

			// SecItemCopyMatching will attempt to copy the item identified by query to the reference itemCopy
			var itemCopy: AnyObject?
			let status = SecItemCopyMatching(query as CFDictionary, &itemCopy)

			// errSecItemNotFound is a special status indicating the read item does not exist.
			// Throw itemNotFound so the client can determine whether or not to handle this case
			guard status != errSecItemNotFound else {
				// throw KeychainError.itemNotFound
				return nil
			}

			// Any status other than errSecSuccess indicates the read operation failed.
			guard status == errSecSuccess else {
				throw KeychainError.unexpectedStatus(status)
			}

			// This implementation of KeychainInterface requires all items to be saved and read as Data. Otherwise, invalidItemFormat is thrown
			guard let data = itemCopy as? Data else {
				throw KeychainError.invalidItemFormat
			}

			return	 String(data: data, encoding: .utf8)
		}


		// ---- Delete String ------------------------------
		static func deleteString(key: String, service: String = defaultService) throws {
			let query: [String: AnyObject] = [
				// kSecAttrService,  kSecAttrAccount, and kSecClass uniquely identify the item to delete in Keychain
				kSecAttrService as String: service as AnyObject,
				kSecAttrAccount as String: key as AnyObject,
				kSecClass as String: kSecClassGenericPassword
			]

			// SecItemDelete attempts to perform a delete operation for the item identified by query.
			// The status indicates if the operation succeeded or failed.
			let status = SecItemDelete(query as CFDictionary)

			// Any status other than errSecSuccess indicates the delete operation failed.
			guard status == errSecSuccess else {
				throw KeychainError.unexpectedStatus(status)
			}
		}
		
		
		// ---- Key Exists ---------------------------------
		static func exists(key: String, service: String = defaultService) throws -> Bool {
			let value = try getString(key: key, service: service)
			return value != nil
		}

		
	}
	
	
	
	
	// ---------------------------------------------------------------------------------------------------
	// ---- Events ---------------------------------------------------------------------------------------
	
	class Events {

		// Config
		public static var sharedInstance = Events()
		private static var eventEmitter: RNCouchbaseLite!
		static var listeners = 0
		private init() {}

		// When React Native instantiates the emitter it is registered here.
		static func registerEventEmitter(eventEmitter: RNCouchbaseLite) {
			Events.eventEmitter = eventEmitter
		}

		
		static func publish(_ eventName: String, _ body: Any? = nil) {
			if Events.listeners > 0 {
				Events.eventEmitter.sendEvent(withName: eventName, body: body)
			}
		}

		// Supported Events
		static var allEvents: [String] = [
			"Database.Change",
			"Document.Change",
			"Replication.Error",
			"Replication.Stopped",
			"Replication.Change",
			"Replication.Push",
			"Replication.Pull",
			"Replication.Pull.Delete",
			"Replication.Pull.AccessRemoved"
		]

	}

}



enum Errors: Error {
	case invalidParameter(String)
	case unexpectedValue(String)
	case invalidState(String)
}

extension NSError {
	func toDictionary() -> Dictionary<String, Any> {
		let dictionary : Dictionary<String, Any> = [
			"code" : self.code,
			"domain" : self.domain,
			"localizedDescription" : self.localizedDescription,
			"userInfo" : self.userInfo
		]
		return dictionary
	}
}

