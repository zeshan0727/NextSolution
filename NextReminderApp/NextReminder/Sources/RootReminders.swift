import Foundation
import SwiftUI
import Combine
import UserNotifications
import UIKit

// MARK: - RootView
enum AppTab: Hashable {
    case reminders
    case calendar
    case add
    case completed
    case settings
}

struct RootView: View {
    @State private var selectedTab: AppTab = .reminders
    @State private var lastRegularTab: AppTab = .reminders
    @State private var isAddingReminder = false

    var body: some View {
        TabView(selection: $selectedTab) {
            NavigationStack {
                RemindersView()
            }
            .tabItem { Label("Reminders", systemImage: "bell.badge.fill") }
            .tag(AppTab.reminders)

            NavigationStack {
                CalendarRemindersView()
            }
            .tabItem { Label("Calendar", systemImage: "calendar") }
            .tag(AppTab.calendar)

            Color.clear
                .tabItem { Label("Add", systemImage: "plus.circle.fill") }
                .tag(AppTab.add)

            NavigationStack {
                CompletedRemindersView()
            }
            .tabItem { Label("Completed", systemImage: "checkmark.circle.fill") }
            .tag(AppTab.completed)

            NavigationStack {
                SettingsView()
            }
            .tabItem { Label("Settings", systemImage: "gearshape.fill") }
            .tag(AppTab.settings)
        }
        .onChange(of: selectedTab) { newValue in
            if newValue == .add {
                isAddingReminder = true
                selectedTab = lastRegularTab
            } else {
                lastRegularTab = newValue
            }
        }
        .sheet(isPresented: $isAddingReminder) {
            NavigationStack {
                ReminderEditorView(reminder: nil)
            }
        }
    }
}

// MARK: - RemindersView
enum QuickReminderFilter: String, CaseIterable, Identifiable {
    case all
    case today
    case upcoming
    case overdue

    var id: String { rawValue }
    var title: String { rawValue.capitalized }
}

struct RemindersView: View {
    @EnvironmentObject private var store: ReminderStore
    @State private var searchText = ""
    @State private var quickFilter: QuickReminderFilter = .all
    @State private var selectedCategoryID: UUID?
    @State private var isShowingFilters = false
    @State private var selectedPriorities: Set<ReminderPriority> = []
    @State private var advancedCategoryIDs: Set<UUID> = []

    private var filteredReminders: [ReminderItem] {
        store.pendingReminders.filter { reminder in
            let matchesSearch = searchText.isEmpty
                || reminder.title.localizedCaseInsensitiveContains(searchText)
                || reminder.notes.localizedCaseInsensitiveContains(searchText)
            let matchesQuick: Bool
            switch quickFilter {
            case .all:
                matchesQuick = true
            case .today:
                matchesQuick = Calendar.current.isDateInToday(reminder.dueDate)
            case .upcoming:
                matchesQuick = reminder.dueDate > Date() && !Calendar.current.isDateInToday(reminder.dueDate)
            case .overdue:
                matchesQuick = reminder.isOverdue
            }
            let matchesCategory = selectedCategoryID == nil || reminder.categoryID == selectedCategoryID
            let matchesAdvancedCategory = advancedCategoryIDs.isEmpty || advancedCategoryIDs.contains(reminder.categoryID)
            let matchesPriority = selectedPriorities.isEmpty || selectedPriorities.contains(reminder.priority)
            return matchesSearch && matchesQuick && matchesCategory && matchesAdvancedCategory && matchesPriority
        }
    }

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 14) {
                header
                quickFilters
                categoryFilters

                if filteredReminders.isEmpty {
                    EmptyStateView(
                        icon: "bell.slash.fill",
                        title: "No reminders found",
                        message: "Add a new reminder or change the active filters."
                    )
                } else {
                    ForEach(filteredReminders) { reminder in
                        NavigationLink(value: reminder.id) {
                            ReminderCard(reminder: reminder, category: store.category(for: reminder.categoryID))
                        }
                        .buttonStyle(.plain)
                        .contextMenu {
                            Button {
                                store.complete(reminder, comment: "")
                            } label: {
                                Label("Complete", systemImage: "checkmark.circle")
                            }
                            Button(role: .destructive) {
                                store.delete(reminder)
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 24)
        }
        .background(Color.nextBackground.ignoresSafeArea())
        .navigationTitle("Next Reminder")
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $searchText, prompt: "Search reminders")
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                NavigationLink {
                    CategoryManagementView()
                } label: {
                    Image(systemName: "line.3.horizontal.decrease.circle")
                }
                .accessibilityLabel("Manage filters")
            }
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    isShowingFilters = true
                } label: {
                    Image(systemName: "slider.horizontal.3")
                }
                .accessibilityLabel("Advanced filters")
            }
        }
        .navigationDestination(for: UUID.self) { id in
            if let reminder = store.reminders.first(where: { $0.id == id }) {
                ReminderDetailView(reminderID: reminder.id)
            }
        }
        .sheet(isPresented: $isShowingFilters) {
            FilterView(
                selectedPriorities: $selectedPriorities,
                selectedCategoryIDs: $advancedCategoryIDs
            )
            .environmentObject(store)
        }
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(greeting)
                    .font(.title2.bold())
                Text("\(store.pendingReminders.count) active reminder\(store.pendingReminders.count == 1 ? "" : "s")")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            ZStack {
                Circle()
                    .fill(Color.nextOrange.opacity(0.15))
                Image(systemName: "bell.fill")
                    .foregroundStyle(.nextOrange)
                    .font(.title3)
            }
            .frame(width: 48, height: 48)
        }
        .padding(.top, 8)
    }

    private var greeting: String {
        let hour = Calendar.current.component(.hour, from: Date())
        if hour < 12 { return "Good morning" }
        if hour < 18 { return "Good afternoon" }
        return "Good evening"
    }

    private var quickFilters: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(QuickReminderFilter.allCases) { filter in
                    Button {
                        quickFilter = filter
                    } label: {
                        Text(filter.title)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(quickFilter == filter ? .white : .primary)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 9)
                            .background(
                                Capsule().fill(quickFilter == filter ? Color.nextOrange : Color.nextCard)
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var categoryFilters: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                Button {
                    selectedCategoryID = nil
                } label: {
                    HStack(spacing: 7) {
                        Image(systemName: "square.grid.2x2.fill")
                        Text("All")
                    }
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(selectedCategoryID == nil ? Color.white : Color.primary)
                    .padding(.horizontal, 13)
                    .padding(.vertical, 9)
                    .background(Capsule().fill(selectedCategoryID == nil ? Color.nextOrange : Color.nextCard))
                }
                .buttonStyle(.plain)

                ForEach(store.categories) { category in
                    Button {
                        selectedCategoryID = category.id
                    } label: {
                        CategoryPill(category: category, selected: selectedCategoryID == category.id)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}
