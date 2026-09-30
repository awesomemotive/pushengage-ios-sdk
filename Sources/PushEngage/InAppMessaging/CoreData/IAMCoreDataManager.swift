import Foundation
import CoreData

/// Error thrown when the CoreData stack could not be set up
/// (e.g. the compiled model is missing from the resource bundle).
enum IAMStoreError: Error {
    case storeUnavailable
}

/// Manager class for handling CoreData operations for In-App Messaging
final class IAMCoreDataManager {
    
    // MARK: - Singleton
    
    static let shared = IAMCoreDataManager()
    
    private init() {
        // Built here rather than lazily: `shared` runs under swift_once, so the runtime
        // already guarantees exactly one construction with no lock of ours held across
        // Core Data's own main-queue work.
        persistentContainer = Self.makeContainer()
    }
    
    // MARK: - Core Data stack
    
    /// Whether the persistence stack is usable. `false` when the CoreData
    /// model could not be located/loaded — in-app messaging then degrades
    /// gracefully instead of crashing the host app.
    var isStoreAvailable: Bool {
        persistentContainer != nil
    }

    /// Loaded exactly once per process: multiple NSManagedObjectModel
    /// instances containing the same entities break NSManagedObject
    /// class↔entity resolution.
    static let managedObjectModel: NSManagedObjectModel? = {
        guard let modelURL = PEResources.bundle.url(forResource: "InAppMessaging", withExtension: "momd"),
              let model = NSManagedObjectModel(contentsOf: modelURL) else {
            return nil
        }
        return model
    }()

    /// Immutable after init, so every later read is a plain read with nothing to
    /// synchronise. nil means the stack is unavailable and IAM degrades gracefully.
    private let persistentContainer: NSPersistentContainer?

    private static func makeContainer() -> NSPersistentContainer? {
        guard let model = IAMCoreDataManager.managedObjectModel else {
            PELogger.error(
                className: String(describing: IAMCoreDataManager.self),
                message: "CoreData model not found in resource bundle — in-app messaging persistence is disabled"
            )
            return nil
        }

        let container = NSPersistentContainer(name: "InAppMessaging", managedObjectModel: model)
        
        // Configure persistent store description
        let description = NSPersistentStoreDescription()
        description.type = NSSQLiteStoreType
        
        // Set the URL for the database file to ensure it's saved to disk
        if let storeURL = getStoreURL() {
            description.url = storeURL
            PELogger.debug(
                className: String(describing: IAMCoreDataManager.self),
                message: "Using persistent store URL: \(storeURL.path)"
            )
        }
        
        // Set options for better performance
        description.setOption(true as NSNumber, forKey: NSMigratePersistentStoresAutomaticallyOption)
        description.setOption(true as NSNumber, forKey: NSInferMappingModelAutomaticallyOption)
        
        container.persistentStoreDescriptions = [description]
        
        container.loadPersistentStores { (storeDescription, error) in
            if let error = error {
                PELogger.error(
                    className: String(describing: IAMCoreDataManager.self),
                    message: "Failed to load Core Data stack: \(error.localizedDescription)"
                )
            } else {
                PELogger.debug(
                    className: String(describing: IAMCoreDataManager.self),
                    message: "Successfully loaded persistent store: \(storeDescription.url?.path ?? "unknown")"
                )
            }
        }
        
        // Configure the view context for better performance
        container.viewContext.automaticallyMergesChangesFromParent = true
        container.viewContext.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
        
        return container
    }
    
    // Helper to get a consistent store URL in the application support directory
    private static func getStoreURL() -> URL? {
        guard let appSupportURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            return nil
        }
        
        // Create directory if needed
        let dbDirectoryURL = appSupportURL.appendingPathComponent("PushEngage", isDirectory: true)
        
        do {
            try FileManager.default.createDirectory(at: dbDirectoryURL, withIntermediateDirectories: true)
            return dbDirectoryURL.appendingPathComponent("InAppMessaging.sqlite")
        } catch {
            PELogger.error(
                className: String(describing: IAMCoreDataManager.self),
                message: "Failed to create database directory: \(error.localizedDescription)"
            )
            return nil
        }
    }
    
    // MARK: - Contexts

    /// Returns the container or throws when the stack is unavailable.
    private func requireContainer() throws -> NSPersistentContainer {
        guard let container = persistentContainer else {
            throw IAMStoreError.storeUnavailable
        }
        return container
    }

    /// Background context for async operations
    private func newBackgroundContext() throws -> NSManagedObjectContext {
        let context = try requireContainer().newBackgroundContext()
        context.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
        return context
    }
    
    // MARK: - CRUD Operations
    
    /// Saves changes in the specified context
    /// - Parameter context: The context to save
    /// - Throws: Core Data errors if save fails
    func saveContext(_ context: NSManagedObjectContext) throws {
        if context.hasChanges {
            try context.save()
        }
    }
    
    /// Performs work synchronously in a background context and saves it.
    /// The view context picks up the save via automaticallyMergesChangesFromParent.
    /// - Parameter work: The work to perform
    /// - Throws: Any error that occurs during the operation
    func performBackgroundTask(_ work: @escaping (NSManagedObjectContext) throws -> Void) throws {
        let context = try newBackgroundContext()
        var workError: Error?

        context.performAndWait {
            do {
                try work(context)
                if context.hasChanges {
                    try context.save()
                }
            } catch {
                workError = error
                PELogger.error(
                    className: String(describing: IAMCoreDataManager.self),
                    message: "Error in performBackgroundTask: \(error.localizedDescription)"
                )
            }
        }

        if let error = workError {
            throw error
        }
    }
    
    /// Deletes all records of a specific entity type
    /// - Parameter entityName: Name of the entity to clear
    func clearAllRecords(forEntityName entityName: String) throws {
        let context = try newBackgroundContext()
        
        var deleteError: Error?
        
        context.performAndWait {
            let fetchRequest = NSFetchRequest<NSFetchRequestResult>(entityName: entityName)
            let deleteRequest = NSBatchDeleteRequest(fetchRequest: fetchRequest)
            
            do {
                try context.execute(deleteRequest)
                try context.save()
            } catch {
                deleteError = error
            }
        }
        
        if let error = deleteError {
            throw error
        }
    }
    
    /// Executes a fetch request on the view context's queue so callers on any
    /// thread fetch safely; results are fully materialised.
    /// - Parameter request: The fetch request to execute
    /// - Returns: Array of fetched objects
    func executeFetchRequest<T>(_ request: NSFetchRequest<T>) throws -> [T] {
        let context = try requireContainer().viewContext
        request.returnsObjectsAsFaults = false
        var result: Result<[T], Error> = .success([])
        context.performAndWait {
            do {
                result = .success(try context.fetch(request))
            } catch {
                result = .failure(error)
            }
        }
        return try result.get()
    }
} 