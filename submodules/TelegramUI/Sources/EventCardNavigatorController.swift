import Foundation
import UIKit
import EventKit
import AccountContext
import SwiftSignalKit
import Postbox
import TelegramCore

// MARK: - Vote models

struct TGVoteEntry: Codable {
    let userId: Int64
    let displayName: String
    let vote: String
    let date: Date
}

// MARK: - Initials avatar

private final class InitialsAvatarView: UIView {
    private let label = UILabel()

    override init(frame: CGRect) {
        super.init(frame: frame)
        clipsToBounds = true
        label.textAlignment = .center
        label.textColor = .white
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)
        NSLayoutConstraint.activate([
            label.centerXAnchor.constraint(equalTo: centerXAnchor),
            label.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }

    required init?(coder: NSCoder) { fatalError() }

    override func layoutSubviews() {
        super.layoutSubviews()
        layer.cornerRadius = bounds.width / 2
        label.font = .systemFont(ofSize: bounds.width * 0.4, weight: .medium)
    }

    func configure(name: String) {
        label.text = name.first.map { String($0).uppercased() } ?? "?"
        let palette: [UIColor] = [.systemBlue, .systemGreen, .systemPurple, .systemOrange, .systemPink, .systemTeal]
        backgroundColor = palette[abs(name.hashValue) % palette.count]
    }
}

// MARK: - Participant cell

private final class ParticipantCell: UITableViewCell {
    private let avatarView = InitialsAvatarView(frame: .zero)
    private let nameLabel = UILabel()
    private let badgeLabel = UILabel()

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        selectionStyle = .none

        nameLabel.font = .systemFont(ofSize: 16)
        nameLabel.textColor = .label

        badgeLabel.font = .systemFont(ofSize: 13)
        badgeLabel.textColor = .secondaryLabel
        badgeLabel.setContentCompressionResistancePriority(.required, for: .horizontal)

        for v in [avatarView, nameLabel, badgeLabel] as [UIView] {
            v.translatesAutoresizingMaskIntoConstraints = false
            contentView.addSubview(v)
        }

        NSLayoutConstraint.activate([
            avatarView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            avatarView.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            avatarView.widthAnchor.constraint(equalToConstant: 36),
            avatarView.heightAnchor.constraint(equalToConstant: 36),

            nameLabel.leadingAnchor.constraint(equalTo: avatarView.trailingAnchor, constant: 12),
            nameLabel.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),

            badgeLabel.leadingAnchor.constraint(greaterThanOrEqualTo: nameLabel.trailingAnchor, constant: 8),
            badgeLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
            badgeLabel.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
        ])
    }

    required init?(coder: NSCoder) { fatalError() }

    func configure(name: String, badge: String?) {
        avatarView.configure(name: name)
        nameLabel.text = name
        badgeLabel.text = badge
        badgeLabel.isHidden = badge == nil
    }
}

// MARK: - Info cell (icon + header label + value + optional green action link)

private final class InfoCell: UITableViewCell {
    private let iconView = UIImageView()
    private let headerLabel = UILabel()
    private let valueLabel = UILabel()
    private let actionsStack = UIStackView()
    private let primaryButton = UIButton(type: .system)
    private let secondaryButton = UIButton(type: .system)
    private var bottomToValue: NSLayoutConstraint!
    private var bottomToActions: NSLayoutConstraint!
    var onAction: (() -> Void)?
    var onSecondaryAction: (() -> Void)?

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        selectionStyle = .none

        let green = UIColor(red: 0.07, green: 0.49, blue: 0.15, alpha: 1)

        iconView.contentMode = .scaleAspectFit
        iconView.tintColor = .secondaryLabel

        headerLabel.font = .systemFont(ofSize: 13)
        headerLabel.textColor = .secondaryLabel

        valueLabel.font = .systemFont(ofSize: 16)
        valueLabel.textColor = .label
        valueLabel.numberOfLines = 2

        primaryButton.titleLabel?.font = .systemFont(ofSize: 14)
        primaryButton.tintColor = green
        primaryButton.contentHorizontalAlignment = .left
        primaryButton.addTarget(self, action: #selector(primaryTapped), for: .touchUpInside)

        secondaryButton.titleLabel?.font = .systemFont(ofSize: 14)
        secondaryButton.tintColor = .secondaryLabel
        secondaryButton.contentHorizontalAlignment = .left
        secondaryButton.addTarget(self, action: #selector(secondaryTapped), for: .touchUpInside)

        actionsStack.axis = .horizontal
        actionsStack.spacing = 16
        actionsStack.alignment = .leading
        actionsStack.addArrangedSubview(primaryButton)
        actionsStack.addArrangedSubview(secondaryButton)

        for v in [iconView, headerLabel, valueLabel, actionsStack] as [UIView] {
            v.translatesAutoresizingMaskIntoConstraints = false
            contentView.addSubview(v)
        }

        bottomToValue   = contentView.bottomAnchor.constraint(equalTo: valueLabel.bottomAnchor, constant: 14)
        bottomToActions = contentView.bottomAnchor.constraint(equalTo: actionsStack.bottomAnchor, constant: 14)

        NSLayoutConstraint.activate([
            iconView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            iconView.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 14),
            iconView.widthAnchor.constraint(equalToConstant: 20),
            iconView.heightAnchor.constraint(equalToConstant: 20),

            headerLabel.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 12),
            headerLabel.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: 10),
            headerLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),

            valueLabel.topAnchor.constraint(equalTo: headerLabel.bottomAnchor, constant: 3),
            valueLabel.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: 10),
            valueLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),

            actionsStack.topAnchor.constraint(equalTo: valueLabel.bottomAnchor, constant: 4),
            actionsStack.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: 8),
            actionsStack.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
        ])
    }

    required init?(coder: NSCoder) { fatalError() }

    func configure(icon: String, header: String, value: String, actionTitle: String?, secondaryActionTitle: String? = nil) {
        iconView.image = UIImage(systemName: icon)
        headerLabel.text = header
        valueLabel.text = value
        let hasActions = actionTitle != nil || secondaryActionTitle != nil
        if hasActions {
            primaryButton.setTitle(actionTitle, for: .normal)
            primaryButton.isHidden = actionTitle == nil
            secondaryButton.setTitle(secondaryActionTitle, for: .normal)
            secondaryButton.isHidden = secondaryActionTitle == nil
            actionsStack.isHidden = false
            bottomToValue.isActive = false
            bottomToActions.isActive = true
        } else {
            actionsStack.isHidden = true
            bottomToActions.isActive = false
            bottomToValue.isActive = true
        }
    }

    @objc private func primaryTapped() { onAction?() }
    @objc private func secondaryTapped() { onSecondaryAction?() }
}

// MARK: - EventCardNavigatorController

public final class EventCardNavigatorController: UIViewController {
    private let chatId: Int64
    private let context: AccountContext
    private var events: [TGEvent] = []
    private var scanDisposable: Disposable?
    private var currentUserId: Int64 = 0
    private var currentUserName: String = "Вы"
    private var initialEventId: String?

    private let tableView = UITableView(frame: .zero, style: .insetGrouped)
    private let goingButton = UIButton(type: .system)
    private let emptyLabel = UILabel()

    private var currentEvent: TGEvent? { events.first }

    public init(chatId: Int64, context: AccountContext, initialEventId: String? = nil) {
        self.chatId = chatId
        self.context = context
        self.initialEventId = initialEventId
        super.init(nibName: nil, bundle: nil)
    }
    required init?(coder: NSCoder) { fatalError() }

    deinit { scanDisposable?.dispose() }

    public override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemGroupedBackground
        title = "Мероприятие"

        navigationItem.leftBarButtonItem = UIBarButtonItem(
            image: UIImage(systemName: "xmark"), style: .plain,
            target: self, action: #selector(closeTapped))
        navigationItem.leftBarButtonItem?.tintColor = .secondaryLabel

        let editButton = UIBarButtonItem(title: "Изменить", style: .plain,
            target: self, action: #selector(editTapped))
        editButton.tintColor = UIColor(red: 0.07, green: 0.49, blue: 0.15, alpha: 1)
        navigationItem.rightBarButtonItem = editButton

        setupTableView()
        setupGoingButton()
        setupEmptyLabel()
        loadCurrentUser()
        reload()
        scanMessageHistory()
    }

    public override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        reload()
    }

    // MARK: - Setup

    private func setupTableView() {
        tableView.dataSource = self
        tableView.delegate = self
        tableView.register(InfoCell.self, forCellReuseIdentifier: "info")
        tableView.register(ParticipantCell.self, forCellReuseIdentifier: "participant")
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "basic")
        tableView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(tableView)
        NSLayoutConstraint.activate([
            tableView.topAnchor.constraint(equalTo: view.topAnchor),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
    }

    private func setupGoingButton() {
        goingButton.titleLabel?.font = .systemFont(ofSize: 17, weight: .semibold)
        goingButton.backgroundColor = UIColor(red: 0.07, green: 0.49, blue: 0.15, alpha: 1)
        goingButton.setTitleColor(.white, for: .normal)
        goingButton.layer.cornerRadius = 14
        goingButton.addTarget(self, action: #selector(goingTapped), for: .touchUpInside)
        goingButton.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(goingButton)
        NSLayoutConstraint.activate([
            goingButton.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            goingButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            goingButton.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -12),
            goingButton.heightAnchor.constraint(equalToConstant: 52),
        ])
        tableView.contentInset.bottom = 80
    }

    private func setupEmptyLabel() {
        emptyLabel.text = "Нет событий в этом чате"
        emptyLabel.font = .systemFont(ofSize: 17)
        emptyLabel.textColor = .secondaryLabel
        emptyLabel.textAlignment = .center
        emptyLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(emptyLabel)
        NSLayoutConstraint.activate([
            emptyLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            emptyLabel.centerYAnchor.constraint(equalTo: view.centerYAnchor),
        ])
    }

    // MARK: - Data

    private func loadCurrentUser() {
        let accountPeerId = context.account.peerId
        let _ = (context.account.postbox.transaction { transaction -> (Int64, String) in
            let userId = accountPeerId.toInt64()
            if let user = transaction.getPeer(accountPeerId) as? TelegramUser {
                let name = [user.firstName, user.lastName].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " ")
                return (userId, name.isEmpty ? "Пользователь" : name)
            }
            return (userId, "Пользователь")
        } |> deliverOnMainQueue).startStandalone { [weak self] (userId, name) in
            self?.currentUserId = userId
            self?.currentUserName = name
            self?.refreshEditButton()
        }
    }

    private func refreshEditButton() {
        guard let event = currentEvent else {
            navigationItem.rightBarButtonItem = nil
            return
        }
        // Show "Изменить" only to the creator; nil creatorId = legacy event (treat as own)
        let isCreator = event.creatorId == nil || event.creatorId == currentUserId
        if isCreator {
            if navigationItem.rightBarButtonItem == nil {
                let editButton = UIBarButtonItem(title: "Изменить", style: .plain,
                    target: self, action: #selector(editTapped))
                editButton.tintColor = UIColor(red: 0.07, green: 0.49, blue: 0.15, alpha: 1)
                navigationItem.rightBarButtonItem = editButton
            }
        } else {
            navigationItem.rightBarButtonItem = nil
        }
    }

    private func reload() {
        let all = TGEventPersistence.loadEvents()
        var sorted = all.filter { $0.chatId == chatId }.sorted { $0.startDate > $1.startDate }
        if let targetId = initialEventId,
           let idx = sorted.firstIndex(where: { $0.id.uuidString == targetId }) {
            let target = sorted.remove(at: idx)
            sorted.insert(target, at: 0)
        }
        events = sorted
        let hasEvents = !events.isEmpty
        tableView.isHidden = !hasEvents
        goingButton.isHidden = !hasEvents
        emptyLabel.isHidden = hasEvents
        guard hasEvents else { return }
        rebuildTitleHeader()
        refreshGoingButton()
        refreshEditButton()
        tableView.reloadData()
    }

    private func rebuildTitleHeader() {
        guard let event = currentEvent else { return }
        let label = UILabel()
        label.text = event.title
        label.font = .systemFont(ofSize: 28, weight: .bold)
        label.textColor = .label
        label.numberOfLines = 0
        label.translatesAutoresizingMaskIntoConstraints = false

        let header = UIView()
        header.addSubview(label)
        NSLayoutConstraint.activate([
            label.topAnchor.constraint(equalTo: header.topAnchor, constant: 8),
            label.bottomAnchor.constraint(equalTo: header.bottomAnchor, constant: -16),
            label.leadingAnchor.constraint(equalTo: header.leadingAnchor, constant: 20),
            label.trailingAnchor.constraint(equalTo: header.trailingAnchor, constant: -20),
        ])

        let width = tableView.bounds.width > 0 ? tableView.bounds.width : UIScreen.main.bounds.width
        let size = header.systemLayoutSizeFitting(
            CGSize(width: width, height: UIView.layoutFittingCompressedSize.height),
            withHorizontalFittingPriority: .required,
            verticalFittingPriority: .fittingSizeLevel)
        header.frame = CGRect(x: 0, y: 0, width: width, height: size.height)
        tableView.tableHeaderView = header
    }

    private func refreshGoingButton() {
        guard let event = currentEvent else { return }
        let myVote = TGEventPersistence.loadVotesV1()[event.id.uuidString]
        switch myVote {
        case "yes":
            goingButton.setTitle("Пойду  ∨", for: .normal)
            goingButton.backgroundColor = UIColor(red: 0.07, green: 0.49, blue: 0.15, alpha: 1)
        case "no":
            goingButton.setTitle("Не иду  ∨", for: .normal)
            goingButton.backgroundColor = .systemGray
        default:
            goingButton.setTitle("Пойду  ∨", for: .normal)
            goingButton.backgroundColor = UIColor(red: 0.07, green: 0.49, blue: 0.15, alpha: 1)
        }
    }

    // MARK: - Section model

    private enum Section { case dateTime, address, reminder, going, notResponded }

    private var computedSections: [Section] {
        var s: [Section] = [.dateTime]
        if !(currentEvent?.location ?? "").isEmpty { s.append(.address) }
        s.append(.reminder)
        s.append(.going)
        if !notRespondedNames.isEmpty { s.append(.notResponded) }
        return s
    }

    private var goingEntries: [TGVoteEntry] {
        guard let event = currentEvent else { return [] }
        return (TGEventPersistence.loadVotesV2()[event.id.uuidString] ?? [])
            .filter { $0.vote == "yes" }.sorted { $0.date < $1.date }
    }

    private var notRespondedNames: [String] {
        guard let event = currentEvent else { return [] }
        let allEntries = TGEventPersistence.loadVotesV2()[event.id.uuidString] ?? []
        let respondedNames = Set(allEntries.map { $0.displayName.lowercased().trimmingCharacters(in: .whitespaces) })
        let currentUserVoted = allEntries.contains { $0.userId == currentUserId }
        let currentNameNorm = currentUserName.lowercased().trimmingCharacters(in: .whitespaces)
        return event.participants.filter { participant in
            let norm = participant.lowercased().trimmingCharacters(in: .whitespaces)
            if respondedNames.contains(norm) { return false }
            if currentUserVoted && norm == currentNameNorm { return false }
            return true
        }
    }

    // MARK: - Actions

    private func addEventToSystemCalendar(_ event: TGEvent) {
        let confirmAlert = UIAlertController(title: "Добавить в Календарь", message: event.title, preferredStyle: .alert)
        confirmAlert.addAction(UIAlertAction(title: "Отмена", style: .cancel))
        confirmAlert.addAction(UIAlertAction(title: "Добавить", style: .default) { [weak self] _ in
            guard let self else { return }
            let store = EKEventStore()
            let doAdd: () -> Void = { [weak self, store] in
                let endDate = event.endDate > event.startDate ? event.endDate : Calendar.current.date(byAdding: .hour, value: 1, to: event.startDate) ?? event.startDate
                let predicate = store.predicateForEvents(withStart: event.startDate, end: endDate, calendars: nil)
                let existing = store.events(matching: predicate)
                let alreadyAdded = existing.contains { $0.title == event.title && abs($0.startDate.timeIntervalSince(event.startDate)) < 1 }
                DispatchQueue.main.async {
                    guard let self else { return }
                    if alreadyAdded {
                        let alert = UIAlertController(title: "Уже в Календаре", message: event.title, preferredStyle: .alert)
                        alert.addAction(UIAlertAction(title: "OK", style: .default))
                        self.present(alert, animated: true)
                        return
                    }
                    let ekEvent = EKEvent(eventStore: store)
                    ekEvent.title = event.title
                    ekEvent.startDate = event.startDate
                    ekEvent.endDate = endDate
                    if let loc = event.location { ekEvent.location = loc }
                    ekEvent.calendar = store.defaultCalendarForNewEvents
                    try? store.save(ekEvent, span: .thisEvent, commit: true)
                    let doneAlert = UIAlertController(title: "Добавлено в Календарь", message: event.title, preferredStyle: .alert)
                    doneAlert.addAction(UIAlertAction(title: "OK", style: .default))
                    self.present(doneAlert, animated: true)
                }
            }
            if #available(iOS 17.0, *) {
                store.requestWriteOnlyAccessToEvents { granted, _ in if granted { doAdd() } }
            } else {
                store.requestAccess(to: .event) { granted, _ in if granted { doAdd() } }
            }
        })
        present(confirmAlert, animated: true)
    }

    @objc private func closeTapped() { dismiss(animated: true) }

    @objc private func editTapped() {
        guard let event = currentEvent else { return }
        let editVC = CreateEventController(context: context, editingEvent: event)
        editVC.onSave = { [weak self] _ in self?.reload() }
        navigationController?.pushViewController(editVC, animated: true)
    }

    @objc private func goingTapped() {
        guard let event = currentEvent else { return }
        let myVote = TGEventPersistence.loadVotesV1()[event.id.uuidString]

        let sheet = UIAlertController(title: nil, message: nil, preferredStyle: .actionSheet)
        let goAction = UIAlertAction(title: "Пойду", style: .default) { [weak self] _ in
            self?.castVote("yes", for: event)
        }
        if myVote == "yes" { goAction.setValue(true, forKey: "checked") }
        sheet.addAction(goAction)

        let noAction = UIAlertAction(title: "Не иду", style: .default) { [weak self] _ in
            self?.castVote("no", for: event)
        }
        if myVote == "no" { noAction.setValue(true, forKey: "checked") }
        sheet.addAction(noAction)

        sheet.addAction(UIAlertAction(title: "Отмена", style: .cancel))
        present(sheet, animated: true)
    }

    private func castVote(_ answer: String, for event: TGEvent) {
        let key = event.id.uuidString
        var votes = TGEventPersistence.loadVotesV1()
        let prev = votes[key]
        votes[key] = (prev == answer) ? nil : answer
        TGEventPersistence.saveVotesV1(votes)

        var votesV2 = TGEventPersistence.loadVotesV2()
        var entries = votesV2[key] ?? []
        entries.removeAll { $0.userId == currentUserId }
        if prev != answer {
            entries.append(TGVoteEntry(
                userId: currentUserId, displayName: currentUserName,
                vote: answer, date: Date()))
        }
        votesV2[key] = entries
        TGEventPersistence.saveVotesV2(votesV2)

        if answer == "yes", prev != "yes" { copyEventToPersonal(event) }
        NotificationCenter.default.post(name: NSNotification.Name("tgEventVoteChanged"), object: nil)
        reload()
    }

    private func copyEventToPersonal(_ event: TGEvent) {
        var stored = TGEventPersistence.loadEvents()
        guard !stored.contains(where: { $0.chatId == nil && $0.title == event.title && $0.startDate == event.startDate }) else { return }
        stored.append(TGEvent(id: UUID(), title: event.title, startDate: event.startDate, endDate: event.endDate,
                              participants: event.participants, location: event.location, chatId: nil))
        TGEventPersistence.saveEvents(stored)
    }

    // MARK: - Message scan

    private func scanMessageHistory() {
        let chatId = self.chatId
        // chatId stored as peerId.toInt64() — use PeerId(Int64) to reconstruct correctly.
        // Also try legacy format where chatId stored only the raw id without namespace.
        let packedPeerId  = PeerId(chatId)
        let groupPeerId   = PeerId(namespace: Namespaces.Peer.CloudGroup,   id: PeerId.Id._internalFromInt64Value(chatId))
        let channelPeerId = PeerId(namespace: Namespaces.Peer.CloudChannel, id: PeerId.Id._internalFromInt64Value(chatId))
        let userPeerId    = PeerId(namespace: Namespaces.Peer.CloudUser,    id: PeerId.Id._internalFromInt64Value(chatId))

        scanDisposable = (context.account.postbox.transaction { transaction -> [TGEvent] in
            var resolvedPeerId: PeerId?
            for candidate in [packedPeerId, groupPeerId, channelPeerId, userPeerId] {
                if transaction.getPeer(candidate) != nil { resolvedPeerId = candidate; break }
            }
            var dbg = "chatId=\(chatId) packed=\(packedPeerId) resolved=\(String(describing: resolvedPeerId))\n"
            guard let peerId = resolvedPeerId else {
                Self.writeDebug(dbg + "NO PEER FOUND\n")
                return []
            }
            let view = transaction.getMessagesHistoryViewState(
                input: .single(peerId: peerId, threadId: nil),
                ignoreMessagesInTimestampRange: nil, ignoreMessageIds: Set(),
                count: 200, clipHoles: true, anchor: .upperBound,
                namespaces: .just(Set([Namespaces.Message.Cloud])))
            dbg += "entries=\(view.entries.count)\n"
            var found: [TGEvent] = []
            for entry in view.entries {
                if let attr = entry.message.attributes.first(where: { $0 is TGEventAttribute }) as? TGEventAttribute,
                   let uuid = UUID(uuidString: attr.eventId) {
                    dbg += "attr: \(attr.title)\n"
                    found.append(TGEvent(id: uuid, title: attr.title,
                        startDate: Date(timeIntervalSince1970: attr.startTimestamp),
                        endDate: Date(timeIntervalSince1970: attr.endTimestamp),
                        participants: [], location: attr.location, chatId: chatId))
                    continue
                }
                let text = entry.message.text
                guard let start = text.range(of: "[TGE:"),
                      let end = text.range(of: "]", range: start.upperBound..<text.endIndex) else { continue }
                struct LegacyMarker: Decodable { let i: String; let t: String; let s: Double; let e: Double; let l: String? }
                let jsonStr = String(text[start.upperBound..<end.lowerBound])
                guard let data = jsonStr.data(using: .utf8),
                      let m = try? JSONDecoder().decode(LegacyMarker.self, from: data),
                      let uuid = UUID(uuidString: m.i) else { continue }
                dbg += "legacy: \(m.t)\n"
                found.append(TGEvent(id: uuid, title: m.t,
                    startDate: Date(timeIntervalSince1970: m.s), endDate: Date(timeIntervalSince1970: m.e),
                    participants: [], location: m.l, chatId: chatId))
            }
            dbg += "found=\(found.count)\n"
            Self.writeDebug(dbg)
            return found
        } |> deliverOnMainQueue).startStandalone { [weak self] discovered in
            guard let self, !discovered.isEmpty else { return }
            var stored = TGEventPersistence.loadEvents()
            let existingIds = Set(stored.map { $0.id })
            let newEvents = discovered.filter { !existingIds.contains($0.id) }
            guard !newEvents.isEmpty else { return }
            stored.append(contentsOf: newEvents)
            TGEventPersistence.saveEvents(stored)
            self.reload()
        }
    }

    private static func writeDebug(_ text: String) {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let url = docs.appendingPathComponent("tgevent_scan_debug.txt")
        let existing = (try? String(contentsOf: url)) ?? ""
        try? (existing + text).write(to: url, atomically: true, encoding: .utf8)
    }
}

// MARK: - UITableViewDataSource

extension EventCardNavigatorController: UITableViewDataSource {
    public func numberOfSections(in tableView: UITableView) -> Int {
        computedSections.count
    }

    public func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        guard section < computedSections.count else { return 0 }
        switch computedSections[section] {
        case .dateTime, .address, .reminder: return 1
        case .going: return max(1, goingEntries.count)
        case .notResponded: return notRespondedNames.count
        }
    }

    public func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        guard indexPath.section < computedSections.count, let event = currentEvent else {
            return UITableViewCell()
        }
        switch computedSections[indexPath.section] {
        case .dateTime:
            let cell = tableView.dequeueReusableCell(withIdentifier: "info", for: indexPath) as! InfoCell
            let df = DateFormatter()
            df.locale = Locale(identifier: "ru_RU")
            df.dateFormat = "EEE, d MMMM · HH:mm"
            var dateStr = df.string(from: event.startDate)
            if let first = dateStr.first { dateStr = first.uppercased() + dateStr.dropFirst() }
            cell.configure(icon: "calendar", header: "Дата и время", value: dateStr, actionTitle: "Добавить в календарь")
            cell.onAction = { [weak self] in self?.addEventToSystemCalendar(event) }
            return cell

        case .address:
            let cell = tableView.dequeueReusableCell(withIdentifier: "info", for: indexPath) as! InfoCell
            cell.configure(icon: "mappin", header: "Адрес", value: event.location ?? "",
                           actionTitle: "Маршрут", secondaryActionTitle: "Копировать")
            cell.onAction = {
                let loc = event.location ?? ""
                let encoded = loc.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
                var urlStr: String
                if let lat = event.locationLatitude, let lon = event.locationLongitude {
                    urlStr = "maps://?ll=\(lat),\(lon)&q=\(encoded)"
                } else {
                    urlStr = "maps://?q=\(encoded)"
                }
                if let url = URL(string: urlStr) { UIApplication.shared.open(url) }
            }
            cell.onSecondaryAction = { UIPasteboard.general.string = event.location }
            return cell

        case .reminder:
            let cell = tableView.dequeueReusableCell(withIdentifier: "info", for: indexPath) as! InfoCell
            cell.configure(icon: "bell", header: "Напоминание", value: reminderLabel(for: event.reminderMinutes), actionTitle: nil)
            return cell

        case .going:
            let entries = goingEntries
            if entries.isEmpty {
                let cell = tableView.dequeueReusableCell(withIdentifier: "basic", for: indexPath)
                cell.textLabel?.text = "Пока никто не ответил"
                cell.textLabel?.textColor = .tertiaryLabel
                cell.textLabel?.font = .systemFont(ofSize: 15)
                cell.selectionStyle = .none
                return cell
            }
            let cell = tableView.dequeueReusableCell(withIdentifier: "participant", for: indexPath) as! ParticipantCell
            let entry = entries[indexPath.row]
            let creatorId = event.creatorId ?? currentUserId
            cell.configure(name: entry.displayName, badge: entry.userId == creatorId ? "Организатор" : nil)
            return cell

        case .notResponded:
            let cell = tableView.dequeueReusableCell(withIdentifier: "participant", for: indexPath) as! ParticipantCell
            cell.configure(name: notRespondedNames[indexPath.row], badge: nil)
            return cell
        }
    }

    public func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        guard section < computedSections.count else { return nil }
        switch computedSections[section] {
        case .going:
            let n = goingEntries.count
            return "Пойдут   \(n) \(participantWord(n))"
        case .notResponded:
            let n = notRespondedNames.count
            return "Не ответили   \(n) \(participantWord(n))"
        default:
            return nil
        }
    }

    private func participantWord(_ n: Int) -> String {
        let mod10 = n % 10, mod100 = n % 100
        if mod10 == 1 && mod100 != 11 { return "участник" }
        if (2...4).contains(mod10) && !(12...14).contains(mod100) { return "участника" }
        return "участников"
    }

    private func reminderLabel(for minutes: Int?) -> String {
        switch minutes {
        case nil:     return "Нет"
        case 15:      return "За 15 минут"
        case 30:      return "За 30 минут"
        case 60:      return "За 1 час"
        case 24 * 60: return "За 1 день"
        default:      return "Нет"
        }
    }
}

// MARK: - UITableViewDelegate

extension EventCardNavigatorController: UITableViewDelegate {
    public func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        guard indexPath.section < computedSections.count else { return 44 }
        switch computedSections[indexPath.section] {
        case .dateTime, .address, .reminder: return UITableView.automaticDimension
        case .going, .notResponded: return 54
        }
    }

    public func tableView(_ tableView: UITableView, estimatedHeightForRowAt indexPath: IndexPath) -> CGFloat { 70 }
}
