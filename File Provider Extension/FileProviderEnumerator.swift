//
//  FileProviderEnumerator.swift
//  Files
//
//  Created by Marino Faggiana on 26/03/18.
//  Copyright © 2018 Marino Faggiana. All rights reserved.
//
//  Author Marino Faggiana <marino.faggiana@nextcloud.com>
//
//  This program is free software: you can redistribute it and/or modify
//  it under the terms of the GNU General Public License as published by
//  the Free Software Foundation, either version 3 of the License, or
//  (at your option) any later version.
//
//  This program is distributed in the hope that it will be useful,
//  but WITHOUT ANY WARRANTY; without even the implied warranty of
//  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
//  GNU General Public License for more details.
//
//  You should have received a copy of the GNU General Public License
//  along with this program.  If not, see <http://www.gnu.org/licenses/>.
//

import FileProvider
import NCCommunication

class FileProviderEnumerator: NSObject, NSFileProviderEnumerator {
    
    var enumeratedItemIdentifier: NSFileProviderItemIdentifier
    var serverUrl: String?
    
    init(enumeratedItemIdentifier: NSFileProviderItemIdentifier) {
        
        self.enumeratedItemIdentifier = enumeratedItemIdentifier
        
        // Select ServerUrl
        if (enumeratedItemIdentifier == .rootContainer) {
            serverUrl = fileProviderData.shared.homeServerUrl
        } else {
            
            let metadata = fileProviderUtility.shared.getTableMetadataFromItemIdentifier(enumeratedItemIdentifier)
            if metadata != nil  {
                if let directorySource = NCManageDatabase.shared.getTableDirectory(predicate: NSPredicate(format: "account == %@ AND serverUrl == %@", metadata!.account, metadata!.serverUrl))  {
                    serverUrl = directorySource.serverUrl + "/" + metadata!.fileName
                }
            }
        }
        
        super.init()
    }

    func invalidate() {
       
    }

    func enumerateItems(for observer: NSFileProviderEnumerationObserver, startingAt page: NSFileProviderPage) {
        
        var items: [NSFileProviderItemProtocol] = []
        
        /*** WorkingSet ***/
        if enumeratedItemIdentifier == .workingSet {
            
            var itemIdentifierMetadata: [NSFileProviderItemIdentifier: tableMetadata] = [:]
            
            // ***** Tags *****
            let tags = NCManageDatabase.shared.getTags(predicate: NSPredicate(format: "account == %@", fileProviderData.shared.account))
            for tag in tags {
                
                guard let metadata = NCManageDatabase.shared.getMetadataFromOcId(tag.ocId)  else { continue }
                fileProviderUtility.shared.createocIdentifierOnFileSystem(metadata: metadata)
                itemIdentifierMetadata[fileProviderUtility.shared.getItemIdentifier(metadata: metadata)] = metadata
            }
            
            // ***** Favorite *****
            fileProviderData.shared.listFavoriteIdentifierRank = NCManageDatabase.shared.getTableMetadatasDirectoryFavoriteIdentifierRank(account: fileProviderData.shared.account)
            for (identifier, _) in fileProviderData.shared.listFavoriteIdentifierRank {
                
                guard let metadata = NCManageDatabase.shared.getMetadataFromOcId(identifier) else { continue }
                itemIdentifierMetadata[fileProviderUtility.shared.getItemIdentifier(metadata: metadata)] = metadata
            }
            
            // create items
            for (_, metadata) in itemIdentifierMetadata {
                let parentItemIdentifier = fileProviderUtility.shared.getParentItemIdentifier(metadata: metadata)
                if parentItemIdentifier != nil {
                    let item = FileProviderItem(metadata: metadata, parentItemIdentifier: parentItemIdentifier!)
                    items.append(item)
                }
            }
            
            observer.didEnumerate(items)
            observer.finishEnumerating(upTo: nil)
            
        } else {
        
        /*** ServerUrl ***/
                
            let paginationEndpoint = NCManageDatabase.shared.getCapabilitiesServerString(account: fileProviderData.shared.account, elements: NCElementsJSON.shared.capabilitiesPaginationEndpoint)
            
            guard let serverUrl = serverUrl else {
                observer.finishEnumerating(upTo: nil)
                return
            }
            
            if (page == NSFileProviderPage.initialPageSortedByDate as NSFileProviderPage || page == NSFileProviderPage.initialPageSortedByName as NSFileProviderPage) {
                
                if paginationEndpoint != nil {
                                    
                    self.getPagination(endpoint: paginationEndpoint!, serverUrl: serverUrl, page: 1, limit: fileProviderData.shared.itemForPage) { (metadatas) in
                        self.completeObserver(observer, numPage: 1, metadatas: metadatas)
                    }
                    
                } else {
                    
                    self.readFileOrFolder(serverUrl: serverUrl) { (metadatas) in
                        self.completeObserver(observer, numPage: 1, metadatas: metadatas)
                    }                    
                }
                
            } else {
                
                let numPage = Int(String(data: page.rawValue, encoding: .utf8)!)!

                if paginationEndpoint != nil {

                    self.getPagination(endpoint: paginationEndpoint!, serverUrl: serverUrl, page: numPage, limit: fileProviderData.shared.itemForPage) { (metadatas) in
                        self.completeObserver(observer, numPage: numPage, metadatas: metadatas)
                    }
                    
                } else {

                    completeObserver(observer, numPage: numPage, metadatas: nil)
                }
            }
        }
    }
    
    func enumerateChanges(for observer: NSFileProviderChangeObserver, from anchor: NSFileProviderSyncAnchor) {
        
        var itemsDelete: [NSFileProviderItemIdentifier] = []
        var itemsUpdate: [FileProviderItem] = []
        
        // Report the deleted items
        //
        if self.enumeratedItemIdentifier == .workingSet {
            for (itemIdentifier, _) in fileProviderData.shared.fileProviderSignalDeleteWorkingSetItemIdentifier {
                itemsDelete.append(itemIdentifier)
            }
            fileProviderData.shared.fileProviderSignalDeleteWorkingSetItemIdentifier.removeAll()
        } else {
            for (itemIdentifier, _) in fileProviderData.shared.fileProviderSignalDeleteContainerItemIdentifier {
                itemsDelete.append(itemIdentifier)
            }
            fileProviderData.shared.fileProviderSignalDeleteContainerItemIdentifier.removeAll()
        }
        
        // Report the updated items
        //
        if self.enumeratedItemIdentifier == .workingSet {
            for (_, item) in fileProviderData.shared.fileProviderSignalUpdateWorkingSetItem {
                itemsUpdate.append(item)
            }
            fileProviderData.shared.fileProviderSignalUpdateWorkingSetItem.removeAll()
        } else {
            for (_, item) in fileProviderData.shared.fileProviderSignalUpdateContainerItem {
                itemsUpdate.append(item)
            }
            fileProviderData.shared.fileProviderSignalUpdateContainerItem.removeAll()
        }
        
        observer.didDeleteItems(withIdentifiers: itemsDelete)
        observer.didUpdate(itemsUpdate)
        
        let data = "\(fileProviderData.shared.currentAnchor)".data(using: .utf8)
        observer.finishEnumeratingChanges(upTo: NSFileProviderSyncAnchor(data!), moreComing: false)
    }
    
    func currentSyncAnchor(completionHandler: @escaping (NSFileProviderSyncAnchor?) -> Void) {
        let data = "\(fileProviderData.shared.currentAnchor)".data(using: .utf8)
        completionHandler(NSFileProviderSyncAnchor(data!))
    }
    
    // --------------------------------------------------------------------------------------------
    //  MARK: - User Function + Network
    // --------------------------------------------------------------------------------------------

    func completeObserver(_ observer: NSFileProviderEnumerationObserver, numPage: Int, metadatas: [tableMetadata]?) {
            
        var numPage = numPage
        var items: [NSFileProviderItemProtocol] = []

        if (metadatas != nil) {
            
            for metadata in metadatas! {
                    
                if metadata.e2eEncrypted || (metadata.session != "" && metadata.session != NCNetworking.shared.sessionIdentifierBackgroundExtension) { continue }
                    
                fileProviderUtility.shared.createocIdentifierOnFileSystem(metadata: metadata)
                        
                let parentItemIdentifier = fileProviderUtility.shared.getParentItemIdentifier(metadata: metadata)
                if parentItemIdentifier != nil {
                    let item = FileProviderItem(metadata: metadata, parentItemIdentifier: parentItemIdentifier!)
                    items.append(item)
                }
            }
            observer.didEnumerate(items)
        }
        
        if (items.count == fileProviderData.shared.itemForPage) {
            numPage += 1
            let providerPage = NSFileProviderPage("\(numPage)".data(using: .utf8)!)
            observer.finishEnumerating(upTo: providerPage)
        } else {
            observer.finishEnumerating(upTo: nil)
        }
    }
        
    func readFileOrFolder(serverUrl: String, completionHandler: @escaping (_ metadatas: [tableMetadata]?) -> Void) {
        
        var directoryEtag: String?
        
        if let tableDirectory = NCManageDatabase.shared.getTableDirectory(predicate: NSPredicate(format: "account == %@ AND serverUrl == %@", fileProviderData.shared.account, serverUrl)) {
            directoryEtag = tableDirectory.etag
        }
            
        NCCommunication.shared.readFileOrFolder(serverUrlFileName: serverUrl, depth: "0", showHiddenFiles: CCUtility.getShowHiddenFiles()) { (account, files, responseData, errorCode, errorDescription) in
        
            if directoryEtag != files.first?.etag {
            
                NCCommunication.shared.readFileOrFolder(serverUrlFileName: serverUrl, depth: "1", showHiddenFiles: CCUtility.getShowHiddenFiles()) { (account, files, responseData, errorCode, errorDescription) in
                    
                    if errorCode == 0 {
                        DispatchQueue.global().async {
                            NCManageDatabase.shared.convertNCCommunicationFilesToMetadatas(files, useMetadataFolder: true, account: account) { (metadataFolder, metadatasFolder, metadatas) in
                                let metadatasResult = NCManageDatabase.shared.getMetadatas(predicate: NSPredicate(format: "account == %@ AND serverUrl == %@ AND status == %d", account, serverUrl, k_metadataStatusNormal))
                                NCManageDatabase.shared.updateMetadatas(metadatas, metadatasResult: metadatasResult)
                                for metadata in metadatasFolder {
                                    let serverUrl = metadata.serverUrl + "/" + metadata.fileNameView
                                    NCManageDatabase.shared.addDirectory(encrypted: metadata.e2eEncrypted, favorite: metadata.favorite, ocId: metadata.ocId, fileId: metadata.fileId, etag: nil, permissions: metadata.permissions, serverUrl: serverUrl, richWorkspace: metadata.richWorkspace, account: metadata.account)
                                }
                                let metadatas = NCManageDatabase.shared.getAdvancedMetadatas(predicate: NSPredicate(format: "account == %@ AND serverUrl == %@", fileProviderData.shared.account, serverUrl), sorted: "fileName", ascending: true)
                                completionHandler(metadatas)
                            }
                        }
                    } else {
                        let metadatas = NCManageDatabase.shared.getAdvancedMetadatas(predicate: NSPredicate(format: "account == %@ AND serverUrl == %@", fileProviderData.shared.account, serverUrl), sorted: "fileName", ascending: true)
                        completionHandler(metadatas)
                    }
                }
            } else {
                let metadatas = NCManageDatabase.shared.getAdvancedMetadatas(predicate: NSPredicate(format: "account == %@ AND serverUrl == %@", fileProviderData.shared.account, serverUrl), sorted: "fileName", ascending: true)
                completionHandler(metadatas)
            }
        }
    }
    
    func getPagination(endpoint:String, serverUrl: String, page: Int, limit: Int, completionHandler: @escaping (_ metadatas: [tableMetadata]?) -> Void) {
        
        let offset = (page - 1) * limit
        var fileNamePath = CCUtility.returnPathfromServerUrl(serverUrl, urlBase: fileProviderData.shared.accountUrlBase, account: fileProviderData.shared.account)!
        if fileNamePath == "" {
            fileNamePath = "/"
        }
        var directoryEtag: String?
        
        if let tableDirectory = NCManageDatabase.shared.getTableDirectory(predicate: NSPredicate(format: "account == %@ AND serverUrl == %@", fileProviderData.shared.account, serverUrl)) {
            if page == 1 {
                directoryEtag = tableDirectory.etag
            }
        }
        
        NCCommunication.shared.readFileOrFolder(serverUrlFileName: serverUrl, depth: "0", showHiddenFiles: CCUtility.getShowHiddenFiles()) { (account, files, responseData, errorCode, errorDescription) in
        
            if errorCode == 0 && files.count == 1 && directoryEtag != files.first?.etag {
                
                if page == 1 {
                    let metadataFolder = NCManageDatabase.shared.convertNCFileToMetadata(files[0], isEncrypted: false, account: account)
                    NCManageDatabase.shared.addMetadata(metadataFolder)
                    NCManageDatabase.shared.addDirectory(encrypted: metadataFolder.e2eEncrypted, favorite: metadataFolder.favorite, ocId: metadataFolder.ocId, fileId: metadataFolder.fileId, etag: metadataFolder.etag, permissions: metadataFolder.permissions, serverUrl: serverUrl, richWorkspace: metadataFolder.richWorkspace, account: metadataFolder.account)
                }
                                
                NCCommunication.shared.iosHelper(fileNamePath: fileNamePath, serverUrl: serverUrl, offset: offset, limit: limit) { (account, files, errorCode, errorDescription) in
                     
                    if errorCode == 0 {
                        DispatchQueue.global().async {
                            NCManageDatabase.shared.convertNCCommunicationFilesToMetadatas(files, useMetadataFolder: false, account: account) { (metadataFolder, metadatasFolder, metadatas) in
                                let metadatasResult = NCManageDatabase.shared.getAdvancedMetadatas(predicate: NSPredicate(format: "account == %@ AND serverUrl == %@ AND status == %d", fileProviderData.shared.account, serverUrl, k_metadataStatusNormal), page: page, limit: fileProviderData.shared.itemForPage, sorted: "fileName", ascending: true)
                                NCManageDatabase.shared.updateMetadatas(metadatas, metadatasResult: metadatasResult)
                                for metadata in metadatasFolder {
                                    let serverUrl = metadata.serverUrl + "/" + metadata.fileNameView
                                    NCManageDatabase.shared.addDirectory(encrypted: metadata.e2eEncrypted, favorite: metadata.favorite, ocId: metadata.ocId, fileId: metadata.fileId, etag: nil, permissions: metadata.permissions, serverUrl: serverUrl, richWorkspace: nil, account: metadata.account)
                                }
                                let metadatas = NCManageDatabase.shared.getAdvancedMetadatas(predicate: NSPredicate(format: "account == %@ AND serverUrl == %@", fileProviderData.shared.account, serverUrl), page: page, limit: fileProviderData.shared.itemForPage, sorted: "fileName", ascending: true)
                                completionHandler(metadatas)
                            }
                        }
                    } else {
                        let metadatas = NCManageDatabase.shared.getAdvancedMetadatas(predicate: NSPredicate(format: "account == %@ AND serverUrl == %@", fileProviderData.shared.account, serverUrl), page: page, limit: fileProviderData.shared.itemForPage, sorted: "fileName", ascending: true)
                        completionHandler(metadatas)
                    }
                }
            } else {
                let metadatas = NCManageDatabase.shared.getAdvancedMetadatas(predicate: NSPredicate(format: "account == %@ AND serverUrl == %@", fileProviderData.shared.account, serverUrl), sorted: "fileName", ascending: true)
                completionHandler(metadatas)
            }
        }
    }
}
