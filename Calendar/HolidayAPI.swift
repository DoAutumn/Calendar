//
//  HolidayAPI.swift
//  Calendar
//
//  Created by [Your Name] on [Today's Date].
//  Copyright © [Year] [Your Name]. All rights reserved.
//

import Foundation

struct HolidayResponse: Codable {
    let code: Int
    let msg: String
    let result: HolidayResult?

    enum CodingKeys: String, CodingKey {
        case code, msg, result
    }
}

struct HolidayResult: Codable {
    let list: [HolidayInfo]

    enum CodingKeys: String, CodingKey {
        case list
    }
}

struct HolidayInfo: Codable {
    let date: String
    let daycode: Int
    let name: String?
    let lunarday: String?
    let lunarmonth: String?

    enum CodingKeys: String, CodingKey {
        case date
        case daycode
        case name
        case lunarday
        case lunarmonth
    }
}

class HolidayAPI {
    private let apiKey = "5e42ad1becfdcc48c05eb18adea4decf"
    private let baseURL = "https://apis.tianapi.com/jiejiari/index"
    private let session: URLSession
    
    init() {
        // 配置会话超时时间为5秒
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 5.0
        configuration.timeoutIntervalForResource = 5.0
        session = URLSession(configuration: configuration)
    }

    func fetchHolidays(forMonth month: Date, completion: @escaping ([HolidayInfo]?, Error?) -> Void) {
        // 格式化日期为 yyyy-MM 格式
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM"
        let dateString = formatter.string(from: month)

        // 构建请求URL
        guard var urlComponents = URLComponents(string: baseURL) else {
            completion(nil, NSError(domain: "HolidayAPI", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid URL"]))
            return
        }

        urlComponents.queryItems = [
            URLQueryItem(name: "key", value: apiKey),
            URLQueryItem(name: "type", value: "2"), // 按月查询
            URLQueryItem(name: "date", value: dateString)
        ]

        guard let url = urlComponents.url else {
            completion(nil, NSError(domain: "HolidayAPI", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid URL components"]))
            return
        }

        // 发送请求
        let task = session.dataTask(with: url) { (data, response, error) in
            if let error = error {
                completion(nil, error)
                return
            }

            guard let data = data else {
                completion(nil, NSError(domain: "HolidayAPI", code: -1, userInfo: [NSLocalizedDescriptionKey: "No data received"]))
                return
            }

            // 解析JSON
            do {
                let decoder = JSONDecoder()
                let holidayResponse = try decoder.decode(HolidayResponse.self, from: data)

                if holidayResponse.code == 200 {
                    completion(holidayResponse.result?.list ?? [], nil)
                } else {
                    completion(nil, NSError(domain: "HolidayAPI", code: holidayResponse.code, userInfo: [NSLocalizedDescriptionKey: holidayResponse.msg]))
                }
            } catch {
                completion(nil, error)
            }
        }

        task.resume()
    }
}
