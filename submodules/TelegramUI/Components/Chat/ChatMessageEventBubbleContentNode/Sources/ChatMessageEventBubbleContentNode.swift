import Foundation
import UIKit
import AsyncDisplayKit
import Display
import Postbox
import TelegramCore
import TelegramPresentationData
import AccountContext
import ChatMessageDateAndStatusNode
import ChatMessageBubbleContentNode
import ChatMessageItemCommon
import ChatControllerInteraction

private let voteStorageKey = "tg_event_votes_v2"
private let eventsStorageKey = "tg_events_v1"

private struct EventVoteEntry: Decodable {
    let vote: String
}

private struct StoredEventLocation: Decodable {
    let id: UUID
    let title: String?
    let location: String?
}

private let titleFont = Font.semibold(16.0)
private let subtitleFont = Font.regular(13.5)
private let locationFont = Font.italic(11.5)
private let buttonFont = Font.regular(12.5)

public final class ChatMessageEventBubbleContentNode: ChatMessageBubbleContentNode {
    private let dateAndStatusNode: ChatMessageDateAndStatusNode
    private let titleNode: TextNode
    private let dateTimeNode: TextNode
    private let locationNode: TextNode
    private let rsvpNode: TextNode
    private let iconView: UIImageView

    // Action area
    private let dividerNode: ASDisplayNode
    private let editButtonNode: TextNode
    private let calendarButtonNode: TextNode
    private let buttonSeparatorNode: ASDisplayNode

    // Inner info bubble background
    private let innerBubbleView: UIView

    // RSVP person icon
    private let rsvpIconView: UIImageView

    // Tap detection
    private var editButtonFrame: CGRect = .zero
    private var calendarButtonFrame: CGRect = .zero
    private var infoBubbleFrame: CGRect = .zero   // inner bubble — tap opens event card
    private var isCreatorFlag: Bool = false

    public private(set) var currentEventId: String?
    private var currentMessageId: Int32 = 0

    // Stored layout state for direct refresh (set in apply block)
    private var storedSubtitleColor: UIColor = .secondaryLabel
    private var storedTitleColor: UIColor = .label
    private var storedTextWidth: CGFloat = 200
    private var storedTextX: CGFloat = 70
    private var storedLocationMaxWidth: CGFloat = 150
    private var storedFirstOptionalRowY: CGFloat = 0   // y right after dateTimeNode

    required public init() {
        self.innerBubbleView = UIView()
        self.innerBubbleView.layer.cornerRadius = 12.0

        self.rsvpIconView = UIImageView()
        self.rsvpIconView.contentMode = .scaleAspectFit

        self.dateAndStatusNode = ChatMessageDateAndStatusNode()
        self.titleNode = TextNode()
        self.titleNode.isUserInteractionEnabled = false
        self.dateTimeNode = TextNode()
        self.dateTimeNode.isUserInteractionEnabled = false
        self.locationNode = TextNode()
        self.locationNode.isUserInteractionEnabled = false
        self.rsvpNode = TextNode()
        self.rsvpNode.isUserInteractionEnabled = false
        self.iconView = UIImageView()
        self.iconView.contentMode = .scaleAspectFit

        self.dividerNode = ASDisplayNode()
        self.dividerNode.isLayerBacked = true
        self.editButtonNode = TextNode()
        self.editButtonNode.isUserInteractionEnabled = false
        self.calendarButtonNode = TextNode()
        self.calendarButtonNode.isUserInteractionEnabled = false
        self.buttonSeparatorNode = ASDisplayNode()
        self.buttonSeparatorNode.isLayerBacked = true

        super.init()

        self.addSubnode(self.titleNode)
        self.addSubnode(self.dateTimeNode)
        self.addSubnode(self.locationNode)
        self.addSubnode(self.rsvpNode)
        self.addSubnode(self.dividerNode)
        self.addSubnode(self.editButtonNode)
        self.addSubnode(self.calendarButtonNode)
        self.addSubnode(self.buttonSeparatorNode)

        self.dateAndStatusNode.reactionSelected = { [weak self] _, value, sourceView in
            guard let self, let item = self.item else { return }
            item.controllerInteraction.updateMessageReaction(item.topMessage, .reaction(value), false, sourceView)
        }
        self.dateAndStatusNode.openReactionPreview = { [weak self] gesture, sourceView, value in
            guard let self, let item = self.item else { gesture?.cancel(); return }
            item.controllerInteraction.openMessageReactionContextMenu(item.topMessage, sourceView, gesture, value)
        }
    }

    required public init?(coder: NSCoder) { fatalError() }

    override public func didLoad() {
        super.didLoad()
        // Insert at 0 so it sits below all ASDisplayKit subnodes and iconView
        self.view.insertSubview(self.innerBubbleView, at: 0)
        self.view.addSubview(self.iconView)
        self.view.addSubview(self.rsvpIconView)
    }

    override public func asyncLayoutContent() -> (_ item: ChatMessageBubbleContentItem, _ layoutConstants: ChatMessageItemLayoutConstants, _ preparePosition: ChatMessageBubblePreparePosition, _ messageSelection: Bool?, _ constrainedSize: CGSize, _ avatarInset: CGFloat) -> (ChatMessageBubbleContentProperties, CGSize?, CGFloat, (CGSize, ChatMessageBubbleContentPosition) -> (CGFloat, (CGFloat) -> (CGSize, (ListViewItemUpdateAnimation, Bool, ListViewItemApply?) -> Void))) {

        let statusLayout = self.dateAndStatusNode.asyncLayout()
        let makeTitleLayout = TextNode.asyncLayout(self.titleNode)
        let makeDateTimeLayout = TextNode.asyncLayout(self.dateTimeNode)
        let makeLocationLayout = TextNode.asyncLayout(self.locationNode)
        let makeRsvpLayout = TextNode.asyncLayout(self.rsvpNode)
        let makeEditLayout = TextNode.asyncLayout(self.editButtonNode)
        let makeCalendarLayout = TextNode.asyncLayout(self.calendarButtonNode)

        return { item, layoutConstants, _, _, constrainedSize, _ in
            var attr: TGEventAttribute?
            for a in item.message.attributes {
                if let a = a as? TGEventAttribute { attr = a; break }
            }

            let incoming = item.message.effectivelyIncoming(item.context.account.peerId)
            let isCreator = !incoming
            let messageTheme = incoming
                ? item.presentationData.theme.theme.chat.message.incoming
                : item.presentationData.theme.theme.chat.message.outgoing

            let titleColor = messageTheme.primaryTextColor
            let subtitleColor = messageTheme.secondaryTextColor
            let accentColor = messageTheme.accentTextColor
            let separatorColor = incoming
                ? UIColor(white: 0.0, alpha: 0.12)
                : UIColor(white: 1.0, alpha: 0.25)
            let innerBubbleColor = incoming
                ? UIColor(white: 0.0, alpha: 0.12)
                : UIColor(white: 1.0, alpha: 0.50)

            let lines = item.message.text.components(separatedBy: "\n")
            let parsedTitle: String = {
                if let l = lines.first, l.hasPrefix("📅 ") { return String(l.dropFirst(2)) }
                return item.message.text
            }()
            let parsedDateTime: String = {
                if let l = lines.first(where: { $0.hasPrefix("🕒 ") }) { return String(l.dropFirst(2)) }
                return ""
            }()
            let parsedLocation: String = {
                if let l = lines.first(where: { $0.hasPrefix("📍 ") }) { return String(l.dropFirst(2)) }
                return ""
            }()

            let titleStr: String
            let dateTimeStr: String
            let locationStr: String

            if let attr = attr {
                let df = DateFormatter()
                df.locale = Locale(identifier: "ru_RU")
                df.dateFormat = "EEE, d MMMM"
                let tf = DateFormatter()
                tf.dateFormat = "HH:mm"
                let start = Date(timeIntervalSince1970: attr.startTimestamp)
                dateTimeStr = "\(df.string(from: start)), \(tf.string(from: start))"
                // Check UserDefaults for latest title + location (may have been edited after message was sent)
                let eId = attr.eventId
                let (latestTitle, latestLocation): (String?, String?) = {
                    guard let data = UserDefaults.standard.data(forKey: eventsStorageKey),
                          let events = try? JSONDecoder().decode([StoredEventLocation].self, from: data),
                          let localEvent = events.first(where: { $0.id.uuidString == eId }) else {
                        return (nil, attr.location)
                    }
                    return (localEvent.title, localEvent.location)
                }()
                titleStr = latestTitle ?? attr.title
                locationStr = latestLocation ?? ""
            } else {
                titleStr = parsedTitle
                dateTimeStr = parsedDateTime
                locationStr = parsedLocation
            }

            var goingCount = 0
            if let eId = attr?.eventId,
               let data = UserDefaults.standard.data(forKey: voteStorageKey),
               let votes = try? JSONDecoder().decode([String: [EventVoteEntry]].self, from: data),
               let entries = votes[eId] {
                goingCount = entries.filter { $0.vote == "yes" }.count
            }
            let rsvpStr = goingCount > 0 ? "👥 Идут: \(goingCount)" : ""

            let contentProperties = ChatMessageBubbleContentProperties(
                hidesSimpleAuthorHeader: false, headerSpacing: 0,
                hidesBackground: .never, forceFullCorners: false, forceAlignment: .none
            )

            return (contentProperties, nil, CGFloat.greatestFiniteMagnitude, { constrainedSize, position in
                let iconSize: CGFloat = 44.0
                let iconRightPad: CGFloat = 12.0
                let sideInset = layoutConstants.text.bubbleInsets.left
                let iconColumnWidth = iconSize + iconRightPad
                let availWidth = constrainedSize.width - layoutConstants.text.bubbleInsets.left - layoutConstants.text.bubbleInsets.right
                let textWidth = max(1.0, availWidth - iconColumnWidth)

                let (titleLayout, titleApply) = makeTitleLayout(TextNodeLayoutArguments(
                    attributedString: NSAttributedString(string: titleStr, attributes: [.font: titleFont, .foregroundColor: titleColor]),
                    backgroundColor: nil, maximumNumberOfLines: 2, truncationType: .end,
                    constrainedSize: CGSize(width: textWidth, height: .greatestFiniteMagnitude),
                    alignment: .natural, cutout: nil, insets: .zero
                ))
                let (dateTimeLayout, dateTimeApply) = makeDateTimeLayout(TextNodeLayoutArguments(
                    attributedString: NSAttributedString(string: dateTimeStr, attributes: [.font: subtitleFont, .foregroundColor: subtitleColor]),
                    backgroundColor: nil, maximumNumberOfLines: 1, truncationType: .end,
                    constrainedSize: CGSize(width: textWidth, height: .greatestFiniteMagnitude),
                    alignment: .natural, cutout: nil, insets: .zero
                ))
                let locationDisplayStr = locationStr.isEmpty ? "" : "📍 " + locationStr
                let (locationLayout, _) = makeLocationLayout(TextNodeLayoutArguments(
                    attributedString: NSAttributedString(string: locationDisplayStr, attributes: [.font: locationFont, .foregroundColor: subtitleColor]),
                    backgroundColor: nil, maximumNumberOfLines: 1, truncationType: .end,
                    constrainedSize: CGSize(width: textWidth - 8.0, height: .greatestFiniteMagnitude),
                    alignment: .natural, cutout: nil, insets: .zero
                ))
                let (rsvpLayout, rsvpApply) = makeRsvpLayout(TextNodeLayoutArguments(
                    attributedString: NSAttributedString(string: rsvpStr, attributes: [.font: locationFont, .foregroundColor: subtitleColor]),
                    backgroundColor: nil, maximumNumberOfLines: 1, truncationType: .end,
                    constrainedSize: CGSize(width: textWidth, height: .greatestFiniteMagnitude),
                    alignment: .natural, cutout: nil, insets: .zero
                ))

                // Button text layouts — full card width, stacked vertically
                let btnW = max(140.0, availWidth - 16.0)
                let (editLayout, editApply) = makeEditLayout(TextNodeLayoutArguments(
                    attributedString: NSAttributedString(
                        string: isCreator ? "Редактировать мероприятие" : "",
                        attributes: [.font: buttonFont, .foregroundColor: accentColor]),
                    backgroundColor: nil, maximumNumberOfLines: 1, truncationType: .end,
                    constrainedSize: CGSize(width: btnW, height: 38.0),
                    alignment: .center, cutout: nil, insets: .zero
                ))
                let (calLayout, calApply) = makeCalendarLayout(TextNodeLayoutArguments(
                    attributedString: NSAttributedString(
                        string: "Добавить в календарь",
                        attributes: [.font: buttonFont, .foregroundColor: accentColor]),
                    backgroundColor: nil, maximumNumberOfLines: 1, truncationType: .end,
                    constrainedSize: CGSize(width: btnW, height: 38.0),
                    alignment: .center, cutout: nil, insets: .zero
                ))

                // Status
                var edited = false
                var viewCount: Int?
                var dateReplies = 0
                var starsCount: Int64?
                var dateReactionsAndPeers = mergedMessageReactionsAndPeers(accountPeerId: item.context.account.peerId, accountPeer: item.associatedData.accountPeer, message: item.message)
                if item.message.isRestricted(platform: "ios", contentSettings: item.context.currentContentSettings.with { $0 }) {
                    dateReactionsAndPeers = ([], [])
                }
                for attribute in item.message.attributes {
                    if let attribute = attribute as? EditedMessageAttribute {
                        edited = !attribute.isHidden
                    } else if let attribute = attribute as? ViewCountMessageAttribute {
                        viewCount = attribute.count
                    } else if let attribute = attribute as? ReplyThreadMessageAttribute, case .peer = item.chatLocation {
                        if let channel = item.message.peers[item.message.id.peerId] as? TelegramChannel, case .group = channel.info {
                            dateReplies = Int(attribute.count)
                        }
                    } else if let attribute = attribute as? PaidStarsMessageAttribute, item.message.id.peerId.namespace == Namespaces.Peer.CloudChannel {
                        starsCount = attribute.stars.value
                    }
                }

                let dateText = stringForMessageTimestampStatus(
                    accountPeerId: item.context.account.peerId,
                    message: item.message,
                    dateTimeFormat: item.presentationData.dateTimeFormat,
                    nameDisplayOrder: item.presentationData.nameDisplayOrder,
                    strings: item.presentationData.strings,
                    associatedData: item.associatedData
                )

                let statusType: ChatMessageDateAndStatusType?
                if item.message.timestamp == 0 {
                    statusType = nil
                } else {
                    switch position {
                    case .linear(_, .None), .linear(_, .Neighbour(true, _, _)):
                        if incoming {
                            statusType = .BubbleIncoming
                        } else {
                            if item.message.flags.contains(.Failed) {
                                statusType = .BubbleOutgoing(.Failed)
                            } else if (item.message.flags.isSending && !item.message.isSentOrAcknowledged) || item.attributes.updatingMedia != nil {
                                statusType = .BubbleOutgoing(.Sending)
                            } else {
                                statusType = .BubbleOutgoing(.Sent(read: item.read))
                            }
                        }
                    default:
                        statusType = nil
                    }
                }

                var statusSuggestedWidthAndContinue: (CGFloat, (CGFloat) -> (CGSize, (ListViewItemUpdateAnimation) -> Void))?
                let messageEffect = item.message.messageEffect(availableMessageEffects: item.associatedData.availableMessageEffects)
                if let statusType {
                    var isReplyThread = false
                    if case .replyThread = item.chatLocation { isReplyThread = true }
                    statusSuggestedWidthAndContinue = statusLayout(ChatMessageDateAndStatusNode.Arguments(
                        context: item.context,
                        presentationData: item.presentationData,
                        edited: edited,
                        impressionCount: viewCount,
                        dateText: dateText,
                        type: statusType,
                        layoutInput: .trailingContent(
                            contentWidth: 1000.0,
                            reactionSettings: shouldDisplayInlineDateReactions(message: item.message, isPremium: item.associatedData.isPremium, forceInline: item.associatedData.forceInlineReactions)
                                ? ChatMessageDateAndStatusNode.TrailingReactionSettings(displayInline: true, preferAdditionalInset: false)
                                : nil
                        ),
                        constrainedSize: CGSize(width: constrainedSize.width - layoutConstants.text.bubbleInsets.left - layoutConstants.text.bubbleInsets.right, height: .greatestFiniteMagnitude),
                        availableReactions: item.associatedData.availableReactions,
                        savedMessageTags: item.associatedData.savedMessageTags,
                        reactions: dateReactionsAndPeers.reactions,
                        reactionPeers: dateReactionsAndPeers.peers,
                        displayAllReactionPeers: item.message.id.peerId.namespace == Namespaces.Peer.CloudUser,
                        areReactionsTags: item.topMessage.areReactionsTags(accountPeerId: item.context.account.peerId),
                        areStarReactionsEnabled: item.associatedData.areStarReactionsEnabled,
                        messageEffect: messageEffect,
                        replyCount: dateReplies,
                        starsCount: starsCount,
                        isPinned: item.message.tags.contains(.pinned) && !item.associatedData.isInPinnedListMode && isReplyThread,
                        hasAutoremove: item.message.isSelfExpiring,
                        canViewReactionList: canViewMessageReactionList(message: item.topMessage),
                        animationCache: item.controllerInteraction.presentationContext.animationCache,
                        animationRenderer: item.controllerInteraction.presentationContext.animationRenderer
                    ))
                }

                var maxContentWidth = sideInset + iconColumnWidth + titleLayout.size.width + layoutConstants.text.bubbleInsets.right
                maxContentWidth = max(maxContentWidth, statusSuggestedWidthAndContinue.map { $0.0 + layoutConstants.text.bubbleInsets.left + layoutConstants.text.bubbleInsets.right } ?? 0)
                // Ensure card is wide enough for button labels (stacked, so take the wider one)
                let minButtonWidth = isCreator
                    ? max(editLayout.size.width, calLayout.size.width) + 32.0
                    : calLayout.size.width + 32.0
                maxContentWidth = max(maxContentWidth, minButtonWidth + layoutConstants.text.bubbleInsets.left + layoutConstants.text.bubbleInsets.right)
                maxContentWidth = max(maxContentWidth, min(280.0, constrainedSize.width))
                let contentWidth = maxContentWidth

                return (contentWidth, { boundingWidth in
                    let statusSizeAndApply = statusSuggestedWidthAndContinue?.1(boundingWidth - layoutConstants.text.bubbleInsets.left - layoutConstants.text.bubbleInsets.right)

                    let topInset = layoutConstants.text.bubbleInsets.top + 2.0
                    let lineSpacing: CGFloat = 5.0

                    var textHeight = titleLayout.size.height + lineSpacing + dateTimeLayout.size.height + lineSpacing
                    if !locationStr.isEmpty { textHeight += locationLayout.size.height + lineSpacing }
                    if !rsvpStr.isEmpty { textHeight += rsvpLayout.size.height + lineSpacing }
                    textHeight = max(0, textHeight - lineSpacing)

                    let blockHeight = max(iconSize, textHeight)

                    // Button rows. Status timestamp overlaps the bottom pad — no extra height added for it.
                    let dividerGap: CGFloat = 4.0
                    let buttonRowHeight: CGFloat = 20.0
                    let buttonTopPad: CGFloat = 8.0
                    let statusH = statusSizeAndApply?.0.height ?? 0.0
                    let buttonBottomPad: CGFloat = statusH > 0 ? statusH + 3.0 : 4.0
                    let actualButtonsH: CGFloat = isCreator
                        ? buttonRowHeight + 0.5 + buttonRowHeight
                        : buttonRowHeight
                    let buttonAreaHeight: CGFloat = buttonTopPad + actualButtonsH + buttonBottomPad

                    let totalHeight = topInset + blockHeight + dividerGap + 0.5 + buttonAreaHeight

                    let layoutSize = CGSize(width: boundingWidth, height: totalHeight)

                    return (layoutSize, { [weak self] animation, _, _ in
                        guard let self else { return }
                        self.item = item
                        self.currentEventId = attr?.eventId
                        self.currentMessageId = item.message.id.id
                        self.isCreatorFlag = isCreator
                        self.storedSubtitleColor = subtitleColor
                        self.storedTitleColor = titleColor
                        self.storedTextWidth = textWidth
                        self.storedTextX = sideInset + iconColumnWidth

                        let _ = titleApply()
                        let _ = dateTimeApply()
                        // locationApply is deferred — applied below with boundingWidth-based constraint
                        let _ = rsvpApply()
                        let _ = editApply()
                        let _ = calApply()

                        let textX = sideInset + iconColumnWidth
                        var y = topInset

                        // Icon top-aligned with first text row
                        let iconFrame = CGRect(x: sideInset, y: topInset, width: iconSize, height: iconSize)
                        self.iconView.frame = iconFrame
                        let iconColor = UIColor(red: 1.0, green: 0.60, blue: 0.0, alpha: 1.0)
                        self.iconView.image = UIImage(systemName: "calendar.circle.fill")?
                            .withConfiguration(UIImage.SymbolConfiguration(pointSize: 36, weight: .medium))
                            .withTintColor(iconColor, renderingMode: .alwaysOriginal)

                        self.titleNode.frame = CGRect(x: textX, y: y, width: titleLayout.size.width, height: titleLayout.size.height)
                        y += titleLayout.size.height + lineSpacing

                        self.dateTimeNode.frame = CGRect(x: textX, y: y, width: dateTimeLayout.size.width, height: dateTimeLayout.size.height)
                        y += dateTimeLayout.size.height + lineSpacing
                        self.storedFirstOptionalRowY = y

                        if !locationStr.isEmpty {
                            self.locationNode.isHidden = false
                            // Compute location layout with the ACTUAL bubble width so we know the exact
                            // space available. innerBubble ends at boundingWidth-6; require 8pt gap → max=boundingWidth-14.
                            let locMaxWidth = max(1, boundingWidth - textX - 14.0)
                            let (finalLocLayout, finalLocApply) = makeLocationLayout(TextNodeLayoutArguments(
                                attributedString: NSAttributedString(string: locationDisplayStr, attributes: [.font: locationFont, .foregroundColor: subtitleColor]),
                                backgroundColor: nil, maximumNumberOfLines: 1, truncationType: .end,
                                constrainedSize: CGSize(width: locMaxWidth, height: .greatestFiniteMagnitude),
                                alignment: .natural, cutout: nil, insets: .zero
                            ))
                            let _ = finalLocApply()
                            self.storedLocationMaxWidth = locMaxWidth
                            self.locationNode.frame = CGRect(x: textX - 3.0, y: y, width: finalLocLayout.size.width + 3.0, height: finalLocLayout.size.height)
                            y += finalLocLayout.size.height + lineSpacing
                        } else {
                            self.locationNode.isHidden = true
                        }

                        if !rsvpStr.isEmpty {
                            self.rsvpIconView.isHidden = true
                            self.rsvpNode.isHidden = false
                            // Same x-offset as locationNode (-3pt to align emoji with text)
                            self.rsvpNode.frame = CGRect(x: textX - 3.0, y: y, width: rsvpLayout.size.width + 3.0, height: rsvpLayout.size.height)
                        } else {
                            self.rsvpIconView.isHidden = true
                            self.rsvpNode.isHidden = true
                        }

                        // Divider and button row
                        let cardLeft = layoutConstants.text.bubbleInsets.left
                        let cardRight = boundingWidth - layoutConstants.text.bubbleInsets.right
                        let cardInnerWidth = cardRight - cardLeft
                        let dividerY = topInset + blockHeight + dividerGap

                        // Inner bubble covers the info block (icon + text), inset from card edges
                        let innerInset: CGFloat = 6.0
                        self.innerBubbleView.backgroundColor = innerBubbleColor
                        let innerFrame = CGRect(
                            x: innerInset, y: innerInset,
                            width: boundingWidth - innerInset * 2,
                            height: dividerY - innerInset
                        )
                        self.innerBubbleView.frame = innerFrame
                        self.infoBubbleFrame = innerFrame

                        self.dividerNode.backgroundColor = separatorColor
                        self.dividerNode.frame = CGRect(x: 0, y: dividerY, width: boundingWidth, height: 0.5)

                        let buttonRowY = dividerY + 0.5 + buttonTopPad

                        if isCreator {
                            // Edit button (top row)
                            self.editButtonNode.isHidden = false
                            self.editButtonNode.frame = CGRect(
                                x: cardLeft + (cardInnerWidth - editLayout.size.width) / 2,
                                y: buttonRowY + (buttonRowHeight - editLayout.size.height) / 2,
                                width: editLayout.size.width,
                                height: editLayout.size.height
                            )
                            self.editButtonFrame = CGRect(x: 0, y: buttonRowY, width: boundingWidth, height: buttonRowHeight)

                            // Horizontal separator between the two buttons
                            let midDividerY = buttonRowY + buttonRowHeight
                            self.buttonSeparatorNode.isHidden = false
                            self.buttonSeparatorNode.backgroundColor = separatorColor
                            self.buttonSeparatorNode.frame = CGRect(x: 0, y: midDividerY, width: boundingWidth, height: 0.5)

                            // Calendar button (bottom row)
                            let calButtonRowY = midDividerY + 0.5
                            self.calendarButtonNode.frame = CGRect(
                                x: cardLeft + (cardInnerWidth - calLayout.size.width) / 2,
                                y: calButtonRowY + (buttonRowHeight - calLayout.size.height) / 2,
                                width: calLayout.size.width,
                                height: calLayout.size.height
                            )
                            self.calendarButtonFrame = CGRect(x: 0, y: calButtonRowY, width: boundingWidth, height: buttonRowHeight)
                        } else {
                            self.editButtonNode.isHidden = true
                            self.buttonSeparatorNode.isHidden = true
                            self.editButtonFrame = .zero
                            self.calendarButtonNode.frame = CGRect(
                                x: cardLeft + (cardInnerWidth - calLayout.size.width) / 2,
                                y: buttonRowY + (buttonRowHeight - calLayout.size.height) / 2,
                                width: calLayout.size.width,
                                height: calLayout.size.height
                            )
                            self.calendarButtonFrame = CGRect(x: 0, y: buttonRowY, width: boundingWidth, height: buttonRowHeight)
                        }

                        if let statusSizeAndApply {
                            self.dateAndStatusNode.frame = CGRect(
                                origin: CGPoint(
                                    x: boundingWidth - layoutConstants.text.bubbleInsets.right - statusSizeAndApply.0.width,
                                    y: totalHeight - statusSizeAndApply.0.height - 2.0
                                ),
                                size: statusSizeAndApply.0
                            )
                            if self.dateAndStatusNode.supernode == nil {
                                self.addSubnode(self.dateAndStatusNode)
                                statusSizeAndApply.1(.None)
                            } else {
                                statusSizeAndApply.1(animation)
                            }
                        } else if self.dateAndStatusNode.supernode != nil {
                            self.dateAndStatusNode.removeFromSupernode()
                        }

                        if let forwardInfo = item.message.forwardInfo, forwardInfo.flags.contains(.isImported) {
                            self.dateAndStatusNode.pressed = { [weak self] in
                                guard let self, let item = self.item else { return }
                                item.controllerInteraction.displayImportedMessageTooltip(self.dateAndStatusNode)
                            }
                        } else if messageEffect != nil {
                            self.dateAndStatusNode.pressed = { [weak self] in
                                guard let self, let item = self.item else { return }
                                item.controllerInteraction.playMessageEffect(item.message)
                            }
                        } else {
                            self.dateAndStatusNode.pressed = nil
                        }
                    })
                })
            })
        }
    }

    override public func animateInsertion(_ currentTimestamp: Double, duration: Double) {
        self.layer.animateAlpha(from: 0.0, to: 1.0, duration: 0.2)
    }

    override public func animateAdded(_ currentTimestamp: Double, duration: Double) {
        self.layer.animateAlpha(from: 0.0, to: 1.0, duration: 0.2)
    }

    override public func animateRemoved(_ currentTimestamp: Double, duration: Double) {
        self.layer.animateAlpha(from: 1.0, to: 0.0, duration: 0.2, removeOnCompletion: false)
    }

    /// Direct refresh: re-reads location + vote data from UserDefaults and updates visible rows immediately.
    /// Called from ChatController when event is edited or a vote is cast, without going through asyncLayoutContent.
    public func refreshFromUserDefaults() {
        guard let eid = currentEventId else { return }

        // Read latest title + location from UserDefaults
        var latestTitle: String? = nil
        let latestLocation: String?
        if let data = UserDefaults.standard.data(forKey: eventsStorageKey),
           let events = try? JSONDecoder().decode([StoredEventLocation].self, from: data),
           let evt = events.first(where: { $0.id.uuidString == eid }) {
            latestTitle = evt.title
            latestLocation = evt.location
        } else {
            latestLocation = (item?.message.attributes.first(where: { $0 is TGEventAttribute }) as? TGEventAttribute)?.location
        }
        let locationDisplayStr = (latestLocation ?? "").isEmpty ? "" : "📍 \(latestLocation!)"

        // Update title if it changed in UserDefaults (e.g. user renamed the event)
        if let newTitle = latestTitle, !newTitle.isEmpty {
            let makeTitleLayout = TextNode.asyncLayout(self.titleNode)
            let (titleLayout, titleApply) = makeTitleLayout(TextNodeLayoutArguments(
                attributedString: NSAttributedString(string: newTitle, attributes: [.font: titleFont, .foregroundColor: storedTitleColor]),
                backgroundColor: nil, maximumNumberOfLines: 2, truncationType: .end,
                constrainedSize: CGSize(width: storedTextWidth, height: .greatestFiniteMagnitude),
                alignment: .natural, cutout: nil, insets: .zero
            ))
            let _ = titleApply()
            self.titleNode.frame = CGRect(x: storedTextX, y: self.titleNode.frame.minY, width: titleLayout.size.width, height: titleLayout.size.height)
        }

        // Read vote count
        var goingCount = 0
        if let data = UserDefaults.standard.data(forKey: voteStorageKey),
           let votes = try? JSONDecoder().decode([String: [EventVoteEntry]].self, from: data),
           let entries = votes[eid] {
            goingCount = entries.filter { $0.vote == "yes" }.count
        }
        let rsvpStr = goingCount > 0 ? "👥 Идут: \(goingCount)" : ""

        let lineSpacing: CGFloat = 5.0
        var y = storedFirstOptionalRowY

        // Update location TextNode
        let makeLocLayout = TextNode.asyncLayout(self.locationNode)
        let (locLayout, locApply) = makeLocLayout(TextNodeLayoutArguments(
            attributedString: NSAttributedString(string: locationDisplayStr,
                attributes: [.font: locationFont, .foregroundColor: storedSubtitleColor]),
            backgroundColor: nil, maximumNumberOfLines: 1, truncationType: .end,
            constrainedSize: CGSize(width: storedLocationMaxWidth, height: .greatestFiniteMagnitude),
            alignment: .natural, cutout: nil, insets: .zero
        ))
        let _ = locApply()
        if locationDisplayStr.isEmpty {
            self.locationNode.isHidden = true
        } else {
            self.locationNode.isHidden = false
            self.locationNode.frame = CGRect(x: storedTextX - 3.0, y: y, width: locLayout.size.width + 3.0, height: locLayout.size.height)
            y += locLayout.size.height + lineSpacing
        }

        // Update rsvp TextNode
        let makeRsvpLayout = TextNode.asyncLayout(self.rsvpNode)
        let (rsvpLayout, rsvpApply) = makeRsvpLayout(TextNodeLayoutArguments(
            attributedString: NSAttributedString(string: rsvpStr,
                attributes: [.font: locationFont, .foregroundColor: storedSubtitleColor]),
            backgroundColor: nil, maximumNumberOfLines: 1, truncationType: .end,
            constrainedSize: CGSize(width: storedTextWidth, height: .greatestFiniteMagnitude),
            alignment: .natural, cutout: nil, insets: .zero
        ))
        let _ = rsvpApply()
        if rsvpStr.isEmpty {
            self.rsvpNode.isHidden = true
        } else {
            self.rsvpNode.isHidden = false
            self.rsvpIconView.isHidden = true
            self.rsvpNode.frame = CGRect(x: storedTextX - 3.0, y: y, width: rsvpLayout.size.width + 3.0, height: rsvpLayout.size.height)
        }
    }

    override public func tapActionAtPoint(_ point: CGPoint, gesture: TapLongTapOrDoubleTapGesture, isEstimating: Bool) -> ChatMessageBubbleContentTapAction {
        if self.dateAndStatusNode.supernode != nil,
           let _ = self.dateAndStatusNode.hitTest(self.view.convert(point, to: self.dateAndStatusNode.view), with: nil) {
            return ChatMessageBubbleContentTapAction(content: .ignore)
        }
        if let eventId = self.currentEventId {
            if isCreatorFlag && editButtonFrame.contains(point) {
                // Encode message ID so ChatController can call requestMessageUpdate after edit
                return ChatMessageBubbleContentTapAction(content: .url(
                    ChatMessageBubbleContentTapAction.Url(url: "tgevent://edit/\(eventId)/\(currentMessageId)", concealed: false)))
            }
            if calendarButtonFrame.contains(point) {
                return ChatMessageBubbleContentTapAction(content: .url(
                    ChatMessageBubbleContentTapAction.Url(url: "tgevent://addcalendar/\(eventId)", concealed: false)))
            }
            // Tap on inner info bubble → open event card
            if infoBubbleFrame.contains(point) {
                return ChatMessageBubbleContentTapAction(content: .url(
                    ChatMessageBubbleContentTapAction.Url(url: "tgevent://open/\(eventId)", concealed: false)))
            }
        }
        return ChatMessageBubbleContentTapAction(content: .none)
    }
}
