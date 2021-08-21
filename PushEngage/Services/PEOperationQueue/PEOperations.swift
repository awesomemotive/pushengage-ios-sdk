//
//  PEOperations.swift
//  PushEngage
//
//  Created by Abhishek on 01/04/21.
//

import Foundation
import UserNotifications

// MARK: - Download operation is create in operation Queue for future depenceny and it make api call sync

@available(iOS 10.0, *)
typealias DownloadOperationInput = (attachmentString: String?,
                                    contentToModifiy: UNMutableNotificationContent,
                                    networkService: NetworkRouter)

@available(iOS 10.0, *)
final class DownloadAttachmentOperation: ChainedAsyncResultOperation<DownloadOperationInput, String, PEError> {
    
    init(inputValue: DownloadOperationInput? = nil) {
        super.init(input: inputValue)
    }
    
    override func main() {
        guard let input = input, let attachmentString = input.attachmentString else {
            self.cancel()
            return
        }
        let networkService = input.networkService
        networkService.requestDownload(.getImage(attachmentString)) { [weak self] result in
            switch result {
            case .success(let result):
                do {
                    try self?.updateAttactment(content: input.contentToModifiy,
                                               attachmentString: attachmentString,
                                               urlName: result.0,
                                               response: result.1)
                    PELogger.info(className: String(describing: DownloadAttachmentOperation.self),
                                  message: "updated-attachements")
                    self?.finish(with: .success("updated-attachements"))
                    
                } catch let error {
                    PELogger.error(className: String(describing: DownloadAttachmentOperation.self),
                                   message: error.localizedDescription)
                    self?.finish(with: .failure(.underlying(error: error)))
                    
                }
            case.failure(let error):
                PELogger.error(className: String(describing: DownloadAttachmentOperation.self),
                               message: error.errorDescription ?? "")
                self?.finish(with: .failure(.underlying(error: error)))
            }
        }
    }
    
    private func updateAttactment(content: UNMutableNotificationContent,
                                  attachmentString: String,
                                  urlName: URL, response: URLResponse)  throws {
        
        let tempDirectoryUrl = FileManager.default.temporaryDirectory
        var attachmentIdString = UUID().uuidString + urlName.lastPathComponent
        if let suggestedFilename = response.suggestedFilename {
            attachmentIdString = UUID().uuidString + suggestedFilename
        }
        
        let tempFileUrl = tempDirectoryUrl.appendingPathComponent(attachmentIdString)
        try FileManager.default.moveItem(at: urlName, to: tempFileUrl)
        let attachment = try UNNotificationAttachment(identifier: attachmentString,
                                                      url: tempFileUrl,
                                                      options: nil)
        content.attachments.append(attachment)
    }
    
    override final func cancel() {
        input?.networkService.cancel()
        cancel(with: .canceled)
    }
}

// MARK: - SponseredNotifictaionOperation is create in operation Queue for future depenceny and it make api call sync

@available(iOS 10.0, *)
typealias SponseredNotificationInput = (previousAttachment: String?,
                                        mutableContent: UNMutableNotificationContent,
                                        notificationLifeCycle: NotificationLifeCycleService,
                                        network: NetworkRouter,
                                        notification: PENotification)
@available(iOS 10.0, *)
final class SponseredNotifictaionOperation: ChainedAsyncResultOperation<SponseredNotificationInput,
                                                                         DownloadOperationInput,
                                                                         PEError> {
    
    init(input: SponseredNotificationInput) {
        super.init(input: input)
    }
    
    override func main() {
        guard let input = input else {
            self.cancel()
            PELogger.debug(className: String(describing: SponseredNotifictaionOperation.self),
                           message: "input is not avialable please check and update properly.")
            return
        }
        input.notificationLifeCycle.withRetrysponseredNotification(with: input.notification) { [weak self] result in
            switch result {
            case .success(let response):
                let links = response.launchURL
                let icon = response.icon
                let body = response.body
                let title = response.title
                let tag = response.tag
                input.mutableContent.title = title
                input.mutableContent.body = body
                input.mutableContent.userInfo[userInfo:
                                     PayloadConstants.custom]?.updateValue(links,
                                                               forKey: PayloadConstants.launchUrlKey)
                input.mutableContent.userInfo[userInfo: PayloadConstants.custom]?[string: PayloadConstants.tag] = tag
                
                if let sponseredID = response.sponseredActionButton?.first?.slabel {
                    input.mutableContent.userInfo[userInfo: PayloadConstants.custom]?
                        .updateValue([["a": sponseredID,
                                       "b": sponseredID]],
                                     forKey: PayloadConstants.actionButton)
                    DependencyInitialize.getUserDefaults().setsponseredID(id: sponseredID)
                }
                PELogger.info(className: String(describing: SponseredNotifictaionOperation.self),
                              message: "content updated with sponsered")
                
                // if successfull then download input will be the associated value for the success case.
                
                self?.finish(with: .success((icon, input.mutableContent, input.network)))
            case .failure(let error):
                PELogger.error(className: String(describing: SponseredNotifictaionOperation.self),
                               message: "\(error) cascading with result provided")
                self?.finish(with: .failure(.sponseredfailWithContent((input.previousAttachment,
                                                                       input.mutableContent,
                                                                       input.network))))
            }
        }
    }
    
    override final func cancel() {
        input?.notificationLifeCycle.canceled()
        cancel(with: .canceled)
    }
}
