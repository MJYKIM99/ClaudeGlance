//
//  L10n.swift
//  ClaudeGlance
//
//  Minimal in-app localization for the HUD-facing strings.
//  Full SwiftUI localization would require .strings catalogs; this
//  covers the dynamic strings the app generates at runtime, which
//  catalogs can't reach anyway.
//

import Foundation

enum AppLanguage: String {
    case system = "system"
    case english = "en"
    case chinese = "zh"

    static var current: AppLanguage {
        let stored = UserDefaults.standard.string(forKey: Defaults.appLanguage) ?? "system"
        let lang = AppLanguage(rawValue: stored) ?? .system
        if lang == .system {
            return Locale.preferredLanguages.first?.hasPrefix("zh") == true ? .chinese : .english
        }
        return lang
    }
}

enum L10n {
    private static let zh: [String: String] = [
        // Status lines (SessionManager / SessionCard)
        "Starting session": "会话启动中",
        "Reading request": "读取请求",
        "Still thinking...": "仍在思考…",
        "Waiting for response...": "等待回复…",
        "Task completed": "任务完成",
        "Task failed": "任务失败",
        "Interrupted": "已中断",
        "Compacting context": "压缩上下文",
        "Spawning subagent": "启动子代理",
        "Processing...": "处理中…",
        "Reporting update": "汇报更新",
        "Waiting for input": "等待输入",
        "Idle (waiting for input)": "空闲(等待输入)",
        // Tool actions
        "Reading file": "读取文件",
        "Writing file": "写入文件",
        "Editing file": "编辑文件",
        "Running command": "运行命令",
        "Searching files": "搜索文件",
        "Searching content": "搜索内容",
        "Spawning agent": "启动代理",
        "Fetching web": "获取网页",
        "Searching web": "搜索网页",
        "Updating todos": "更新待办",
        "Editing notebook": "编辑笔记本",
        "Continuing command": "继续命令",
        "Applying patch": "应用补丁",
        "Updating plan": "更新计划",
        "Generating image": "生成图片",
        "Requesting input": "请求输入",
        // Card chrome
        "auto-hide in ": "将于 ",
        "Dismiss this session": "关闭此会话",
        "Copy Session ID": "复制会话 ID",
        "Copy Project Path": "复制项目路径",
        "Open in Finder": "在 Finder 中打开",
        "View Transcript": "查看会话记录",
        "Dismiss": "关闭",
        "Focus Terminal": "聚焦终端",
        // Menu bar
        "Show HUD": "显示悬浮窗",
        "Hide HUD": "隐藏悬浮窗",
        "Notch HUD (Experimental)": "刘海 HUD(实验)",
        "Auto Expand on Activity": "有活动时自动展开",
        "Desktop Pet": "桌面宠物",
        "Pet Theme": "宠物主题",
        "Pet Animation Speed": "宠物动画速度",
        "Today's Stats": "今日统计",
        "Tool Calls": "工具调用",
        "Sessions": "会话数",
        "Top": "最常用",
        "Active Time": "活跃时长",
        "7-Day Trend": "7 天趋势",
        "Active Sessions": "活跃会话",
        "Restart Service": "重启服务",
        "Settings...": "设置…",
        "Quit": "退出",
        "Service": "服务",
        "Checking...": "检查中…",
        "Starting...": "启动中…",
        "Running": "运行中",
        "Not Running": "未运行",
        "today": "今日",
        "no data": "无数据",
        // Card actions
        "Pin to Top": "置顶",
        "Unpin from Top": "取消置顶",
        "Set Label...": "设置标签…",
        "Remove Label": "移除标签",
        "Session Label": "会话标签",
        "events": "条记录",
        "Collapse all": "全部收起",
        "Dismiss all": "清空已完成",
    ]

    /// Translate a HUD string. Unknown keys fall back to the source
    /// text, so partial coverage degrades gracefully to English.
    static func tr(_ key: String) -> String {
        if AppLanguage.current == .chinese, let zh = zh[key] {
            return zh
        }
        return key
    }

    /// Strings with a runtime suffix (e.g. "auto-hide in 42s") can't
    /// be looked up whole — this handles the one such format.
    static func autoHideIn(_ seconds: Int) -> String {
        AppLanguage.current == .chinese ? "将于 \(seconds)s 后隐藏" : "auto-hide in \(seconds)s"
    }

    static func toolFailed(_ tool: String) -> String {
        AppLanguage.current == .chinese ? "工具失败: \(tool)" : "Tool failed: \(tool)"
    }

    static func historyCount(_ count: Int) -> String {
        AppLanguage.current == .chinese ? "\(count) 条记录" : "\(count) events"
    }

    static func activeCount(_ count: Int) -> String {
        AppLanguage.current == .chinese ? "\(count) 个会话" : "\(count) active"
    }
}
