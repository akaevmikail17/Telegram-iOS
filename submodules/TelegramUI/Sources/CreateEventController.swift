import Foundation
import UIKit
import Display
import AccountContext
import SwiftSignalKit
import TelegramCore
import TelegramPresentationData
import UserNotifications
import EventKit
import CoreLocation
import LocationUI

// MARK: - Delegate

protocol CreateEventControllerDelegate: AnyObject {
    func createEventController(_ controller: CreateEventController, didCreate event: TGEvent)
    func createEventController(_ controller: CreateEventController, didUpdate event: TGEvent)
}

// MARK: - Text input cell (single line)

private final class TextInputCell: UITableViewCell {
    let textField = UITextField()
    var onTextChange: ((String) -> Void)?

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        selectionStyle = .none
        textField.clearButtonMode = .whileEditing
        textField.returnKeyType = .next
        textField.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(textField)
        NSLayoutConstraint.activate([
            textField.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            textField.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
            textField.topAnchor.constraint(equalTo: contentView.topAnchor),
            textField.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
        ])
        textField.addTarget(self, action: #selector(textChanged), for: .editingChanged)
    }

    required init?(coder: NSCoder) { fatalError() }
    @objc private func textChanged() { onTextChange?(textField.text ?? "") }
}

// MARK: - Multiline text cell (description)

private final class TextViewCell: UITableViewCell, UITextViewDelegate {
    let textView = UITextView()
    private let placeholder = UILabel()
    var onTextChange: ((String) -> Void)?
    var onHeightChange: (() -> Void)?
    private let maxLength = 2048

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        selectionStyle = .none

        textView.font = .systemFont(ofSize: 16)
        textView.isScrollEnabled = false
        textView.backgroundColor = .clear
        textView.textContainerInset = .zero
        textView.textContainer.lineFragmentPadding = 0
        textView.delegate = self
        textView.translatesAutoresizingMaskIntoConstraints = false

        placeholder.text = "Добавьте описание (необязательно)"
        placeholder.font = .systemFont(ofSize: 16)
        placeholder.textColor = .placeholderText
        placeholder.translatesAutoresizingMaskIntoConstraints = false

        contentView.addSubview(textView)
        contentView.addSubview(placeholder)

        NSLayoutConstraint.activate([
            textView.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 10),
            textView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            textView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
            textView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -10),
            textView.heightAnchor.constraint(greaterThanOrEqualToConstant: 64),

            placeholder.topAnchor.constraint(equalTo: textView.topAnchor),
            placeholder.leadingAnchor.constraint(equalTo: textView.leadingAnchor),
            placeholder.trailingAnchor.constraint(equalTo: textView.trailingAnchor),
        ])
    }

    required init?(coder: NSCoder) { fatalError() }

    func textViewDidChange(_ textView: UITextView) {
        placeholder.isHidden = !textView.text.isEmpty
        onTextChange?(textView.text)
        onHeightChange?()
    }

    func textView(_ textView: UITextView, shouldChangeTextIn range: NSRange, replacementText text: String) -> Bool {
        let current = textView.text ?? ""
        guard let r = Range(range, in: current) else { return true }
        return current.replacingCharacters(in: r, with: text).count <= maxLength
    }

    func configure(text: String) {
        textView.text = text
        placeholder.isHidden = !text.isEmpty
    }
}

// MARK: - Date picker cell

private final class DatePickerCell: UITableViewCell {
    let titleLabel = UILabel()
    let picker = UIDatePicker()
    var onValueChange: ((Date) -> Void)?

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        selectionStyle = .none

        titleLabel.font = .systemFont(ofSize: 16)
        titleLabel.setContentHuggingPriority(.defaultLow, for: .horizontal)
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(titleLabel)

        if #available(iOS 13.4, *) { picker.preferredDatePickerStyle = .compact }
        picker.tintColor = UIColor(red: 0.07, green: 0.49, blue: 0.15, alpha: 1)
        picker.setContentHuggingPriority(.defaultHigh, for: .horizontal)
        picker.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(picker)

        NSLayoutConstraint.activate([
            titleLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            titleLabel.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: picker.leadingAnchor, constant: -8),
            picker.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -12),
            picker.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 8),
            picker.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -8),
        ])

        picker.addTarget(self, action: #selector(changed), for: .valueChanged)
    }

    required init?(coder: NSCoder) { fatalError() }

    func configure(title: String, mode: UIDatePicker.Mode, date: Date) {
        titleLabel.text = title
        picker.datePickerMode = mode
        picker.minuteInterval = mode == .time ? 15 : 1
        picker.date = date
    }

    @objc private func changed() { onValueChange?(picker.date) }
}

// MARK: - Toggle cell with optional subtitle

private final class ToggleCell: UITableViewCell {
    let toggle = UISwitch()
    private let subtitleLabel = UILabel()
    var onToggle: ((Bool) -> Void)?

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        selectionStyle = .none

        subtitleLabel.font = .systemFont(ofSize: 13)
        subtitleLabel.textColor = .secondaryLabel
        subtitleLabel.numberOfLines = 0
        subtitleLabel.translatesAutoresizingMaskIntoConstraints = false

        toggle.onTintColor = UIColor(red: 0.07, green: 0.49, blue: 0.15, alpha: 1)
        toggle.translatesAutoresizingMaskIntoConstraints = false
        toggle.addTarget(self, action: #selector(toggled), for: .valueChanged)
    }

    required init?(coder: NSCoder) { fatalError() }

    private var subtitleConstraints: [NSLayoutConstraint] = []

    func configure(title: String, subtitle: String?, isOn: Bool) {
        textLabel?.text = title
        textLabel?.font = .systemFont(ofSize: 16)
        toggle.isOn = isOn

        NSLayoutConstraint.deactivate(subtitleConstraints)
        subtitleConstraints = []
        subtitleLabel.removeFromSuperview()
        toggle.removeFromSuperview()

        if let subtitle = subtitle, !subtitle.isEmpty {
            subtitleLabel.text = subtitle
            contentView.addSubview(toggle)
            contentView.addSubview(subtitleLabel)
            accessoryView = nil

            subtitleConstraints = [
                toggle.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
                toggle.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 12),

                subtitleLabel.topAnchor.constraint(equalTo: toggle.bottomAnchor, constant: 4),
                subtitleLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
                subtitleLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
                subtitleLabel.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -12),
            ]
            NSLayoutConstraint.activate(subtitleConstraints)
        } else {
            toggle.translatesAutoresizingMaskIntoConstraints = true
            accessoryView = toggle
        }
    }

    @objc private func toggled() { onToggle?(toggle.isOn) }
}

// MARK: - Controller

final class CreateEventController: UIViewController {
    weak var delegate: CreateEventControllerDelegate?
    var onSave: ((TGEvent) -> Void)?
    private let context: AccountContext
    private let editingEvent: TGEvent?
    private var pickerDisposable: Disposable?

    private let tableView = UITableView(frame: .zero, style: .insetGrouped)

    // Form state
    private var eventTitle       = ""
    private var eventDescription = ""
    private var eventDate        = Calendar.current.startOfDay(for: Date())
    private var startTime: Date  = {
        var c = Calendar.current.dateComponents([.year, .month, .day], from: Date())
        c.hour = (Calendar.current.component(.hour, from: Date()) + 1) % 24
        c.minute = 0; c.second = 0
        return Calendar.current.date(from: c) ?? Date()
    }()
    private var endTime: Date    = {
        var c = Calendar.current.dateComponents([.year, .month, .day], from: Date())
        c.hour = (Calendar.current.component(.hour, from: Date()) + 2) % 24
        c.minute = 0; c.second = 0
        return Calendar.current.date(from: c) ?? Date()
    }()
    private var showEndTime      = false
    private var participants: [String] = []
    private var reminderMinutes: Int?  = 60
    private var eventLocation          = ""
    private var locationLatitude: Double?
    private var locationLongitude: Double?


    // Section indices
    private enum Sec: Int {
        case titleDesc = 0
        case dateTime  = 1
        case location  = 2
        case reminder  = 3
        case participants = 4
        case danger    = 5
    }

    init(context: AccountContext, editingEvent: TGEvent? = nil, initialParticipants: [String] = []) {
        self.context = context
        self.editingEvent = editingEvent
        if let e = editingEvent {
            eventTitle       = e.title
            eventDescription = e.description ?? ""
            eventDate        = Calendar.current.startOfDay(for: e.startDate)
            startTime        = e.startDate
            endTime          = e.endDate
            showEndTime      = e.startDate != e.endDate
            participants     = e.participants
            reminderMinutes  = e.reminderMinutes
            eventLocation    = e.location ?? ""
            locationLatitude  = e.locationLatitude
            locationLongitude = e.locationLongitude
        } else {
            participants = initialParticipants
        }
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError() }
    deinit { pickerDisposable?.dispose() }

    // MARK: Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        title = editingEvent == nil ? "Новое мероприятие" : "Редактировать меропр..."
        view.backgroundColor = .systemGroupedBackground

        navigationItem.leftBarButtonItem = UIBarButtonItem(
            image: UIImage(systemName: "xmark"), style: .plain,
            target: self, action: #selector(cancelTapped))
        navigationItem.leftBarButtonItem?.tintColor = .secondaryLabel

        navigationItem.rightBarButtonItem = UIBarButtonItem(
            title: "Сохранить", style: .done,
            target: self, action: #selector(saveTapped))
        navigationItem.rightBarButtonItem?.tintColor = UIColor(red: 0.07, green: 0.49, blue: 0.15, alpha: 1)

        tableView.dataSource = self
        tableView.delegate   = self
        tableView.register(TextInputCell.self,    forCellReuseIdentifier: "text")
        tableView.register(TextViewCell.self,     forCellReuseIdentifier: "textView")
        tableView.register(DatePickerCell.self,   forCellReuseIdentifier: "datePicker")
        tableView.register(ToggleCell.self,       forCellReuseIdentifier: "toggle")
        tableView.register(UITableViewCell.self,  forCellReuseIdentifier: "basic")
        tableView.register(LocationInputCell.self, forCellReuseIdentifier: "location")
        tableView.frame = view.bounds
        tableView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(tableView)
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        if let cell = tableView.cellForRow(at: IndexPath(row: 0, section: Sec.titleDesc.rawValue)) as? TextInputCell {
            cell.textField.becomeFirstResponder()
        }
    }

    // MARK: - Actions

    @objc private func cancelTapped() { dismiss(animated: true) }

    @objc private func saveTapped() {
        let title = eventTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else {
            let a = UIAlertController(title: "Введите название", message: nil, preferredStyle: .alert)
            a.addAction(UIAlertAction(title: "OK", style: .default))
            present(a, animated: true); return
        }
        let start = combined(date: eventDate, time: startTime)
        var end   = showEndTime ? combined(date: eventDate, time: endTime) : start
        if showEndTime && end <= start {
            end = Calendar.current.date(byAdding: .hour, value: 1, to: start) ?? end
        }

        var event = TGEvent(id: editingEvent?.id ?? UUID(), title: title, startDate: start, endDate: end,
                            participants: participants,
                            location: eventLocation.isEmpty ? nil : eventLocation)
        event.reminderMinutes  = reminderMinutes
        event.description      = eventDescription.isEmpty ? nil : eventDescription
        event.locationLatitude  = locationLatitude
        event.locationLongitude = locationLongitude
        if let e = editingEvent {
            event.chatId = e.chatId
            event.chatIsGroup = e.chatIsGroup
            event.creatorId = e.creatorId
        } else {
            event.creatorId = context.account.peerId.toInt64()
        }

        var stored = TGEventPersistence.loadEvents()
        if editingEvent != nil {
            stored = stored.map { $0.id == event.id ? event : $0 }
        } else {
            stored.append(event)
        }
        TGEventPersistence.saveEvents(stored)

        // Notify chat bubbles to refresh (covers both direct-edit and EventCardNavigator → Изменить paths)
        NotificationCenter.default.post(
            name: NSNotification.Name("tgEventSaved"),
            object: nil,
            userInfo: ["eventId": event.id.uuidString]
        )

        cancelEventNotification(for: event.id)
        if reminderMinutes != nil {
            UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { [weak self] granted, _ in
                DispatchQueue.main.async {
                    if granted {
                        scheduleEventNotification(for: event)
                    } else {
                        let alert = UIAlertController(
                            title: "Нет разрешения на уведомления",
                            message: "Напоминание не будет работать. Разрешите уведомления в Настройках.",
                            preferredStyle: .alert)
                        alert.addAction(UIAlertAction(title: "Отмена", style: .cancel))
                        alert.addAction(UIAlertAction(title: "Настройки", style: .default) { _ in
                            if let url = URL(string: UIApplication.openSettingsURLString) {
                                UIApplication.shared.open(url)
                            }
                        })
                        self?.present(alert, animated: true)
                    }
                }
            }
        }

        onSave?(event)
        if editingEvent != nil {
            delegate?.createEventController(self, didUpdate: event)
        } else {
            delegate?.createEventController(self, didCreate: event)
        }
        dismiss(animated: true)
    }

    @objc private func cancelEventTapped() {
        guard let event = editingEvent else { return }
        let alert = UIAlertController(
            title: "Отменить мероприятие?",
            message: "Участники получат уведомление.",
            preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "Отменить мероприятие", style: .destructive) { [weak self] _ in
            guard let self else { return }
            var stored = TGEventPersistence.loadEvents()
            stored.removeAll { $0.id == event.id }
            TGEventPersistence.saveEvents(stored)
            cancelEventNotification(for: event.id)
            self.dismiss(animated: true)
        })
        alert.addAction(UIAlertAction(title: "Назад", style: .cancel))
        present(alert, animated: true)
    }

    private func showReminderPicker() {
        let sheet = UIAlertController(title: "Напоминание", message: nil, preferredStyle: .actionSheet)
        let options: [(String, Int?)] = [
            ("Нет", nil), ("За 15 минут", 15), ("За 30 минут", 30),
            ("За 1 час", 60), ("За 1 день", 24 * 60),
        ]
        for (label, value) in options {
            let action = UIAlertAction(title: label, style: .default) { [weak self] _ in
                self?.reminderMinutes = value
                self?.tableView.reloadRows(at: [IndexPath(row: 0, section: Sec.reminder.rawValue)], with: .none)
            }
            if value == reminderMinutes { action.setValue(true, forKey: "checked") }
            sheet.addAction(action)
        }
        sheet.addAction(UIAlertAction(title: "Отмена", style: .cancel))
        present(sheet, animated: true)
    }

    @objc private func addParticipantTapped() {
        let sheet = UIAlertController(title: nil, message: nil, preferredStyle: .actionSheet)
        sheet.addAction(UIAlertAction(title: "Выбрать из контактов", style: .default) { [weak self] _ in
            self?.openContactPicker()
        })
        sheet.addAction(UIAlertAction(title: "Добавить вручную", style: .default) { [weak self] _ in
            self?.addManually()
        })
        sheet.addAction(UIAlertAction(title: "Отмена", style: .cancel))
        present(sheet, animated: true)
    }

    private func openContactPicker() {
        let params = ContactSelectionControllerParams(
            context: context, autoDismiss: false,
            title: { _ in "Участники" },
            displayDeviceContacts: true, multipleSelection: .always)
        let picker = context.sharedContext.makeContactSelectionController(params)
        pickerDisposable?.dispose()
        pickerDisposable = (picker.result |> take(1) |> deliverOnMainQueue).startStrict(next: { [weak self] result in
            guard let self else { return }
            if let (peers, _, _, _, _, _) = result {
                let pd = self.context.sharedContext.currentPresentationData.with { $0 }
                for listPeer in peers {
                    let name: String
                    switch listPeer {
                    case let .peer(enginePeer, _, _):
                        name = enginePeer.displayTitle(strings: pd.strings, displayOrder: pd.nameDisplayOrder)
                    case let .deviceContact(_, contact):
                        name = [contact.firstName, contact.lastName].filter { !$0.isEmpty }.joined(separator: " ")
                    }
                    if !name.isEmpty && !self.participants.contains(name) { self.participants.append(name) }
                }
                self.tableView.reloadSections(IndexSet(integer: Sec.participants.rawValue), with: .automatic)
            }
            self.navigationController?.popViewController(animated: true)
        })
        navigationController?.pushViewController(picker, animated: true)
    }

    private func addManually() {
        let alert = UIAlertController(title: "Добавить участника", message: nil, preferredStyle: .alert)
        alert.addTextField { tf in
            tf.placeholder = "Имя или @username"
            tf.autocapitalizationType = .words
            tf.autocorrectionType = .no
        }
        alert.addAction(UIAlertAction(title: "Добавить", style: .default) { [weak self, weak alert] _ in
            guard let self,
                  let text = alert?.textFields?.first?.text?.trimmingCharacters(in: .whitespaces),
                  !text.isEmpty else { return }
            if text.hasPrefix("@") {
                self.resolveAndAdd(username: String(text.dropFirst()))
            } else {
                self.appendParticipant(text)
            }
        })
        alert.addAction(UIAlertAction(title: "Отмена", style: .cancel))
        present(alert, animated: true)
    }

    private func resolveAndAdd(username: String) {
        let loading = UIAlertController(title: nil, message: "Поиск @\(username)…", preferredStyle: .alert)
        let indicator = UIActivityIndicatorView(style: .medium)
        indicator.startAnimating()
        indicator.translatesAutoresizingMaskIntoConstraints = false
        loading.view.addSubview(indicator)
        NSLayoutConstraint.activate([
            indicator.centerXAnchor.constraint(equalTo: loading.view.centerXAnchor),
            indicator.bottomAnchor.constraint(equalTo: loading.view.bottomAnchor, constant: -16),
        ])
        present(loading, animated: true)
        pickerDisposable?.dispose()
        pickerDisposable = (context.engine.peers.resolvePeerByName(name: username, referrer: nil)
            |> filter { if case .progress = $0 { return false }; return true }
            |> take(1)
            |> timeout(10, queue: Queue.mainQueue(), alternate: .single(.result(nil)))
            |> deliverOnMainQueue).startStandalone(next: { [weak self, weak loading] result in
            guard let self else { return }
            loading?.dismiss(animated: true) {
                if case let .result(peer) = result, let peer = peer {
                    let pd = self.context.sharedContext.currentPresentationData.with { $0 }
                    self.appendParticipant(peer.displayTitle(strings: pd.strings, displayOrder: pd.nameDisplayOrder))
                } else {
                    let err = UIAlertController(title: "Не найдено",
                                                message: "@\(username) не существует или недоступен",
                                                preferredStyle: .alert)
                    err.addAction(UIAlertAction(title: "OK", style: .default))
                    self.present(err, animated: true)
                }
            }
        })
    }

    private func appendParticipant(_ name: String) {
        guard !participants.contains(name) else { return }
        participants.append(name)
        tableView.insertRows(at: [IndexPath(row: participants.count - 1, section: Sec.participants.rawValue)], with: .automatic)
    }

    @objc private func removeParticipant(_ sender: UIButton) {
        let idx = sender.tag
        guard idx < participants.count else { return }
        participants.remove(at: idx)
        tableView.deleteRows(at: [IndexPath(row: idx, section: Sec.participants.rawValue)], with: .automatic)
        tableView.reloadSections(IndexSet(integer: Sec.participants.rawValue), with: .none)
    }

    private func combined(date: Date, time: Date) -> Date {
        let cal = Calendar.current
        var dc = cal.dateComponents([.year, .month, .day], from: date)
        let tc = cal.dateComponents([.hour, .minute], from: time)
        dc.hour = tc.hour; dc.minute = tc.minute; dc.second = 0
        return cal.date(from: dc) ?? date
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

// MARK: - UITableViewDataSource

extension CreateEventController: UITableViewDataSource {
    func numberOfSections(in tv: UITableView) -> Int { 6 }

    func tableView(_ tv: UITableView, numberOfRowsInSection section: Int) -> Int {
        switch Sec(rawValue: section) {
        case .titleDesc:     return 2
        case .dateTime:      return showEndTime ? 4 : 3  // date, startTime, toggle, [endTime]
        case .location:      return 1
        case .reminder:      return 1
        case .participants:  return participants.count + 1
        case .danger:        return editingEvent != nil ? 1 : 0
        default:             return 0
        }
    }

    func tableView(_ tv: UITableView, cellForRowAt ip: IndexPath) -> UITableViewCell {
        switch Sec(rawValue: ip.section) {

        case .titleDesc:
            if ip.row == 0 {
                let cell = tv.dequeueReusableCell(withIdentifier: "text", for: ip) as! TextInputCell
                cell.textField.placeholder = "Название"
                cell.textField.font = .systemFont(ofSize: 16, weight: .medium)
                cell.textField.text = eventTitle
                cell.onTextChange = { [weak self] t in self?.eventTitle = t }
                return cell
            } else {
                let cell = tv.dequeueReusableCell(withIdentifier: "textView", for: ip) as! TextViewCell
                cell.configure(text: eventDescription)
                cell.onTextChange = { [weak self] t in self?.eventDescription = t }
                cell.onHeightChange = { [weak self] in
                    guard let self else { return }
                    UIView.setAnimationsEnabled(false)
                    self.tableView.beginUpdates()
                    self.tableView.endUpdates()
                    UIView.setAnimationsEnabled(true)
                }
                return cell
            }

        case .dateTime:
            // row 0: date, row 1: start time, row 2: toggle end time, row 3: end time (if on)
            if ip.row == 0 {
                let cell = tv.dequeueReusableCell(withIdentifier: "datePicker", for: ip) as! DatePickerCell
                cell.configure(title: "Дата:", mode: .date, date: eventDate)
                cell.onValueChange = { [weak self] d in self?.eventDate = d }
                return cell
            } else if ip.row == 1 {
                let cell = tv.dequeueReusableCell(withIdentifier: "datePicker", for: ip) as! DatePickerCell
                cell.configure(title: "Начало:", mode: .time, date: startTime)
                cell.onValueChange = { [weak self] d in self?.startTime = d }
                return cell
            } else if ip.row == 2 {
                let cell = tv.dequeueReusableCell(withIdentifier: "toggle", for: ip) as! ToggleCell
                cell.configure(title: "Указывать время завершения", subtitle: nil, isOn: showEndTime)
                cell.onToggle = { [weak self] on in
                    guard let self else { return }
                    self.showEndTime = on
                    let endRow = IndexPath(row: 3, section: Sec.dateTime.rawValue)
                    if on {
                        tv.insertRows(at: [endRow], with: .automatic)
                    } else {
                        tv.deleteRows(at: [endRow], with: .automatic)
                    }
                }
                return cell
            } else {
                let cell = tv.dequeueReusableCell(withIdentifier: "datePicker", for: ip) as! DatePickerCell
                cell.configure(title: "Конец:", mode: .time, date: endTime)
                cell.onValueChange = { [weak self] d in self?.endTime = d }
                return cell
            }

        case .location:
            let cell = tv.dequeueReusableCell(withIdentifier: "location", for: ip) as! LocationInputCell
            cell.textField.text = eventLocation
            cell.onTextChange = { [weak self] t in
                self?.eventLocation = t
                if t.isEmpty {
                    self?.locationLatitude = nil
                    self?.locationLongitude = nil
                }
            }
            cell.onMapTap = { [weak self] in self?.presentLocationSearch() }
            return cell

        case .reminder:
            let cell = tv.dequeueReusableCell(withIdentifier: "basic", for: ip)
            cell.selectionStyle = .default
            cell.textLabel?.font = .systemFont(ofSize: 16)
            cell.textLabel?.textColor = .label
            cell.textLabel?.text = "Напоминание"
            cell.detailTextLabel?.text = reminderLabel(for: reminderMinutes)
            let detail = UILabel()
            detail.text = reminderLabel(for: reminderMinutes)
            detail.font = .systemFont(ofSize: 16)
            detail.textColor = .secondaryLabel
            detail.sizeToFit()
            cell.accessoryView = detail
            cell.accessoryType = .none
            return cell

        case .participants:
            if ip.row < participants.count {
                let cell = tv.dequeueReusableCell(withIdentifier: "basic", for: ip)
                cell.selectionStyle = .none
                cell.textLabel?.text = participants[ip.row]
                cell.textLabel?.textColor = .label
                cell.textLabel?.font = .systemFont(ofSize: 16)
                let btn = UIButton(type: .system)
                btn.setImage(UIImage(systemName: "xmark.circle.fill"), for: .normal)
                btn.tintColor = UIColor.systemRed.withAlphaComponent(0.7)
                btn.frame = CGRect(x: 0, y: 0, width: 28, height: 28)
                btn.tag = ip.row
                btn.addTarget(self, action: #selector(removeParticipant(_:)), for: .touchUpInside)
                cell.accessoryView = btn
                return cell
            } else {
                let cell = tv.dequeueReusableCell(withIdentifier: "basic", for: ip)
                cell.selectionStyle = .default
                cell.textLabel?.text = "Добавить участника"
                cell.textLabel?.textColor = UIColor(red: 0.07, green: 0.49, blue: 0.15, alpha: 1)
                cell.textLabel?.font = .systemFont(ofSize: 16)
                cell.imageView?.image = UIImage(systemName: "person.badge.plus")
                cell.imageView?.tintColor = UIColor(red: 0.07, green: 0.49, blue: 0.15, alpha: 1)
                cell.accessoryView = nil
                cell.accessoryType = .none
                return cell
            }

        case .danger:
            let cell = tv.dequeueReusableCell(withIdentifier: "basic", for: ip)
            cell.selectionStyle = .default
            cell.textLabel?.text = "Отменить мероприятие"
            cell.textLabel?.textColor = .systemRed
            cell.textLabel?.font = .systemFont(ofSize: 16)
            cell.textLabel?.textAlignment = .center
            cell.accessoryView = nil
            cell.accessoryType = .none
            return cell

        default:
            return UITableViewCell()
        }
    }

    func tableView(_ tv: UITableView, titleForHeaderInSection section: Int) -> String? { nil }

    func tableView(_ tv: UITableView, titleForFooterInSection section: Int) -> String? {
        switch Sec(rawValue: section) {
        case .reminder: return "Гости тоже получат уведомление о начале мероприятия."
        case .danger:   return editingEvent != nil ? "Участники получат уведомление при обновлении вашего мероприятия." : nil
        default:        return nil
        }
    }
}

// MARK: - UITableViewDelegate

extension CreateEventController: UITableViewDelegate {
    func tableView(_ tv: UITableView, heightForRowAt ip: IndexPath) -> CGFloat {
        switch Sec(rawValue: ip.section) {
        case .titleDesc: return ip.row == 0 ? 52 : UITableView.automaticDimension
        case .dateTime:  return UITableView.automaticDimension
        default:         return 52
        }
    }

    func tableView(_ tv: UITableView, estimatedHeightForRowAt ip: IndexPath) -> CGFloat { 52 }

    func tableView(_ tv: UITableView, didSelectRowAt ip: IndexPath) {
        tv.deselectRow(at: ip, animated: true)
        switch Sec(rawValue: ip.section) {
        case .participants where ip.row == participants.count:
            addParticipantTapped()
        case .location:
            presentLocationSearch()
        case .reminder:
            showReminderPicker()
        case .danger:
            cancelEventTapped()
        default:
            break
        }
    }

    func tableView(_ tv: UITableView, canEditRowAt ip: IndexPath) -> Bool {
        Sec(rawValue: ip.section) == .participants && ip.row < participants.count
    }

    func tableView(_ tv: UITableView, commit editingStyle: UITableViewCell.EditingStyle, forRowAt ip: IndexPath) {
        if editingStyle == .delete {
            participants.remove(at: ip.row)
            tv.deleteRows(at: [ip], with: .automatic)
            tv.reloadSections(IndexSet(integer: Sec.participants.rawValue), with: .none)
        }
    }

    // MARK: - Location search

    private func presentLocationSearch() {
        var initialLocation: CLLocationCoordinate2D?
        if let lat = locationLatitude, let lon = locationLongitude {
            initialLocation = CLLocationCoordinate2D(latitude: lat, longitude: lon)
        }

        let locationPicker = LocationPickerController(
            context: context,
            updatedPresentationData: nil,
            mode: .pick,
            initialLocation: initialLocation,
            completion: { [weak self] location, _, _, name, _ in
                guard let self else { return }
                let displayName = name ?? location.venue?.title ?? ""
                self.eventLocation = displayName
                self.locationLatitude = location.latitude
                self.locationLongitude = location.longitude
                self.tableView.reloadRows(at: [IndexPath(row: 0, section: Sec.location.rawValue)], with: .none)
                // LocationPickerController calls dismiss() automatically after this closure.
            }
        )

        // LocationPickerController is a Display VC whose navigationBar lives in its own view
        // (ViewController.loadView adds it to displayNode directly). We can present it without
        // wrapping in a Display NavigationController — that wrapper was the source of the extra
        // black/white background layers. Without a Display NavController, dismiss() correctly
        // falls through to self.presentingViewController?.dismiss().
        let screenSize = UIScreen.main.bounds.size
        let safeArea = self.view.safeAreaInsets
        let deviceMetrics = DeviceMetrics(
            screenSize: screenSize,
            scale: UIScreen.main.scale,
            statusBarHeight: safeArea.top,
            onScreenNavigationHeight: safeArea.bottom > 0 ? safeArea.bottom : nil
        )
        let layout = ContainerViewLayout(
            size: screenSize,
            metrics: LayoutMetrics(widthClass: .compact, heightClass: .regular, orientation: nil),
            deviceMetrics: deviceMetrics,
            intrinsicInsets: .zero,
            safeInsets: safeArea,
            additionalInsets: .zero,
            statusBarHeight: safeArea.top,
            inputHeight: nil,
            inputHeightIsInteractivellyChanging: false,
            inVoiceOver: false
        )
        locationPicker.containerLayoutUpdated(layout, transition: .immediate)
        locationPicker.modalPresentationStyle = .fullScreen
        self.present(locationPicker, animated: true)
    }
}

// MARK: - LocationInputCell

private final class LocationInputCell: UITableViewCell {
    let textField = UITextField()
    private let mapButton = UIButton(type: .system)
    var onTextChange: ((String) -> Void)?
    var onMapTap: (() -> Void)?

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        selectionStyle = .none

        textField.placeholder = "Место (необязательно)"
        textField.font = .systemFont(ofSize: 16)
        textField.returnKeyType = .next
        textField.translatesAutoresizingMaskIntoConstraints = false
        textField.addTarget(self, action: #selector(textChanged), for: .editingChanged)
        contentView.addSubview(textField)

        mapButton.setImage(UIImage(systemName: "map"), for: .normal)
        mapButton.tintColor = .secondaryLabel
        mapButton.addTarget(self, action: #selector(mapTapped), for: .touchUpInside)
        mapButton.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(mapButton)

        NSLayoutConstraint.activate([
            mapButton.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
            mapButton.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            mapButton.widthAnchor.constraint(equalToConstant: 28),
            mapButton.heightAnchor.constraint(equalToConstant: 28),

            textField.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            textField.trailingAnchor.constraint(equalTo: mapButton.leadingAnchor, constant: -8),
            textField.topAnchor.constraint(equalTo: contentView.topAnchor),
            textField.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
        ])
    }

    required init?(coder: NSCoder) { fatalError() }
    @objc private func textChanged() { onTextChange?(textField.text ?? "") }
    @objc private func mapTapped() { onMapTap?() }
}

