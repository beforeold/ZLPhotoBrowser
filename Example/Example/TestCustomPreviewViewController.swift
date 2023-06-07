//
//  TestCustomPreviewViewController.swift
//  Example
//
//  Created by Brook_Mobius on 6/7/23.
//

import UIKit
import Photos
import ZLPhotoBrowser

class TestCustomPreviewViewController: UIViewController {
  
  override func viewDidLoad() {
    super.viewDidLoad()
    
    view.backgroundColor = .systemBackground
    
    showCustomView()
    
    let fullItem = UIBarButtonItem(title: "Show Full Screen", style: .plain, target: self, action: #selector(onCreatePhotosPreview))
    navigationItem.rightBarButtonItem = fullItem
  }
  
  @objc func onCreatePhotosPreview() {
      let options = PHFetchOptions()
      options.predicate = NSPredicate(format: "mediaType == %ld", PHAssetMediaType.image.rawValue)
      options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
      let result = PHAsset.fetchAssets(with: options)
      var assets: [ZLPhotoModel] = []
      
      let limit = 20
      var loopCount = 0
      result.enumerateObjects(options: []) { asset, index, stop in
          loopCount += 1
          if loopCount > limit {
              stop.pointee = true
              return
          }
          
          let photo = ZLPhotoModel(asset: asset)
          photo.isSelected = index % 2 == 0
          assets.append(photo)
      }
      
      // let index = (0..<limit).randomElement()!
      let index = 0
      let vc = PhotoPreview.createPhotoPreviewVC(
          photos: assets,
          index: index,
          embedsInNavigationController: true,
          removingReason: "keep") { selectingModel in
              print("selectingModel", selectingModel)
          } removingItemCallback: { reason, model in
              print("removingCallback", reason, model)
          } removingAllCallback: { [weak self] in
              print("removingAllCallback")
              self?.dismiss(animated: true)
          }

      show(vc, sender: nil)
  }

  @objc func showCustomView() {
      let options = PHFetchOptions()
      options.predicate = NSPredicate(format: "mediaType == %ld", PHAssetMediaType.image.rawValue)
      options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
      let result = PHAsset.fetchAssets(with: options)
      var assets: [ZLPhotoModel] = []
      
      let limit = 20
      var loopCount = 0
      result.enumerateObjects(options: []) { asset, index, stop in
          loopCount += 1
          if loopCount > limit {
              stop.pointee = true
              return
          }
          
          let photo = ZLPhotoModel(asset: asset)
          photo.isSelected = index % 2 == 0
          assets.append(photo)
      }
      
      // let index = (0..<limit).randomElement()!
      let index = 0
      let vc = PhotoPreview.createPhotoPreviewVC(
          photos: assets,
          index: index,
          embedsInNavigationController: true,
          context: [
            "showsTestSettings": false,
            "hidesNavView": true,
            "aspectFill": true,
            "disablesScaleBehavior": true,
            "assetInset": 16 as CGFloat,
            "assetWidth": (UIScreen.main.bounds.width - 2 * 16),
            "assetHeight": 240 as CGFloat,
            "thumbnailLength": 40 as CGFloat,
            "thumbnailContainerHeight": 64 as CGFloat,
            "thumbnailSpacing": 4 as CGFloat,
            "thumbnailCornerRadius": 8 as CGFloat,
            "thumbnailCornerPadding": 0 as CGFloat,
          ],
          removingReason: nil) { selectingModel in
              print("selectingModel", selectingModel)
          } removingItemCallback: { reason, model in
              print("removingCallback", reason, model)
          } removingAllCallback: { [weak self] in
              print("removingAllCallback")
              self?.dismiss(animated: true)
          }

    self.addChild(vc)
    self.view.addSubview(vc.view)
    vc.view.frame = CGRect(
      x: 0,
      y: 100,
      width: view.bounds.width,
      height: 240 + 64
    )
  }
  
}
