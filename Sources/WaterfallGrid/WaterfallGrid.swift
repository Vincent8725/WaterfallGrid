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
    @State private var latestPreferences = [ElementPreferenceData]() // 新增：存储最新的偏好数据

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
                                                                                             preferences: newPreferences)
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
    
        // 对 preferences 排序，确保处理顺序一致性
        let sortedPreferences = preferences.sorted { $0.id.hashValue < $1.id.hashValue }
    
        sortedPreferences.forEach { preference in
            if let minValue = heights.min(), let indexMin = heights.firstIndex(of: minValue) {
                let preferenceSizeWidth = scrollDirection == .vertical ? preference.size.width : preference.size.height
                let preferenceSizeHeight = scrollDirection == .vertical ? preference.size.height : preference.size.width
                
                // 检查尺寸是否有效
                guard preferenceSizeWidth > 0, preferenceSizeHeight > 0 else { return }
                
                let width = preferenceSizeWidth * CGFloat(indexMin) + CGFloat(indexMin) * spacing
                let height = heights[indexMin]
                let offset = CGPoint(x: 0 - (scrollDirection == .vertical ? width : height),
                                     y: 0 - (scrollDirection == .vertical ? height : width))
                heights[indexMin] += preferenceSizeHeight + spacing
                alignmentGuides[preference.id] = offset
            }
        }
        
        let gridHeight = max(0, (heights.max() ?? 0) - spacing)
        
        return (alignmentGuides, gridHeight)
    }

    func columnWidth(columns: Int, spacing: CGFloat, scrollDirection: Axis.Set, geometrySize: CGSize) -> CGFloat {
        // 增加对列数为 0 或负数的检查
        guard columns > 0 else { return 0 }
        
        let geometrySizeWidth = scrollDirection == .vertical ? geometrySize.width : geometrySize.height
        let totalSpacing = spacing * CGFloat(max(0, columns - 1))
        let availableWidth = max(0, geometrySizeWidth - totalSpacing)
        return availableWidth / CGFloat(columns)
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
