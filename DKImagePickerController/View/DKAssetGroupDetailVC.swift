//
//  DKAssetGroupDetailVC.swift
//  DKImagePickerController
//
//  Created by ZhangAo on 15/8/10.
//  Copyright (c) 2015年 ZhangAo. All rights reserved.
//

import UIKit
import AVFoundation
import Photos

private extension UICollectionView {
    
    func indexPathsForElements(in rect: CGRect, _ hidesCamera: Bool) -> [IndexPath] {
        let allLayoutAttributes = collectionViewLayout.layoutAttributesForElements(in: rect)!
        
        if hidesCamera {
            return allLayoutAttributes.map { $0.indexPath }
        } else {
            return allLayoutAttributes.compactMap { $0.indexPath.item == 0 ? nil : IndexPath(item: $0.indexPath.item - 1, section: $0.indexPath.section) }
        }
    }
    
}

// Show all images in the asset group
public class DKAssetGroupDetailVC: UIViewController, UICollectionViewDelegate, UICollectionViewDataSource, DKGroupDataManagerObserver, UIGestureRecognizerDelegate {
    	
    private lazy var selectGroupButton: UIButton = {
        let button = UIButton()
		
        let globalTitleColor = UINavigationBar.appearance().titleTextAttributes?[NSAttributedString.Key.foregroundColor] as? UIColor
		button.setTitleColor(globalTitleColor ?? UIColor.black, for: .normal)
		
        let globalTitleFont = UINavigationBar.appearance().titleTextAttributes?[NSAttributedString.Key.font] as? UIFont
		button.titleLabel!.font = globalTitleFont ?? UIFont.boldSystemFont(ofSize: 18.0)
		
		button.addTarget(self, action: #selector(showGroupSelector), for: .touchUpInside)
        return button
    }()
		
    public var collectionView: UICollectionView!
    internal weak var imagePickerController: DKImagePickerController!
    internal var topContainerView: UIView?
    private var selectedGroupId: String?
	private var groupListVC: DKAssetGroupListVC!
    private var hidesCamera: Bool = false
	private var footerView: UIView?
    private var currentViewSize: CGSize!
    private var registeredCellIdentifiers = Set<String>()
    private var thumbnailSize = CGSize.zero
    public var lastSelectedItemIndex: IndexPath?
    public var selectedIndexPaths = [[String:Any]]()
	
	override public func viewWillLayoutSubviews() {
		super.viewWillLayoutSubviews()
		
		if let currentViewSize = self.currentViewSize, currentViewSize.equalTo(self.view.bounds.size) {
			return
		} else {
			currentViewSize = self.view.bounds.size
		}

		self.collectionView?.collectionViewLayout.invalidateLayout()
	}
    
    override public func viewDidLoad() {
        super.viewDidLoad()
        
        self.addTopContainerView()
		
		let layout = self.imagePickerController.UIDelegate.layoutForImagePickerController(self.imagePickerController).init()
        self.collectionView = UICollectionView(frame: CGRect.zero, collectionViewLayout: layout)
        self.collectionView.backgroundColor = self.imagePickerController.UIDelegate.imagePickerControllerCollectionViewBackgroundColor()
        self.collectionView.allowsMultipleSelection = true
		self.collectionView.delegate = self
		self.collectionView.dataSource = self
		self.view.addSubview(self.collectionView)
        
        //Long Press
        let longPressGesture:UILongPressGestureRecognizer = UILongPressGestureRecognizer(target: self, action: #selector(handleLongPress))
        longPressGesture.minimumPressDuration = 0.5
        longPressGesture.delegate = self
        self.collectionView.addGestureRecognizer(longPressGesture)
		
		self.footerView = self.imagePickerController.UIDelegate.imagePickerControllerFooterView(self.imagePickerController)
		if let footerView = self.footerView {
			self.view.addSubview(footerView)
		}
		
		self.hidesCamera = self.imagePickerController.sourceType == .photo
		self.checkPhotoPermission()
    }
    
    @objc func handleLongPress(longPressGesture:UILongPressGestureRecognizer) {
        // ignore if the gesture has not been finished
        if (longPressGesture.state != .began) {
            return
        }

        let p = longPressGesture.location(in: self.collectionView)
        guard let indexPath = self.collectionView.indexPathForItem(at: p) else { return }

        self.imagePickerController.UIDelegate.imagePickerController(self.imagePickerController, didLongPressAt: indexPath)
    }
    
    func addTopContainerView() {
        if let topContainerView = self.topContainerView {
            let width = UIScreen.main.bounds.width
            topContainerView.frame = CGRect(x: 0, y: 0, width: width, height: width);
            self.view.insertSubview(topContainerView, at: 0)
        }
    }
    
    override public func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        
        self.updateCachedAssets()
    }
	
	override public func viewDidLayoutSubviews() {
		super.viewDidLayoutSubviews()
        
        var offsetHeight = CGFloat(0)
        if let topContainerView = self.topContainerView {
            offsetHeight = topContainerView.frame.height
        }
		
		if let footerView = self.footerView {
			footerView.frame = CGRect(x: 0, y: self.view.bounds.height - footerView.bounds.height, width: self.view.bounds.width, height: footerView.bounds.height)
			self.collectionView.frame = CGRect(x: 0, y: offsetHeight, width: self.view.bounds.width, height: self.view.bounds.height - footerView.bounds.height - offsetHeight)
			
		} else {
			self.collectionView.frame = CGRect(x: 0, y: offsetHeight, width: self.view.bounds.width, height: self.view.bounds.height - offsetHeight)
		}
	}
	
	internal func checkPhotoPermission() {
		func photoDenied() {
			self.view.addSubview(DKPermissionView.permissionView(.photo))
			self.view.backgroundColor = UIColor.black
			self.collectionView?.isHidden = true
		}
		
		func setup() {
            self.resetCachedAssets()
			getImageManager().groupDataManager.addObserver(self)
			self.groupListVC = DKAssetGroupListVC(selectedGroupDidChangeBlock: { [unowned self] groupId in
				self.selectAssetGroup(groupId)
			}, defaultAssetGroup: self.imagePickerController.defaultAssetGroup)
			self.groupListVC.loadGroups()
		}
		
		DKImageManager.checkPhotoPermission { granted in
			granted ? setup() : photoDenied()
		}
	}
	
    func selectAssetGroup(_ groupId: String?) {
        if self.selectedGroupId == groupId {
            self.updateTitleView()
            return
        }
        
        self.selectedGroupId = groupId
		self.updateTitleView()
        
        let group = getImageManager().groupDataManager.fetchGroupWithGroupId(self.selectedGroupId!)
        if (group.totalCount > 0) {
            let firstAssetCellIndex = self.hidesCamera ? 0 : 1
            if let asset = self.fetchAsset(for: firstAssetCellIndex) {
                lastSelectedItemIndex = IndexPath(row: firstAssetCellIndex, section: 0)
                self.imagePickerController.defaultSelectedAssets = [asset]
                if let highlightCallback = self.imagePickerController.didHighlightImage {
                    // highlight the first cell by default
                    highlightCallback([asset])
                }
            }
        }
        
		self.collectionView!.reloadData()
    }
	
	func updateTitleView() {
		let group = getImageManager().groupDataManager.fetchGroupWithGroupId(self.selectedGroupId!)
		self.title = group.groupName
		
		let groupsCount = getImageManager().groupDataManager.groupIds?.count ?? 0
		self.selectGroupButton.setTitle(group.groupName + (groupsCount > 1 ? "  \u{25be}" : "" ), for: .normal)
		self.selectGroupButton.sizeToFit()
		self.selectGroupButton.isEnabled = groupsCount > 1
		
		self.navigationItem.titleView = self.selectGroupButton
	}
    
    @objc func showGroupSelector() {
        DKPopoverViewController.popoverViewController(self.groupListVC, fromView: self.selectGroupButton)
    }
    
    public func fetchAsset(for index: Int) -> DKAsset? {
        if !self.hidesCamera && index == 0 {
            return nil
        }
        let assetIndex = (index - (self.hidesCamera ? 0 : 1))
        let group = getImageManager().groupDataManager.fetchGroupWithGroupId(self.selectedGroupId!)
        return getImageManager().groupDataManager.fetchAsset(group, index: assetIndex)
    }
    
    func isCameraCell(indexPath: IndexPath) -> Bool {
        return indexPath.row == 0 && !self.hidesCamera
    }
	
    // MARK: - Cells
    
    func registerCellIfNeeded(cellClass: DKAssetGroupDetailBaseCell.Type) {
        let cellReuseIdentifier = cellClass.cellReuseIdentifier()
        
        if !self.registeredCellIdentifiers.contains(cellReuseIdentifier) {
            self.collectionView.register(cellClass, forCellWithReuseIdentifier: cellReuseIdentifier)
            self.registeredCellIdentifiers.insert(cellReuseIdentifier)
        }
    }
    
    func dequeueReusableCell(for indexPath: IndexPath) -> DKAssetGroupDetailBaseCell {
        let asset = self.fetchAsset(for: indexPath.row)!
        
        let cellClass: DKAssetGroupDetailBaseCell.Type!
        if asset.isVideo {
            cellClass = self.imagePickerController.UIDelegate.imagePickerControllerCollectionVideoCell()
        } else {
            cellClass = self.imagePickerController.UIDelegate.imagePickerControllerCollectionImageCell()
        }
        self.registerCellIfNeeded(cellClass: cellClass)
        
        let cell = self.collectionView.dequeueReusableCell(withReuseIdentifier: cellClass.cellReuseIdentifier(), for: indexPath) as! DKAssetGroupDetailBaseCell
        self.setup(assetCell: cell, for: indexPath, with: asset)
        
        return cell
    }
    
    func dequeueReusableCameraCell(for indexPath: IndexPath) -> DKAssetGroupDetailBaseCell {
        let cellClass = self.imagePickerController.UIDelegate.imagePickerControllerCollectionCameraCell()
        self.registerCellIfNeeded(cellClass: cellClass)
        
        let cell = self.collectionView.dequeueReusableCell(withReuseIdentifier: cellClass.cellReuseIdentifier(), for: indexPath)
        return cell as! DKAssetGroupDetailBaseCell
    }
	
    func setup(assetCell cell: DKAssetGroupDetailBaseCell, for indexPath: IndexPath, with asset: DKAsset) {
        cell.asset = asset
        cell.isCellFocused = lastSelectedItemIndex == indexPath
		let tag = indexPath.row + 1
		cell.tag = tag
		
        if self.thumbnailSize.equalTo(CGSize.zero) {
            self.thumbnailSize = self.collectionView!.collectionViewLayout.layoutAttributesForItem(at: indexPath)!.size.toPixel()
        }
        
        asset.fetchImageWithSize(self.thumbnailSize, options: nil, contentMode: .aspectFill) { (image, info) in
            if cell.tag == tag {
                cell.thumbnailImage = image
            }
        }

        if let index = self.imagePickerController.selectedAssets.firstIndex(of: asset) {
			cell.isSelected = true
			cell.index = index
			self.collectionView!.selectItem(at: indexPath, animated: false, scrollPosition: [])
		} else {
			cell.isSelected = false
			self.collectionView!.deselectItem(at: indexPath, animated: false)
		}
	}

    // MARK: - UICollectionViewDelegate, UICollectionViewDataSource methods

    public func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
		guard let selectedGroupId = self.selectedGroupId else { return 0 }
		
		let group = getImageManager().groupDataManager.fetchGroupWithGroupId(selectedGroupId)
        return (group.totalCount ?? 0) + (self.hidesCamera ? 0 : 1)
    }
    
    public func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        let cell: DKAssetGroupDetailBaseCell!
        if self.isCameraCell(indexPath: indexPath) {
            cell = self.dequeueReusableCameraCell(for: indexPath)
        } else {
            cell = self.dequeueReusableCell(for: indexPath)
        }
        
        return cell
    }
    
    public func collectionView(_ collectionView: UICollectionView, shouldSelectItemAt indexPath: IndexPath) -> Bool {
        if let firstSelectedAsset = self.imagePickerController.selectedAssets.first,
            let selectedAsset = (collectionView.cellForItem(at: indexPath) as? DKAssetGroupDetailBaseCell)?.asset, self.imagePickerController.allowMultipleTypes == false && firstSelectedAsset.isVideo != selectedAsset.isVideo && !self.imagePickerController.singleSelect {

            let alert = UIAlertController(
                    title: DKImageLocalizedStringWithKey("selectPhotosOrVideos")
                    , message: DKImageLocalizedStringWithKey("selectPhotosOrVideosError")
                    , preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: DKImageLocalizedStringWithKey("ok"), style: .cancel) { _ in })
            self.imagePickerController.present(alert, animated: true){}

            return false
        }
		
		let shouldSelect = self.imagePickerController.selectedAssets.count < self.imagePickerController.maxSelectableCount
		if !shouldSelect {
			self.imagePickerController.UIDelegate.imagePickerControllerDidReachMaxLimit(self.imagePickerController)
		}
		
		return shouldSelect
    }
    
    public func collectionView(_ collectionView: UICollectionView, shouldDeselectItemAt indexPath: IndexPath) -> Bool {
        let shouldDeselect = lastSelectedItemIndex == indexPath && !self.imagePickerController.singleSelect
        if (!shouldDeselect) {
            lastSelectedItemIndex = indexPath
            if let cell = collectionView.cellForItem(at: indexPath) as? DKAssetGroupDetailBaseCell, let asset = cell.asset, let highlightCallback = self.imagePickerController.didHighlightImage {
                highlightCallback([asset])
            }
            (collectionView.cellForItem(at: indexPath) as? DKAssetGroupDetailBaseCell)?.isCellFocused = true
            collectionView.reloadData()
        }
        return shouldDeselect
    }
    
    public func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        if self.isCameraCell(indexPath: indexPath) {
            if UIImagePickerController.isSourceTypeAvailable(.camera) {
                self.imagePickerController.presentCamera()
            }
        } else if let cell = collectionView.cellForItem(at: indexPath) as? DKAssetGroupDetailBaseCell, let selectedAsset = cell.asset  {
            lastSelectedItemIndex = indexPath
            self.imagePickerController.selectImage(selectedAsset)
            if let highlightCallback = self.imagePickerController.didHighlightImage {
                highlightCallback([selectedAsset])
            }

            if let cell = collectionView.cellForItem(at: indexPath) as? DKAssetGroupDetailBaseCell {
                cell.index = self.imagePickerController.selectedAssets.count - 1
                cell.isCellFocused = true
                selectedIndexPaths.append(["index": cell.index, "indexPath": indexPath])
            }
            collectionView.reloadData()
        }
    }
    
    public func collectionView(_ collectionView: UICollectionView, didDeselectItemAt indexPath: IndexPath) {
        
		if let cell = (collectionView.cellForItem(at: indexPath) as? DKAssetGroupDetailBaseCell), let removedAsset = cell.asset {
            let removedIndex = self.imagePickerController.selectedAssets.firstIndex(of: removedAsset)!
            if (selectedIndexPaths.count > removedIndex) {
                selectedIndexPaths.remove(at: removedIndex)
            }
            let firstAssetCellIndex = self.hidesCamera ? 0 : 1
            lastSelectedItemIndex = selectedIndexPaths.last?["indexPath"] as? IndexPath ?? IndexPath(row: firstAssetCellIndex, section: 0)
            if let cell = collectionView.cellForItem(at: lastSelectedItemIndex!) as? DKAssetGroupDetailBaseCell, let asset = cell.asset {
                if let highlightCallback = self.imagePickerController.didHighlightImage {
                    highlightCallback([asset])
                }
                cell.isCellFocused = true
            }
			/// Minimize the number of cycles.
			let indexPathsForSelectedItems = collectionView.indexPathsForSelectedItems!
			let indexPathsForVisibleItems = collectionView.indexPathsForVisibleItems
			
			let intersect = Set(indexPathsForVisibleItems).intersection(Set(indexPathsForSelectedItems))
			
			for selectedIndexPath in intersect {
                if let selectedCell = (collectionView.cellForItem(at: selectedIndexPath) as? DKAssetGroupDetailBaseCell), let selectedCellAsset = selectedCell.asset, let selectedIndex = self.imagePickerController.selectedAssets.firstIndex(of: selectedCellAsset) {
					if selectedIndex > removedIndex {
						selectedCell.index = selectedCell.index - 1
					}
				}
			}
			
            collectionView.reloadData()
			self.imagePickerController.deselectImage(removedAsset)
		}
    }
    
    public func scrollViewDidScroll(_ scrollView: UIScrollView) {
        self.updateCachedAssets()
    }
    
    // MARK: - Asset Caching
    
    var previousPreheatRect = CGRect.zero
    
    fileprivate func resetCachedAssets() {
        getImageManager().stopCachingForAllAssets()
        self.previousPreheatRect = .zero
    }

    func updateCachedAssets() {
        // Update only if the view is visible.
        guard isViewLoaded && view.window != nil && self.selectedGroupId != nil else { return }
        
        // The preheat window is twice the height of the visible rect.
        let preheatRect = view!.bounds.insetBy(dx: 0, dy: -0.5 * view!.bounds.height)
        
        // Update only if the visible area is significantly different from the last preheated area.
        let delta = abs(preheatRect.midY - self.previousPreheatRect.midY)
        guard delta > view.bounds.height / 3 else { return }
        
        let group = getImageManager().groupDataManager.fetchGroupWithGroupId(self.selectedGroupId!)
        
        // Compute the assets to start caching and to stop caching.
        let (addedRects, removedRects) = self.differencesBetweenRects(self.previousPreheatRect, preheatRect)
        let addedAssets = addedRects
            .flatMap { rect in self.collectionView!.indexPathsForElements(in: rect, self.hidesCamera) }
            .map { indexPath in getImageManager().groupDataManager.fetchOriginalAsset(group, index: indexPath.item) }
        let removedAssets = removedRects
            .flatMap { rect in self.collectionView!.indexPathsForElements(in: rect, self.hidesCamera) }
            .map { indexPath in getImageManager().groupDataManager.fetchOriginalAsset(group, index: indexPath.item) }
        
        // Update the assets the PHCachingImageManager is caching.
        getImageManager().startCachingAssets(for: addedAssets,
                                             targetSize: self.thumbnailSize, contentMode: .aspectFill, options: nil)
        getImageManager().stopCachingAssets(for: removedAssets,
                                            targetSize: self.thumbnailSize, contentMode: .aspectFill, options: nil)
        
        // Store the preheat rect to compare against in the future.
        self.previousPreheatRect = preheatRect
    }
    
    fileprivate func differencesBetweenRects(_ old: CGRect, _ new: CGRect) -> (added: [CGRect], removed: [CGRect]) {
        if old.intersects(new) {
            var added = [CGRect]()
            if new.maxY > old.maxY {
                added += [CGRect(x: new.origin.x, y: old.maxY,
                                 width: new.width, height: new.maxY - old.maxY)]
            }
            if old.minY > new.minY {
                added += [CGRect(x: new.origin.x, y: new.minY,
                                 width: new.width, height: old.minY - new.minY)]
            }
            var removed = [CGRect]()
            if new.maxY < old.maxY {
                removed += [CGRect(x: new.origin.x, y: new.maxY,
                                   width: new.width, height: old.maxY - new.maxY)]
            }
            if old.minY < new.minY {
                removed += [CGRect(x: new.origin.x, y: old.minY,
                                   width: new.width, height: new.minY - old.minY)]
            }
            return (added, removed)
        } else {
            return ([new], [old])
        }
    }
	
	// MARK: - DKGroupDataManagerObserver methods
	
	func groupDidUpdate(_ groupId: String) {
		if self.selectedGroupId == groupId {
			self.updateTitleView()
		}
	}
	
	func group(_ groupId: String, didRemoveAssets assets: [DKAsset]) {
		for (_, selectedAsset) in self.imagePickerController.selectedAssets.enumerated() {
			for removedAsset in assets {
				if selectedAsset.isEqual(removedAsset) {
					self.imagePickerController.deselectImage(selectedAsset)
				}
			}
		}
	}
    
    func groupDidUpdateComplete(_ groupId: String) {
        if self.selectedGroupId == groupId {
            self.resetCachedAssets()
            self.collectionView?.reloadData()
        }
    }

}
