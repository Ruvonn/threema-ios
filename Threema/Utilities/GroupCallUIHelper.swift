import CocoaLumberjackSwift
import Foundation
import GroupCalls
import ThreemaMacros

final class GroupCallUIHelper: NSObject {
    @objc func setGlobalGroupCallsManagerSingletonUIDelegate() {
        GlobalGroupCallManagerSingleton.shared.uiDelegate = self
    }
}

// MARK: - GroupCallManagerSingletonUIDelegate

extension GroupCallUIHelper: GroupCallManagerSingletonUIDelegate {
    private var isAppLocked: Bool {
        MainActor.assumeIsolated {
            SharedAppProvider.isAppLocked
        }
    }
    
    func showViewController(_ viewController: GroupCallViewController) {
        Task { @MainActor in
            guard SharedAppProvider.alertViewShown == nil else {
                DDLogError("[GroupCall] Do not show GroupCallViewController because an alert is being presented.")
                return
            }
            SharedAppProvider.currentTopViewController?.present(viewController, animated: true)
        }
    }
    
    @MainActor
    func showAlert(for groupCallError: GroupCallErrorProtocol) {
        guard let currentTopViewController = SharedAppProvider.currentTopViewController else {
            DDLogError("`SharedAppProvider.currentTopViewController` not available.")
            return
        }
        
        Task { @MainActor in
            UIAlertTemplate.showAlert(
                owner: currentTopViewController,
                title: BundleUtil.localizedString(forKey: groupCallError.alertTitleKey),
                message: BundleUtil.localizedString(forKey: groupCallError.alertMessageKey)
            )
        }
    }
    
    @MainActor
    func showGroupCallFullAlert(maxParticipants: Int?, onOK: @escaping () -> Void) {
        let title = #localize("group_call_alert_full_title")
        let message =
            if let maxParticipants {
                String.localizedStringWithFormat(#localize("group_call_alert_full_message_count"), maxParticipants)
            }
            else {
                #localize("group_call_alert_full_message")
            }
        
        Task { @MainActor in
            guard let currentTopViewController = SharedAppProvider.currentTopViewController else {
                DDLogError("`SharedAppProvider.currentTopViewController` not available.")
                return
            }
            
            UIAlertTemplate.showAlert(
                owner: currentTopViewController,
                title: title,
                message: message
            ) { _ in
                onOK()
            }
        }
    }
    
    func newBannerForStartGroupCall(
        conversationManagedObjectID: NSManagedObjectID,
        title: String,
        body: String,
        identifier: String
    ) {
        // No toast if disabled or passcode showing
        if !UserSettings.shared().inAppPreview ||
            isAppLocked {
            return
        }
        
        let businessInjector = BusinessInjector.ui

        if !businessInjector.pushSettingManager.canMasterDndSendPush() {
            return
        }
        
        guard businessInjector.entityManager.performAndWait({
            if let conversation = businessInjector.entityManager.entityFetcher
                .managedObject(with: conversationManagedObjectID) as? ConversationEntity {
                if let group = businessInjector.groupManager.getGroup(conversation: conversation) {
                    // We show a notification anyways when notify when mentioned is set to true
                    if !group.pushSetting.mentioned, !group.pushSetting.canSendPush() {
                        return false
                    }
                }
            }

            return true
        }) else {
            return
        }

        // Is this for the currently visible conversation?
        Task { @MainActor in
            if let mainTabBar = SharedAppProvider.tabBarController,
               let viewControllers = mainTabBar.viewControllers {
                if viewControllers.count <= kChatTabBarIndex {
                    return
                }
                let chatNavVc = viewControllers[Int(kChatTabBarIndex)] as! UINavigationController
                if let curChatVc = chatNavVc.topViewController as? ChatViewController,
                   curChatVc.conversation.objectID == conversationManagedObjectID {
                    if UIAccessibility.isVoiceOverRunning,
                       !curChatVc.isRecording(),
                       !curChatVc.isPlayingAudioMessage() {
                        let accessibilityText =
                            "\(#localize("new_message_accessibility"))\(body)"
                        UIAccessibility.post(notification: .announcement, argument: accessibilityText)
                    }
                    return
                }
            }
            NotificationBannerHelper.newBannerForStartGroupCall(
                conversationManagedObjectID: conversationManagedObjectID,
                title: title,
                body: body,
                identifier: identifier
            )
        }
    }
}
