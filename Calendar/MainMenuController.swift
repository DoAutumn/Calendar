//
//  MainMenuController.swift
//  Calendar
//
//  Created by Emil Kreutzman on 23/09/2017.
//  Copyright © 2017 Emil Kreutzman. All rights reserved.
//

import Cocoa

class MainMenuController: NSObject, NSCollectionViewDataSource {
    
    func collectionView(_ collectionView: NSCollectionView, numberOfItemsInSection section: Int) -> Int {
        return controller.itemCount()
    }
    
    func collectionView(_ collectionView: NSCollectionView, itemForRepresentedObjectAt indexPath: IndexPath) -> NSCollectionViewItem {
        let id = NSUserInterfaceItemIdentifier.init(rawValue: "CalendarDayItem")
        
        let item = collectionView.makeItem(withIdentifier: id, for: indexPath)
        guard let calendarItem = item as? CalendarDayItem else {
            return item
        }
        
        let day = controller.getItemAt(index: indexPath.item)
        
        calendarItem.setBold(bold: !day.isNumber)
        calendarItem.setText(text: day.text)
        calendarItem.setPartlyTransparent(partlyTransparent: !day.isCurrentMonth)
        calendarItem.setIsToday(isToday: day.isToday)
        calendarItem.setHolidayInfo(daycode: day.holidayDaycode)
        calendarItem.setIsWeekend(isWeekend: day.isWeekend)
        calendarItem.setLunarDay(lunarDay: day.lunarDay ?? "")
        
        return calendarItem
    }
    
    @IBOutlet weak var controller: CalendarController!
    
    @IBOutlet weak var statusMenu: NSMenu!
    
    @IBOutlet weak var apiMenuItem: NSMenuItem!
    
    @IBOutlet weak var monthLabel: NSButton!
    
    @IBOutlet weak var buttonLeft: NSButton!
    
    @IBOutlet weak var buttonRight: NSButton!
    
    @IBOutlet weak var collectionView: NSCollectionView!
    
    @IBOutlet weak var settingsWindow: NSWindow!
    
    let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    
    private func updateMenuTime() {
        statusItem.title = controller.getFormattedDate()
    }
    
    private func updateCalendar() {
        monthLabel.title = controller.getMonth()
        applyUIModifications()
        collectionView.reloadData()
    }
    
    private func getBasicAttributes(button: NSButton, color: NSColor, alpha: CGFloat) -> [NSAttributedStringKey : Any] {
        let style = NSMutableParagraphStyle()
        style.alignment = .center
        
        return [
            NSAttributedStringKey.foregroundColor: color.withAlphaComponent(alpha),
            NSAttributedStringKey.font: NSFont.systemFont(ofSize: (button.font?.pointSize)!, weight: NSFont.Weight.light),
            NSAttributedStringKey.backgroundColor: NSColor.clear,
            NSAttributedStringKey.paragraphStyle: style,
            NSAttributedStringKey.kern: 0.5 // some additional character spacing
        ]
    }
    
    private func applyButtonHighlightSettings(button: NSButton) {
        let color = NSColor.textColor
        let defaultAlpha: CGFloat = 0.75
        let pressedAlpha: CGFloat = 0.45
        
        let defaultAttributes = getBasicAttributes(button: button, color: color, alpha: defaultAlpha)
        let pressedAttributes = getBasicAttributes(button: button, color: color, alpha: pressedAlpha)
        
        button.attributedTitle = NSAttributedString(string: button.title, attributes: defaultAttributes)
        button.attributedAlternateTitle = NSAttributedString(string: button.title, attributes: pressedAttributes)
        button.alignment = .center
    }
    
    private func applyUIModifications() {
        statusItem.button?.font = NSFont.monospacedDigitSystemFont(ofSize: (statusItem.button?.font?.pointSize)!, weight: .regular)
        
        applyButtonHighlightSettings(button: monthLabel)
        applyButtonHighlightSettings(button: buttonLeft)
        applyButtonHighlightSettings(button: buttonRight)
    }
    
    override func awakeFromNib() {
        super.awakeFromNib()
        // 初始隐藏错误菜单项
        apiMenuItem.isHidden = true
    }
    
    func refreshState() {
        statusItem.menu = statusMenu
        controller.subscribe(onTimeUpdate: updateMenuTime, onCalendarUpdate: updateCalendar)
        
        // 订阅API错误回调
        controller.onAPIError = { [weak self] errorMessage in
           self?.updateErrorDisplay(message: errorMessage)
        }
        
        // 初始隐藏错误菜单项
        // updateErrorDisplay(message: nil)
    }

    // 更新错误信息显示
    private func updateErrorDisplay(message: String?) {
        if let errorMessage = message {
            // 显示错误信息
            apiMenuItem.title = errorMessage
            apiMenuItem.isHidden = false
            // 设置红色文本
            let attributes: [NSAttributedStringKey: Any] = [
                .foregroundColor: NSColor(red: 212/255, green: 57/255, blue: 0.0, alpha: 1.0)
            ]
            apiMenuItem.attributedTitle = NSAttributedString(string: errorMessage, attributes: attributes)
        } else {
            // 隐藏错误信息
            apiMenuItem.isHidden = true
        }
    }
    
    func deactivate() {
        controller.pause()
        // 清空错误回调避免内存泄漏
        controller.onAPIError = nil
    }
    
    @IBAction func openSettingsClicked(_ sender: NSMenuItem) {
        let settingsWindowController = NSWindowController.init(window: settingsWindow)
        settingsWindowController.showWindow(sender)
        
        // bring settings window to front
        NSApp.activate(ignoringOtherApps: true)
    }
    
    @IBAction func leftClicked(_ sender: NSButton) {
        controller.decrementMonth()
    }
    
    @IBAction func rightClicked(_ sender: NSButton) {
        controller.incrementMonth()
    }
    
    @IBAction func clearMonthHopping(_ sender: Any) {
        controller.resetMonth()
    }
    
    @IBAction func refreshHolidayData(_ sender: NSMenuItem) {
        // 重新获取节假日数据
        controller.refreshHolidayData()
        
        // 临时显示刷新提示
        apiMenuItem.title = "正在刷新..."
        apiMenuItem.isHidden = false
        let attributes: [NSAttributedStringKey: Any] = [
            .foregroundColor: NSColor(red: 0.0, green: 122.0/255, blue: 1.0, alpha: 1.0)
        ]
        apiMenuItem.attributedTitle = NSAttributedString(string: "正在刷新...", attributes: attributes)
        
        // 3秒后恢复隐藏状态（如果没有错误）
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
            // 只有在没有错误信息时才隐藏
            if self.apiMenuItem.title == "正在刷新..." {
                self.apiMenuItem.isHidden = true
            }
        }
    }

}
