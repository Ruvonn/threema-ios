import SwiftUI
import ThreemaFramework
import UIKit

final class SceneDelegate: UIResponder, UIWindowSceneDelegate {
    
    private(set) weak static var current: SceneDelegate?
    
    /// Readable from any thread (see `AppBackgroundState`). Backed by a write-through flag updated on every
    /// foreground/background transition, so it no longer blocks on `DispatchQueue.main.sync` off the main thread.
    static var isAppInBackground: Bool {
        AppBackgroundState.isInBackground
    }
    
    var currentTopViewController: UIViewController? {
        var topViewController = window?.rootViewController
        while let presentedViewController = topViewController?.presentedViewController {
            topViewController = presentedViewController
        }
        return topViewController
    }
    
    var window: UIWindow?
    private(set) var rootCoordinator: RootCoordinator?
    
    /// Write through, so the state can be read from any thread (see `AppActiveState`)
    var isActive = false {
        didSet {
            AppActiveState.isActive = isActive
        }
    }

    var isAppLocked: Bool = false
    var orientationLock: UIInterfaceOrientationMask = .all

    var isPresentingEnterLicense: Bool {
        window?.rootViewController?.presentedViewController is EnterLicenseViewController
    }

    var isPresentingKeyGeneration: Bool {
        let vc = window?.rootViewController?.presentedViewController
        return vc is SplashViewController
            || vc is RestoreOptionDataViewController
            || vc is RestoreOptionBackupViewController
            || vc is RestoreIdentityViewController
    }
    
    override init() {
        AppLaunchManager.preLaunchSetup()
        super.init()
        startSentryIfNeeded()
        
        Self.current = self
    }

    func scene(
        _ scene: UIScene,
        willConnectTo session: UISceneSession,
        options connectionOptions: UIScene.ConnectionOptions
    ) {
        // Use this method to optionally configure and attach the UIWindow `window` to the provided UIWindowScene
        // `scene`.
        // If using a storyboard, the `window` property will automatically be initialized and attached to the scene.
        // This delegate does not imply the connecting scene or session are new (see
        // `application:configurationForConnectingSceneSession` instead).
        guard let windowScene = scene as? UIWindowScene else {
            return
        }
                
        let window = UIWindow(windowScene: windowScene)
        self.window = window
        
        let rootCoordinator = RootCoordinator(
            window: window,
            windowScene: windowScene,
            bootstrap: .live()
        )
        self.rootCoordinator = rootCoordinator
        rootCoordinator.start()
    }

    func sceneDidDisconnect(_ scene: UIScene) {
        // Called as the scene is being released by the system.
        // This occurs shortly after the scene enters the background, or when its session is discarded.
        // Release any resources associated with this scene that can be re-created the next time the scene connects.
        // The scene may re-connect later, as its session was not necessarily discarded (see
        // `application:didDiscardSceneSessions` instead).
    }

    func sceneDidBecomeActive(_ scene: UIScene) {
        isActive = true
        AppBackgroundState.isInBackground = false
        rootCoordinator?.hidePrivacyOverlay()
    }

    func sceneWillResignActive(_ scene: UIScene) {
        defer {
            isActive = false
        }
        rootCoordinator?.showPrivacyOverlay()
    }

    func sceneWillEnterForeground(_ scene: UIScene) {
        AppBackgroundState.isInBackground = false
        rootCoordinator?.sceneWillEnterForeground()
    }

    func sceneDidEnterBackground(_ scene: UIScene) {
        AppBackgroundState.isInBackground = true
        rootCoordinator?.sceneDidEnterBackground()
    }
    
    // MARK: - Helpers
    
    private func startSentryIfNeeded() {
        #if !DISABLE_SENTRY
            guard !ProcessInfoHelper.isRunningForScreenshots else {
                return
            }
            let sentry = SentryClient()
            sentry.start()
        #endif
    }
    
    func presentPasscodeView() {
        rootCoordinator?.requestReauthenticationIfNeeded()
    }
    
    func presentIDBackupRestore() {
        let vc = window?.rootViewController?.presentedViewController
        if let splashVC = vc as? SplashViewController {
            splashVC.showRestoreIdentityViewController()
        }
        else if let restoreBackupVC = vc as? RestoreOptionBackupViewController,
                let splashVC = restoreBackupVC.parent as? SplashViewController {
            splashVC.showRestoreIdentityViewController()
        }
        else if let restoreVC = vc as? RestoreIdentityViewController {
            restoreVC.updateTextViewWithBackupCode()
        }
    }
}
