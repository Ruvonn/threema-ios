import CocoaLumberjackSwift
import Coordinator
import LocalAuthentication
import ThreemaFramework
import ThreemaMacros
import UIKit

// MARK: - Delegate

@MainActor
protocol PasscodeCoordinatorDelegate: AnyObject {
    func passcodeCoordinatorDidAuthenticate(
        _ coordinator: PasscodeCoordinator,
        appContainer: AppDependencyContainer,
        evaluatedPolicyDomainState: Data?
    )
    func passcodeCoordinatorDidRequestErase(_ coordinator: PasscodeCoordinator)
}

// MARK: - PasscodeCoordinator

/// Authenticate the user (passcode + biometrics) and report success/failure.
/// Privacy overlay is owned by `PrivacyCoordinator`.
@MainActor
final class PasscodeCoordinator: NSObject, Coordinator {

    // MARK: - Coordinator

    var childCoordinators: [any Coordinator] = []
    private(set) lazy var rootViewController: UIViewController = makeLockScreenViewController()

    // MARK: - Dependencies

    private weak var windowScene: UIWindowScene?
    private let appContainer: AppDependencyContainer
    private weak var delegate: PasscodeCoordinatorDelegate?

    private let setAppLocked: (Bool) -> Void
    private let authenticateBiometrics: () async throws -> Bool
    private let appName: String

    // MARK: - State

    /// Captured during a biometrics-changed error so the delegate can persist it to UserSettings.
    private var evaluatedPolicyDomainState: Data?
    private var passcodeWindow: PasscodeWindow?

    // MARK: - Init

    init(
        windowScene: UIWindowScene,
        appContainer: AppDependencyContainer,
        delegate: PasscodeCoordinatorDelegate,
        setAppLocked: @escaping (Bool) -> Void = { isAppLocked in
            MainActor.assumeIsolated({
                SceneDelegate.current?.isAppLocked = isAppLocked
            })
        },
        authenticateBiometrics: @escaping () async throws -> Bool = {
            try await TouchIDAuthentication.tryBiometricAuthentication()
        },
        appName: String = TargetManager.appName
    ) {
        self.windowScene = windowScene
        self.appContainer = appContainer
        self.delegate = delegate
        self.setAppLocked = setAppLocked
        self.authenticateBiometrics = authenticateBiometrics
        self.appName = appName
    }

    // MARK: - Coordinator lifecycle

    func start() {
        guard appContainer.passcodeLock.isPasscodeRequired() else {
            DDLogWarn("PasscodeCoordinator started but passcode is not required.")
            reportSuccess()
            return
        }
        
        if appContainer.passcodeLock.isWithinGracePeriod() {
            DDLogVerbose("Passcode within grace period — skipping prompt.")
            reportSuccess()
            return
        }

        guard let windowScene else {
            return
        }

        let window = PasscodeWindow(windowScene: windowScene)
        window.rootViewController = rootViewController
        window.makeKeyAndVisible()
        passcodeWindow = window
        setAppLocked(true)

        // Defer biometrics so the lock UI is on screen before iOS shows the system sheet.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
            self?.tryBiometricAuthentication()
        }
    }

    // MARK: - Biometrics

    private func tryBiometricAuthentication() {
        guard appContainer.passcodeLock.isBiometricAuthenticationEnabled() else {
            return
        }

        Task { @MainActor [weak self] in
            guard let self else {
                return
            }
            do {
                let ok = try await authenticateBiometrics()
                guard ok else {
                    return
                }
                DDLogVerbose("Authenticated using biometrics.")
                reportSuccess()
            }
            catch let TouchIDAuthentication.BiometricAuthenticationError.biometricsChanged(newPolicyDomainStateData) {
                handleBiometricsChanged(evaluatePolicyStateData: newPolicyDomainStateData)
            }
            catch {
                DDLogVerbose("Biometric authentication failed: \(error)")
            }
        }
    }

    private func handleBiometricsChanged(evaluatePolicyStateData: Data?) {
        evaluatedPolicyDomainState = evaluatePolicyStateData

        let context = LAContext()
        let title: String = {
            guard context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: nil) else {
                return ""
            }
            
            switch context.biometryType {
            case .faceID:
                return #localize("alert_biometrics_changed_title_face")
            case .touchID:
                return #localize("alert_biometrics_changed_title_touch")
            case .none, .opticID:
                return ""
            @unknown default:
                return ""
            }
        }()
        
        let message = String.localizedStringWithFormat(
            #localize("alert_biometrics_changed_message"),
            appName,
            appName
        )

        let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: #localize("ok"), style: .default))
        rootViewController.present(alert, animated: true)
    }

    // MARK: - Helpers

    private func makeLockScreenViewController() -> JKLLockScreenViewController {
        let vc = JKLLockScreenViewController(
            nibName: NSStringFromClass(JKLLockScreenViewController.self),
            bundle: BundleUtil.frameworkBundle()
        )
        vc.lockScreenMode = .normal
        vc.delegate = self
        return vc
    }

    private func reportSuccess() {
        passcodeWindow?.isHidden = true
        passcodeWindow = nil
        setAppLocked(false)
        delegate?.passcodeCoordinatorDidAuthenticate(
            self,
            appContainer: appContainer,
            evaluatedPolicyDomainState: evaluatedPolicyDomainState
        )
    }
}

// MARK: - JKLLockScreenViewControllerDelegate

extension PasscodeCoordinator: JKLLockScreenViewControllerDelegate {

    func didPasscodeEnteredCorrectly(_ viewController: JKLLockScreenViewController) {
        DDLogVerbose("Passcode entered correctly.")
        reportSuccess()
    }

    func didPasscodeViewDismiss(_ viewController: JKLLockScreenViewController) {
        // Intentional no-op. Dismissal only happens after we swap windows.
    }

    func shouldEraseApplicationData(_ viewController: JKLLockScreenViewController) {
        DDLogError("Erase application data requested from passcode screen.")
        delegate?.passcodeCoordinatorDidRequestErase(self)
    }

    func allowTouchIDLockScreenViewController(_ lockScreenViewController: JKLLockScreenViewController) -> Bool {
        appContainer.passcodeLock.isBiometricAuthenticationEnabled()
    }
}
