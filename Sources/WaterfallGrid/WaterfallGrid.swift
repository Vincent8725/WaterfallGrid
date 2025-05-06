//
//  Copyright © 2019 Paolo Leonardi.
//
//  Licensed under the MIT license. See the LICENSE file for more info.
//

import SwiftUI

/// A container that presents items of variable heights arranged in a grid.
@available(iOS 13, OSX 10.15, tvOS 13, visionOS 1, watchOS 6, *)
public struct WaterfallGrid<Data, ID, Content>: View where Data : RandomAccessCollection, Content : View, ID : Hashable {

    @Environment(\.gridStyle) private var style
    @Environment(\.scrollOptions) private var scrollOptions

    private let data: Data
    private let dataId: KeyPath<Data.Element, ID>
    private let content: (Data.Element) -> Content

    @State private var loaded = false
    @State private var gridHeight: CGFloat = 0
    @State private var alignmentGuides = [AnyHashable: CGPoint]() {
        didSet { loaded = !oldValue.isEmpty }
    }
    // 新增: 用于存储每个元素的最新 Preference 数据
    @State private var elementPreferences = [AnyHashable: ElementPreferenceData]()
    // 新增: 用于防抖处理的 DispatchWorkItem
    @State private var recalculationTask: DispatchWorkItem? = nil

    public var body: some View {
        VStack {
            GeometryReader { geometry in
                self.grid(in: geometry)
                    // 修改 .onPreferenceChange 的处理逻辑
                    .onPreferenceChange(ElementPreferenceKey.self) { incomingPreferences in
                        // 取消任何已存在的、还未执行的重新计算任务
                        self.recalculationTask?.cancel()

                        // 将传入的 Preference 数组转换为字典，方便查找和比较
                        // 注意：这里的 incomingPreferences 包含了本次更新周期内所有报告了 Preference 的子视图信息
                        let incomingPrefsDict = Dictionary(incomingPreferences.map { ($0.id, $0) }, uniquingKeysWith: { $1 })

                        // 检查新的 Preference 信息是否与已存储的不同
                        // 注意：这需要 ElementPreferenceData 遵循 Equatable 协议
                        // 使用 NSDictionary 是比较字典的一种方式，也可以手动比较
                        if !NSDictionary(dictionary: self.elementPreferences).isEqual(to: incomingPrefsDict) {

                            // 如果信息有变，则更新存储的 Preference
                            self.elementPreferences = incomingPrefsDict

                            // 创建一个新的防抖任务
                            let task = DispatchWorkItem {
                                // 使用当前存储的所有元素的 Preference 数据进行计算
                                let currentPreferencesArray = Array(self.elementPreferences.values)
                                // 在后台线程执行计算密集型任务
                                DispatchQueue.global(qos: .userInteractive).async {
                                    let (newAlignmentGuides, newGridHeight) = self.alignmentsAndGridHeight(
                                        columns: self.style.columns,
                                        spacing: self.style.spacing,
                                        scrollDirection: self.scrollOptions.direction,
                                        preferences: currentPreferencesArray // 使用更新后的完整数据
                                    )
                                    // 计算完成后，回到主线程更新 UI 相关的状态
                                    DispatchQueue.main.async {
                                        // 在更新状态前，再次检查任务是否已被取消（可能在等待期间有新的更新进来）
                                        if !(self.recalculationTask?.isCancelled ?? true) {
                                            self.alignmentGuides = newAlignmentGuides
                                            self.gridHeight = newGridHeight
                                        }
                                    }
                                }
                            }
                            // 将新任务赋值给 state 变量
                            self.recalculationTask = task
                            // 延迟一小段时间后执行任务（例如 50 毫秒），实现防抖效果
                            // 这可以防止在短时间内（如图片快速加载）发生多次昂贵的计算
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05, execute: task)
                        }
                    }
            }
        }
        .frame(width: self.scrollOptions.direction == .horizontal ? gridHeight : nil,
               height: self.scrollOptions.direction == .vertical ? gridHeight : nil)
    }

    private func grid(in geometry: GeometryProxy) -> some View {
        let columnWidth = self.columnWidth(columns: style.columns, spacing: style.spacing,
                                           scrollDirection: scrollOptions.direction, geometrySize: geometry.size)
        return
            ZStack(alignment: .topLeading) {
                ForEach(data, id: self.dataId) { element in
                    self.content(element)
                        .frame(width: self.scrollOptions.direction == .vertical ? columnWidth : nil,
                               height: self.scrollOptions.direction == .horizontal ? columnWidth : nil)
                        .background(PreferenceSetter(id: element[keyPath: self.dataId]))
                        .alignmentGuide(.top, computeValue: { _ in self.alignmentGuides[element[keyPath: self.dataId]]?.y ?? 0 })
                        .alignmentGuide(.leading, computeValue: { _ in self.alignmentGuides[element[keyPath: self.dataId]]?.x ?? 0 })
                        .opacity(self.alignmentGuides[element[keyPath: self.dataId]] != nil ? 1 : 0)
                }
            }
            .animation(self.loaded ? self.style.animation : nil, value: UUID())
    }

    // MARK: - Helpers

    func alignmentsAndGridHeight(columns: Int, spacing: CGFloat, scrollDirection: Axis.Set, preferences: [ElementPreferenceData]) -> ([AnyHashable: CGPoint], CGFloat) {
        var heights = Array(repeating: CGFloat(0), count: columns)
        var alignmentGuides = [AnyHashable: CGPoint]()

        preferences.forEach { preference in
            if let minValue = heights.min(), let indexMin = heights.firstIndex(of: minValue) {
                let preferenceSizeWidth = scrollDirection == .vertical ? preference.size.width : preference.size.height
                let preferenceSizeHeight = scrollDirection == .vertical ? preference.size.height : preference.size.width
                let width = preferenceSizeWidth * CGFloat(indexMin) + CGFloat(indexMin) * spacing
                let height = heights[indexMin]
                let offset = CGPoint(x: 0 - (scrollDirection == .vertical ? width : height),
                                     y: 0 - (scrollDirection == .vertical ? height : width))
                heights[indexMin] += preferenceSizeHeight + spacing
                alignmentGuides[preference.id] = offset
            }
        }
        
        let gridHeight = max(0, (heights.max() ?? spacing) - spacing)
        
        return (alignmentGuides, gridHeight)
    }

    func columnWidth(columns: Int, spacing: CGFloat, scrollDirection: Axis.Set, geometrySize: CGSize) -> CGFloat {
        let geometrySizeWidth = scrollDirection == .vertical ? geometrySize.width : geometrySize.height
        let width = max(0, geometrySizeWidth - (spacing * (CGFloat(columns) - 1)))
        return width / CGFloat(columns)
    }
}

// MARK: - Initializers

extension WaterfallGrid {

    /// Creates an instance that uniquely identifies views across updates based
    /// on the `id` key path to a property on an underlying data element.
    ///
    /// - Parameter data: A collection of data.
    /// - Parameter id: Key path to a property on an underlying data element.
    /// - Parameter content: A function that can be used to generate content on demand given underlying data.
    public init(_ data: Data, id: KeyPath<Data.Element, ID>, content: @escaping (Data.Element) -> Content) {
        self.data = data
        self.dataId = id
        self.content = content
    }

}

extension WaterfallGrid where ID == Data.Element.ID, Data.Element : Identifiable {

    /// Creates an instance that uniquely identifies views across updates based
    /// on the identity of the underlying data element.
    ///
    /// - Parameter data: A collection of identified data.
    /// - Parameter content: A function that can be used to generate content on demand given underlying data.
    public init(_ data: Data, content: @escaping (Data.Element) -> Content) {
        self.data = data
        self.dataId = \Data.Element.id
        self.content = content
    }

}
