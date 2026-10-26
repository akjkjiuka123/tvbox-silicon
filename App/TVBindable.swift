import SwiftUI
import Perception

/// Back-port of `@Bindable` for perceptible objects that also builds on iOS 17 and later.
///
/// Perception ships its own `Bindable`, but marks it `obsoleted: 17`, so a target whose deployment
/// target is iOS 16 can no longer reference it once it has to run on 17 too. This wrapper only needs
/// dynamic member lookup over a reference-writable key path, which is enough for the `$model.field`
/// bindings the views use.
@dynamicMemberLookup
@propertyWrapper
struct TVBindable<Value> {
    var wrappedValue: Value

    init(wrappedValue: Value) {
        self.wrappedValue = wrappedValue
    }

    init(_ value: Value) {
        self.wrappedValue = value
    }

    var projectedValue: TVBindable<Value> { self }

    subscript<Subject>(dynamicMember keyPath: ReferenceWritableKeyPath<Value, Subject>) -> Binding<Subject> {
        Binding(
            get: { wrappedValue[keyPath: keyPath] },
            set: { wrappedValue[keyPath: keyPath] = $0 }
        )
    }
}
