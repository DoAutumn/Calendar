// Calendar — a menu-bar clock + month calendar for macOS.
// Shows lunar dates, statutory holidays (休) and makeup workdays (班)
// via the TianAPI jiejiari endpoint. Falls back to Gregorian-only when
// the API is unavailable.
//
// Build via ./build_app.sh.

import Cocoa

// MARK: - Settings

struct SettingsKeys {
    let showSeconds = "TIME_WITH_SECONDS"
    let use24Hours = "USE_24_H"
    let showAMPM = "AM_PM"
    let showDate = "SHOW_DATE"
    let showDayOfWeek = "DAY_OF_WEEK"
}

enum Settings {
    private static let d = UserDefaults.standard
    private static let keys = SettingsKeys()

    static var showSeconds: Bool {
        get { d.bool(forKey: keys.showSeconds) }
        set { d.set(newValue, forKey: keys.showSeconds) }
    }
    static var use24Hours: Bool {
        get { d.bool(forKey: keys.use24Hours) }
        set { d.set(newValue, forKey: keys.use24Hours) }
    }
    static var showAMPM: Bool {
        get { d.bool(forKey: keys.showAMPM) }
        set { d.set(newValue, forKey: keys.showAMPM) }
    }
    static var showDate: Bool {
        get { d.bool(forKey: keys.showDate) }
        set { d.set(newValue, forKey: keys.showDate) }
    }
    static var showDayOfWeek: Bool {
        get { d.bool(forKey: keys.showDayOfWeek) }
        set { d.set(newValue, forKey: keys.showDayOfWeek) }
    }

    static func registerDefaults() {
        let defaults: [String: Any] = [
            keys.showSeconds: false,
            keys.showDate: true,
            keys.showDayOfWeek: true,
            keys.use24Hours: true,
            keys.showAMPM: true,
        ]
        for (key, value) in defaults where d.object(forKey: key) == nil {
            d.set(value, forKey: key)
        }
    }
}

// MARK: - Holiday API

struct HolidayResponse: Codable {
    let code: Int
    let msg: String
    let result: HolidayResult?
}

struct HolidayResult: Codable {
    let list: [HolidayInfo]
}

struct HolidayInfo: Codable {
    let date: String
    let daycode: Int
    let name: String?
    let lunarday: String?
    let lunarmonth: String?
}

final class HolidayAPI {
    private let apiKey = "5e42ad1becfdcc48c05eb18adea4decf"
    private let baseURL = "https://apis.tianapi.com/jiejiari/index"
    private let session: URLSession

    init() {
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 5
        configuration.timeoutIntervalForResource = 5
        session = URLSession(configuration: configuration)
    }

    func fetchHolidays(forMonth month: Date, completion: @escaping ([HolidayInfo]?, Error?) -> Void) {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM"
        let dateString = formatter.string(from: month)

        guard var components = URLComponents(string: baseURL) else {
            completion(nil, NSError(domain: "HolidayAPI", code: -1,
                                    userInfo: [NSLocalizedDescriptionKey: "Invalid URL"]))
            return
        }
        components.queryItems = [
            URLQueryItem(name: "key", value: apiKey),
            URLQueryItem(name: "type", value: "2"),
            URLQueryItem(name: "date", value: dateString),
        ]
        guard let url = components.url else {
            completion(nil, NSError(domain: "HolidayAPI", code: -1,
                                    userInfo: [NSLocalizedDescriptionKey: "Invalid URL components"]))
            return
        }

        session.dataTask(with: url) { data, _, error in
            if let error {
                completion(nil, error)
                return
            }
            guard let data else {
                completion(nil, NSError(domain: "HolidayAPI", code: -1,
                                        userInfo: [NSLocalizedDescriptionKey: "No data received"]))
                return
            }
            do {
                let response = try JSONDecoder().decode(HolidayResponse.self, from: data)
                if response.code == 200 {
                    completion(response.result?.list ?? [], nil)
                } else {
                    completion(nil, NSError(domain: "HolidayAPI", code: response.code,
                                            userInfo: [NSLocalizedDescriptionKey: response.msg]))
                }
            } catch {
                completion(nil, error)
            }
        }.resume()
    }
}

// MARK: - Calendar model

struct Day {
    var isNumber = false
    var isToday = false
    var isCurrentMonth = false
    var isWeekend = false
    var text = "0"
    var lunarDay: String?
    var holidayDaycode: Int?
}

final class CalendarModel {
    var calendar = Calendar.autoupdatingCurrent
    let formatter = DateFormatter()
    let monthFormatter = DateFormatter()
    private let dateFormatter = DateFormatter()
    var locale: Locale!
    private var timer: Timer?

    private(set) var shownItemCount = 0
    private(set) var weekdays: [String] = []
    private var daysInWeek = 0
    private var monthOffset = 0

    private(set) var currentMonth: Date?
    private var lastFirstWeekdayLastMonth: Date?
    private var lastTick: Date? = Date()
    private var tick: Date?
    private var tickInterval: Double = 60

    var onTimeUpdate: (() -> Void)?
    var onCalendarUpdate: (() -> Void)?
    var onAPIError: ((String) -> Void)?
    var onAPIIdle: (() -> Void)?

    private var holidayInfo: [String: HolidayInfo] = [:]
    private let holidayAPI = HolidayAPI()
    private var pendingFetches = 0
    private var lastFetchError: String?
    private var fetchGeneration = 0

    init() {
        let languageIdentifier = Locale.preferredLanguages[0]
        locale = Locale(identifier: languageIdentifier)

        monthFormatter.locale = locale
        monthFormatter.dateFormat = "MMMM yyyy"

        dateFormatter.locale = Locale(identifier: "en_US_POSIX")
        dateFormatter.dateFormat = "yyyy-MM-dd"

        calendar.locale = locale
        weekdays = calendar.veryShortWeekdaySymbols
        daysInWeek = weekdays.count

        let maxWeeksInMonth = (calendar.maximumRange(of: .day)?.upperBound ?? 31) / daysInWeek
        shownItemCount = daysInWeek * (maxWeeksInMonth + 2 + 1)

        updateCurrentlyShownDays()
    }

    func setDateFormat() {
        formatter.locale = locale

        var dateTemplate = ""
        dateTemplate += Settings.showDayOfWeek ? "EEE" : ""
        dateTemplate += Settings.showDate ? "dMMM" : ""

        formatter.setLocalizedDateFormatFromTemplate(dateTemplate)
        let showAnyDateInfo = Settings.showDayOfWeek || Settings.showDate
        let dateFormat = showAnyDateInfo
            ? (formatter.dateFormat ?? "").replacingOccurrences(of: ",", with: "") + "  "
            : ""

        var timeTemplate = "mm"
        timeTemplate += Settings.showSeconds ? "ss" : ""
        timeTemplate += Settings.use24Hours ? "H" : "h"
        formatter.setLocalizedDateFormatFromTemplate(timeTemplate)
        var timeFormat = formatter.dateFormat ?? ""

        if Settings.use24Hours || !Settings.showAMPM {
            timeFormat = timeFormat.replacingOccurrences(of: "a", with: "")
        }

        formatter.dateFormat = "\(dateFormat)\(timeFormat)"
        initTiming(useSeconds: Settings.showSeconds)
    }

    private func onTick() {
        guard let last = lastTick else { return }
        tick = calendar.date(byAdding: .second, value: Int(tickInterval), to: last)

        onTimeUpdate?()
        if let tick, !calendar.isDate(tick, equalTo: last, toGranularity: .day) {
            onCalendarUpdate?()
        }

        let now = Date()
        if let tick, abs(tick.timeIntervalSince1970 - now.timeIntervalSince1970) > 0.5 {
            self.tick = now
        }
        lastTick = self.tick
    }

    private func initTiming(useSeconds: Bool) {
        tickInterval = useSeconds ? 1 : 60
        let now = Date()
        let fireAfter = useSeconds ? 1 : 60 - calendar.component(.second, from: now)

        timer?.invalidate()

        let fireAt = calendar.date(byAdding: .second, value: fireAfter, to: now)!
        timer = Timer(fire: fireAt, interval: tickInterval, repeats: true) { [weak self] _ in
            self?.onTick()
        }
        RunLoop.main.add(timer!, forMode: .common)

        lastTick = calendar.date(byAdding: .second, value: Int(-tickInterval), to: now)
        onTick()
    }

    private func daysInMonth(month: Date) -> Int {
        calendar.range(of: .day, in: .month, for: month)?.count ?? 30
    }

    private func getLastFirstWeekday(month: Date) -> Date {
        let weekday = (daysInWeek + calendar.component(.weekday, from: month) - calendar.firstWeekday) % daysInWeek
        let d = (calendar.ordinality(of: .day, in: .month, for: month) ?? 1) - weekday
        let totalDaysInMonth = daysInMonth(month: month)
        let lastFirstWeekdayNumber = (totalDaysInMonth - d) / daysInWeek * daysInWeek + d
        let dayOfMonth = calendar.ordinality(of: .day, in: .month, for: month) ?? 1
        return calendar.date(byAdding: .day, value: lastFirstWeekdayNumber - dayOfMonth, to: month)!
    }

    private func updateCurrentlyShownDays() {
        currentMonth = calendar.date(byAdding: .month, value: monthOffset, to: Date())!
        let lastMonth = calendar.date(byAdding: .month, value: -1, to: currentMonth!)!
        lastFirstWeekdayLastMonth = getLastFirstWeekday(month: lastMonth)

        let nextMonth = calendar.date(byAdding: .month, value: 1, to: currentMonth!)!
        beginHolidayFetch()
        fetchHolidayData(forMonth: lastMonth)
        fetchHolidayData(forMonth: currentMonth!)
        fetchHolidayData(forMonth: nextMonth)
    }

    private func beginHolidayFetch() {
        fetchGeneration += 1
        holidayInfo.removeAll()
        lastFetchError = nil
        pendingFetches = 0
    }

    private func fetchHolidayData(forMonth month: Date) {
        let generation = fetchGeneration
        pendingFetches += 1
        holidayAPI.fetchHolidays(forMonth: month) { [weak self] holidays, error in
            guard let self else { return }
            DispatchQueue.main.async {
                guard generation == self.fetchGeneration else { return }
                self.pendingFetches = max(0, self.pendingFetches - 1)

                if let error {
                    let message = "API错误: \(error.localizedDescription)"
                    self.lastFetchError = message
                    print(message)
                    if self.pendingFetches == 0 {
                        self.onAPIError?(message)
                    }
                    return
                }

                if let holidays {
                    for holiday in holidays {
                        self.holidayInfo[holiday.date] = holiday
                    }
                }

                self.onCalendarUpdate?()

                if self.pendingFetches == 0 {
                    if let err = self.lastFetchError, self.holidayInfo.isEmpty {
                        self.onAPIError?(err)
                    } else {
                        self.onAPIIdle?()
                    }
                }
            }
        }
    }

    func subscribe(onTimeUpdate: @escaping () -> Void, onCalendarUpdate: @escaping () -> Void) {
        self.onTimeUpdate = onTimeUpdate
        self.onCalendarUpdate = onCalendarUpdate
        if tick == nil {
            onCalendarUpdate()
            setDateFormat()
        }
    }

    func pause() {
        timer?.invalidate()
        timer = nil
        tick = nil
    }

    func itemCount() -> Int { shownItemCount }

    func getItemAt(index: Int) -> Day {
        var day = Day()
        if index < daysInWeek {
            day.text = weekdays[(calendar.firstWeekday + index - 1) % daysInWeek]
            return day
        }

        let dayOffset = index - daysInWeek
        guard let lastFirstWeekday = lastFirstWeekdayLastMonth,
              let currentMonth else { return day }
        let date = calendar.date(byAdding: .day, value: dayOffset, to: lastFirstWeekday)!

        day.isNumber = true
        day.text = String(calendar.ordinality(of: .day, in: .month, for: date) ?? 0)
        day.isCurrentMonth = calendar.isDate(date, equalTo: currentMonth, toGranularity: .month)
        day.isToday = calendar.isDateInToday(date)

        let dateString = dateFormatter.string(from: date)
        if let holidayData = holidayInfo[dateString] {
            day.holidayDaycode = holidayData.daycode
            if holidayData.lunarday == "初一" {
                day.lunarDay = holidayData.lunarmonth
            } else {
                day.lunarDay = holidayData.lunarday
            }
        }

        let weekday = calendar.component(.weekday, from: date)
        day.isWeekend = weekday == 1 || weekday == 7
        return day
    }

    func getFormattedDate() -> String {
        guard let tick else { return "" }
        return formatter.string(from: tick)
    }

    func getMonth() -> String {
        guard let currentMonth else { return "" }
        return monthFormatter.string(from: currentMonth)
    }

    /// Lunar date for the header under「月份 年」.
    /// Current month → today; other months → that month's 1st.
    /// Example: `丙午年 七月初九`
    func getLunarMonthHeader() -> String {
        guard let currentMonth else { return "" }
        let now = Date()
        let reference: Date
        if calendar.isDate(currentMonth, equalTo: now, toGranularity: .month) {
            reference = now
        } else {
            let parts = calendar.dateComponents([.year, .month], from: currentMonth)
            guard let firstOfMonth = calendar.date(from: parts) else { return "" }
            reference = firstOfMonth
        }
        return formatLunarDate(reference)
    }

    private func formatLunarDate(_ date: Date) -> String {
        let chineseCal = Calendar(identifier: .chinese)
        let comps = chineseCal.dateComponents([.year, .month, .day], from: date)
        guard let year = comps.year, let month = comps.month, let day = comps.day,
              (1...12).contains(month), (1...30).contains(day) else { return "" }

        let stems = ["甲", "乙", "丙", "丁", "戊", "己", "庚", "辛", "壬", "癸"]
        let branches = ["子", "丑", "寅", "卯", "辰", "巳", "午", "未", "申", "酉", "戌", "亥"]
        let months = ["正月", "二月", "三月", "四月", "五月", "六月",
                      "七月", "八月", "九月", "十月", "冬月", "腊月"]
        let days = [
            "初一", "初二", "初三", "初四", "初五", "初六", "初七", "初八", "初九", "初十",
            "十一", "十二", "十三", "十四", "十五", "十六", "十七", "十八", "十九", "二十",
            "廿一", "廿二", "廿三", "廿四", "廿五", "廿六", "廿七", "廿八", "廿九", "三十",
        ]

        let ganZhi = stems[(year - 1) % 10] + branches[(year - 1) % 12]
        // Leap months share the previous month's number in Chinese calendar.
        let isLeap: Bool = {
            guard let previous = chineseCal.date(byAdding: .month, value: -1, to: date) else {
                return false
            }
            return chineseCal.component(.month, from: previous) == month
        }()
        let leap = isLeap ? "闰" : ""
        return "\(ganZhi)年 \(leap)\(months[month - 1])\(days[day - 1])"
    }

    func incrementMonth() {
        monthOffset += 1
        updateCurrentlyShownDays()
        onCalendarUpdate?()
    }

    func decrementMonth() {
        monthOffset -= 1
        updateCurrentlyShownDays()
        onCalendarUpdate?()
    }

    func resetMonth() {
        monthOffset = 0
        updateCurrentlyShownDays()
        onCalendarUpdate?()
    }

    func refreshHolidayData() {
        guard let currentMonth else { return }
        beginHolidayFetch()
        let lastMonth = calendar.date(byAdding: .month, value: -1, to: currentMonth)!
        let nextMonth = calendar.date(byAdding: .month, value: 1, to: currentMonth)!
        fetchHolidayData(forMonth: lastMonth)
        fetchHolidayData(forMonth: currentMonth)
        fetchHolidayData(forMonth: nextMonth)
    }
}

// MARK: - Day cell

final class DayCellView: NSView {
    private let dayLabel = NSTextField(labelWithString: "")
    private let lunarLabel = NSTextField(labelWithString: "")
    private let holidayLabel = NSTextField(labelWithString: "")

    private let holidayTextColor = NSColor(red: 212 / 255, green: 57 / 255, blue: 0, alpha: 1)
    private let workdayTextColor = NSColor(red: 90 / 255, green: 90 / 255, blue: 90 / 255, alpha: 1)
    private let holidayBackgroundColor = NSColor(red: 253 / 255, green: 247 / 255, blue: 244 / 255, alpha: 1)
    private let workdayBackgroundColor = NSColor(red: 221 / 255, green: 221 / 255, blue: 221 / 255, alpha: 1)
    private let todayBorderColor = NSColor(red: 0.149, green: 0.286, blue: 0.859, alpha: 1)

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.cornerRadius = 6
        layer?.masksToBounds = true

        for label in [dayLabel, lunarLabel, holidayLabel] {
            label.isBezeled = false
            label.drawsBackground = false
            label.isEditable = false
            label.isSelectable = false
            label.alignment = .center
            label.lineBreakMode = .byClipping
            addSubview(label)
        }

        dayLabel.font = NSFont.systemFont(ofSize: 15)
        lunarLabel.font = NSFont.systemFont(ofSize: 8)
        lunarLabel.textColor = NSColor.secondaryLabelColor
        holidayLabel.font = NSFont.systemFont(ofSize: 9)
        holidayLabel.textColor = holidayTextColor
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override func layout() {
        super.layout()
        let w = bounds.width
        dayLabel.frame = NSRect(x: 0, y: bounds.height - 22, width: w, height: 20)
        lunarLabel.frame = NSRect(x: 0, y: 1, width: w, height: 12)
        holidayLabel.frame = NSRect(x: -2, y: bounds.height - 15, width: 17, height: 14)
    }

    func configure(_ day: Day) {
        dayLabel.stringValue = day.text
        lunarLabel.stringValue = day.isNumber ? (day.lunarDay ?? "") : ""
        holidayLabel.stringValue = ""

        layer?.backgroundColor = CGColor.clear
        layer?.borderWidth = 0
        layer?.borderColor = CGColor.clear
        alphaValue = 1
        dayLabel.textColor = NSColor.textColor
        holidayLabel.textColor = holidayTextColor

        if !day.isNumber {
            dayLabel.font = NSFont.boldSystemFont(ofSize: 15)
            dayLabel.textColor = NSColor.secondaryLabelColor
            lunarLabel.stringValue = ""
            return
        }

        dayLabel.font = NSFont.systemFont(ofSize: 15)
        dayLabel.textColor = NSColor.textColor
        alphaValue = day.isCurrentMonth ? 1 : 0.4

        if day.isToday {
            layer?.borderWidth = 1
            layer?.borderColor = todayBorderColor.cgColor
        }

        switch day.holidayDaycode {
        case 1:
            holidayLabel.stringValue = "休"
            layer?.backgroundColor = holidayBackgroundColor.cgColor
            dayLabel.textColor = holidayTextColor
        case 3:
            holidayLabel.stringValue = "班"
            holidayLabel.textColor = workdayTextColor
            layer?.backgroundColor = workdayBackgroundColor.cgColor
        default:
            break
        }

        if day.isWeekend, holidayLabel.stringValue.isEmpty {
            dayLabel.textColor = holidayTextColor
        }
    }
}

// MARK: - Calendar menu view

final class CalendarMenuView: NSView {
    let model: CalendarModel

    private let monthButton = NSButton(title: "", target: nil, action: nil)
    private let lunarLabel = NSTextField(labelWithString: "")
    private let leftButton = NSButton(title: "◀", target: nil, action: nil)
    private let rightButton = NSButton(title: "▶", target: nil, action: nil)
    private var cells: [DayCellView] = []

    private let contentWidth: CGFloat = 330
    private let cellWidth: CGFloat = 40
    private let cellHeight: CGFloat = 35
    private let interitem: CGFloat = 8
    private let columns = 7
    private let headerHeight: CGFloat = 52

    init(model: CalendarModel) {
        self.model = model
        let rows = model.itemCount() / columns
        let gridHeight = CGFloat(rows) * cellHeight
        let totalHeight: CGFloat = headerHeight + gridHeight
        super.init(frame: NSRect(x: 0, y: 0, width: 350, height: totalHeight))

        setupHeader()
        setupGrid(rows: rows)
        reload()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    private func setupHeader() {
        for button in [leftButton, rightButton, monthButton] {
            button.isBordered = false
            button.setButtonType(.momentaryChange)
            button.wantsLayer = true
            addSubview(button)
        }

        lunarLabel.isBezeled = false
        lunarLabel.drawsBackground = false
        lunarLabel.isEditable = false
        lunarLabel.isSelectable = false
        lunarLabel.alignment = .center
        lunarLabel.font = NSFont.systemFont(ofSize: 11)
        lunarLabel.textColor = NSColor.secondaryLabelColor
        addSubview(lunarLabel)

        leftButton.target = self
        leftButton.action = #selector(leftClicked)
        rightButton.target = self
        rightButton.action = #selector(rightClicked)
        monthButton.target = self
        monthButton.action = #selector(monthClicked)

        layoutHeader()

        styleNavButton(leftButton)
        styleNavButton(rightButton)
        styleMonthButton(monthButton)
    }

    private func layoutHeader() {
        // Title + lunar stacked near the top; arrows vertically centered on that stack.
        let topPad: CGFloat = 2
        let monthH: CGFloat = 22
        let lunarH: CGFloat = 14
        let stackGap: CGFloat = 1
        let stackH = monthH + stackGap + lunarH
        let contentTop = bounds.height - topPad
        let stackBottom = contentTop - stackH
        let stackMidY = stackBottom + stackH / 2
        let arrowH: CGFloat = 22

        monthButton.frame = NSRect(x: 80, y: contentTop - monthH, width: 190, height: monthH)
        lunarLabel.frame = NSRect(x: 40, y: stackBottom, width: 270, height: lunarH)
        leftButton.frame = NSRect(x: 0, y: stackMidY - arrowH / 2, width: 60, height: arrowH)
        rightButton.frame = NSRect(x: 290, y: stackMidY - arrowH / 2, width: 60, height: arrowH)
    }

    private func setupGrid(rows: Int) {
        let originX: CGFloat = 10
        let originY: CGFloat = 0
        cells.reserveCapacity(model.itemCount())

        for index in 0..<model.itemCount() {
            let row = index / columns
            let col = index % columns
            // Cocoa coords: row 0 is bottom visually if we don't flip — put
            // weekday headers at the top by inverting row.
            let visualRow = rows - 1 - row
            let x = originX + CGFloat(col) * (cellWidth + interitem)
            let y = originY + CGFloat(visualRow) * cellHeight
            let cell = DayCellView(frame: NSRect(x: x, y: y, width: cellWidth, height: cellHeight))
            addSubview(cell)
            cells.append(cell)
        }
    }

    private func styleNavButton(_ button: NSButton) {
        let color = NSColor.tertiaryLabelColor
        let font = NSFont.systemFont(ofSize: 13, weight: .light)
        let style = NSMutableParagraphStyle()
        style.alignment = .center

        func attrs(alpha: CGFloat) -> [NSAttributedString.Key: Any] {
            [
                .foregroundColor: color.withAlphaComponent(alpha),
                .font: font,
                .paragraphStyle: style,
                .kern: 0.5,
            ]
        }
        button.attributedTitle = NSAttributedString(string: button.title, attributes: attrs(alpha: 1.0))
        button.attributedAlternateTitle = NSAttributedString(string: button.title, attributes: attrs(alpha: 0.5))
        button.alignment = .center
    }

    private func styleMonthButton(_ button: NSButton) {
        let color = NSColor.labelColor
        let font = NSFont.systemFont(ofSize: 16, weight: .medium)
        let style = NSMutableParagraphStyle()
        style.alignment = .center

        func attrs(alpha: CGFloat) -> [NSAttributedString.Key: Any] {
            [
                .foregroundColor: color.withAlphaComponent(alpha),
                .font: font,
                .paragraphStyle: style,
                .kern: 0.3,
            ]
        }
        button.attributedTitle = NSAttributedString(string: button.title, attributes: attrs(alpha: 0.9))
        button.attributedAlternateTitle = NSAttributedString(string: button.title, attributes: attrs(alpha: 0.5))
        button.alignment = .center
    }

    func reload() {
        monthButton.title = model.getMonth()
        styleMonthButton(monthButton)
        styleNavButton(leftButton)
        styleNavButton(rightButton)
        lunarLabel.stringValue = model.getLunarMonthHeader()

        let count = min(cells.count, model.itemCount())
        for i in 0..<count {
            cells[i].configure(model.getItemAt(index: i))
        }
        needsDisplay = true
    }

    @objc private func leftClicked() { model.decrementMonth() }
    @objc private func rightClicked() { model.incrementMonth() }
    @objc private func monthClicked() { model.resetMonth() }
}

// MARK: - Month abbreviation bar (above Settings)

final class MonthAbbreviationView: NSView {
    private static let abbreviations = [
        "Jan", "Feb", "Mar", "Apr", "May", "Jun",
        "Jul", "Aug", "Sep", "Oct", "Nov", "Dec",
    ]
    private static let fullNames = [
        "January", "February", "March", "April", "May", "June",
        "July", "August", "September", "October", "November", "December",
    ]

    private var buttons: [NSButton] = []
    private var expandedIndex: Int?

    init() {
        super.init(frame: NSRect(x: 0, y: 0, width: 350, height: 28))
        setupButtons()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    private func setupButtons() {
        for (index, abbr) in Self.abbreviations.enumerated() {
            let button = NSButton(title: abbr, target: self, action: #selector(monthTapped(_:)))
            button.tag = index
            button.isBordered = false
            button.setButtonType(.momentaryChange)
            button.wantsLayer = true
            button.alignment = .center
            addSubview(button)
            buttons.append(button)
        }
        layoutButtons()
        refreshTitles()
    }

    override func layout() {
        super.layout()
        layoutButtons()
    }

    private func layoutButtons() {
        guard !buttons.isEmpty else { return }
        // Match calendar grid side inset so Jan/Dec sit at the content edges.
        let inset: CGFloat = 10
        let available = max(bounds.width - inset * 2, 1)
        var widths: [CGFloat] = []
        var totalPreferred: CGFloat = 0

        for index in buttons.indices {
            let title = displayTitle(for: index)
            let font = titleFont(expanded: index == expandedIndex)
            let width = max((title as NSString).size(withAttributes: [.font: font]).width + 4, 1)
            widths.append(width)
            totalPreferred += width
        }

        // Always stretch so the row spans full width (minus inset).
        let scale = available / totalPreferred
        var x = inset
        for (index, button) in buttons.enumerated() {
            let w = widths[index] * scale
            button.frame = NSRect(x: x, y: 2, width: w, height: bounds.height - 4)
            x += w
        }
    }

    private func displayTitle(for index: Int) -> String {
        index == expandedIndex ? Self.fullNames[index] : Self.abbreviations[index]
    }

    private func titleFont(expanded: Bool) -> NSFont {
        NSFont.systemFont(ofSize: expanded ? 11 : 10, weight: expanded ? .medium : .regular)
    }

    private func refreshTitles() {
        for (index, button) in buttons.enumerated() {
            let expanded = index == expandedIndex
            let title = displayTitle(for: index)
            let color = expanded ? NSColor.labelColor : NSColor.secondaryLabelColor
            let font = titleFont(expanded: expanded)
            let style = NSMutableParagraphStyle()
            style.alignment = .center

            func attrs(alpha: CGFloat) -> [NSAttributedString.Key: Any] {
                [
                    .foregroundColor: color.withAlphaComponent(alpha),
                    .font: font,
                    .paragraphStyle: style,
                ]
            }
            button.attributedTitle = NSAttributedString(string: title, attributes: attrs(alpha: 1))
            button.attributedAlternateTitle = NSAttributedString(string: title, attributes: attrs(alpha: 0.55))
        }
        layoutButtons()
    }

    @objc private func monthTapped(_ sender: NSButton) {
        let index = sender.tag
        expandedIndex = (expandedIndex == index) ? nil : index
        refreshTitles()
    }
}

// MARK: - Settings window

final class SettingsWindowController: NSWindowController {
    private let model: CalendarModel
    private var boxes: [NSButton] = []

    init(model: CalendarModel) {
        self.model = model
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 410, height: 250),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "Settings"
        window.isReleasedWhenClosed = false
        window.center()
        super.init(window: window)
        buildUI()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    private func buildUI() {
        guard let content = window?.contentView else { return }

        let timeLabel = makeSectionLabel("Time options")
        timeLabel.frame = NSRect(x: 31, y: 196, width: 93, height: 22)
        content.addSubview(timeLabel)

        let dateLabel = makeSectionLabel("Date options")
        dateLabel.frame = NSRect(x: 31, y: 68, width: 93, height: 22)
        content.addSubview(dateLabel)

        let titles = [
            "Show the time with seconds",
            "Use a 24-hour clock",
            "Show AM/PM",
            "Show date",
            "Show the day of the week",
        ]
        let ys: [CGFloat] = [194, 162, 130, 66, 34]

        for (i, title) in titles.enumerated() {
            let box = NSButton(checkboxWithTitle: title, target: self, action: #selector(checkBoxClicked(_:)))
            box.tag = i + 1
            box.frame = NSRect(x: 139, y: ys[i], width: 220, height: 30)
            content.addSubview(box)
            boxes.append(box)
        }

        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—"
        let versionLabel = NSTextField(labelWithString: "v\(version)")
        versionLabel.alignment = .center
        versionLabel.textColor = .tertiaryLabelColor
        versionLabel.font = NSFont.systemFont(ofSize: 11)
        versionLabel.frame = NSRect(x: 0, y: 8, width: 410, height: 16)
        content.addSubview(versionLabel)

        refreshBoxes()
    }

    private func makeSectionLabel(_ title: String) -> NSTextField {
        let label = NSTextField(labelWithString: title)
        label.alignment = .right
        label.textColor = .secondaryLabelColor
        return label
    }

    func refreshBoxes() {
        let values = [
            Settings.showSeconds,
            Settings.use24Hours,
            Settings.showAMPM,
            Settings.showDate,
            Settings.showDayOfWeek,
        ]
        for (i, box) in boxes.enumerated() {
            box.state = values[i] ? .on : .off
        }
        updateAMPMEnabled()
    }

    private func updateAMPMEnabled() {
        guard boxes.count >= 3 else { return }
        boxes[2].isEnabled = boxes[1].state == .off
    }

    @objc private func checkBoxClicked(_ sender: NSButton) {
        switch sender.tag {
        case 1: Settings.showSeconds = sender.state == .on
        case 2: Settings.use24Hours = sender.state == .on
        case 3: Settings.showAMPM = sender.state == .on
        case 4: Settings.showDate = sender.state == .on
        case 5: Settings.showDayOfWeek = sender.state == .on
        default: break
        }
        updateAMPMEnabled()
        model.setDateFormat()
    }
}

// MARK: - API status row (custom view so clicks don't dismiss the menu)

final class APIStatusView: NSView {
    private let button = NSButton(title: "", target: nil, action: nil)
    private(set) var message: String = ""

    var onClick: (() -> Void)?

    init() {
        super.init(frame: NSRect(x: 0, y: 0, width: 350, height: 22))
        button.isBordered = false
        button.alignment = .left
        button.lineBreakMode = .byTruncatingTail
        button.target = self
        button.action = #selector(clicked)
        button.frame = NSRect(x: 14, y: 1, width: 322, height: 20)
        addSubview(button)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    func setMessage(_ text: String, color: NSColor) {
        message = text
        let attrs: [NSAttributedString.Key: Any] = [
            .foregroundColor: color,
            .font: NSFont.menuFont(ofSize: 0),
        ]
        button.attributedTitle = NSAttributedString(string: text, attributes: attrs)
    }

    @objc private func clicked() {
        onClick?()
    }
}

// MARK: - App controller

final class AppController: NSObject, NSMenuDelegate {
    private let model = CalendarModel()
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private var calendarView: CalendarMenuView!
    private var settingsController: SettingsWindowController!
    private var statusMenu: NSMenu!
    private var apiMenuItem: NSMenuItem!
    private var apiStatusView: APIStatusView!
    private var refreshing = false

    func start() {
        Settings.registerDefaults()
        calendarView = CalendarMenuView(model: model)
        settingsController = SettingsWindowController(model: model)

        statusMenu = NSMenu()
        statusMenu.delegate = self

        let calendarItem = NSMenuItem()
        calendarItem.view = calendarView
        statusMenu.addItem(calendarItem)
        statusMenu.addItem(.separator())

        let monthAbbrevItem = NSMenuItem()
        monthAbbrevItem.view = MonthAbbreviationView()
        statusMenu.addItem(monthAbbrevItem)

        let settingsItem = NSMenuItem(title: "Settings", action: #selector(openSettings), keyEquivalent: ",")
        settingsItem.target = self
        statusMenu.addItem(settingsItem)

        // Custom view: clicking the status/error row refreshes without dismissing the menu.
        apiStatusView = APIStatusView()
        apiStatusView.onClick = { [weak self] in self?.refreshHolidays() }
        apiMenuItem = NSMenuItem()
        apiMenuItem.view = apiStatusView
        apiMenuItem.isHidden = true
        statusMenu.addItem(apiMenuItem)

        statusItem.menu = statusMenu
        if let button = statusItem.button {
            button.font = NSFont.monospacedDigitSystemFont(ofSize: button.font?.pointSize ?? 13, weight: .regular)
        }

        bindModelCallbacks()
    }

    func resume() {
        bindModelCallbacks()
    }

    func pause() {
        model.pause()
        model.onAPIError = nil
        model.onAPIIdle = nil
    }

    func menuWillOpen(_ menu: NSMenu) {
        updateCalendar()
        updateMenuTime()
    }

    private func bindModelCallbacks() {
        model.subscribe(onTimeUpdate: { [weak self] in self?.updateMenuTime() },
                        onCalendarUpdate: { [weak self] in self?.updateCalendar() })
        model.onAPIError = { [weak self] message in self?.updateErrorDisplay(message: message) }
        model.onAPIIdle = { [weak self] in
            guard let self, !self.refreshing else { return }
            self.updateErrorDisplay(message: nil)
        }
    }

    private func updateMenuTime() {
        statusItem.button?.title = model.getFormattedDate()
    }

    private func updateCalendar() {
        calendarView.reload()
    }

    /// Mirrors Calendar-master: show error under Settings; hide the row on success.
    private func updateErrorDisplay(message: String?) {
        if let errorMessage = message {
            refreshing = false
            apiMenuItem.isHidden = false
            let color = NSColor(red: 212 / 255, green: 57 / 255, blue: 0, alpha: 1)
            apiStatusView.setMessage(errorMessage, color: color)
        } else {
            refreshing = false
            apiMenuItem.isHidden = true
        }
    }

    @objc private func openSettings() {
        settingsController.refreshBoxes()
        settingsController.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func refreshHolidays() {
        refreshing = true
        apiMenuItem.isHidden = false
        let color = NSColor(red: 0, green: 122 / 255, blue: 1, alpha: 1)
        apiStatusView.setMessage("正在刷新...", color: color)
        model.refreshHolidayData()
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in
            guard let self else { return }
            if self.apiStatusView.message == "正在刷新..." {
                self.updateErrorDisplay(message: nil)
            }
        }
    }
}

// MARK: - App delegate

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let controller = AppController()

    func applicationWillFinishLaunching(_ notification: Notification) {
        Settings.registerDefaults()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        controller.start()
    }

    func applicationDidChangeOcclusionState(_ notification: Notification) {
        if NSApp.occlusionState.contains(.visible) {
            controller.resume()
        } else {
            controller.pause()
        }
    }
}

// MARK: - main

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
