//
//  ZLWeakProxy.swift
//  ZLPhotoBrowser
//
//  Created by long on 2021/3/10.
//
//  Copyright (c) 2020 Long Zhang <495181165@qq.com>
//
//  Permission is hereby granted, free of charge, to any person obtaining a copy
//  of this software and associated documentation files (the "Software"), to deal
//  in the Software without restriction, including without limitation the rights
//  to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
//  copies of the Software, and to permit persons to whom the Software is
//  furnished to do so, subject to the following conditions:
//
//  The above copyright notice and this permission notice shall be included in
//  all copies or substantial portions of the Software.
//
//  THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
//  IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
//  FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
//  AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
//  LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
//  OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
//  THE SOFTWARE.

import UIKit

class ZLWeakProxy: NSObject {
    
    private weak var target: NSObjectProtocol?
    
    init(target: NSObjectProtocol) {
        self.target = target
        super.init()
    }
    
    class func proxy(withTarget target: NSObjectProtocol) -> ZLWeakProxy {
        return ZLWeakProxy(target: target)
    }
    
    override func forwardingTarget(for aSelector: Selector!) -> Any? {
        return target
    }
    
    override func responds(to aSelector: Selector!) -> Bool {
        return target?.responds(to: aSelector) ?? false
    }
    
}

import Photos

private func clamp(_ minValue: Int, _ value: Int, _ maxValue: Int) -> Int {
    return max(minValue, min(value, maxValue))
}

public typealias ZLAssetFromFrameProvider = ((Int) -> CGRect?)?

public struct PhotoPreview {
    /// create a preview vc
    /// - Parameters:
    ///   - photos: the photos with selecte status
    ///   - index: the displaying index at first
    ///   - selectionEventCallback: the callback event for currentModel with selected updated
    /// - Returns: the navigation controller
    public static func createPhotoPreviewVC(
        photos: [ZLPhotoModel],
        index: Int = 0,
        isMenuContextPreview: Bool = false,
        embedsInNavigationController: Bool = false,
        removingReason: String? = nil,
        selectionEventCallback: @escaping (ZLPhotoModel) -> Void,
        fromFrameProvider: ZLAssetFromFrameProvider = nil,
        removingItemCallback: ((_ reason: String, _ model: ZLPhotoModel) -> Void)? = nil,
        removingAllCallback: (() -> Void)? = nil
    ) -> UIViewController {
        let vc = PhotoPreviewController(
            photos: photos,
            index: index
        )
        vc.isMenuContextPreview = isMenuContextPreview
        vc.selectionEventCallback = selectionEventCallback
        vc.fromFrameProvider = fromFrameProvider
        vc.removingReason = removingReason
        vc.removingItemCallback = removingItemCallback
        vc.removingAllCallback = removingAllCallback
        
        if embedsInNavigationController {
            return ZLImageNavController(rootViewController: vc)
        }
        
        return vc
    }
}

public protocol AppTracking {
    
    /// track event
    /// - Parameters:
    ///   - event: the event name
    ///   - alternativeEvent: the alternativeEvent if any
    ///   - action: the action name
    ///   - properties: the properties
    ///   - platformOptions: specify  platfor nams if needed
    func trackEvent(
      event: String,
      alternativeEvent: String?,
      action: String?,
      properties: [String: Any],
      platformOptions: [String]?
    )
}

extension PhotoPreview {
    public static var appTracker: AppTracking?
    
    static func trackEvent(
        event: String,
        action: String,
        properties: [String: Any] = [:]
    ) {
        appTracker?.trackEvent(
            event: event,
            alternativeEvent: nil,
            action: action,
            properties: properties,
            platformOptions: nil
        )
    }
}

class PhotoPreviewController: UIViewController {
    
    static let colItemSpacing: CGFloat = 40
    
    static let selPhotoPreviewH: CGFloat = 80
    
    static let previewVCScrollNotification = Notification.Name("previewVCScrollNotification")
    
    var arrDataSources: [ZLPhotoModel]
    
    var selectionEventCallback: (ZLPhotoModel) -> Void = { _ in }
    var fromFrameProvider: ZLAssetFromFrameProvider = nil
    
    var removingReason: String?
    var removingItemCallback: ((_ reason: String, _ model: ZLPhotoModel) -> Void)?
    var removingAllCallback: (() -> Void)?
    
    var currentIndex: Int {
        didSet {
#if DEBUG
            print("currentIndex", currentIndex)
#endif
           popInteractiveTransition?.currentIndex = currentIndex
        }
    }
    
    lazy var collectionView: UICollectionView = {
        let layout = UICollectionViewFlowLayout()
        layout.scrollDirection = .horizontal
        
        let view = UICollectionView(frame: .zero, collectionViewLayout: layout)
        view.backgroundColor = .clear
        view.dataSource = self
        view.delegate = self
        view.isPagingEnabled = true
        view.showsHorizontalScrollIndicator = false
        
        ZLPhotoPreviewCell.zl.register(view)
        ZLGifPreviewCell.zl.register(view)
        ZLLivePhotoPreviewCell.zl.register(view)
        ZLVideoPreviewCell.zl.register(view)
        
        return view
    }()
    
    private let showBottomViewAndSelectBtn: Bool
    
    private var indexBeforOrientationChanged: Int
    
    private var ignoresDidScroll = false
    
    private lazy var navView: UIView = {
        let view = UIView()
        view.backgroundColor = .zl.navBarColorOfPreviewVC
        return view
    }()
    
    private var navBlurView: UIVisualEffectView?
    
    private lazy var backBtn: UIButton = {
        let btn = ZLEnlargeButton(type: .custom)
        btn.enlargeInset = 5
        let image: UIImage? = UIImage(named: "ic_left") ?? .zl.getImage("zl_navBack")
        btn.setImage(image, for: .normal)
        btn.imageEdgeInsets = UIEdgeInsets(top: 0, left: -10, bottom: 0, right: 0)
        btn.addTarget(self, action: #selector(backBtnClick), for: .touchUpInside)
        return btn
    }()
    
    private lazy var selectBtn: ZLEnlargeButton = {
        let btn = ZLEnlargeButton(type: .custom)
        btn.setImage(UIImage(named: "ic_checkbox_unselected") ?? .zl.getImage("zl_btn_circle"), for: .normal)
        btn.setImage(UIImage(named: "ic_checkbox_selected") ?? .zl.getImage("zl_btn_selected"), for: .selected)
        btn.enlargeInset = 10
        btn.addTarget(self, action: #selector(selectBtnClick), for: .touchUpInside)
        return btn
    }()
    
    private lazy var indexLabel: UILabel = {
        let label = UILabel()
        label.backgroundColor = .zl.indexLabelBgColor
        label.font = .zl.font(ofSize: 14)
        label.textColor = .white
        label.textAlignment = .center
        label.layer.cornerRadius = 25.0 / 2
        label.layer.masksToBounds = true
        label.isHidden = true
        return label
    }()
  
    private lazy var titleIndexLabel: UILabel = {
        let label = UILabel()
        label.font = UIFont(name: "SFPro-Semibold", size: 17)
        label.textColor = .white
        label.textAlignment = .center
        return label
    }()
  
    var isMenuContextPreview = false
  
    private lazy var bottomView: UIView = {
        let view = UIView()
        view.backgroundColor = .zl.bottomToolViewBgColorOfPreviewVC
        return view
    }()
    
    private lazy var keepButton: UIButton = {
        let title = NSLocalizedString("keep", comment: "")
        let image = UIImage(named: "ic_star_sparkle_filled_16")
        
        let button = SpacingButton(type: .custom)
        button.titleEdgeInsets = . init(top: 0, left: 8, bottom: 0, right: 0)
        button.contentEdgeInsets = .init(top: 4, left: 8, bottom: 4, right: 12)
        button.backgroundColor = UIColor(white: 1.0, alpha: 0.2)
        button.layer.cornerRadius = 15
        button.titleLabel?.font = UIFont(name: "SFPro", size: 13)
        button.addTarget(self, action: #selector(onKeepButtonEvent), for: .touchUpInside)
        button.setTitle(title, for: .normal)
        button.setImage(image, for: .normal)
        
        return button
    }()
    
    private var bottomBlurView: UIVisualEffectView?
    
    private lazy var editBtn: UIButton = {
        let btn = createBtn(localLanguageTextValue(.edit), #selector(editBtnClick))
        btn.titleLabel?.lineBreakMode = .byCharWrapping
        btn.titleLabel?.numberOfLines = 0
        btn.contentHorizontalAlignment = .left
        return btn
    }()
    
    private lazy var originalBtn: UIButton = {
        let btn = createBtn(localLanguageTextValue(.originalPhoto), #selector(originalPhotoClick))
        btn.titleLabel?.lineBreakMode = .byCharWrapping
        btn.titleLabel?.numberOfLines = 2
        btn.contentHorizontalAlignment = .left
        btn.setImage(.zl.getImage("zl_btn_original_circle"), for: .normal)
        btn.setImage(.zl.getImage("zl_btn_original_selected"), for: .selected)
        btn.setImage(.zl.getImage("zl_btn_original_selected"), for: [.selected, .highlighted])
        btn.adjustsImageWhenHighlighted = false
        btn.titleEdgeInsets = UIEdgeInsets(top: 0, left: 10, bottom: 0, right: 0)
        return btn
    }()
    
    private lazy var doneBtn: UIButton = {
        let btn = createBtn(localLanguageTextValue(.done), #selector(doneBtnClick), true)
        btn.backgroundColor = .zl.bottomToolViewBtnNormalBgColorOfPreviewVC
        btn.layer.masksToBounds = true
        btn.layer.cornerRadius = ZLLayout.bottomToolBtnCornerRadius
        return btn
    }()
    
    private var selPhotoPreview: PhotoPreviewSelectedView?
    
    private var isFirstAppear = true
    
    private var hideNavView = false
    
    private var popInteractiveTransition: PhotoPreviewPopInteractiveTransition?
    
    private var orientation: UIInterfaceOrientation = .unknown
    
    /// 是否在点击确定时候，当未选择任何照片时候，自动选择当前index的照片
    var autoSelectCurrentIfNotSelectAnyone = true
    
    /// 界面消失时，通知上个界面刷新（针对预览视图）
    var backBlock: (() -> Void)?
    
    override var prefersStatusBarHidden: Bool {
        return !ZLPhotoUIConfiguration.default().showStatusBarInPreviewInterface
    }
    
    override var preferredStatusBarStyle: UIStatusBarStyle {
        return ZLPhotoUIConfiguration.default().statusBarStyle
    }
    
    deinit {
        zl_debugPrint("ZLPhotoPreviewController deinit")
    }
    
    init(photos: [ZLPhotoModel], index: Int, showBottomViewAndSelectBtn: Bool = true) {
        arrDataSources = photos
        self.showBottomViewAndSelectBtn = showBottomViewAndSelectBtn
        currentIndex = index
        indexBeforOrientationChanged = index
        super.init(nibName: nil, bundle: nil)
    }
    
    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        // setup style
        ZLPhotoConfiguration.default()
            .showSelectedPhotoPreview(true)
            .maxSelectCount(1_000_000)
            .showSelectedIndex(false)
            .animateSelectBtnWhenSelect(false)
        
        ZLPhotoUIConfiguration.default()
            .navBarColorOfPreviewVC(collectionViewColor)
            .previewVCBgColor(collectionViewColor)
            .bottomToolViewBgColorOfPreviewVC(collectionViewColor)
            .showStatusBarInPreviewInterface(true)
            .statusBarStyle(.lightContent)
            .navViewBlurEffectOfPreview(nil)
            .bottomViewBlurEffectOfPreview(nil)
        
        setupUI()
        
        addPopInteractiveTransition()
        resetSubViewStatus()
      
        setupGestureDepend(on: collectionView)
    }
  
    fileprivate func setupGestureDepend(on scrollView: UIScrollView) {
        if let navPan = navigationController?.interactivePopGestureRecognizer {
            collectionView.panGestureRecognizer.require(toFail: navPan)
        }
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        
        navigationController?.setNavigationBarHidden(true, animated: animated)
    }
    
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        navigationController?.delegate = self
        
        guard isFirstAppear else { return }
        isFirstAppear = false
        
        reloadCurrentCell()
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        navigationController?.setNavigationBarHidden(false, animated: animated)
    }
    
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        
        var insets = UIEdgeInsets(top: 20, left: 0, bottom: 0, right: 0)
        if #available(iOS 11.0, *) {
            insets = self.view.safeAreaInsets
        }
        insets.top = max(20, insets.top)
        
        /*
        collectionView.frame = CGRect(
            x: -ZLPhotoPreviewController.colItemSpacing / 2,
            y: 0,
            width: view.frame.width + ZLPhotoPreviewController.colItemSpacing,
            height: view.frame.height
        )
        */
        
        let navH = insets.top + 44
        navView.frame = CGRect(x: 0, y: 0, width: view.frame.width, height: navH)
        navBlurView?.frame = navView.bounds
        
        collectionView.frame = CGRect(
            x: -ZLPhotoPreviewController.colItemSpacing / 2,
            y: navH,
            width: view.frame.width + ZLPhotoPreviewController.colItemSpacing,
            height: getItemHeight()
        )
      
        if isMenuContextPreview {
          collectionView.frame = view.bounds
        }
        
        backBtn.frame = CGRect(x: insets.left, y: insets.top, width: 60, height: 44)
        selectBtn.frame = CGRect(x: view.frame.width - 40 - insets.right, y: insets.top + (44 - 25) / 2, width: 25, height: 25)
        indexLabel.frame = selectBtn.bounds
        
        refreshBottomViewFrame()
        
        let ori = UIApplication.shared.statusBarOrientation
        if ori != orientation {
            orientation = ori
            
            collectionView.performBatchUpdates(nil) { _ in
                self.collectionView.setContentOffset(
                    CGPoint(x: (self.view.frame.width + ZLPhotoPreviewController.colItemSpacing) * CGFloat(self.indexBeforOrientationChanged), y: 0),
                    animated: false
                )
            }
        }
    }
    
    private func reloadCurrentCell() {
        guard let cell = collectionView.cellForItem(at: IndexPath(row: currentIndex, section: 0)) else {
            return
        }
        if let cell = cell as? ZLGifPreviewCell {
            cell.loadGifWhenCellDisplaying()
        } else if let cell = cell as? ZLLivePhotoPreviewCell {
            cell.loadLivePhotoData()
        }
    }
    
    private func refreshBottomViewFrame() {
        var insets = UIEdgeInsets(top: 20, left: 0, bottom: 0, right: 0)
        if #available(iOS 11.0, *) {
            insets = view.safeAreaInsets
        }
        var bottomViewH = ZLLayout.bottomToolViewH
        var showSelPhotoPreview = false
        if ZLPhotoConfiguration.default().showSelectedPhotoPreview
//            , let nav = navigationController as? ZLImageNavControllerProtocol
        {
//            if !nav.arrSelectedModels.isEmpty {
                showSelPhotoPreview = true
                bottomViewH += ZLPhotoPreviewController.selPhotoPreviewH
                selPhotoPreview?.frame = CGRect(x: 0, y: 0, width: view.frame.width, height: Self.selPhotoPreviewH)
//            }
        }
        let btnH = ZLLayout.bottomToolBtnH
        
        // ignore ZLLayout.bottomToolViewH
        bottomViewH = Self.selPhotoPreviewH
        bottomView.layer.masksToBounds = true
        doneBtn.isHidden = true
        
        bottomView.frame = CGRect(x: 0, y: view.frame.height - insets.bottom - bottomViewH, width: view.frame.width, height: bottomViewH + insets.bottom)
        bottomBlurView?.frame = bottomView.bounds
        
        let btnY: CGFloat = showSelPhotoPreview ? ZLPhotoPreviewController.selPhotoPreviewH + ZLLayout.bottomToolBtnY : ZLLayout.bottomToolBtnY
        
        let btnMaxWidth = (bottomView.bounds.width - 30) / 3
        
        let editTitle = localLanguageTextValue(.edit)
        let editBtnW = editTitle.zl.boundingRect(font: ZLLayout.bottomToolTitleFont, limitSize: CGSize(width: CGFloat.greatestFiniteMagnitude, height: 30)).width
        editBtn.frame = CGRect(x: 15, y: btnY, width: min(btnMaxWidth, editBtnW), height: btnH)
        
        let originTitle = localLanguageTextValue(.originalPhoto)
        let originBtnW = originTitle.zl.boundingRect(font: ZLLayout.bottomToolTitleFont, limitSize: CGSize(width: CGFloat.greatestFiniteMagnitude, height: 30)).width + 30
        let originBtnMaxW = min(btnMaxWidth, originBtnW)
        originalBtn.frame = CGRect(x: (bottomView.bounds.width - originBtnMaxW) / 2 - 5, y: btnY, width: originBtnMaxW, height: btnH)
        
        let selCount = (navigationController as? ZLImageNavControllerProtocol)?.arrSelectedModels.count ?? 0
        var doneTitle = localLanguageTextValue(.done)
        if ZLPhotoConfiguration.default().showSelectCountOnDoneBtn, selCount > 0 {
            doneTitle += "(" + String(selCount) + ")"
        }
        let doneBtnW = doneTitle.zl.boundingRect(font: ZLLayout.bottomToolTitleFont, limitSize: CGSize(width: CGFloat.greatestFiniteMagnitude, height: 30)).width + 20
        doneBtn.frame = CGRect(x: bottomView.bounds.width - doneBtnW - 15, y: btnY, width: doneBtnW, height: btnH)
    }
    
    private func setupUI() {
        view.backgroundColor = .zl.previewVCBgColor
        automaticallyAdjustsScrollViewInsets = false
        
        let config = ZLPhotoConfiguration.default()
        
        
        // - navView
        view.addSubview(navView)
        
        if let effect = ZLPhotoUIConfiguration.default().navViewBlurEffectOfPreview {
            navBlurView = UIVisualEffectView(effect: effect)
            navView.addSubview(navBlurView!)
        }
        
        navView.addSubview(backBtn)
        navView.addSubview(selectBtn)
        
        navView.addSubview(titleIndexLabel)
        titleIndexLabel.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
          titleIndexLabel.centerXAnchor.constraint(equalTo: navView.centerXAnchor),
          titleIndexLabel.centerYAnchor.constraint(equalTo: backBtn.centerYAnchor),
        ])
        addDebugGestureForTitleIndexLabel()
      
        selectBtn.addSubview(indexLabel)
        
        // - collectionView
        view.addSubview(collectionView)
        
        // - bottomView
        view.addSubview(bottomView)
        
        if let effect = ZLPhotoUIConfiguration.default().bottomViewBlurEffectOfPreview {
            bottomBlurView = UIVisualEffectView(effect: effect)
            bottomView.addSubview(bottomBlurView!)
        }
        
        if config.showSelectedPhotoPreview {
            /*
            let selModels = (navigationController as? ZLImageNavControllerProtocol)?.arrSelectedModels ?? []
            selPhotoPreview = PhotoPreviewSelectedView(selModels: selModels, currentShowModel: arrDataSources[currentIndex])
            */
            
            selPhotoPreview = PhotoPreviewSelectedView(selModels: self.arrDataSources, currentShowModel: arrDataSources[currentIndex])
            
            selPhotoPreview?.selectBlock = { [weak self] model in
                self?.handleSelectEvent(model: model)
                
                let action = "click_photo_preview_detail_select"
                PhotoPreview.trackEvent(event: "Clean", action: action)
            }
            
            selPhotoPreview?.endDraggingBlock = {
                let action = "click_photo_preview_detail_silde"
                PhotoPreview.trackEvent(event: "Clean", action: action)
            }
            
            selPhotoPreview?.scrollPositionBlock = { [weak self] model in
                self?.onSelPhotoPreviewScrollPositionBlock(model)
            }
            
            selPhotoPreview?.ignoresDidScrollCallbackForOther = { [weak self] ignoresDidScrollCallbackForOther in
                self?.ignoresDidScroll = ignoresDidScrollCallbackForOther
            }
            
            selPhotoPreview?.endSortBlock = { [weak self] models in
                self?.refreshCurrentCellIndex(models)
            }
            bottomView.addSubview(selPhotoPreview!)
        }
        
        editBtn.isHidden = (!config.allowEditImage && !config.allowEditVideo)
        bottomView.addSubview(editBtn)
        
        originalBtn.isHidden = !(config.allowSelectOriginal && config.allowSelectImage)
        originalBtn.isSelected = (navigationController as? ZLImageNavControllerProtocol)?.isSelectedOriginal ?? false
        bottomView.addSubview(originalBtn)
        
        bottomView.addSubview(doneBtn)
        
        // - overlay
        if let reason = removingReason, reason == "keep" {
            view.addSubview(keepButton)
            keepButton.translatesAutoresizingMaskIntoConstraints = false
            NSLayoutConstraint.activate([
                keepButton.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 24),
                keepButton.bottomAnchor.constraint(equalTo: bottomView.topAnchor, constant: -20),
                keepButton.heightAnchor.constraint(equalToConstant: 2 * 15),
            ])
        }
        
        view.bringSubviewToFront(navView)
    }
    
    private func createBtn(_ title: String, _ action: Selector, _ isDone: Bool = false) -> UIButton {
        let btn = UIButton(type: .custom)
        btn.titleLabel?.font = ZLLayout.bottomToolTitleFont
        btn.setTitle(title, for: .normal)
        btn.setTitleColor(
            isDone ? .zl.bottomToolViewDoneBtnNormalTitleColorOfPreviewVC : .zl.bottomToolViewBtnNormalTitleColorOfPreviewVC,
            for: .normal
        )
        btn.setTitleColor(
            isDone ? .zl.bottomToolViewDoneBtnDisableTitleColorOfPreviewVC : .zl.bottomToolViewBtnDisableTitleColorOfPreviewVC,
            for: .disabled
        )
        btn.addTarget(self, action: action, for: .touchUpInside)
        return btn
    }
    
    private func addPopInteractiveTransition() {
        guard (navigationController?.viewControllers.count ?? 0) > 1 else {
            // 仅有当前vc一个时候，说明不是从相册进入，不添加交互动画
            return
        }
        
        popInteractiveTransition = PhotoPreviewPopInteractiveTransition(viewController: self)
        popInteractiveTransition?.currentIndex = currentIndex
        popInteractiveTransition?.fromFrameProvider = fromFrameProvider
        popInteractiveTransition?.shouldStartTransition = { [weak self] point -> Bool in
            guard let `self` = self else { return false }
            if !self.hideNavView, self.navView.frame.contains(point) || self.bottomView.frame.contains(point) {
                return false
            }
            
            guard self.collectionView.cellForItem(at: IndexPath(row: self.currentIndex, section: 0)) != nil else {
                return false
            }
            
            return true
        }
        popInteractiveTransition?.startTransition = { [weak self] in
            guard let `self` = self else { return }
            
            self.navView.alpha = 0
            self.bottomView.alpha = 0
            
            guard let cell = self.collectionView.cellForItem(at: IndexPath(row: self.currentIndex, section: 0)) else {
                return
            }
            if cell is ZLVideoPreviewCell {
                (cell as! ZLVideoPreviewCell).pauseWhileTransition()
            } else if cell is ZLLivePhotoPreviewCell {
                (cell as! ZLLivePhotoPreviewCell).livePhotoView.stopPlayback()
            } else if cell is ZLGifPreviewCell {
                (cell as! ZLGifPreviewCell).pauseGif()
            }
        }
        popInteractiveTransition?.cancelTransition = { [weak self] in
            guard let `self` = self else { return }
            
            self.hideNavView = false
            self.navView.isHidden = false
            self.bottomView.isHidden = false
            UIView.animate(withDuration: 0.5) {
                self.navView.alpha = 1
                self.bottomView.alpha = 1
            }
            
            guard let cell = self.collectionView.cellForItem(at: IndexPath(row: self.currentIndex, section: 0)) else {
                return
            }
            if cell is ZLGifPreviewCell {
                (cell as! ZLGifPreviewCell).resumeGif()
            }
        }
    }
    
    /// reset subview status including:
    /// navView, selectBtn, indexLabel, titleIndexLabel
    /// buttomView, editBtn, originalBtn, doneBtn
    private func resetSubViewStatus() {
        if arrDataSources.isEmpty {
            return
        }
        
        guard let nav = navigationController as? ZLImageNavControllerProtocol else {
            zlLoggerInDebug("Navigation controller is null")
            return
        }
        let config = ZLPhotoConfiguration.default()
        let currentModel = arrDataSources[currentIndex]
        
        if (!config.allowMixSelect && currentModel.type == .video) || (!config.showSelectBtnWhenSingleSelect && config.maxSelectCount == 1) {
            selectBtn.isHidden = true
        } else {
            selectBtn.isHidden = false
        }
        selectBtn.isSelected = arrDataSources[currentIndex].isSelected
        resetIndexLabelStatus()
        titleIndexLabel.text = "\(currentIndex + 1)/\(arrDataSources.count)"
        
        guard showBottomViewAndSelectBtn else {
            selectBtn.isHidden = true
            bottomView.isHidden = true
            return
        }
        let selCount = nav.arrSelectedModels.count
        var doneTitle = localLanguageTextValue(.done)
        if ZLPhotoConfiguration.default().showSelectCountOnDoneBtn, selCount > 0 {
            doneTitle += "(" + String(selCount) + ")"
        }
        doneBtn.setTitle(doneTitle, for: .normal)
        
        /*
        selPhotoPreview?.isHidden = selCount == 0
        */
        refreshBottomViewFrame()
        
        var hideEditBtn = true
        if selCount < config.maxSelectCount || nav.arrSelectedModels.contains(where: { $0 == currentModel }) {
            if config.allowEditImage,
               currentModel.type == .image || (currentModel.type == .gif && !config.allowSelectGif) || (currentModel.type == .livePhoto && !config.allowSelectLivePhoto) {
                hideEditBtn = false
            }
            if config.allowEditVideo,
               currentModel.type == .video,
               selCount == 0 || (selCount == 1 && nav.arrSelectedModels.first == currentModel) {
                hideEditBtn = false
            }
        }
        editBtn.isHidden = hideEditBtn
        
        if ZLPhotoConfiguration.default().allowSelectOriginal,
           ZLPhotoConfiguration.default().allowSelectImage {
            originalBtn.isHidden = !((currentModel.type == .image) || (currentModel.type == .livePhoto && !config.allowSelectLivePhoto) || (currentModel.type == .gif && !config.allowSelectGif))
        }
      
      if isMenuContextPreview {
        navView.isHidden = true
        bottomView.isHidden = true
      }
    }
    
    private func resetIndexLabelStatus() {
        guard ZLPhotoConfiguration.default().showSelectedIndex else {
            indexLabel.isHidden = true
            return
        }
        guard let nav = navigationController as? ZLImageNavControllerProtocol else {
            zlLoggerInDebug("Navigation controller is null")
            return
        }
        if let index = nav.arrSelectedModels.firstIndex(where: { $0 == self.arrDataSources[self.currentIndex] }) {
            indexLabel.isHidden = false
            indexLabel.text = String(index + 1)
        } else {
            indexLabel.isHidden = true
        }
    }
    
    // MARK: btn actions
    
    @objc private func backBtnClick() {
        handleBackEvent()
    }
    
    private func handleBackEvent() {
        backBlock?()
        let vc = navigationController?.popViewController(animated: true)
        if vc == nil {
            navigationController?.dismiss(animated: true, completion: nil)
        }
    }
    
    @objc private func onKeepButtonEvent() {
        handleRemovingCurrentIndex(reason: "keep")
    }
    
    private func handleRemovingCurrentIndex(reason: String) {
        let currentModel = arrDataSources[currentIndex]
        
        arrDataSources.remove(at: currentIndex)
        collectionView.deleteItems(at: [IndexPath(item: currentIndex, section: 0)])
        
        removingItemCallback?(reason, currentModel)
        
        if arrDataSources.isEmpty {
            if let removingAllCallback = removingAllCallback {
                removingAllCallback()
            } else {
                handleBackEvent()
            }
            return
        }
        
        let nav = navigationController as? ZLImageNavControllerProtocol
        nav?.arrSelectedModels.removeAll { $0 == currentModel }
        
        let newIndex = collectionView.indexPathsForVisibleItems.first?.item ?? 0
        updateCurrentIndex(newIndex)
        
        let newModel = arrDataSources[newIndex]
        selPhotoPreview?.removeModel(
            model: currentModel,
            newModel: newModel
        )
    }
    
    @objc private func selectBtnClick() {
        let currentModel = arrDataSources[currentIndex]
        handleSelectEvent(model: currentModel)
    }
    
    private func handleSelectEvent(model: ZLPhotoModel) {
        guard let nav = navigationController as? ZLImageNavControllerProtocol else {
            zlLoggerInDebug("Navigation controller is null")
            return
        }
        
        let currentModel = model
        if currentModel.isSelected {
            currentModel.isSelected = false
            nav.arrSelectedModels.removeAll { $0 == currentModel }
            selPhotoPreview?.deselectModel(model: currentModel)
        } else {
            if !canAddModel(currentModel, currentSelectCount: nav.arrSelectedModels.count, sender: self) {
                return
            }
            currentModel.isSelected = true
            nav.arrSelectedModels.append(currentModel)
            selPhotoPreview?.addSelModel(model: currentModel)
        }
        selectionEventCallback(currentModel)
        resetSubViewStatus()
    }
    
    private func updateCurrentIndex(_ index: Int) {
        currentIndex = index
        
        resetSubViewStatus()
        updateCurrentAssetDebugInfoLabel()
    }
    
    @objc private func editBtnClick() {
        let config = ZLPhotoConfiguration.default()
        let model = arrDataSources[currentIndex]
        
        var requestAvAssetID: PHImageRequestID?
        let hud = ZLProgressHUD(style: ZLPhotoUIConfiguration.default().hudStyle)
        hud.timeoutBlock = { [weak self] in
            showAlertView(localLanguageTextValue(.timeout), self)
            if let requestAvAssetID = requestAvAssetID {
                PHImageManager.default().cancelImageRequest(requestAvAssetID)
            }
        }
        
        if model.type == .image || (!config.allowSelectGif && model.type == .gif) || (!config.allowSelectLivePhoto && model.type == .livePhoto) {
            hud.show(timeout: ZLPhotoConfiguration.default().timeout)
            requestAvAssetID = ZLPhotoManager.fetchImage(for: model.asset, size: model.previewSize) { [weak self] image, isDegraded in
                if !isDegraded {
                    if let image = image {
                        self?.showEditImageVC(image: image)
                    } else {
                        showAlertView(localLanguageTextValue(.imageLoadFailed), self)
                    }
                    hud.hide()
                }
            }
        } else if model.type == .video || config.allowEditVideo {
            hud.show(timeout: ZLPhotoConfiguration.default().timeout)
            // fetch avasset
            requestAvAssetID = ZLPhotoManager.fetchAVAsset(forVideo: model.asset) { [weak self] avAsset, _ in
                hud.hide()
                if let avAsset = avAsset {
                    self?.showEditVideoVC(model: model, avAsset: avAsset)
                } else {
                    showAlertView(localLanguageTextValue(.timeout), self)
                }
            }
        }
    }
    
    @objc private func originalPhotoClick() {
        originalBtn.isSelected.toggle()
        
        let config = ZLPhotoConfiguration.default()
        
        let nav = (navigationController as? ZLImageNavControllerProtocol)
        nav?.isSelectedOriginal = originalBtn.isSelected
        if nav?.arrSelectedModels.count == 0 {
            selectBtnClick()
        } else if config.maxSelectCount == 1,
                  !config.showSelectBtnWhenSingleSelect,
                  !originalBtn.isSelected,
                  nav?.arrSelectedModels.count == 1,
                  let currentModel = nav?.arrSelectedModels.first
        {
            currentModel.isSelected = false
            currentModel.editImage = nil
            currentModel.editImageModel = nil
            nav?.arrSelectedModels.removeAll { $0 == currentModel }
            selPhotoPreview?.deselectModel(model: currentModel)
            resetSubViewStatus()
            let index = config.sortAscending ? arrDataSources.lastIndex { $0 == currentModel } : arrDataSources.firstIndex { $0 == currentModel }
            if let index = index {
                collectionView.reloadItems(at: [IndexPath(row: index, section: 0)])
            }
        }
    }
    
    @objc private func doneBtnClick() {
        guard let nav = navigationController as? ZLImageNavControllerProtocol else {
            zlLoggerInDebug("Navigation controller is null")
            return
        }
        
        func callBackBeforeDone() {
            if let block = ZLPhotoConfiguration.default().operateBeforeDoneAction {
                block(self) { [weak nav] in
                    nav?.selectImageBlock?()
                }
            } else {
                nav.selectImageBlock?()
            }
        }
        
        let currentModel = arrDataSources[currentIndex]
        if autoSelectCurrentIfNotSelectAnyone {
            if nav.arrSelectedModels.isEmpty, canAddModel(currentModel, currentSelectCount: nav.arrSelectedModels.count, sender: self) {
                nav.arrSelectedModels.append(currentModel)
            }
            
            if !nav.arrSelectedModels.isEmpty {
                callBackBeforeDone()
            }
        } else {
            callBackBeforeDone()
        }
    }
    
    private func onSelPhotoPreviewScrollPositionBlock(_ model: ZLPhotoModel) {
        guard let index = arrDataSources.lastIndex(of: model) else {
            return
        }
        
        if index == currentIndex { return }
        
        updateCurrentIndex(index)
        collectionView.scrollToItem(at: IndexPath(row: index, section: 0), at: .centeredHorizontally, animated: false)
        indexBeforOrientationChanged = self.currentIndex
        reloadCurrentCell()
        
        /*
        collectionView.performBatchUpdates({
            self.collectionView.scrollToItem(at: IndexPath(row: index, section: 0), at: .centeredHorizontally, animated: true)
        }) { _ in
            self.indexBeforOrientationChanged = self.currentIndex
            self.reloadCurrentCell()
        }
        */
    }
    
    private func refreshCurrentCellIndex(_ models: [ZLPhotoModel]) {
        let nav = navigationController as? ZLImageNavControllerProtocol
        nav?.arrSelectedModels.removeAll()
        nav?.arrSelectedModels.append(contentsOf: models)
        guard ZLPhotoConfiguration.default().showSelectedIndex else {
            return
        }
        resetIndexLabelStatus()
    }
    
    private func tapPreviewCell() {
        hideNavView.toggle()
        
        let currentCell = collectionView.cellForItem(at: IndexPath(row: currentIndex, section: 0))
        if let cell = currentCell as? ZLVideoPreviewCell {
            if cell.isPlaying {
                hideNavView = true
            }
        }
        
        // always show navViews
        /*
        navView.isHidden = hideNavView
        bottomView.isHidden = showBottomViewAndSelectBtn ? hideNavView : true
        */
    }
    
    private func showEditImageVC(image: UIImage) {
        let model = arrDataSources[currentIndex]
        let nav = navigationController as? ZLImageNavControllerProtocol
        ZLEditImageViewController.showEditImageVC(parentVC: self, image: image, editModel: model.editImageModel) { [weak self, weak nav] ei, editImageModel in
            guard let `self` = self else { return }
            model.editImage = ei
            model.editImageModel = editImageModel
            if nav?.arrSelectedModels.contains(where: { $0 == model }) == false {
                model.isSelected = true
                nav?.arrSelectedModels.append(model)
                self.resetSubViewStatus()
                self.selPhotoPreview?.addSelModel(model: model)
            } else {
                self.selPhotoPreview?.refreshCell(for: model)
            }
            self.collectionView.reloadItems(at: [IndexPath(row: self.currentIndex, section: 0)])
        }
    }
    
    private func showEditVideoVC(model: ZLPhotoModel, avAsset: AVAsset) {
        let nav = navigationController as? ZLImageNavControllerProtocol
        let vc = ZLEditVideoViewController(avAsset: avAsset)
        vc.modalPresentationStyle = .fullScreen
        
        vc.editFinishBlock = { [weak self, weak nav] url in
            if let u = url {
                ZLPhotoManager.saveVideoToAlbum(url: u) { [weak self, weak nav] suc, asset in
                    if suc, asset != nil {
                        let m = ZLPhotoModel(asset: asset!)
                        nav?.arrSelectedModels.removeAll()
                        nav?.arrSelectedModels.append(m)
                        nav?.selectImageBlock?()
                    } else {
                        showAlertView(localLanguageTextValue(.saveVideoError), self)
                    }
                }
            } else {
                nav?.arrSelectedModels.removeAll()
                nav?.arrSelectedModels.append(model)
                nav?.selectImageBlock?()
            }
        }
        
        present(vc, animated: false, completion: nil)
    }
    
}

extension PhotoPreviewController {
    func addDebugGestureForTitleIndexLabel() {
        let tap = UITapGestureRecognizer(target: self, action: #selector(onTitleIndexLaelEvent))
#if DEBUG
        tap.numberOfTapsRequired = 2
#else
        tap.numberOfTapsRequired = 9
#endif
        titleIndexLabel.addGestureRecognizer(tap)
        titleIndexLabel.isUserInteractionEnabled = true
    }
    
    @objc func onTitleIndexLaelEvent() {
        if debugInfoLabel == nil {
            let scrollView = UIScrollView()
            scrollView.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview(scrollView)
            NSLayoutConstraint.activate([
                scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 12),
                scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -12),
                scrollView.topAnchor.constraint(equalTo: navView.bottomAnchor, constant: 12),
                scrollView.heightAnchor.constraint(equalToConstant: 111)
            ])
            
            let container = UIView()
            container.translatesAutoresizingMaskIntoConstraints = false
            scrollView.addSubview(container)
            
            
            let label = UILabel()
            if #available(iOS 13.0, *) {
                label.backgroundColor = .systemBackground
                label.textColor = .label
            } else {
                // Fallback on earlier versions
            }
            
            label.font = .systemFont(ofSize: 13)
            label.numberOfLines = 0
            label.tag = PhotoPreviewController.debugInfoLabelTag
            label.translatesAutoresizingMaskIntoConstraints = false
            container.addSubview(label)
            
            if #available(iOS 11.0, *) {
                NSLayoutConstraint.activate([
                    container.leadingAnchor.constraint(equalTo: scrollView.leadingAnchor, constant: 0),
                    container.widthAnchor.constraint(equalToConstant: view.bounds.width - 2 * 12),
                    container.topAnchor.constraint(equalTo: scrollView.topAnchor, constant: 0),
                    {
                       let ret = container.bottomAnchor.constraint(equalTo: scrollView.bottomAnchor, constant: 0)
                        ret.priority = .defaultHigh
                        return ret
                    }(),
                    
                    label.leadingAnchor.constraint(equalTo: container.leadingAnchor),
                    label.widthAnchor.constraint(equalToConstant: view.bounds.width - 2 * 12),
                    label.topAnchor.constraint(equalTo: container.topAnchor),
                    label.bottomAnchor.constraint(equalTo: container.bottomAnchor),
                ])
            } else {
                // Fallback on earlier versions
            }
        }
        updateCurrentAssetDebugInfoLabel()
    }
    
    private static let debugInfoLabelTag = 729345267
    var debugInfoLabel: UILabel? {
        return view.viewWithTag(PhotoPreviewController.debugInfoLabelTag) as? UILabel
    }
    
    func formatDate(_ date: Date?) -> String? {
        guard let date = date else { return nil }
        let formatter = DateFormatter()
        formatter.timeZone = .current
        formatter.dateFormat = "YYYY-MM-dd HH:mm:ss"

        return formatter.string(from: date)
    }

    func toString(_ dict: [AnyHashable: Any]) -> String {
        guard let data = try? JSONSerialization.data(withJSONObject: dict) else {
            return ""
        }
        
        let string = String(data: data, encoding: .utf8)
        return string ?? ""
    }
    
    func updateCurrentAssetDebugInfoLabel() {
        guard let debugInfoLabel = debugInfoLabel else { return }
        
        (debugInfoLabel.superview as? UIScrollView)?.contentOffset = .zero
        
        let manager = PHImageManager.default()
        let requestOptions = PHImageRequestOptions()
        requestOptions.isSynchronous = false
        requestOptions.deliveryMode = .fastFormat
        requestOptions.isNetworkAccessAllowed = true
        
        let model = arrDataSources[currentIndex]
        let asset = model.asset
        
        var totalProperties: [String: Any] = [:]
        var desc = ""
        desc += "id: \(asset.localIdentifier)\n"
        
        let createString = formatDate(asset.creationDate) ?? ""
        desc += "create: \(createString)\n"
        desc += "pixel: \(asset.pixelWidth)x\(asset.pixelHeight)\n"
        desc += "isFav: \(asset.isFavorite)    "
        
        if #available(iOS 13, *) {
            manager.requestImageDataAndOrientation(for: asset, options: requestOptions) { (data, fileName, orientation, info) in
                DispatchQueue.global().async {
                    let size = PhotoPreviewController.fileSize(asset: asset)
                    let formatter:ByteCountFormatter = ByteCountFormatter()
                    formatter.countStyle = .decimal
                    formatter.allowedUnits = [.useMB, .useKB]
                    let string = formatter.string(fromByteCount: size)
                    desc += "fileSize: \(string)    "
                    
                    if let data = data,
                       let cImage = CIImage(data: data) {
                        totalProperties = cImage.properties
                        let string = self.toString(totalProperties)
                        print(string)
                        let hasLensModel = (totalProperties["{Exif}"] as? [String: Any])?["LensModel"] != nil
                        desc += "isCam: \(hasLensModel)\n"
                        desc += "other:\n"
                    }
                    
                    // prefix 400 to ensure render fast in the debugInfoLabel.text
                    let text = String(desc + totalProperties.description.prefix(333) + " ...")
                    
                    DispatchQueue.main.async {
                        debugInfoLabel.text = text
                    }
                }
            }
        } else {
            // Fallback on earlier versions
        }
    }
    
    static func fileSize(asset: PHAsset) -> Int64 {
      let resources = PHAssetResource.assetResources(for: asset)
      let total = resources.reduce(0) { (partialResult, resource) -> Int64 in
        let fileSize = resource.value(forKey: "fileSize") as? Int64
        return partialResult + (fileSize ?? 0)
      }
      
      return total
    }
}

extension PhotoPreviewController: UINavigationControllerDelegate {
    
    func navigationController(_: UINavigationController, animationControllerFor operation: UINavigationController.Operation, from _: UIViewController, to _: UIViewController) -> UIViewControllerAnimatedTransitioning? {
        if operation == .push {
            return nil
        }
        return popInteractiveTransition?.interactive == true ? ZLPhotoPreviewAnimatedTransition() : nil
    }
    
    func navigationController(_: UINavigationController, interactionControllerFor _: UIViewControllerAnimatedTransitioning) -> UIViewControllerInteractiveTransitioning? {
        return popInteractiveTransition?.interactive == true ? popInteractiveTransition : nil
    }
    
}

// MARK: scroll view delegate

extension PhotoPreviewController {
    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        if ignoresDidScroll {
            return
        }
        
        NotificationCenter.default.post(name: ZLPhotoPreviewController.previewVCScrollNotification, object: nil)
        
        let offset = scrollView.contentOffset
        var page = Int(round(offset.x / (view.bounds.width + ZLPhotoPreviewController.colItemSpacing)))
        page = clamp(0, page, arrDataSources.count - 1)
        if page == currentIndex {
            return
        }
        
        updateCurrentIndex(page)
        selPhotoPreview?.currentShowModelChanged(model: arrDataSources[currentIndex])
    }
    
    func scrollViewWillBeginDragging(_ scrollView: UIScrollView) {
        selPhotoPreview?.ignoresDidScroll = true
    }
    
    func scrollViewDidEndDecelerating(_: UIScrollView) {
        selPhotoPreview?.ignoresDidScroll = false
        
        indexBeforOrientationChanged = currentIndex
        let cell = collectionView.cellForItem(at: IndexPath(row: currentIndex, section: 0))
        if let cell = cell as? ZLGifPreviewCell {
            cell.loadGifWhenCellDisplaying()
        } else if let cell = cell as? ZLLivePhotoPreviewCell {
            cell.loadLivePhotoData()
        }
    }
    
}

extension PhotoPreviewController: UICollectionViewDataSource, UICollectionViewDelegateFlowLayout {
    
    func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, minimumInteritemSpacingForSectionAt section: Int) -> CGFloat {
        return ZLPhotoPreviewController.colItemSpacing
    }
    
    func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, minimumLineSpacingForSectionAt section: Int) -> CGFloat {
        return ZLPhotoPreviewController.colItemSpacing
    }
    
    func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, insetForSectionAt section: Int) -> UIEdgeInsets {
      var inset = ZLPhotoPreviewController.colItemSpacing / 2
      if isMenuContextPreview {
        inset = 0
      }
        return UIEdgeInsets(top: 0, left: inset, bottom: 0, right: inset)
    }
    
    func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, sizeForItemAt indexPath: IndexPath) -> CGSize {
        return CGSize(width: view.bounds.width, height: getItemHeight())
    }
    
    func getItemHeight() -> CGFloat {
        if isMenuContextPreview {
          return view.bounds.height
        }
      
        var insets = UIEdgeInsets(top: 20, left: 0, bottom: 0, right: 0)
        if #available(iOS 11.0, *) {
            insets = self.view.safeAreaInsets
        }
        
        let navH = insets.top + 44
        return view.frame.height - navH - insets.bottom - Self.selPhotoPreviewH
    }
    
    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        return arrDataSources.count
    }
    
    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        let config = ZLPhotoConfiguration.default()
        let model = arrDataSources[indexPath.row]
        
        let baseCell: ZLPreviewBaseCell
        
        if config.allowSelectGif, model.type == .gif {
            let cell = collectionView.dequeueReusableCell(withReuseIdentifier: ZLGifPreviewCell.zl.identifier, for: indexPath) as! ZLGifPreviewCell
            
            cell.singleTapBlock = { [weak self] in
                self?.tapPreviewCell()
            }
            
            cell.model = model
            
            baseCell = cell
        } else if config.allowSelectLivePhoto, model.type == .livePhoto {
            let cell = collectionView.dequeueReusableCell(withReuseIdentifier: ZLLivePhotoPreviewCell.zl.identifier, for: indexPath) as! ZLLivePhotoPreviewCell
            
            cell.model = model
            
            baseCell = cell
        } else if config.allowSelectVideo, model.type == .video {
            let cell = collectionView.dequeueReusableCell(withReuseIdentifier: ZLVideoPreviewCell.zl.identifier, for: indexPath) as! ZLVideoPreviewCell
            
            cell.model = model
            
            baseCell = cell
        } else {
            let cell = collectionView.dequeueReusableCell(withReuseIdentifier: ZLPhotoPreviewCell.zl.identifier, for: indexPath) as! ZLPhotoPreviewCell

            cell.singleTapBlock = { [weak self] in
                self?.tapPreviewCell()
            }

            cell.model = model

            baseCell = cell
        }
        
        baseCell.singleTapBlock = { [weak self] in
            self?.tapPreviewCell()
        }
        
        return baseCell
    }
    
    var collectionViewColor: UIColor {
        let color = UIColor(red: 0.09, green: 0.09, blue: 0.09, alpha: 1)
        return color
    }
    
    func collectionView(_ collectionView: UICollectionView, didEndDisplaying cell: UICollectionViewCell, forItemAt indexPath: IndexPath) {
        (cell as? ZLPreviewBaseCell)?.resetSubViewStatusWhenCellEndDisplay()
    }
}


extension Int {
    var px: CGFloat {
        return CGFloat(self) * UIScreen.main.bounds.width / 375
    }
}

// MARK: 下方显示的已选择照片列表

class PhotoPreviewSelectedView: UIView, UICollectionViewDataSource, UICollectionViewDelegate, UICollectionViewDragDelegate, UICollectionViewDropDelegate {
    static let itemLength: CGFloat = 40
    static var insetLength: CGFloat = UIScreen.main.bounds.width * 0.5 - itemLength * 0.5
    static let minimumSpacing: CGFloat = 12
    typealias ZLPhotoPreviewSelectedViewCell = PhotoPreviewSelectedViewCell
    private lazy var collectionView: UICollectionView = {
        let layout = UICollectionViewFlowLayout()
        layout.itemSize = CGSize(width: Self.itemLength, height: Self.itemLength)
        layout.minimumLineSpacing = Self.minimumSpacing
        layout.minimumInteritemSpacing = Self.minimumSpacing
        layout.scrollDirection = .horizontal
        layout.sectionInset = UIEdgeInsets(top: 10, left: Self.insetLength, bottom: 10, right: Self.insetLength)
        
        let view = UICollectionView(frame: .zero, collectionViewLayout: layout)
        view.backgroundColor = .clear
        view.dataSource = self
        view.delegate = self
        view.showsHorizontalScrollIndicator = false
        view.alwaysBounceHorizontal = true
        ZLPhotoPreviewSelectedViewCell.zl.register(view)
        
        // no need for reordering, thus disable drag interaction
        /*
        if #available(iOS 11.0, *) {
            view.dragDelegate = self
            view.dropDelegate = self
            view.dragInteractionEnabled = true
            view.isSpringLoaded = true
        } else {
            let longPressGesture = UILongPressGestureRecognizer(target: self, action: #selector(longPressAction))
            view.addGestureRecognizer(longPressGesture)
        }
        */
        
        return view
    }()
    
    /// data source array
    private var arrSelectedModels: [ZLPhotoModel]
    
    private var currentShowModel: ZLPhotoModel
    
    private var isDraging = false
    
    var ignoresDidScroll = false
    
    /// callback on didSelect item
    var selectBlock: ((ZLPhotoModel) -> Void)?
    
    /// scroll position changed callback
    var scrollPositionBlock: (ZLPhotoModel) -> Void = { _ in }
    
    /// ignores other scroll callback when this view is dragging
    var ignoresDidScrollCallbackForOther: (Bool) -> Void = { _ in }
    
    /// callback when end dragging
    var endDraggingBlock: () -> Void = { }
    
    var endSortBlock: (([ZLPhotoModel]) -> Void)?
    
    init(selModels: [ZLPhotoModel], currentShowModel: ZLPhotoModel) {
        arrSelectedModels = selModels
        self.currentShowModel = currentShowModel
        super.init(frame: .zero)
        
        setupUI()
    }
    
    private func setupUI() {
        addSubview(collectionView)
    }
    
    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func layoutSubviews() {
        super.layoutSubviews()
        
        collectionView.frame = CGRect(x: 0, y: 10, width: bounds.width, height: 80)
        if let index = arrSelectedModels.firstIndex(where: { $0 == self.currentShowModel }) {
            collectionView.scrollToItem(at: IndexPath(row: index, section: 0), at: .centeredHorizontally, animated: false)
        }
    }
    
    func currentShowModelChanged(model: ZLPhotoModel) {
        guard currentShowModel != model else {
            return
        }
        currentShowModel = model
        
        if let index = arrSelectedModels.firstIndex(where: { $0 == self.currentShowModel }) {
            collectionView.performBatchUpdates({
                self.collectionView.scrollToItem(at: IndexPath(row: index, section: 0), at: .centeredHorizontally, animated: true)
            }) { _ in
                self.collectionView.reloadItems(at: self.collectionView.indexPathsForVisibleItems)
            }
        } else {
            collectionView.reloadItems(at: collectionView.indexPathsForVisibleItems)
        }
    }
    
    func addSelModel(model: ZLPhotoModel) {
        refreshCell(for: model)
        /*
        arrSelectedModels.append(model)
        let indexPath = IndexPath(row: arrSelectedModels.count - 1, section: 0)
        collectionView.insertItems(at: [indexPath])
        collectionView.scrollToItem(at: indexPath, at: .centeredHorizontally, animated: true)
        */
    }
    
    func deselectModel(model: ZLPhotoModel) {
        refreshCell(for: model)
    }
    
    func removeModel(model: ZLPhotoModel, newModel: ZLPhotoModel) {
        guard let index = arrSelectedModels.firstIndex(where: { $0 == model }) else {
            return
        }
        
        currentShowModel = newModel
        arrSelectedModels.remove(at: index)
        collectionView.performBatchUpdates {
            self.collectionView.deleteItems(at: [IndexPath(item: index, section: 0)])
        } completion: { _ in
            self.collectionView.reloadItems(at: self.collectionView.indexPathsForVisibleItems)
        }
    }
    
    func refreshCell(for model: ZLPhotoModel) {
        guard let index = arrSelectedModels.firstIndex(where: { $0 == model }) else {
            return
        }
        collectionView.reloadItems(at: [IndexPath(row: index, section: 0)])
    }
    
    // MARK: iOS10 拖动
    
    @objc func longPressAction(_ gesture: UILongPressGestureRecognizer) {
        if gesture.state == .began {
            guard let indexPath = collectionView.indexPathForItem(at: gesture.location(in: collectionView)) else {
                return
            }
            isDraging = true
            collectionView.beginInteractiveMovementForItem(at: indexPath)
        } else if gesture.state == .changed {
            collectionView.updateInteractiveMovementTargetPosition(gesture.location(in: collectionView))
        } else if gesture.state == .ended {
            isDraging = false
            collectionView.endInteractiveMovement()
            endSortBlock?(arrSelectedModels)
        } else {
            isDraging = false
            collectionView.cancelInteractiveMovement()
        }
    }
    
    func collectionView(_ collectionView: UICollectionView, canMoveItemAt indexPath: IndexPath) -> Bool {
        return true
    }
    
    func collectionView(_ collectionView: UICollectionView, moveItemAt sourceIndexPath: IndexPath, to destinationIndexPath: IndexPath) {
        let moveModel = arrSelectedModels[sourceIndexPath.row]
        arrSelectedModels.remove(at: sourceIndexPath.row)
        arrSelectedModels.insert(moveModel, at: destinationIndexPath.row)
    }
    
    // MARK: iOS11 拖动
    
    @available(iOS 11.0, *)
    func collectionView(_ collectionView: UICollectionView, itemsForBeginning session: UIDragSession, at indexPath: IndexPath) -> [UIDragItem] {
        isDraging = true
        let itemProvider = NSItemProvider()
        let item = UIDragItem(itemProvider: itemProvider)
        return [item]
    }
    
    @available(iOS 11.0, *)
    func collectionView(_ collectionView: UICollectionView, dropSessionDidUpdate session: UIDropSession, withDestinationIndexPath destinationIndexPath: IndexPath?) -> UICollectionViewDropProposal {
        if collectionView.hasActiveDrag {
            return UICollectionViewDropProposal(operation: .move, intent: .insertAtDestinationIndexPath)
        }
        return UICollectionViewDropProposal(operation: .forbidden)
    }
    
    @available(iOS 11.0, *)
    func collectionView(_ collectionView: UICollectionView, performDropWith coordinator: UICollectionViewDropCoordinator) {
        isDraging = false
        guard let destinationIndexPath = coordinator.destinationIndexPath else {
            return
        }
        guard let item = coordinator.items.first else {
            return
        }
        guard let sourceIndexPath = item.sourceIndexPath else {
            return
        }
        
        if coordinator.proposal.operation == .move {
            collectionView.performBatchUpdates({
                let moveModel = self.arrSelectedModels[sourceIndexPath.row]
                
                self.arrSelectedModels.remove(at: sourceIndexPath.row)
                
                self.arrSelectedModels.insert(moveModel, at: destinationIndexPath.row)
                
                collectionView.deleteItems(at: [sourceIndexPath])
                collectionView.insertItems(at: [destinationIndexPath])
            }, completion: nil)
            
            coordinator.drop(item.dragItem, toItemAt: destinationIndexPath)
            
            endSortBlock?(arrSelectedModels)
        }
    }
    
    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        return arrSelectedModels.count
    }
    
    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        let cell = collectionView.dequeueReusableCell(withReuseIdentifier: ZLPhotoPreviewSelectedViewCell.zl.identifier, for: indexPath) as! ZLPhotoPreviewSelectedViewCell
        
        let model = arrSelectedModels[indexPath.row]
        cell.model = model
        
        let isSelected = model.isSelected
        let isFocused = model == currentShowModel
        let borderColor = UIColor(red: 95 / 255.0, green: 112 / 255.0, blue: 254 / 255.0, alpha: 1.0)
        
        cell.imageView.layer.borderColor = borderColor.cgColor
        cell.imageView.layer.borderWidth = isFocused ? 2 : 0
        cell.hudView.isHidden = true
        
        if isSelected {
            let image = UIImage(named: "ic_similar_checkmark")
            cell.checkmarkImageView.isHidden = false
            cell.checkmarkImageView.image = image ?? .zl.getImage("zl_btn_selected")
        } else {
            cell.checkmarkImageView.isHidden = true
        }
        
        return cell
    }
    
    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        guard !isDraging else {
            return
        }
        let model = arrSelectedModels[indexPath.row]
        selectBlock?(model)
        collectionView.reloadItems(at: [indexPath])
        
        /*
        collectionView.performBatchUpdates({
            self.collectionView.scrollToItem(at: indexPath, at: .centeredHorizontally, animated: true)
        }) { _ in
            self.collectionView.reloadItems(at: self.collectionView.indexPathsForVisibleItems)
        }
        selectBlock?(m)
        */
    }
    
    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        if ignoresDidScroll {
            return
        }
        
        let index = properIndexForRestPosition(offset: scrollView.contentOffset)
        let model = arrSelectedModels[index]
        scrollPositionBlock(model)
        
        if currentShowModel != model {
            currentShowModel = model
            self.collectionView.reloadItems(at: self.collectionView.indexPathsForVisibleItems)
        }
    }
    
    func scrollViewWillBeginDragging(_ scrollView: UIScrollView) {
        ignoresDidScrollCallbackForOther(true)
    }
    
    func scrollViewDidEndDragging(_ scrollView: UIScrollView, willDecelerate decelerate: Bool) {
        endDraggingBlock()
    }
    
    func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) {
        ignoresDidScrollCallbackForOther(false)
    }
    
    func scrollViewWillEndDragging(_ scrollView: UIScrollView, withVelocity velocity: CGPoint, targetContentOffset: UnsafeMutablePointer<CGPoint>) {
        let index = properIndexForRestPosition(offset: targetContentOffset.pointee)
        targetContentOffset.pointee.x = Double(index) * (Self.itemLength + Self.minimumSpacing)
    }
    
    /// find proper index to rest the scroll view at current offset
    func properIndexForRestPosition(offset: CGPoint) -> Int {
        let value = Int(offset.x)
        let base = Int(Self.itemLength + Self.minimumSpacing)
        var page = value / base
        let leftValue = value % base
        if leftValue > base / 2 {
            page += 1
        }

        return clamp(0, page, arrSelectedModels.count - 1)
    }
}


class PhotoPreviewSelectedViewCell: UICollectionViewCell {
    
    fileprivate lazy var imageView: UIImageView = {
        let view = UIImageView()
        view.contentMode = .scaleAspectFill
        view.clipsToBounds = true
        return view
    }()
    
    private lazy var tagImageView: UIImageView = {
        let view = UIImageView()
        view.contentMode = .scaleAspectFit
        view.clipsToBounds = true
        return view
    }()
    
    private lazy var tagLabel: UILabel = {
        let label = UILabel()
        label.font = .zl.font(ofSize: 13)
        label.textColor = .white
        return label
    }()
    
    
    fileprivate lazy var hudView: UIView = {
        let view = UIView()
        view.backgroundColor = .black.withAlphaComponent(0.5)
        view.layer.cornerRadius = 8
        view.layer.masksToBounds = true
        
        return view
    }()
    
    fileprivate lazy var checkmarkImageView: UIImageView = {
        let view = UIImageView()
        
        return view
    }()
    
    
    private var imageRequestID: PHImageRequestID = PHInvalidImageRequestID
    
    private var imageIdentifier: String = ""
    
    var model: ZLPhotoModel! {
        didSet {
            self.configureCell()
        }
    }
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        
        imageView.layer.cornerRadius = 8
        imageView.layer.masksToBounds = true
        // imageView.layer.borderColor = UIColor.zl.bottomToolViewBtnNormalBgColorOfPreviewVC.cgColor
        imageView.layer.borderColor = UIColor(red: 0.373, green: 0.439, blue: 0.996, alpha: 1).cgColor
      
        contentView.addSubview(imageView)
        contentView.addSubview(tagImageView)
        contentView.addSubview(tagLabel)
        
        contentView.addSubview(hudView)
        hudView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            hudView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            hudView.topAnchor.constraint(equalTo: contentView.topAnchor),
            hudView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            hudView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
        ])
        
        contentView.addSubview(checkmarkImageView)
        checkmarkImageView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            checkmarkImageView.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
            checkmarkImageView.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
        ])
    }
    
    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func layoutSubviews() {
        super.layoutSubviews()
        
        let frame = bounds
        imageView.frame = frame
        tagImageView.frame = CGRect(x: 5, y: bounds.height - 25, width: 20, height: 20)
        tagLabel.frame = CGRect(x: 5, y: bounds.height - 25, width: bounds.width - 10, height: 20)
    }
    
    private func configureCell() {
        let size = CGSize(width: bounds.width * 1.5, height: bounds.height * 1.5)
        
        if imageRequestID > PHInvalidImageRequestID {
            PHImageManager.default().cancelImageRequest(imageRequestID)
        }
        
        if model.type == .video {
            tagImageView.isHidden = false
            tagImageView.image = .zl.getImage("zl_video")
            tagLabel.isHidden = true
        } else if ZLPhotoConfiguration.default().allowSelectGif, model.type == .gif {
            tagImageView.isHidden = true
            tagLabel.isHidden = false
            tagLabel.text = "GIF"
        } else if ZLPhotoConfiguration.default().allowSelectLivePhoto, model.type == .livePhoto {
            tagImageView.isHidden = false
            tagImageView.image = .zl.getImage("zl_livePhoto")
            tagLabel.isHidden = true
        } else {
            if let _ = model.editImage {
                tagImageView.isHidden = false
                tagImageView.image = .zl.getImage("zl_editImage_tag")
            } else {
                tagImageView.isHidden = true
                tagLabel.isHidden = true
            }
        }
        
        // always hide tagImageView
        tagImageView.isHidden = true
        
        imageIdentifier = model.ident
        imageView.image = nil
        
        if let ei = model.editImage {
            imageView.image = ei
        } else {
            imageRequestID = ZLPhotoManager.fetchImage(for: model.asset, size: size, completion: { [weak self] image, _ in
                if self?.imageIdentifier == self?.model.ident {
                    self?.imageView.image = image
                }
            })
        }
        
        
    }
}


extension ZLImageNavController: ZLImageNavControllerProtocol {
    
}

public protocol ZLImageNavControllerProtocol: UINavigationController {
  
  var isSelectedOriginal: Bool { get set }
  
  var arrSelectedModels: [ZLPhotoModel]  { get set }
  
  var selectImageBlock: (() -> Void)? { get set }
  
  var cancelBlock: (() -> Void)? { get set }
  
}


class PhotoPreviewPopInteractiveTransition: UIPercentDrivenInteractiveTransition {
    typealias ZLPhotoPreviewController = PhotoPreviewController
    
    weak var transitionContext: UIViewControllerContextTransitioning?
    
    weak var viewController: ZLPhotoPreviewController?
    
    var shadowView: UIView?
    
    var imageView: UIImageView?
    
    var imageViewOriginalFrame: CGRect = .zero
    
    var startPanPoint: CGPoint = .zero
    
    var interactive: Bool = false
    
    var shouldStartTransition: ((CGPoint) -> Bool)?
  
    var currentIndex: Int = 0
    var fromFrameProvider: ZLAssetFromFrameProvider = nil
    
    var startTransition: (() -> Void)?
    
    var cancelTransition: (() -> Void)?
    
    var finishTransition: (() -> Void)?
    
    init(viewController: ZLPhotoPreviewController) {
        super.init()
        self.viewController = viewController
        let dismissPan = UIPanGestureRecognizer(target: self, action: #selector(dismissPanAction(_:)))
        viewController.view.addGestureRecognizer(dismissPan)
    }
    
    @objc func dismissPanAction(_ pan: UIPanGestureRecognizer) {
        let point = pan.location(in: viewController?.view)
        
        if pan.state == .began {
            guard shouldStartTransition?(point) == true else {
                interactive = false
                return
            }
            startPanPoint = point
            interactive = true
            startTransition?()
            viewController?.navigationController?.popViewController(animated: true)
        } else if pan.state == .changed {
            guard interactive else {
                return
            }
            let result = panResult(pan)
            imageView?.frame = result.frame
            shadowView?.alpha = pow(result.scale, 2)
            
            update(result.scale)
        } else if pan.state == .cancelled || pan.state == .ended {
            guard interactive else {
                return
            }
            
            let vel = pan.velocity(in: viewController?.view)
            let p = pan.translation(in: viewController?.view)
            let percent: CGFloat = max(0.0, p.y / (viewController?.view.bounds.height ?? UIScreen.main.bounds.height))
            
            let dismiss = vel.y > 300 || (percent > 0.1 && vel.y > -300)
            
            if dismiss {
                finish()
            } else {
                cancel()
            }
            imageViewOriginalFrame = .zero
            startPanPoint = .zero
            interactive = false
        }
    }
    
    func panResult(_ pan: UIPanGestureRecognizer) -> (frame: CGRect, scale: CGFloat) {
        // 拖动偏移量
        let translation = pan.translation(in: viewController?.view)
        let currentTouch = pan.location(in: viewController?.view)
        
        // 由下拉的偏移值决定缩放比例，越往下偏移，缩得越小。scale值区间[0.3, 1.0]
        let scale = min(1.0, max(0.3, 1 - translation.y / UIScreen.main.bounds.height))
        
        let width = imageViewOriginalFrame.size.width * scale
        let height = imageViewOriginalFrame.size.height * scale
        
        // 计算x和y。保持手指在图片上的相对位置不变。
        let xRate = (startPanPoint.x - imageViewOriginalFrame.origin.x) / imageViewOriginalFrame.size.width
        let currentTouchDeltaX = xRate * width
        let x = currentTouch.x - currentTouchDeltaX
        
        let yRate = (startPanPoint.y - imageViewOriginalFrame.origin.y) / imageViewOriginalFrame.size.height
        let currentTouchDeltaY = yRate * height
        let y = currentTouch.y - currentTouchDeltaY
        
        return (CGRect(x: x.isNaN ? 0 : x, y: y.isNaN ? 0 : y, width: width, height: height), scale)
    }
    
    override func startInteractiveTransition(_ transitionContext: UIViewControllerContextTransitioning) {
        self.transitionContext = transitionContext
        startAnimate()
    }
    
    func startAnimate() {
        guard let transitionContext = transitionContext else {
            return
        }
        
        guard let fromVC = transitionContext.viewController(forKey: .from) as? ZLPhotoPreviewController,
              let toVC = transitionContext.viewController(forKey: .to) else {
                  return
              }
        
        let containerView = transitionContext.containerView
        containerView.addSubview(toVC.view)
        
        guard let cell = fromVC.collectionView.cellForItem(at: IndexPath(row: fromVC.currentIndex, section: 0)) as? ZLPreviewBaseCell else {
            return
        }
        
        shadowView = UIView(frame: containerView.bounds)
        shadowView?.backgroundColor = ZLPhotoUIConfiguration.default().previewVCBgColor
        containerView.addSubview(shadowView!)
        
        let fromImageViewFrame = cell.animateImageFrame(convertTo: containerView)
        
        imageView = UIImageView(frame: fromImageViewFrame)
        imageView?.contentMode = .scaleAspectFill
        imageView?.clipsToBounds = true
        imageView?.image = cell.currentImage
        containerView.addSubview(imageView!)
        
        imageViewOriginalFrame = imageView!.frame
    }
    
    override func finish() {
        super.finish()
        finishAnimate()
    }
    
    func finishAnimate() {
        guard let transitionContext = transitionContext else {
            return
        }
        
        let toFrame = self.fromFrameProvider?(currentIndex)
        
        UIView.animate(withDuration: 0.25, animations: {
            if let toFrame = toFrame {
                self.imageView?.frame = toFrame
            } else {
                self.imageView?.alpha = 0
            }
            self.shadowView?.alpha = 0
        }) { _ in
            self.imageView?.removeFromSuperview()
            self.shadowView?.removeFromSuperview()
            self.imageView = nil
            self.shadowView = nil
            self.finishTransition?()
            transitionContext.finishInteractiveTransition()
            transitionContext.completeTransition(!transitionContext.transitionWasCancelled)
        }
    }
    
    override func cancel() {
        super.cancel()
        cancelAnimate()
    }
    
    func cancelAnimate() {
        guard let transitionContext = transitionContext else {
            return
        }
        
        UIView.animate(withDuration: 0.25, animations: {
            self.imageView?.frame = self.imageViewOriginalFrame
            self.shadowView?.alpha = 1
        }) { _ in
            self.imageView?.removeFromSuperview()
            self.shadowView?.removeFromSuperview()
            self.cancelTransition?()
            transitionContext.cancelInteractiveTransition()
            transitionContext.completeTransition(!transitionContext.transitionWasCancelled)
        }
    }
}

/// a base class to update intrinsicContentSize for a button with spacing between image and title
///
/// see: iphone - UIButton Text Margin / Padding - Stack Overflow
/// ref: https://stackoverflow.com/questions/5363789/uibutton-text-margin-padding
class SpacingButton: UIButton {
  override var intrinsicContentSize: CGSize {
    let baseSize = super.intrinsicContentSize
    return CGSize(
      width: baseSize.width + titleEdgeInsets.left + titleEdgeInsets.right,
      height: baseSize.height + titleEdgeInsets.top + titleEdgeInsets.bottom
    )
  }
}
