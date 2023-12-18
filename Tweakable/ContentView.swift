//

import SwiftUI

struct PreferenceValue: Equatable {
    var initialValue: Any
    var label: String
    var edit: (String, Binding<Any>) -> AnyView
    init<T>(initialValue: T, label: String, edit: @escaping (String, Binding<T>) -> AnyView) {
        self.initialValue = initialValue
        self.label = label
        self.edit = { label, binding in
            let b: Binding<T> = Binding(get: { binding.wrappedValue as! T }, set: { binding.wrappedValue = $0 })
            return edit(label, b)
        }
    }

    static func ==(lhs: Self, rhs: Self) -> Bool {
        return true // todo we can't compare closures
    }
}

struct TweakablePreference: PreferenceKey {
    static var defaultValue: [TweakableKey:PreferenceValue] = [:]
    static func reduce(value: inout Value, nextValue: () -> Value) {
        value.merge(nextValue(), uniquingKeysWith: { $1 })
    }
}

struct TweakableValuesKey: EnvironmentKey {
    static var defaultValue: [TweakableKey: Any] = [:]
}

extension EnvironmentValues {
    var tweakables: TweakableValuesKey.Value {
        get { self[TweakableValuesKey.self] }
        set { self[TweakableValuesKey.self] = newValue }
    }
}

protocol TweakableType {
    associatedtype V: View
    static func edit(label: String, binding: Binding<Self>) -> V
}

extension Double: TweakableType {
    static func edit(label: String, binding: Binding<Self>) -> some View {
        Slider(value: binding, in: 0...300) { Text(label) }
    }
}

extension Bool: TweakableType {
    static func edit(label: String, binding: Binding<Self>) -> some View {
        Toggle(label, isOn: binding)
    }
}

extension Color: TweakableType {
    static func edit(label: String, binding: Binding<Self>) -> some View {
        ColorPicker(label, selection: binding)
    }
}

struct TweakableKey: Hashable, Comparable {
    var line: UInt8
    var column: UInt8
    var file: String

    static func <(lhs: Self, rhs: Self) -> Bool {
        if lhs.file < rhs.file { return true }
        if lhs.file > rhs.file { return false }

        if lhs.line < rhs.line { return true }
        if lhs.line > rhs.line { return false }

        if lhs.column < rhs.column { return true }
        if lhs.column > rhs.column { return false }

        return false
    }
}

extension View {
    func tweakable<Value: TweakableType, Output: View>(_ label: String, initialValue: Value, line: UInt8 = #line, column: UInt8 = #column, file: String = #file, @ViewBuilder content: @escaping (AnyView, Value) -> Output) -> some View {
        let key = TweakableKey(line: line, column: column, file: file)
        return modifier(Tweakable(label: label, initialValue: initialValue, edit: Value.edit, key: key, run: content))
    }

    func tweakable<Value, Editor: View, Output: View>(_ label: String, initialValue: Value, line: UInt8 = #line, column: UInt8 = #column, file: String = #file, edit: @escaping (String, Binding<Value>) -> Editor, @ViewBuilder content: @escaping (AnyView, Value) -> Output) -> some View {
        let key = TweakableKey(line: line, column: column, file: file)
        return modifier(Tweakable(label: label, initialValue: initialValue, edit: edit, key: key, run: content))
    }
}

struct Tweakable<Value, Editor: View, Output: View>: ViewModifier {
    var label: String
    var initialValue: Value
    var edit: (String, Binding<Value>) -> Editor
    var key: TweakableKey
    @ViewBuilder var run: (AnyView, Value) -> Output
    @Environment(\.tweakables) var tweakables

    func body(content: Content) -> some View {
        run(AnyView(content), (tweakables[key] as? Value) ?? initialValue)
            .transformPreference(TweakablePreference.self) { value in
                value[key] = .init(initialValue: initialValue, label: label, edit: { AnyView(edit($0, $1)) })
            }
    }
}

struct TweakableGUI: ViewModifier {
    @State private var definitions: [TweakableKey: PreferenceValue] = [:]
    @State private var values: [TweakableKey: Any] = [:]

    func body(content: Content) -> some View {
        content
            .environment(\.tweakables, values)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .safeAreaInset(edge: .bottom) {
                ScrollView {
                    VStack(alignment: .leading) {
                        ForEach(values.keys.sorted(), id: \.self) { key in
                            let b = Binding($values[key])!
                            let def = definitions[key]!
                            VStack(alignment: .leading) {
                                def.edit(def.label, b)
                                let filename = (key.file as NSString).lastPathComponent

                                Text("\(filename):\(key.line)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                .frame(maxHeight: 200)
            }
            .onPreferenceChange(TweakablePreference.self, perform: { value in
                values = value.mapValues { $0.initialValue }
                definitions = value
            })
    }
}

struct TweakableView<Value, Content: View>: View {
    var label: String
    var initialValue: Value
    var edit: (String, Binding<Value>) -> AnyView
    @ViewBuilder var content: (Value) -> Content
    private var key: TweakableKey
    @Environment(\.tweakables) private var tweakables

    init<Editor: View>(_ label: String, initialValue: Value, file: String = #file, line: UInt8 = #line, column: UInt8 = #column, edit: @escaping (String, Binding<Value>) -> Editor, @ViewBuilder content: @escaping (Value) -> Content) {
        self.label = label
        self.initialValue = initialValue
        self.edit = { AnyView(edit($0, $1)) }
        self.content = content
        self.key = .init(line: line, column: column, file: file)
    }


    var body: some View {
        content((tweakables[key] as? Value) ?? initialValue)
            .transformPreference(TweakablePreference.self) { value in
                value[key] = .init(initialValue: initialValue, label: label, edit: { AnyView(edit($0, $1)) })
            }
    }
}

extension TweakableView where Value: TweakableType {
    init(_ label: String, initialValue: Value, file: String = #file, line: UInt8 = #line, column: UInt8 = #column, @ViewBuilder content: @escaping (Value) -> Content) {
        self.init(label, initialValue: initialValue, edit: { Value.edit(label: $0, binding: $1) }, content: content)
    }
}

struct ContentView: View {
    var body: some View {
        TweakableView("Content", initialValue: true) { value in
            if value {
                Text("Hello, world!")
            } else {
                Image(systemName: "globe")
            }
        }
            .tweakable("alignment", initialValue: Alignment.center, edit: { title, binding in
                HStack {
                    Button("Leading") { binding.wrappedValue = .leading }
                    Button("Center") { binding.wrappedValue = .center }
                    Button("Trailing") { binding.wrappedValue = .trailing }
                }
            }) {
                $0.frame(maxWidth: .infinity, alignment: $1)
            }
            .tweakable("padding", initialValue: 10) {
                $0.padding($1)
            }
            .tweakable("offset", initialValue: 10) {
                $0.offset(x: $1)
            }
            .tweakable("foreground color", initialValue: Color.white) {
                $0.foregroundStyle($1)
            }
            .tweakable("padding", initialValue: Color.blue) {
                $0.background($1)
            }
//            .background(Color.blue)
            .modifier(TweakableGUI())
    }
}

#Preview {
    ContentView()
}
