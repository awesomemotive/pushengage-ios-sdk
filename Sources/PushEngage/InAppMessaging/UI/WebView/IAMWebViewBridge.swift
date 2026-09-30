import WebKit
import CoreData

/// Protocol for handling custom in-app message actions
protocol IAMCustomActionDelegate: AnyObject {
    /// Called when a custom action is triggered
    /// - Parameters:
    ///   - actionId: The ID of the action that was triggered
    ///   - parameters: Additional parameters for the action
    func handleCustomAction(actionId: String, parameters: [String: String])
}

/// Protocol defining the message action handling
protocol IAMActionHandling: AnyObject {
    /// Called when a message action is triggered
    /// - Parameters:
    ///   - actionType: The type of action
    ///   - parameters: Additional parameters for the action
    func handleAction(type: IAMActionType, parameters: [String: String])
    
    /// Delegate for handling custom actions
    var customActionDelegate: IAMCustomActionDelegate? { get set }
}
