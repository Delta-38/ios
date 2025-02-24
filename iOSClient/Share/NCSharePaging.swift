//
//  NCSharePaging.swift
//  Nextcloud
//
//  Created by Marino Faggiana on 25/07/2019.
//  Copyright © 2019 Marino Faggiana. All rights reserved.
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


import Foundation
import Parchment
import NCCommunication

class NCSharePaging: UIViewController {
    
    private let pagingViewController = NCShareHeaderViewController()
    private let appDelegate = UIApplication.shared.delegate as! AppDelegate
    
    private var activityEnabled = true
    private var commentsEnabled = true
    private var sharingEnabled = true
    
    @objc var metadata = tableMetadata()
    @objc var indexPage: Int = 0
        
    override func viewDidLoad() {
        super.viewDidLoad()
        
        // Verify Comments & Sharing enabled
        let serverVersionMajor = NCManageDatabase.shared.getCapabilitiesServerInt(account: appDelegate.account, elements: NCElementsJSON.shared.capabilitiesVersionMajor)
        let comments = NCManageDatabase.shared.getCapabilitiesServerBool(account: appDelegate.account, elements: NCElementsJSON.shared.capabilitiesFilesComments, exists: false)
        if serverVersionMajor >= k_files_comments && comments == false {
            commentsEnabled = false
        }
        let sharing = NCManageDatabase.shared.getCapabilitiesServerBool(account: appDelegate.account, elements: NCElementsJSON.shared.capabilitiesFileSharingApiEnabled, exists: false)
        if sharing == false {
            sharingEnabled = false
        }
        let activity = NCManageDatabase.shared.getCapabilitiesServerArray(account: appDelegate.account, elements: NCElementsJSON.shared.capabilitiesActivity)
        if activity == nil {
            activityEnabled = false
        }
        if indexPage == NCBrandGlobal.shared.indexPageComments && !commentsEnabled {
            indexPage = NCBrandGlobal.shared.indexPageActivity
        }
        if indexPage == NCBrandGlobal.shared.indexPageSharing && !sharingEnabled {
            indexPage = NCBrandGlobal.shared.indexPageActivity
        }
        if indexPage == NCBrandGlobal.shared.indexPageActivity && !activityEnabled {
            if sharingEnabled {
                indexPage = NCBrandGlobal.shared.indexPageSharing
            } else if commentsEnabled {
                indexPage = NCBrandGlobal.shared.indexPageComments
            }
        }
        
        pagingViewController.activityEnabled = activityEnabled
        pagingViewController.commentsEnabled = commentsEnabled
        pagingViewController.sharingEnabled = sharingEnabled
       
        pagingViewController.metadata = metadata
        
        NotificationCenter.default.addObserver(self, selector: #selector(self.changeTheming), name: NSNotification.Name(rawValue: k_notificationCenter_changeTheming), object: nil)
        
        self.navigationItem.leftBarButtonItem = UIBarButtonItem(title: NSLocalizedString("_cancel_", comment: ""), style: .done, target: self, action: #selector(exitTapped))

        // Pagination
        addChild(pagingViewController)
        view.addSubview(pagingViewController.view)
        pagingViewController.didMove(toParent: self)
                
        // Customization
        pagingViewController.indicatorOptions = .visible(
            height: 1,
            zIndex: Int.max,
            spacing: .zero,
            insets: UIEdgeInsets(top: 0, left: 5, bottom: 0, right: 5)
        )
        
        // Contrain the paging view to all edges.
        pagingViewController.view.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            pagingViewController.view.topAnchor.constraint(equalTo: view.topAnchor),
            pagingViewController.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            pagingViewController.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            pagingViewController.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
        ])
        
        pagingViewController.dataSource = self
        pagingViewController.delegate = self
        pagingViewController.select(index: indexPage)
        let pagingIndexItem = self.pagingViewController(pagingViewController, pagingItemAt: indexPage) as! PagingIndexItem
        self.title = pagingIndexItem.title
        
        changeTheming()
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        
        if appDelegate.disableSharesView {
            self.dismiss(animated: false, completion: nil)
        }
        
        pagingViewController.menuItemSize = .fixed(width: self.view.bounds.width/3, height: 40)
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        
        NotificationCenter.default.postOnMainThread(name: k_notificationCenter_reloadDataSource, userInfo: ["ocId":metadata.ocId, "serverUrl":metadata.serverUrl])
    }
    
    @objc func exitTapped() {
        self.dismiss(animated: true, completion: nil)
    }
    
    //MARK: - NotificationCenter
    
    @objc func changeTheming() {
        view.backgroundColor = NCBrandColor.shared.backgroundForm
        
        pagingViewController.backgroundColor = NCBrandColor.shared.backgroundForm
        pagingViewController.menuBackgroundColor = NCBrandColor.shared.backgroundForm
        pagingViewController.selectedBackgroundColor = NCBrandColor.shared.backgroundForm
        pagingViewController.textColor = NCBrandColor.shared.textView
        pagingViewController.selectedTextColor = NCBrandColor.shared.textView
        pagingViewController.indicatorColor = NCBrandColor.shared.brandElement
        (pagingViewController.view as! NCSharePagingView).setupConstraints()
        pagingViewController.reloadMenu()
    }
}

// MARK: - PagingViewController Delegate

extension NCSharePaging: PagingViewControllerDelegate {
    
    func pagingViewController(_ pagingViewController: PagingViewController, willScrollToItem pagingItem: PagingItem, startingViewController: UIViewController, destinationViewController: UIViewController) {
        
        guard let item = pagingItem as? PagingIndexItem else { return }
         
        if item.index == NCBrandGlobal.shared.indexPageActivity && !activityEnabled {
            pagingViewController.contentInteraction = .none
        } else if item.index == NCBrandGlobal.shared.indexPageComments && !commentsEnabled {
            pagingViewController.contentInteraction = .none
        } else if item.index == NCBrandGlobal.shared.indexPageSharing && !sharingEnabled {
            pagingViewController.contentInteraction = .none
        } else {
            self.title = item.title
        }
    }
}

// MARK: - PagingViewController DataSource

extension NCSharePaging: PagingViewControllerDataSource {
    
    func pagingViewController(_: PagingViewController, viewControllerAt index: Int) -> UIViewController {
    
        let height = pagingViewController.options.menuHeight + NCSharePagingView.HeaderHeight
        let topSafeArea = UIApplication.shared.keyWindow?.safeAreaInsets.top ?? 0
        
        switch index {
        case NCBrandGlobal.shared.indexPageActivity:
            let viewController = UIStoryboard(name: "NCActivity", bundle: nil).instantiateInitialViewController() as! NCActivity
            viewController.insets = UIEdgeInsets(top: height - topSafeArea, left: 0, bottom: 0, right: 0)
            viewController.didSelectItemEnable = false
            viewController.filterFileId = metadata.fileId
            viewController.objectType = "files"
            return viewController
        case NCBrandGlobal.shared.indexPageComments:
            let viewController = UIStoryboard(name: "NCShare", bundle: nil).instantiateViewController(withIdentifier: "comments") as! NCShareComments
            viewController.metadata = metadata
            viewController.height = height
            return viewController
        case NCBrandGlobal.shared.indexPageSharing:
            let viewController = UIStoryboard(name: "NCShare", bundle: nil).instantiateViewController(withIdentifier: "sharing") as! NCShare
            viewController.sharingEnabled = sharingEnabled
            viewController.metadata = metadata
            viewController.height = height
            return viewController
        default:
            return UIViewController()
        }
    }
    
    func pagingViewController(_: PagingViewController, pagingItemAt index: Int) -> PagingItem {
        
        switch index {
        case NCBrandGlobal.shared.indexPageActivity:
            return PagingIndexItem(index: index, title: NSLocalizedString("_activity_", comment: ""))
        case NCBrandGlobal.shared.indexPageComments:
            return PagingIndexItem(index: index, title: NSLocalizedString("_comments_", comment: ""))
        case NCBrandGlobal.shared.indexPageSharing:
            return PagingIndexItem(index: index, title: NSLocalizedString("_sharing_", comment: ""))
        default:
            return PagingIndexItem(index: index, title: "")
        }
    }
   
    func numberOfViewControllers(in pagingViewController: PagingViewController) -> Int {
        return 3
    }
}

// MARK: - Header

class NCShareHeaderViewController: PagingViewController {
    
    public var image: UIImage?
    public var metadata: tableMetadata?
    
    public var activityEnabled = true
    public var commentsEnabled = true
    public var sharingEnabled = true

    override func loadView() {
        view = NCSharePagingView(
            options: options,
            collectionView: collectionView,
            pageView: pageViewController.view,
            metadata: metadata
        )
    }
    
    override func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        if indexPath.item == NCBrandGlobal.shared.indexPageActivity && !activityEnabled {
            return
        }
        if indexPath.item == NCBrandGlobal.shared.indexPageComments && !commentsEnabled {
            return
        }
        if indexPath.item == NCBrandGlobal.shared.indexPageSharing && !sharingEnabled {
            return
        }
        super.collectionView(collectionView, didSelectItemAt: indexPath)
    }
}

class NCSharePagingView: PagingView {
    
    static let HeaderHeight: CGFloat = 250
    var metadata: tableMetadata?
    
    var headerHeightConstraint: NSLayoutConstraint?
    
    public init(options: Parchment.PagingOptions, collectionView: UICollectionView, pageView: UIView, metadata: tableMetadata?) {
        super.init(options: options, collectionView: collectionView, pageView: pageView)
        
        self.metadata = metadata
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func setupConstraints() {
        
        let headerView = Bundle.main.loadNibNamed("NCShareHeaderView", owner: self, options: nil)?.first as! NCShareHeaderView
        headerView.backgroundColor = NCBrandColor.shared.backgroundForm
        headerView.ocId = metadata!.ocId
        
        if FileManager.default.fileExists(atPath: CCUtility.getDirectoryProviderStorageIconOcId(metadata!.ocId, etag: metadata!.etag)) {
            headerView.imageView.image = UIImage.init(contentsOfFile: CCUtility.getDirectoryProviderStorageIconOcId(metadata!.ocId, etag: metadata!.etag))
        } else {
            if metadata!.directory {
                let image = UIImage.init(named: "folder")!
                headerView.imageView.image = CCGraphics.changeThemingColorImage(image, width: image.size.width*2, height: image.size.height*2, color: NCBrandColor.shared.brandElement)
            } else if metadata!.iconName.count > 0 {
                headerView.imageView.image = UIImage.init(named: metadata!.iconName)
            } else {
                headerView.imageView.image = UIImage.init(named: "file")
            }
        }
        headerView.fileName.text = metadata?.fileNameView
        headerView.fileName.textColor = NCBrandColor.shared.textView
        if metadata!.favorite {
            headerView.favorite.setImage(CCGraphics.changeThemingColorImage(UIImage.init(named: "favorite"), width: 40, height: 40, color: NCBrandColor.shared.yellowFavorite), for: .normal)
        } else {
            headerView.favorite.setImage(CCGraphics.changeThemingColorImage(UIImage.init(named: "favorite"), width: 40, height: 40, color: NCBrandColor.shared.textInfo), for: .normal)
        }
        headerView.info.text = CCUtility.transformedSize(metadata!.size) + ", " + CCUtility.dateDiff(metadata!.date as Date)
        addSubview(headerView)
        
        pageView.translatesAutoresizingMaskIntoConstraints = false
        collectionView.translatesAutoresizingMaskIntoConstraints = false
        headerView.translatesAutoresizingMaskIntoConstraints = false
        
        headerHeightConstraint = headerView.heightAnchor.constraint(
            equalToConstant: NCSharePagingView.HeaderHeight
        )
        headerHeightConstraint?.isActive = true
        
        NSLayoutConstraint.activate([
            collectionView.leadingAnchor.constraint(equalTo: leadingAnchor),
            collectionView.trailingAnchor.constraint(equalTo: trailingAnchor),
            collectionView.heightAnchor.constraint(equalToConstant: options.menuHeight),
            collectionView.topAnchor.constraint(equalTo: headerView.bottomAnchor),
            
            headerView.topAnchor.constraint(equalTo: topAnchor),
            headerView.leadingAnchor.constraint(equalTo: leadingAnchor),
            headerView.trailingAnchor.constraint(equalTo: trailingAnchor),
            
            pageView.leadingAnchor.constraint(equalTo: leadingAnchor),
            pageView.trailingAnchor.constraint(equalTo: trailingAnchor),
            pageView.bottomAnchor.constraint(equalTo: bottomAnchor),
            pageView.topAnchor.constraint(equalTo: topAnchor, constant: 10)
        ])
    }
}

class NCShareHeaderView: UIView {
    
    @IBOutlet weak var imageView: UIImageView!
    @IBOutlet weak var fileName: UILabel!
    @IBOutlet weak var info: UILabel!
    @IBOutlet weak var favorite: UIButton!
    
    private let appDelegate = UIApplication.shared.delegate as! AppDelegate
    var ocId = ""

    @IBAction func touchUpInsideFavorite(_ sender: UIButton) {
        if let metadata = NCManageDatabase.shared.getMetadataFromOcId(ocId) {
            NCNetworking.shared.favoriteMetadata(metadata, urlBase: appDelegate.urlBase) { (errorCode, errorDescription) in
                if errorCode == 0 {
                    if !metadata.favorite {
                        self.favorite.setImage(CCGraphics.changeThemingColorImage(UIImage.init(named: "favorite"), width: 40, height: 40, color: NCBrandColor.shared.yellowFavorite), for: .normal)
                    } else {
                        self.favorite.setImage(CCGraphics.changeThemingColorImage(UIImage.init(named: "favorite"), width: 40, height: 40, color: NCBrandColor.shared.textInfo), for: .normal)
                    }
                } else {
                    NCContentPresenter.shared.messageNotification("_error_", description: errorDescription, delay: TimeInterval(k_dismissAfterSecond), type: NCContentPresenter.messageType.error, errorCode: errorCode)
                }
            }
        }
    }
}
