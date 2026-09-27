//
//  HealthStoreShared.swift
//  iHealth
//
//  HKHealthStore 全 App 唯一实例。
//
//  Apple 官方推荐：一个 App 只创建一个 HKHealthStore。
//  多实例会导致：
//  · authorizationStatus 缓存不一致
//  · HKObserverQuery 重复注册
//  · 内存中多份查询状态
//

import HealthKit

extension HKHealthStore {
    /// 全 App 共享的唯一实例。
    ///
    /// HKHealthStore 是 Sendable 且线程安全的，用 nonisolated 让它
    /// 可以从任意 actor 上下文访问（绕开 MainActor 默认隔离推断）。
    nonisolated static let shared = HKHealthStore()
}
