#!/usr/bin/env python3
from pathlib import Path

path = Path(__file__).resolve().parent / "patch_v138.py"
text = path.read_text()
old = '''replace_once(
    root,
    \'\'\'        .confirmationDialog(
            "What would you like to create?",\'\'\',
    \'\'\'        .onReceive(NotificationCenter.default.publisher(for: .nextGmailConnectionInvalidated)) { notification in
            gmailDisconnectAlert = (notification.object as? String)
                ?? GmailConnectionIssueStore.shared.load()?.message
                ?? "Gmail disconnected. Reconnect Gmail to resume automatic sending."
            selectedTab = .settings
        }
        .onReceive(NotificationCenter.default.publisher(for: .nextGmailReconnectRequested)) { _ in
            gmailDisconnectAlert = GmailConnectionIssueStore.shared.load()?.message
                ?? "Gmail disconnected. Reconnect Gmail to resume automatic sending."
            selectedTab = .settings
        }
        .alert("Gmail Disconnected", isPresented: Binding(
            get: { gmailDisconnectAlert != nil },
            set: { if !$0 { gmailDisconnectAlert = nil } }
        )) {
            Button("Open Settings") { selectedTab = .settings }
            Button("Dismiss", role: .cancel) { gmailDisconnectAlert = nil }
        } message: {
            Text("\\(gmailDisconnectAlert ?? \"Gmail connection is unavailable\")\\n\\nOpen Settings → Email Reminder Automations and reconnect Gmail.")
        }
        .confirmationDialog(
            "What would you like to create?",\'\'\'
)'''
new = '''replace_once(
    root,
    \'\'\'        .sheet(item: $openedAutomation) { item in\'\'\',
    \'\'\'        .onReceive(NotificationCenter.default.publisher(for: .nextGmailConnectionInvalidated)) { notification in
            gmailDisconnectAlert = (notification.object as? String)
                ?? GmailConnectionIssueStore.shared.load()?.message
                ?? "Gmail disconnected. Reconnect Gmail to resume automatic sending."
            selectedTab = .settings
        }
        .onReceive(NotificationCenter.default.publisher(for: .nextGmailReconnectRequested)) { _ in
            gmailDisconnectAlert = GmailConnectionIssueStore.shared.load()?.message
                ?? "Gmail disconnected. Reconnect Gmail to resume automatic sending."
            selectedTab = .settings
        }
        .alert("Gmail Disconnected", isPresented: Binding(
            get: { gmailDisconnectAlert != nil },
            set: { if !$0 { gmailDisconnectAlert = nil } }
        )) {
            Button("Open Settings") { selectedTab = .settings }
            Button("Dismiss", role: .cancel) { gmailDisconnectAlert = nil }
        } message: {
            Text("\\(gmailDisconnectAlert ?? \"Gmail connection is unavailable\")\\n\\nOpen Settings → Email Reminder Automations and reconnect Gmail.")
        }
        .sheet(item: $openedAutomation) { item in\'\'\'
)'''
if old not in text:
    raise SystemExit("Could not adjust v1.3.8 RootView integration point")
path.write_text(text.replace(old, new, 1))
print("Adjusted v1.3.8 Gmail alert RootView integration point.")
