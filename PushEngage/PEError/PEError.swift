//
//  PEError.swift
//  PushEngage
//
//  Created by Abhishek on 05/02/21.
//

import Foundation

 enum PEError: Error {
    case contentNotFound
    case networkError
    case downloadAttachmentfailed
    case parametersNil
    case encodingFailed
    case missingURL
    case parsingError
    case invalidStatusCode(String?, Int?)
    case dataEncodeingFailed
    case errorResponse(String)
    case networkNotReachable
    case cancelled
    case missingInputURL
    case missingRedirectURL
    case underlying(error: Swift.Error)
    case incorrectParameter
    case tiggerfailure
    case mediaLengthExceeded
    case requestFailureException
    case dataNotFound
    case networkResponseFaliure(Int?, String?)
    case dataTypeCastingError
    case requestTimeout
    case failedToLogError
    case stiteStatusNotActive
    case subscriberNotAvailable
    case profilealreadyExist
    case siteKeyNotAvailable
    case permissionNotDetermined
    case notificationUserActionFailed(String?)
    case sponseredfailWithContent(attachmentString: String?, networkService: NetworkRouterType)
}

extension PEError: LocalizedError {
    
    var errorDescription: String? {
        switch self {
        case .contentNotFound:
            return .contentNotFound
        case .networkError:
            return .network
        case .downloadAttachmentfailed:
            return .downloadAttachmentfailed
        case .parametersNil:
            return .parametersNil
        case .encodingFailed:
            return .encodingFailed
        case .missingURL:
            return .missingURL
        case .parsingError:
            return .parsingError
        case .invalidStatusCode(let message, let code):
            return "message: - \(message ?? "") error code: - \(code ?? -100 )"
        case .dataEncodeingFailed:
            return .dataEncodeingFailed
        case .errorResponse(let errorMessage):
            return errorMessage
        case .networkNotReachable:
            return .networkNotReachable
        case .cancelled:
            return .canceled
        case .missingInputURL:
            return .missingInputURL
        case .missingRedirectURL:
            return .missingRedirectURL
        case .underlying(let error):
            return error.localizedDescription
        case .sponseredfailWithContent:
            return .sponseredfailWithContent
        case .incorrectParameter:
            return .incorrectParameter
        case .tiggerfailure:
            return .tiggerfailure
        case .mediaLengthExceeded:
            return .mediaLengthExceeded
        case .requestFailureException:
            return .urlRequestException
        case .dataNotFound:
            return .dataNotFound
        case .networkResponseFaliure(let status, let message):
            return String(format: .networkResponseFaliure,
                          "\(status ?? -100)", "\(message ?? "")")
        case .dataTypeCastingError:
            return .dataTypeCastingError
        case .requestTimeout:
            return  .requestTimeOut
        case .failedToLogError:
            return  .failedToLogError
        case .stiteStatusNotActive:
            return .siteStatusNotActive
        case .subscriberNotAvailable:
            return .subscriberNotAvailable
        case .profilealreadyExist:
            return .profileAlreadyExist
        case .siteKeyNotAvailable:
            return .siteKeyNotAvailable
        case .permissionNotDetermined:
            return .permissionNotDetermine
        case .notificationUserActionFailed(let errorMessage):
            return String(format: .notificationUserActionFailed,
                          errorMessage ?? "")
        }
    }
}
