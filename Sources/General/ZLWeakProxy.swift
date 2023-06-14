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
    public typealias PreviewVC = UIViewController & PhotosResetable
    
    /// create a preview vc
    /// - Parameters:
    ///   - photos: the photos with selecte status
    ///   - index: the displaying index at first
    ///   - selectionEventCallback: the callback event for currentModel with selected updated
    /// - Returns: the navigation controller
    public static func createPhotoPreviewVC(
        photos: [ZLPhotoModel],
        index: Int,
        isMenuContextPreview: Bool = false,
        embedsInNavigationController: Bool = false,
        context: [String: Any]? = nil,
        removingReason: String? = nil,
        selectionEventCallback: @escaping (ZLPhotoModel) -> Void,
        fromFrameProvider: ZLAssetFromFrameProvider = nil,
        removingItemCallback: ((_ reason: String, _ model: ZLPhotoModel) -> Void)? = nil,
        removingAllCallback: (() -> Void)? = nil
    ) -> PreviewVC {
        PhotoInfoViewModel.shared.prepare(context: context)
        
        let models: [ZLPhotoModel]
        if photos.isEmpty {
            // placeholder item for initial
            let model = ZLPhotoModel(asset: .init())
            models = [model]
        } else {
            models = photos
        }
        
        let vc = PhotoPreviewController(
            photos: models,
            index: index
        )
        vc.isMenuContextPreview = isMenuContextPreview
        vc.selectionEventCallback = selectionEventCallback
        vc.fromFrameProvider = fromFrameProvider
        vc.removingReason = removingReason
        vc.removingItemCallback = removingItemCallback
        vc.removingAllCallback = removingAllCallback
        vc.context = context
        
        if embedsInNavigationController {
            return ZLImageNavController(rootViewController: vc)
        }
        
        return vc
    }
}

/// layout metrics for the preview context
fileprivate struct LayoutContext {
    let context: [String: Any]?
    
    let assetInset: CGFloat
    let assetWidth: CGFloat?
    let assetHeight: CGFloat?
    let thumbnailLength: CGFloat
    let thumbnailContainerHeight: CGFloat
    let thumbnailSpacing: CGFloat
    let thumbnailCornerRadius: CGFloat
    let thumbnailCornerPadding: CGFloat
    
    init(context: [String: Any]?) {
        self.context = context
        
        self.assetInset = (context?["assetInset"] as? CGFloat) ?? 0
        self.assetWidth = (context?["assetWidth"] as? CGFloat)
        self.assetHeight = (context?["assetHeight"] as? CGFloat)
        self.thumbnailLength = (context?["thumbnailLength"] as? CGFloat) ?? 40
        self.thumbnailContainerHeight = (context?["thumbnailContainerHeight"] as? CGFloat) ?? 80
        self.thumbnailSpacing = (context?["thumbnailSpacing"] as? CGFloat) ?? 8
        self.thumbnailCornerRadius = (context?["thumbnailCornerRadius"] as? CGFloat) ?? 0
        self.thumbnailCornerPadding = (context?["thumbnailCornerPadding"] as? CGFloat) ?? 2
    }
    
}

public protocol PhotosResetable: AnyObject {
    var photos: [ZLPhotoModel] { get set }
    func refreshSelection()
}

public protocol SelectedViewProviding {
    var selectedViews: [UIView] { get }
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
        properties: [String: Any]
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
    
    /// the context of the caller
    var context: [String: Any]?
    
    var removingReason: String?
    var removingItemCallback: ((_ reason: String, _ model: ZLPhotoModel) -> Void)?
    var removingAllCallback: (() -> Void)?
    
    private var infoVC: UIViewController!
    
    private let showBottomViewAndSelectBtn: Bool
    
    private var indexBeforOrientationChanged: Int
    
    private var ignoresDidScroll = false
    
    var isMenuContextPreview = false
    
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
        view.contentInsetAdjustmentBehavior = .never
        
        ZLPhotoPreviewCell.zl.register(view)
        ZLGifPreviewCell.zl.register(view)
        ZLLivePhotoPreviewCell.zl.register(view)
        ZLVideoPreviewCell.zl.register(view)
        
        return view
    }()

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
        let selectedImage = UIImage(named: "ic_checkbox_selected") ?? .zl.getImage("zl_btn_selected")
        let btn = ZLEnlargeButton(type: .custom)
        btn.setImage(UIImage(named: "ic_checkbox_unselected") ?? .zl.getImage("zl_btn_circle"), for: .normal)
        btn.setImage(selectedImage, for: .selected)
        btn.enlargeInset = 10
        btn.addTarget(self, action: #selector(selectBtnClick), for: .touchUpInside)
        return btn
    }()
    
    /// the index label on the select button
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
    
    private lazy var topRightIndexView: UIButton = {
        let button = UIButton(type: .custom)
        button.titleLabel?.font = UIFont.systemFont(ofSize: 11, weight: .regular)
        button.setTitleColor(.white, for: .normal)
        button.contentEdgeInsets = .init(top: 4, left: 8, bottom: 4, right: 8)
        button.isUserInteractionEnabled = false
        button.layer.cornerRadius = 11
        button.layer.masksToBounds = true
        
        // use blur effect instead of alpha backgroundColor
        let blurEffect = UIBlurEffect(style: .systemUltraThinMaterial)
        let visualEffectView = UIVisualEffectView(effect: blurEffect)
        visualEffectView.frame = button.bounds
        visualEffectView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        visualEffectView.isUserInteractionEnabled = false
        button.insertSubview(visualEffectView, at: 0)
        
        return button
    }()
    
    private lazy var bottomView: UIView = {
        let view = UIView()
        /*
        view.backgroundColor = .zl.bottomToolViewBgColorOfPreviewVC
        */
        view.backgroundColor = .clear
        return view
    }()
    
    private lazy var keepButton: UIButton = {
        let title = NSLocalizedString("keep", comment: "")
        let image = UIImage(named: "ic_star_sparkle_filled_16")
        
        let button = ZLSpacingButton(type: .custom)
        button.titleEdgeInsets = . init(top: 0, left: 8, bottom: 0, right: 0)
        button.contentEdgeInsets = .init(top: 4, left: 8, bottom: 4, right: 12)
        button.layer.cornerRadius = 15
        button.layer.masksToBounds = true
        button.titleLabel?.font = sfProFont(13)
        button.addTarget(self, action: #selector(onKeepButtonEvent), for: .touchUpInside)
        button.setTitle(title, for: .normal)
        button.setImage(image, for: .normal)
        
        return button
    }()
    
    private lazy var saveButton: UIButton = {
        let button = ZLSpacingButton(type: .custom)
        button.titleEdgeInsets = . init(top: 0, left: 8, bottom: 0, right: 0)
        button.contentEdgeInsets = .init(top: 4, left: 8, bottom: 4, right: 12)
        button.layer.cornerRadius = 15
        button.layer.masksToBounds = true
        button.titleLabel?.font = sfProFont(13)
        button.addTarget(self, action: #selector(onSaveButtonEvent), for: .touchUpInside)
        button.setTitle("save badcase", for: .normal)
        
        // use blur effect instead of alpha backgroundColor
        let blurEffect = UIBlurEffect(style: .systemUltraThinMaterial)
        let visualEffectView = UIVisualEffectView(effect: blurEffect)
        visualEffectView.frame = button.bounds
        visualEffectView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        visualEffectView.isUserInteractionEnabled = false
        button.insertSubview(visualEffectView, at: 0)
        
        return button
    }()
    
    private lazy var infoButton: UIButton = {
        let image = UIImage(named: "ic_about_plain")
        let selectedImage = UIImage(named: "ic_about_colored")
        
        let button = ZLSpacingButton(type: .custom)
        button.addTarget(self, action: #selector(onInfoButtonEvent(_:)), for: .touchUpInside)
        button.setImage(image, for: .normal)
        button.setImage(selectedImage, for: .selected)
        
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
    
    private var selPhotoPreview: SelectedPhotoPreview?
    
    private var hasAppear = true
    
    /// is hidding nav view
    private var isHiddingNavView = false
    
    private var popInteractiveTransition: PhotoPreviewPopInteractiveTransition?
    
    private var orientation: UIInterfaceOrientation = .unknown
    
    fileprivate lazy var layoutContext: LayoutContext = {
        return LayoutContext(context: self.context)
    }()
    
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
        self.arrDataSources = photos
        self.showBottomViewAndSelectBtn = showBottomViewAndSelectBtn
        self.currentIndex = index
        self.indexBeforOrientationChanged = index
        
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
        updateCurrentIndex(currentIndex)
        
        setupGestureDepend(on: collectionView)
        
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
        
        if !hasAppear {
            reloadCurrentCell()
            hasAppear = true
        }
        
        if !isMenuContextPreview {
            trackPageExposure()
        }
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        navigationController?.setNavigationBarHidden(false, animated: animated)
    }
    
    override func viewWillLayoutSubviews() {
        super.viewWillLayoutSubviews()
        
        var insets = UIEdgeInsets(top: 20, left: 0, bottom: 0, right: 0)
        if #available(iOS 11.0, *) {
            insets = self.view.safeAreaInsets
        }
        insets.top = max(20, insets.top)

        var navH = insets.top + 44
        navView.frame = CGRect(x: 0, y: 0, width: view.frame.width, height: navH)
        navBlurView?.frame = navView.bounds
        
        if let hidesNavView = context?["hidesNavView"] as? Bool, hidesNavView {
            navH = 0
        }
        
        // default inset behavior
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
        /*
        selectBtn.frame = CGRect(x: view.frame.width - 40 - insets.right, y: insets.top + (44 - 25) / 2, width: 25, height: 25)
        */
        infoButton.frame = CGRect(x: view.frame.width - 40 - insets.right, y: insets.top + (44 - 25) / 2, width: 25, height: 25)
        indexLabel.frame = selectBtn.bounds
        
        refreshBottomViewFrame()
        
        checkTopMask()
    }
    
    // MARK: - private
    private func checkTopMask() {
        guard let _ = context?["assetInset"] else {
            return
        }
        
        let topCornerRadius: CGFloat = 20
        let path = UIBezierPath(
            roundedRect: self.view.bounds,
          byRoundingCorners: [.topLeft, .topRight],
          cornerRadii: CGSize(width: topCornerRadius, height: topCornerRadius)
        )
        
        let maskLayer = CAShapeLayer()
        maskLayer.frame = self.view.bounds
        maskLayer.path = path.cgPath
        
        self.view.layer.mask = maskLayer
    }
    
    private func trackPageExposure() {
        // track exposure
        var properties: [String: Any] = [:]
        properties["from"] = context?["from"]
        
        PhotoPreview.trackEvent(
            event: "Clean",
            action: "photo_preview_detail",
            properties: properties
        )
    }
    
    private func trackKeepAction() {
        var properties: [String: Any] = [:]
        properties["from"] = context?["from"]
        
        PhotoPreview.trackEvent(
            event: "Clean",
            action: "click_photo_preview_detail_keep",
            properties: properties
        )
    }
    
    private func trackInfoAction() {
        var properties: [String: Any] = [:]
        properties["from"] = context?["from"]
        
        PhotoPreview.trackEvent(
            event: "Clean",
            action: "click_photo_preview_detail_info",
            properties: properties
        )
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
        
        let thumbnailContainerHeight = self.layoutContext.thumbnailContainerHeight
        
        var bottomViewH = ZLLayout.bottomToolViewH
        var showSelPhotoPreview = false
        if ZLPhotoConfiguration.default().showSelectedPhotoPreview
//            , let nav = navigationController as? ZLImageNavControllerProtocol
        {
//            if !nav.arrSelectedModels.isEmpty {
                showSelPhotoPreview = true
                bottomViewH += ZLPhotoPreviewController.selPhotoPreviewH
                selPhotoPreview?.frame = CGRect(x: 0, y: 0, width: view.frame.width, height: thumbnailContainerHeight)
//            }
        }
        let btnH = ZLLayout.bottomToolBtnH
        
        // ignore ZLLayout.bottomToolViewH
        bottomViewH = thumbnailContainerHeight
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
        view.backgroundColor = UIColor(red: 23 / 255.0, green: 23 / 255.0, blue: 23 / 255.0, alpha: 1)
        
        let config = ZLPhotoConfiguration.default()
        
        
        // - navView
        view.addSubview(navView)
        
        if let effect = ZLPhotoUIConfiguration.default().navViewBlurEffectOfPreview {
            navBlurView = UIVisualEffectView(effect: effect)
            navView.addSubview(navBlurView!)
        }
        
        navView.addSubview(backBtn)
        /*
        navView.addSubview(selectBtn)
        */
        navView.addSubview(infoButton)
        
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
            selPhotoPreview = SelectedPhotoPreview(
                selModels: self.arrDataSources,
                currentShowModel: arrDataSources[currentIndex],
                layoutContext: layoutContext
            )
            
            selPhotoPreview?.selectBlock = { [weak self] model in
                var properties: [String: Any] = [:]
                properties["from"] = self?.context?["from"]
                
                let selectAction = "click_photo_preview_detail_select"
                let cancelAction = "click_photo_preview_detail_cancel_select"
                let action = model.isSelected ? cancelAction : selectAction
                PhotoPreview.trackEvent(event: "Clean", action: action, properties: properties)
                
                self?.handleSelectEvent(model: model)
            }
            
            selPhotoPreview?.endDraggingBlock = { [weak self] in
                var properties: [String: Any] = [:]
                properties["from"] = self?.context?["from"]
                
                let action = "click_photo_preview_detail_slide"
                PhotoPreview.trackEvent(event: "Clean", action: action, properties: properties)
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
        do {
            let button = keepButton
            view.addSubview(keepButton)
            button.translatesAutoresizingMaskIntoConstraints = false
            NSLayoutConstraint.activate([
                button.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 24),
                button.bottomAnchor.constraint(equalTo: bottomView.topAnchor, constant: -20),
                button.heightAnchor.constraint(equalToConstant: 2 * 15),
            ])
            keepButton.isHidden = (removingReason != "keep")
        }
        
        do {
            // use blur effect instead of alpha backgroundColor
            let blurEffect = UIBlurEffect(style: .systemUltraThinMaterial)
            let visualEffectView = UIVisualEffectView(effect: blurEffect)
            visualEffectView.isUserInteractionEnabled = false
            visualEffectView.layer.cornerRadius = keepButton.layer.cornerRadius
            visualEffectView.layer.masksToBounds = true
            self.view.insertSubview(visualEffectView, belowSubview: keepButton)
            visualEffectView.isHidden = (removingReason != "keep")
            
            // same layout with keepButton
            visualEffectView.translatesAutoresizingMaskIntoConstraints = false
            NSLayoutConstraint.activate([
                visualEffectView.leadingAnchor.constraint(equalTo: keepButton.leadingAnchor),
                visualEffectView.trailingAnchor.constraint(equalTo: keepButton.trailingAnchor),
                visualEffectView.topAnchor.constraint(equalTo: keepButton.topAnchor),
                visualEffectView.bottomAnchor.constraint(equalTo: keepButton.bottomAnchor),
            ])
        }
        
        let settings: UserDefaults? = .init(suiteName: "bubble_settings")
        let show = (settings?.bool(forKey: "settings.qa.showsTestSettings")) ?? false
        let enables = (context?["showsTestSettings"] as? Bool) ?? true
        if show && enables {
          view.addSubview(saveButton)
          saveButton.translatesAutoresizingMaskIntoConstraints = false
          NSLayoutConstraint.activate([
              saveButton.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 24),
              saveButton.bottomAnchor.constraint(equalTo: bottomView.topAnchor, constant: -80),
              saveButton.heightAnchor.constraint(equalToConstant: 2 * 15),
          ])
        }
        
        let button = selectBtn
        view.addSubview(button)
        button.translatesAutoresizingMaskIntoConstraints = false
        
        var constraints = [
            button.widthAnchor.constraint(equalToConstant: 30),
            button.heightAnchor.constraint(equalToConstant: 30),
        ]
        if let _ = context?["assetInset"] as? CGFloat {
            let item = button.bottomAnchor.constraint(equalTo: collectionView.bottomAnchor, constant: -10)
            constraints.append(item)
        } else {
            let item = button.centerYAnchor.constraint(equalTo: keepButton.centerYAnchor)
            constraints.append(item)
        }
        let item = button.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -14)
        constraints.append(item)

        NSLayoutConstraint.activate(constraints)
        
        setupPhotoInfoView()
        
        setupTopRightIndexView()
        
        view.bringSubviewToFront(navView)
    }
    
    private func setupPhotoInfoView() {
        if let ignoresPhotoInfo = context?["ignoresPhotoInfo"] as? Bool, ignoresPhotoInfo {
            return
        }
        
        let rootView = PhotoInfoView(viewModel: .shared)
        infoVC = UIHostingController(rootView: rootView)
        view.addSubview(infoVC.view)
        infoVC.view.backgroundColor = .clear
        infoVC.view.isUserInteractionEnabled = false
        infoVC.view.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            infoVC.view.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            infoVC.view.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            infoVC.view.topAnchor.constraint(equalTo: navView.bottomAnchor, constant: 22),
        ])
    }
    
    private func setupTopRightIndexView() {
        guard let showsTopRightIndexView = context?["showsTopRightIndexView"] as? Bool, showsTopRightIndexView else {
            return
        }
        
        let margin: CGFloat = 12
        view.addSubview(topRightIndexView)
        topRightIndexView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            topRightIndexView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -margin),
            topRightIndexView.topAnchor.constraint(equalTo: view.topAnchor, constant: margin),
            topRightIndexView.heightAnchor.constraint(equalToConstant: 22),
        ])
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
            if !self.isHiddingNavView, self.navView.frame.contains(point) || self.bottomView.frame.contains(point) {
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
            
            self.isHiddingNavView = false
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
        
        let indexText = "\(currentIndex + 1)/\(arrDataSources.count)"
        titleIndexLabel.text = indexText
        topRightIndexView.setTitle(indexText, for: .normal)
        
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
        
        let hidesNavView = (context?["hidesNavView"] as? Bool) ?? false
        if hidesNavView {
            navView.isHidden = true
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
        
        trackKeepAction()
    }
    
    @objc private func onSaveButtonEvent() {
        handleSaveBadCase()
    }
    
    @objc private func onInfoButtonEvent(_ button: UIButton) {
        var isSelected = button.isSelected
        
        if !isSelected {
            // track display photo info
            trackInfoAction()
        }
        
        isSelected.toggle()
        
        button.isSelected = isSelected
        
        PhotoInfoViewModel.shared.update(isDisplaying: isSelected)
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
    
    
    private func handleSaveBadCase() {
        let albumName = getAblumNameFromContext()
        createAlbum(albumName: albumName) { album in
          self.saveAssetToAlbum(album, albumName: albumName)
        }
    }
    
    private func getAblumNameFromContext() -> String {
        let albumName = "badcase"
        guard let from = context?["from"] as? String else { return albumName }
        if from == "photo_clean_same" {
            return "duplicate_badcase"
        }
        if from == "photo_clean_similar" {
            return "similar_badcase"
        }
        if from == "photo_clean_screenshots" {
            return "screenshot_badcase"
        }
        if from == "photo_clean_blurred" {
            return "blur_badcase"
        }
        if from == "photo_clean_notes" {
            return "notes_badcase"
        }
        if from == "photo_clean_keeplist" {
            return "keep_badcase"
        }
        return albumName
    }
    
    private func saveAssetToAlbum(_ ablum :PHAssetCollection?, albumName: String) {
      let currentModel = arrDataSources[currentIndex]
      PHPhotoLibrary.shared().performChanges({
          let request = PHAssetCollectionChangeRequest(for: ablum!)
          request?.addAssets([currentModel.asset] as NSFastEnumeration)
          
          }) { (isHandle, error) in
              if isHandle {
                  self.showToast("保存成功")
              }else{
                  self.showToast(error?.localizedDescription ?? "")
              }
          }
    }
    
    private func showToast(_ message: String) {
        DispatchQueue.main.async {
            let toastLabel = UILabel(frame: CGRect(x: self.view.frame.size.width/2 - 150, y: self.view.frame.size.height-100, width: 300, height: 35))
            toastLabel.backgroundColor = UIColor.black.withAlphaComponent(0.6)
            toastLabel.textColor = UIColor.white
            toastLabel.textAlignment = .center
            toastLabel.text = message
            toastLabel.font = UIFont.systemFont(ofSize: 14)
            toastLabel.alpha = 0.0
            toastLabel.layer.cornerRadius = 10;
            toastLabel.clipsToBounds  =  true
            self.view.addSubview(toastLabel)
            UIView.animate(withDuration: 0.5, delay: 0.0, options: .curveEaseOut, animations: {
                toastLabel.alpha = 1.0
            }, completion: { _ in
                UIView.animate(withDuration: 0.5, delay: 2.0, options: .curveEaseOut, animations: {
                    toastLabel.alpha = 0.0
                }, completion: { _ in
                    toastLabel.removeFromSuperview()
                })
            })
        }
    }
    
    private func createAlbum(albumName: String, completion: @escaping (PHAssetCollection?) -> Void) {
        // 检查相册是否已存在，如果不存在则创建相册
        let fetchOptions = PHFetchOptions()
        fetchOptions.predicate = NSPredicate(format: "title = %@", albumName)
        let fetchResult = PHAssetCollection.fetchAssetCollections(with: .album, subtype: .any, options: fetchOptions)
        if let album = fetchResult.firstObject {
            // 相册已存在，直接返回
            completion(album)
        } else {
            // 相册不存在，创建相册
            var albumPlaceholder: PHObjectPlaceholder?
            PHPhotoLibrary.shared().performChanges({
                let albumChangeRequest = PHAssetCollectionChangeRequest.creationRequestForAssetCollection(withTitle: albumName)
                albumPlaceholder = albumChangeRequest.placeholderForCreatedAssetCollection
            }, completionHandler: { (success, error) in
                guard success, let albumPlaceholder = albumPlaceholder else {
                    completion(nil)
                    return
                }
                let fetchResult = PHAssetCollection.fetchAssetCollections(withLocalIdentifiers: [albumPlaceholder.localIdentifier], options: nil)
                let album = fetchResult.firstObject
                completion(album)
            })
        }
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
        
        let asset = arrDataSources[index].asset
        PhotoInfoViewModel.shared.apply(asset: asset)
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
        if let tapPreviewCellCallback = context?["tapPreviewCellCallback"] as? (PHAsset, Int) -> Void {
            let model = arrDataSources[currentIndex]
            tapPreviewCellCallback(model.asset, currentIndex)
            return
        }
        
        isHiddingNavView.toggle()
        
        let currentCell = collectionView.cellForItem(at: IndexPath(row: currentIndex, section: 0))
        if let cell = currentCell as? ZLVideoPreviewCell {
            if cell.isPlaying {
                isHiddingNavView = true
            }
        }
        
        // always show navViews
        // return here
        /*
        navView.isHidden = isHiddingNavView
        bottomView.isHidden = showBottomViewAndSelectBtn ? isHiddingNavView : true
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

extension PhotoPreviewController: SelectedViewProviding {
    var selectedViews: [UIView] {
        return self.selPhotoPreview?.selectedViews ?? []
    }
}

extension PhotoPreviewController: PhotosResetable {
    var photos: [ZLPhotoModel] {
        get {
            return arrDataSources
        }
        
        set {
            // update preview area
            self.reset(photos: newValue)
        }
    }
    
    private func reset(photos: [ZLPhotoModel]) {
        self.arrDataSources = photos
        self.indexBeforOrientationChanged = 0
        self.updateCurrentIndex(0)
        self.collectionView.reloadData()
        self.collectionView.contentOffset = .zero
        
        // update select view
        self.selPhotoPreview?.photos = photos
    }
    
    func refreshSelection() {
        self.resetSubViewStatus()
        self.selPhotoPreview?.refreshSelection()
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
                    let (size, _) = PhotoPreviewController.fileSize(asset: asset)
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
    
    static func fileSize(asset: PHAsset) -> (Int64, String?) {
        let resources = PHAssetResource.assetResources(for: asset)
        
        var fileName: String?
        let total = resources.reduce(0) { (partialResult, resource) -> Int64 in
            let fileSize = resource.value(forKey: "fileSize") as? Int64
            if fileName == nil {
                // set once only
                fileName = resource.originalFilename
            }
            return partialResult + (fileSize ?? 0)
        }
        
        return (total, fileName)
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
        
        var page = Int(round(offset.x / usedSpacePerItem))
        page = clamp(0, page, arrDataSources.count - 1)
        if page == currentIndex {
            return
        }
        
        updateCurrentIndex(page)
        selPhotoPreview?.currentShowModelChanged(model: arrDataSources[currentIndex])
    }
    
    var usedSpacePerItem: CGFloat {
        return view.bounds.width + ZLPhotoPreviewController.colItemSpacing
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
        return CGSize(width: getItemWidth(), height: getItemHeight())
    }
    
    func getItemWidth() -> CGFloat {
        if let assetWidth = self.layoutContext.assetWidth {
            return assetWidth
        }
        
        return view.bounds.width
    }
    
    func getItemHeight() -> CGFloat {
        if let assetHeight = self.layoutContext.assetHeight {
            return assetHeight
        }
        
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
            
            let aspectFill = (context?["aspectFill"] as? Bool) ?? false
            let disablesScaleBehavior = (context?["disablesScaleBehavior"] as? Bool) ?? false
            
            if aspectFill {
                cell.preview.aspectFill = true
            }
            
            if disablesScaleBehavior {
                cell.preview.disablesScaleBehavior = true
            }
            
            cell.singleTapBlock = { [weak self] in
                self?.tapPreviewCell()
            }

            cell.model = model

            baseCell = cell
        }
        
        baseCell.singleTapBlock = { [weak self] in
            self?.tapPreviewCell()
        }
        
        if let configureCell = context?["configureCell"] as? (UICollectionViewCell, IndexPath) -> Void {
            configureCell(baseCell, indexPath)
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


fileprivate struct HapticFeedback {
  /// selection change
  ///
  /// @note haptic feedback might not work on old devices
  static func selectionChanged() {
    let feedback = UISelectionFeedbackGenerator()
    feedback.prepare()
    feedback.selectionChanged()
  }
}

fileprivate extension Int {
    var actualPixel: CGFloat {
        return CGFloat(self) * UIScreen.main.bounds.width / 375
    }
}

// MARK: 下方显示的已选择照片列表

class SelectedPhotoPreview: UIView, UICollectionViewDataSource, UICollectionViewDelegateFlowLayout, UICollectionViewDragDelegate, UICollectionViewDropDelegate {
    typealias ZLPhotoPreviewSelectedViewCell = PhotoPreviewSelectedViewCell
    
    private lazy var collectionView: UICollectionView = {
        // minus a bit to silence UICollectionViewFlowLayout layout warning
        var verticalInset = 0.5 * (self.layoutContext.thumbnailContainerHeight - self.layoutContext.thumbnailLength)
        verticalInset -= 0.5
        
        let minimumSpacing = self.layoutContext.thumbnailSpacing
 
        let itemLength = self.layoutContext.thumbnailLength
        let assetInset = self.layoutContext.assetInset
        let forCenterInset = 0.5 * (UIScreen.main.bounds.width - itemLength - 2 * assetInset)
        
        let layout = UICollectionViewFlowLayout()
        layout.itemSize = CGSize(width: itemLength, height: itemLength)
        layout.minimumLineSpacing = minimumSpacing
        layout.minimumInteritemSpacing = minimumSpacing
        layout.scrollDirection = .horizontal
        layout.sectionInset = UIEdgeInsets(
            top: verticalInset,
            left: forCenterInset,
            bottom: verticalInset,
            right: forCenterInset
        )
        
        let view = UICollectionView(frame: .zero, collectionViewLayout: layout)
        view.backgroundColor = .clear
        view.dataSource = self
        view.delegate = self
        view.showsHorizontalScrollIndicator = false
        view.alwaysBounceHorizontal = true
        view.contentInsetAdjustmentBehavior = .never
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
    
    private var focusHudView: UIView!
  
    private var isDraging = false
    
    var ignoresDidScroll = false
    
    fileprivate var layoutContext: LayoutContext!
    
    /// callback on didSelect item
    var selectBlock: ((ZLPhotoModel) -> Void)?
    
    /// scroll position changed callback
    var scrollPositionBlock: (ZLPhotoModel) -> Void = { _ in }
    
    /// ignores other scroll callback when this view is dragging
    var ignoresDidScrollCallbackForOther: (Bool) -> Void = { _ in }
    
    /// callback when end dragging
    var endDraggingBlock: () -> Void = { }
    
    var endSortBlock: (([ZLPhotoModel]) -> Void)?
    
    fileprivate init(
        selModels: [ZLPhotoModel],
        currentShowModel: ZLPhotoModel,
        layoutContext: LayoutContext
    ) {
        self.arrSelectedModels = selModels
        self.currentShowModel = currentShowModel
        self.layoutContext = layoutContext
        
        super.init(frame: .zero)
        
        setupUI()
    }
    
    private func setupUI() {
        addSubview(collectionView)
        addFocusHudView()
    }
    
    private func addFocusHudView() {
        let borderColor = UIColor(red: 95 / 255.0, green: 112 / 255.0, blue: 254 / 255.0, alpha: 1.0)
        
        let view = UIView()
        view.isUserInteractionEnabled = false
        view.layer.borderColor = borderColor.cgColor
        view.layer.borderWidth = 2
        view.layer.cornerRadius = self.layoutContext.thumbnailCornerRadius
        addSubview(view)
        
        // center the focus view
        let itemLength = self.layoutContext.thumbnailLength
        view.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            view.widthAnchor.constraint(equalToConstant: itemLength),
            view.heightAnchor.constraint(equalToConstant: itemLength),
            view.centerXAnchor.constraint(equalTo: collectionView.centerXAnchor),
            view.centerYAnchor.constraint(equalTo: collectionView.centerYAnchor),
        ])
        focusHudView = view
    }
    
    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func layoutSubviews() {
        super.layoutSubviews()
        
        self.collectionView.frame = self.bounds
        
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
        let selectedImage = UIImage(named: "ic_checkbox_selected") ?? .zl.getImage("zl_btn_selected")

        cell.imageView.layer.cornerRadius = self.layoutContext.thumbnailCornerRadius
        cell.hudView.isHidden = true
        cell.checkmarkImageView.image = selectedImage
        cell.checkmarkImageView.isHidden = !isSelected
        cell.cornerPadding = self.layoutContext.thumbnailCornerPadding
        cell.isHidden = false
      
        return cell
    }
    
    func reconfigureVisiableCells() {
        if collectionView.visibleCells.isEmpty {
            collectionView.reloadData()
            return
        }
        
        let cells = collectionView.visibleCells.compactMap { cell in
            return cell as? ZLPhotoPreviewSelectedViewCell
        }
        
        cells.forEach { cell in
            cell.checkmarkImageView.isHidden = !cell.model.isSelected
            cell.isHidden = false
        }
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
            HapticFeedback.selectionChanged()
            currentShowModel = model
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
        targetContentOffset.pointee.x = Double(index) * usedSpacePerItem
    }
    
    var usedSpacePerItem: CGFloat {
        return self.layoutContext.thumbnailLength + self.layoutContext.thumbnailSpacing
    }
    
    /// find proper index to rest the scroll view at current offset
    func properIndexForRestPosition(offset: CGPoint) -> Int {
        let value = Int(offset.x)
        let base = Int(usedSpacePerItem)
        var page = value / base
        let leftValue = value % base
        if leftValue > base / 2 {
            page += 1
        }

        return clamp(0, page, arrSelectedModels.count - 1)
    }
}

extension SelectedPhotoPreview: SelectedViewProviding {
    var selectedViews: [UIView] {
        let selectedCells: [UIView] = collectionView.indexPathsForVisibleItems
            .sorted {
                $0.item < $1.item
            }
            .compactMap { indexPath in
                guard let cell = collectionView.cellForItem(at: indexPath) as? ZLPhotoPreviewSelectedViewCell else {
                    return nil
                }
                guard cell.model.isSelected else {
                    return nil
                }
                
                return cell
            }
        
        if self.currentShowModel.isSelected {
            UIView.animate(withDuration: 0.25) {
                self.focusHudView.alpha = 0
            }
        }
      
        return selectedCells
    }
}

extension SelectedPhotoPreview: PhotosResetable {
    var photos: [ZLPhotoModel] {
        get {
            return arrSelectedModels
        }
        
        set {
            self.reset(photos: newValue)
        }
    }
    
    func reset(photos: [ZLPhotoModel]) {
        self.arrSelectedModels = photos
        if let first = photos.first {
            self.currentShowModel = first
        }
        self.focusHudView.alpha = 1.0
        self.collectionView.reloadData()
        self.collectionView.contentOffset = .zero
    }
    
    func refreshSelection() {
        self.focusHudView.alpha = 1.0
        self.reconfigureVisiableCells()
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
    
    private var corners: [NSLayoutConstraint]!
    
    var cornerPadding: CGFloat = 2 {
        didSet {
            corners.forEach {
                $0.constant = -cornerPadding
            }
        }
    }
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        
        /*
        imageView.layer.cornerRadius = 8
        imageView.layer.masksToBounds = true
        imageView.layer.borderColor = UIColor.zl.bottomToolViewBtnNormalBgColorOfPreviewVC.cgColor
        */
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
        corners = [
            checkmarkImageView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -2),
            checkmarkImageView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -2),
        ]
        NSLayoutConstraint.activate(corners)
    }
    
    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func prepareForReuse() {
        super.prepareForReuse()
        
        self.isHidden = false
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

extension ZLImageNavController: PhotosResetable {
    var photos: [ZLPhotoModel] {
        get {
            return resetableTopVC?.photos ?? []
        }
        
        set {
            self.reset(photos: newValue)
        }
    }
    
    func reset(photos: [ZLPhotoModel]) {
        resetableTopVC?.photos = photos
    }
    
    func refreshSelection() {
        resetableTopVC?.refreshSelection()
    }
    
    var resetableTopVC: PhotosResetable? {
        return topViewController as? PhotosResetable
    }
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
class ZLSpacingButton: UIButton {
  override var intrinsicContentSize: CGSize {
    let baseSize = super.intrinsicContentSize
    return CGSize(
      width: baseSize.width + titleEdgeInsets.left + titleEdgeInsets.right,
      height: baseSize.height + titleEdgeInsets.top + titleEdgeInsets.bottom
    )
  }
}


extension String {
    fileprivate var stringWithKey: String {
        return NSLocalizedString(self, comment: "")
    }
}

import SwiftUI

struct PhotoInfo {
    struct Item {
        let key: String
        let value: String
    }
    
    var name: String
    var itemList: [Item]
    
    static let placeholder: PhotoInfo = .init(
        name: "--",
        itemList: [
            .init(key: "dimension".stringWithKey, value: "--"),
            .init(key: "size".stringWithKey, value: "--"),
            .init(key: "date".stringWithKey, value: "--"),
            .init(key: "album".stringWithKey, value: "--"),
            .init(key: "phone".stringWithKey, value: "--"),
        ]
    )
}

struct AlbumInfo {
    let id: String
    let title: String?
    let assetIdSet: Set<String>
}

class PhotoInfoViewModel: ObservableObject {
    /// a shared instance to save its albumList
    static let shared: PhotoInfoViewModel = .init()
    
    @Published var info: PhotoInfo = .placeholder
    
    @Published var isDisplaying = false
    
    var recentAddTitle: String?
    var favorateTitle: String?
    
    @Published var albumList: [AlbumInfo]? {
        didSet {
            updateAlbumTitle()
        }
    }
    
    private var asset: PHAsset?
    
    private init() {
        
    }
    
    func update(isDisplaying: Bool) {
        self.isDisplaying = isDisplaying
        
        if isDisplaying, let asset = asset {
            apply(asset: asset)
        }
    }
    
    func updateAlbumTitle() {
        
    }
    
    func prepare(context: [String: Any]?) {
        if let ignoresPhotoInfo = context?["ignoresPhotoInfo"] as? Bool, ignoresPhotoInfo {
            return
        }
        
        update(isDisplaying: false)
        
        if albumList != nil {
            return
        }
        
        let status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        guard status == .authorized || status == .limited else {
            return
        }
        
        DispatchQueue.global().async {
            let collectionResult = PHCollection.fetchTopLevelUserCollections(with: nil)
            var albumList: [AlbumInfo] = []
            
            collectionResult.enumerateObjects { collection, _, _ in
                guard let assetCollection = collection as? PHAssetCollection else { return }
                
                var idSet: Set<String> = []
                let assetResult = PHAsset.fetchAssets(in: assetCollection, options: nil)
                assetResult.enumerateObjects { asset, _, _ in
                    idSet.insert(asset.localIdentifier)
                }
                
                let albumInfo = AlbumInfo(
                    id: assetCollection.localIdentifier,
                    title: assetCollection.localizedTitle,
                    assetIdSet: idSet)
                albumList.append(albumInfo)
            }
            let favoriteTitle = PHAssetCollection.fetchAssetCollections(
                with: .smartAlbum,
                subtype: .smartAlbumFavorites,
                options: nil
            )
                .firstObject?
                .localizedTitle
            let recentAddTitle = PHAssetCollection.fetchAssetCollections(
                with: .smartAlbum,
                subtype: .smartAlbumRecentlyAdded,
                options: nil
            )
                .firstObject?
                .localizedTitle
            
            DispatchQueue.main.async {
                self.favorateTitle = favoriteTitle
                self.recentAddTitle = recentAddTitle
                self.albumList = albumList
            }
        }
    }
    
    func apply(asset: PHAsset) {
        self.asset = asset
        
        guard isDisplaying else {
            return
        }
        
        loadInfo(asset: asset)
    }
    
    private func otherPossibleAlbumTitle(asset: PHAsset) -> String {
        if let favorateTitle = favorateTitle, asset.isFavorite {
            return favorateTitle
        }
        
        if let recentAddTitle = recentAddTitle {
            return recentAddTitle
        }
        
        return "unknown".stringWithKey
    }
    
    private func loadInfo(asset: PHAsset) {
        // ignore the invalid asset created by `PHAsset()`
        if asset.localIdentifier.contains("null") {
            return
        }
        
        let manager = PHImageManager.default()
        let requestOptions = PHImageRequestOptions()
        requestOptions.isSynchronous = false
        requestOptions.deliveryMode = .fastFormat
        requestOptions.isNetworkAccessAllowed = true
        
        manager.requestImageDataAndOrientation(for: asset, options: requestOptions) { (data, fileType, orientation, info) in
            DispatchQueue.global().async {
                var itemList: [PhotoInfo.Item] = []
                itemList.append(.init(key: "dimension".stringWithKey, value: "\(asset.pixelWidth) x \(asset.pixelHeight)"))
                
                let (size, fileName) = PhotoPreviewController.fileSize(asset: asset)
                
                let formatter: ByteCountFormatter = ByteCountFormatter()
                formatter.countStyle = .decimal
                formatter.allowedUnits = [.useMB, .useKB]
                let sizeString = formatter.string(fromByteCount: size)
                itemList.append(.init(key: "size".stringWithKey, value: sizeString))

                let date = asset.creationDate ?? Date()
                let dateString = formatDate(date) ?? "unknown".stringWithKey
                itemList.append(.init(key: "date".stringWithKey, value: dateString))
                
                let phoneString: String
                if let data = data,
                   let properties = CIImage(data: data)?.properties,
                   let tiff = properties["{TIFF}"] as? [String: Any],
                   let model = tiff["Model"] as? String {
                    phoneString = model
                }  else {
                    phoneString = "unknown".stringWithKey
                }
                
                DispatchQueue.main.async {
                    guard asset.localIdentifier == self.asset?.localIdentifier else {
                        return
                    }
                    
                    let firstAlbum = self.albumList?.first {
                        $0.assetIdSet.contains(asset.localIdentifier)
                    }
                    
                    let albumString = firstAlbum?.title ?? self.otherPossibleAlbumTitle(asset: asset)
                    itemList.append(.init(key: "album".stringWithKey, value: albumString))
                    
                    itemList.append(.init(key: "phone".stringWithKey, value: phoneString))
                    
                    let nameComponents = fileName.map { $0.components(separatedBy: ".") } ?? []
                    let nameString = nameComponents.first ?? "unknown".stringWithKey
                    
                    let info = PhotoInfo(name: nameString, itemList: itemList)
                    self.info = info
                }
            }
        }
    }
}

struct PhotoInfoView: View {
    @StateObject var viewModel: PhotoInfoViewModel
    
    var body: some View {
        itemListView
        .font(Font(sfProFont(13)))
        .padding(24)
        .frame(
          maxWidth: .infinity
        )
        .background(backgroundColor)
        .cornerRadius(16)
        .opacity(viewModel.isDisplaying ? 1.0 : 0.0)
    }
    
    private var itemListView: some View {
        HStack {
            itemList
            Spacer()
        }
    }
    
    var itemList: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(viewModel.info.itemList, id: \.key) { item in
                HStack(spacing: 5) {
                    Text("\(item.key):")
                        .foregroundColor(grayColor)
                    Text(item.value)
                        .foregroundColor(.white)
                }
            }
        }
    }
    
    var backgroundColor: Color {
        let uicolor = UIColor(white: 0, alpha: 0.7)
        return Color(uicolor)
    }
    
    var grayColor: Color {
        let uicolor = UIColor(red: 146 / 255.0, green: 146 / 255.0, blue: 146 / 255.0, alpha: 1.0)
        return Color(uicolor)
    }
}

fileprivate func sfProFont(_ size: CGFloat) -> UIFont {
    let uifont = UIFont(name: "SFPro", size: size)
    
    return uifont ?? UIFont.systemFont(ofSize: size)
}


fileprivate func formatDate(_ date: Date?) -> String? {
    guard let date = date else { return nil }
    let formatter = DateFormatter()
    formatter.timeZone = .current
    formatter.dateStyle = .medium
    formatter.timeStyle = .short

    return formatter.string(from: date)
}


#if DEBUG
struct PhotoInfoView_Previews: PreviewProvider {
    static var previews: some View {
        PhotoInfoView(viewModel: {
            let ins = PhotoInfoViewModel.shared
            ins.info = .init(
                name: "IMG_20230405_135917 ",
                itemList: [
                    .init(key: "Dimension", value: "3648 x 2736"),
                    .init(key: "Size", value: "12.30MB"),
                    .init(key: "Date", value: "Apr 4, 2023 10:02"),
                    .init(key: "Album", value: "Twitter"),
                    .init(key: "Phone", value: "iPhone 14 pro"),
                ]
            )
            return ins
        }()
        )
        .frame(width: 380)
    }
}
#endif
