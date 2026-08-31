import CocoaLumberjackSwift
import os
import UIKit

/// Centralized accessor for app-level shared state (window, top view controller,
/// tab bar controller, lifecycle flags, etc). Routes between the legacy
/// `AppDelegate`-owned hierarchy and the `SceneDelegate` / `RootCoordinator`
/// hierarchy gated by `SCENE_DELEGATE_ROOT_COORDINATOR_DEVELOPMENT`.
///
/// Call sites should depend on this type rather than reaching into
/// `AppDelegate.shared()` directly — the latter crashes under the scene flow
/// because `UIApplication.shared.delegate` is an app delegate for the scene
/// life cycle instead of the `AppDelegate`.
@MainActor
enum SharedAppProvider {
    
    /// Compile time flag, thus it needs no isolation
    nonisolated static var isSceneDelegateDevelopment: Bool {
        #if SCENE_DELEGATE_ROOT_COORDINATOR_DEVELOPMENT
            return true
        #else
            return false
        #endif
    }

    // MARK: - Navigation

    static var tabBarController: UITabBarController? {
        if isSceneDelegateDevelopment {
            SceneDelegate.current?.rootCoordinator?.tabBarController
        }
        else {
            AppDelegate.shared()?.tabBarController()
        }
    }

    static var currentTopViewController: UIViewController? {
        if isSceneDelegateDevelopment {
            SceneDelegate.current?.currentTopViewController
        }
        else {
            AppDelegate.shared()?.currentTopViewController()
        }
    }

    static var window: UIWindow? {
        if isSceneDelegateDevelopment {
            SceneDelegate.current?.window
        }
        else {
            AppDelegate.shared()?.window
        }
    }

    // MARK: - Lifecycle

    /// Readable from any thread
    nonisolated static var isAppActive: Bool {
        AppActiveState.isActive
    }

    static var isAppLocked: Bool {
        if isSceneDelegateDevelopment {
            SceneDelegate.current?.isAppLocked == true
        }
        else {
            AppDelegate.shared()?.isAppLocked == true
        }
    }

    // MARK: - Coordinator access

    static var appCoordinator: AppCoordinator? {
        if isSceneDelegateDevelopment {
            SceneDelegate.current?.rootCoordinator?.appCoordinator
        }
        else {
            AppDelegate.shared()?.appCoordinator as? AppCoordinator
        }
    }

    static func execute(_ closure: (AppCoordinator) -> Void) {
        if let appCoordinator {
            closure(appCoordinator)
        }
        else {
            fatalError("AppCoordinator not found.")
        }
    }

    // MARK: - License

    static var isPresentingEnterLicense: Bool {
        if isSceneDelegateDevelopment {
            SceneDelegate.current?.isPresentingEnterLicense == true
        }
        else {
            AppDelegate.shared()?.isPresentingEnterLicense() == true
        }
    }

    static var isPresentingKeyGeneration: Bool {
        if isSceneDelegateDevelopment {
            SceneDelegate.current?.isPresentingKeyGeneration == true
        }
        else {
            AppDelegate.shared()?.isPresentingKeyGeneration() == true
        }
    }

    static func presentIDBackupRestore() {
        if isSceneDelegateDevelopment {
            SceneDelegate.current?.presentIDBackupRestore()
        }
        else {
            AppDelegate.shared()?.presentIDBackupRestore()
        }
    }

    // MARK: - Passcode

    static func presentPasscodeView() {
        if isSceneDelegateDevelopment {
            SceneDelegate.current?.presentPasscodeView()
        }
        else {
            AppDelegate.shared()?.presentPasscodeView()
        }
    }

    // MARK: - Class-level bridges

    /// Readable from any thread (see `AppBackgroundState`), so it never blocks on the main thread.
    nonisolated static var isAppInBackground: Bool {
        AppBackgroundState.isInBackground
    }

    static var keyWindow: UIWindow? {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first(where: \.isKeyWindow)
    }

    static var alertViewShown: UIAlertController? {
        window?.rootViewController?.presentedViewController as? UIAlertController
    }

    // MARK: - Trait collection

    static var isCompactSizeClass: Bool {
        appCoordinator?.splitViewController.traitCollection.horizontalSizeClass == .compact
    }

    // MARK: - Orientation (per-scene)

    static var orientationLock: UIInterfaceOrientationMask {
        get {
            if isSceneDelegateDevelopment {
                SceneDelegate.current?.orientationLock ?? .all
            }
            else {
                AppDelegate.shared()?.orientationLock ?? .all
            }
        }
        set {
            if isSceneDelegateDevelopment {
                SceneDelegate.current?.orientationLock = newValue
            }
            else {
                AppDelegate.shared()?.orientationLock = newValue
            }
        }
    }
}

// MARK: - AtomicFlag

/// Thread-safe boolean flag, readable and writable from any thread. Backs the app lifecycle flags below so they can be
/// read without hopping to the main thread.
final class AtomicFlag: @unchecked Sendable {

    private let lock: OSAllocatedUnfairLock<Bool>

    init(_ initialValue: Bool) {
        lock = OSAllocatedUnfairLock(initialState: initialValue)
    }

    var value: Bool {
        get { lock.withLock { $0 } }
        set { lock.withLock { $0 = newValue } }
    }
}

// MARK: - AppActiveState

/// Thread-safe storage of `SharedAppProvider.isAppActive`
///
/// `AppDelegate` and `SceneDelegate` write it on every change, so it can be read without hopping to the main thread.
@objc final class AppActiveState: NSObject {

    @objc static var isActive: Bool {
        get { state.value }
        set { state.value = newValue }
    }

    private static let state = AtomicFlag(false)
}

// MARK: - AppBackgroundState

/// Thread-safe storage of `SharedAppProvider.isAppInBackground`
///
/// `AppDelegate` and `SceneDelegate` write it on every foreground/background transition, so it can be read without
/// hopping to the main thread. Previously `isAppInBackground` read `UIApplication.applicationState` behind a
/// `DispatchQueue.main.sync`, which deadlocked (app freeze) when read off the main thread from a context the main
/// thread waits on — e.g. from inside a Core Data `performAndWait` block (see `WCSessionManager`). Mirrors
/// `AppActiveState`.
@objc final class AppBackgroundState: NSObject {

    @objc static var isInBackground: Bool {
        get { state.value }
        set { state.value = newValue }
    }

    private static let state = AtomicFlag(false)
}
