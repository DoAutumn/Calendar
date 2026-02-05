//
//  CalendarDayItem.swift
//  Calendar
//
//  Created by Emil Kreutzman on 24/09/2017.
//  Copyright © 2017 Emil Kreutzman. All rights reserved.
//

import Cocoa

class CalendarDayItem: NSCollectionViewItem {
    
    @IBOutlet weak var holidayLabel: NSTextField!
    @IBOutlet weak var lunarDayLabel: NSTextField!
    
    // 颜色定义
    private let holidayTextColor = NSColor(red: 212/255, green: 57/255, blue: 0.0, alpha: 1.0)
    private let workdayTextColor = NSColor(red: 90/255, green: 90/255, blue: 90/255, alpha: 1.0)
    private let holidayBackgroundColor = NSColor(red: 253/255, green: 247/255, blue: 244/255, alpha: 1.0)
    private let workdayBackgroundColor = NSColor(red: 221/255, green: 221/255, blue: 221/255, alpha: 1.0)
    private let todayBorderColor = NSColor(red: 0.149, green: 0.286, blue: 0.859, alpha: 1.0)
    
    public func setIsToday(isToday: Bool) {
        if (isToday) {
            view.layer?.cornerRadius = 6.0
            view.layer?.borderWidth = 1.0
            view.layer?.borderColor = todayBorderColor.cgColor
            view.layer?.backgroundColor = CGColor.clear
        } else {
            view.layer?.borderWidth = 0.0
            view.layer?.borderColor = CGColor.clear
        }
    }
    
    public func setPartlyTransparent(partlyTransparent: Bool) {
        view.layer?.opacity = partlyTransparent ? 0.4 : 1.0
    }
    
    public func setBold(bold: Bool) {
        let fontSize = (textField?.font?.pointSize)!
        if bold {
            textField?.font = NSFont.boldSystemFont(ofSize: fontSize)
        } else {
            textField?.font = NSFont.systemFont(ofSize: fontSize)
        }
    }
    
    public func setHolidayInfo(daycode: Int?) {
        // 重置样式
        view.layer?.backgroundColor = CGColor.clear
        textField?.textColor = NSColor.textColor
        holidayLabel.textColor = holidayTextColor
        
        guard let daycode = daycode else {
            holidayLabel.stringValue = ""
            return
        }
        
        switch daycode {
        case 1: // 法定节假日
            holidayLabel.stringValue = "休"
            view.layer?.backgroundColor = holidayBackgroundColor.cgColor
            textField?.textColor = holidayTextColor
        case 3: // 调休日（需上班）
            holidayLabel.stringValue = "班"
            holidayLabel.textColor = workdayTextColor
            view.layer?.backgroundColor = workdayBackgroundColor.cgColor
        default:
            holidayLabel.stringValue = ""
        }
    }
    
    public func setIsWeekend(isWeekend: Bool) {
        if isWeekend {
            textField?.textColor = holidayTextColor
        } else {
            // 非周末保持默认颜色，除非是节假日
            if holidayLabel.stringValue.isEmpty {
                textField?.textColor = NSColor.textColor
            }
        }
    }
    
    public func setText(text: String) {
        textField?.stringValue = text
    }
    
    public func setLunarDay(lunarDay: String) {
        lunarDayLabel?.stringValue = lunarDay
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        view.wantsLayer = true
        view.layer?.cornerRadius = 6.0
        view.layer?.masksToBounds = true
        textField?.alignment = NSTextAlignment.center
        holidayLabel.stringValue = ""
    }
    
}
