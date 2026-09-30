import Foundation

/// Protocol defining the message display behavior
protocol IAMMessageDisplaying: AnyObject {
    /// Called when the message is ready to be displayed
    func messageWillDisplay()
    /// Called after the message has been displayed
    func messageDidDisplay()
    /// Called when the message will be dismissed
    func messageWillDismiss()
    /// Called after the message has been dismissed
    func messageDidDismiss()
} 