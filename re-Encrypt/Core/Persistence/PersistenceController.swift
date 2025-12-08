import CoreData

final class PersistenceController {
    @MainActor static let shared = PersistenceController()

    let container: NSPersistentContainer

    private init(inMemory: Bool = false) {
        container = NSPersistentContainer(name: "PasswordManagerModel")

        if inMemory {
            container.persistentStoreDescriptions.first?.url = URL(fileURLWithPath: "/dev/null")
        }

        container.loadPersistentStores { description, error in
            if let error = error as NSError? {
                // If migration fails, delete the store and retry
                if error.code == NSPersistentStoreIncompatibleVersionHashError ||
                   error.code == NSMigrationMissingMappingModelError {
                    
                    if let url = description.url {
                        try? FileManager.default.removeItem(at: url)
                        self.container.loadPersistentStores { _, error in
                            if let error = error {
                                fatalError("Unresolved error after reset \(error)")
                            }
                        }
                    }
                } else {
                    fatalError("Unresolved error \(error)")
                }
            }
        }

        // Configure main context
        let context = container.viewContext
        context.automaticallyMergesChangesFromParent = true
        context.mergePolicy = NSMergePolicy.mergeByPropertyObjectTrump
        context.undoManager = nil
    }

    func saveContext() {
        let context = container.viewContext
        if context.hasChanges {
            do {
                try context.save()
            } catch {
                print("Unresolved error \(error)")
            }
        }
    }
}
