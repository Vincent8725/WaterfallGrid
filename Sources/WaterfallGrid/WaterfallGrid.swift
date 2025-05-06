//
//  Copyright © 2019 Paolo Leonardi.
//
//  Licensed under the MIT license. See the LICENSE file for more info.
//

import SwiftUI

/// A container that presents items of variable heights arranged in a grid.
@available(iOS 14, OSX 10.15, tvOS 13, visionOS 1, watchOS 6, *)
public struct WaterfallGrid<Data, ID, Content>: View where Data : RandomAccessCollection, Content : View, ID : Hashable {

    @Environment(\.gridStyle) private var style
    @Environment(\.scrollOptions) private var scrollOptions

    private let data: Data
    private let dataId: KeyPath<Data.Element, ID>
    private let content: (Data.Element) -> Content

    @State private var loaded = false
    @State private var gridHeight: CGFloat = 0
    // 添加一个状态来暂存最新的 preferences
    @State private var latestPreferences = [ElementPreferenceData]()

    @State private var alignmentGuides = [AnyHashable: CGPoint]() {
        didSet { loaded = !oldValue.isEmpty }
    }
    
    public var body: some View {
        VStack {
            GeometryReader { geometry in
                self.grid(in: geometry)
                    // 当 Preference 变化时，仅更新 latestPreferences
                    .onPreferenceChange(ElementPreferenceKey.self) { preferences in
                        self.latestPreferences = preferences
                    }
                    // 当 latestPreferences 更新后，再触发异步计算
                    .onChange(of: latestPreferences) { newPreferences in
                        DispatchQueue.global(qos: .userInteractive).async {
                            let (alignmentGuides, gridHeight) = self.alignmentsAndGridHeight(columns: self.style.columns,
                                                                                             spacing: self.style.spacing,
                                                                                             scrollDirection: self.scrollOptions.direction,
                                                                                             preferences: newPreferences) // 使用新的 preferences
                            DispatchQueue.main.async {
                                // 检查计算结果是否与当前状态不同，避免不必要的更新
                                if self.alignmentGuides != alignmentGuides || self.gridHeight != gridHeight {
                                    self.alignmentGuides = alignmentGuides
                                    self.gridHeight = gridHeight
                                }
                            }
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
            // 让动画依赖于 alignmentGuides 的变化，而不是每次都用 UUID()
            .animation(self.loaded ? self.style.animation : nil, value: alignmentGuides)
    }

    // MARK: - Helpers

    func alignmentsAndGridHeight(columns: Int, spacing: CGFloat, scrollDirection: Axis.Set, preferences: [ElementPreferenceData]) -> ([AnyHashable: CGPoint], CGFloat) {
        // 增加对列数为 0 或负数的检查
        guard columns > 0 else {
            return ([:], 0)
        }
        
        var heights = Array(repeating: CGFloat(0), count: columns)
        var alignmentGuides = [AnyHashable: CGPoint]()

        // 对 preferences 排序，确保处理顺序一致性（可选，但有时有帮助）
        let sortedPreferences = preferences.sorted { $0.id.hashValue < $1.id.hashValue }

        sortedPreferences.forEach { preference in
            if let minValue = heights.min(), let indexMin = heights.firstIndex(of: minValue) {
                let preferenceSizeWidth = scrollDirection == .vertical ? preference.size.width : preference.size.height
                let preferenceSizeHeight = scrollDirection == .vertical ? preference.size.height : preference.size.width
                
                // 确保宽度计算基于有效的 columnWidth，这里假设 preference.size.width 已经是正确的列宽
                // 如果不是，需要重新获取 columnWidth
                // let currentColumnWidth = self.columnWidth(...) // 可能需要传递 geometry.size
                
                // 检查 preferenceSizeWidth 是否有效，避免除零或无效计算
                guard preferenceSizeWidth > 0 else { return }

                let xOffset: CGFloat
                let yOffset: CGFloat

                if scrollDirection == .vertical {
                    xOffset = CGFloat(indexMin) * (preferenceSizeWidth + spacing) // 使用实际宽度 + spacing
                    yOffset = heights[indexMin]
                    heights[indexMin] += preferenceSizeHeight + spacing
                } else {
                    xOffset = heights[indexMin]
                    yOffset = CGFloat(indexMin) * (preferenceSizeHeight + spacing) // 水平滚动时，高度是固定的列宽
                    heights[indexMin] += preferenceSizeWidth + spacing
                }
                
                // alignmentGuide 的计算逻辑似乎是计算负偏移量，保持原样
                let guideOffset = CGPoint(x: 0 - (scrollDirection == .vertical ? xOffset : yOffset),
                                          y: 0 - (scrollDirection == .vertical ? yOffset : xOffset))

                alignmentGuides[preference.id] = guideOffset
            }
        }
        
        let gridHeight = max(0, (heights.max() ?? 0) - spacing) // 如果 heights 为空，max 返回 nil，用 0 处理
        
        return (alignmentGuides, gridHeight)
    }

    func columnWidth(columns: Int, spacing: CGFloat, scrollDirection: Axis.Set, geometrySize: CGSize) -> CGFloat {
        // 增加对列数为 0 或负数的检查
        guard columns > 0 else { return 0 }
        let geometrySizeWidth = scrollDirection == .vertical ? geometrySize.width : geometrySize.height
        let totalSpacing = spacing * CGFloat(max(0, columns - 1)) // 确保 spacing 计算正确
        let availableWidth = max(0, geometrySizeWidth - totalSpacing)
        return availableWidth / CGFloat(columns)
    }
}

// MARK: - Initializers

@available(iOS 14, *)
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

@available(iOS 14, *)
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
