import Foundation

/// Vector 3D inmutable en el marco de referencia del dispositivo.
public struct Vector3: Equatable, Sendable {
    public let x: Float
    public let y: Float
    public let z: Float

    public init(_ x: Float, _ y: Float, _ z: Float) {
        self.x = x
        self.y = y
        self.z = z
    }

    public static let zero = Vector3(0, 0, 0)

    public func magnitude() -> Float {
        (x * x + y * y + z * z).squareRoot()
    }

    public func dot(_ other: Vector3) -> Float {
        x * other.x + y * other.y + z * other.z
    }

    /// Vector unitario. Devuelve `zero` en vez de NaN si la magnitud es 0.
    public func normalized() -> Vector3 {
        let m = magnitude()
        guard m >= 1e-6 else { return .zero }
        return Vector3(x / m, y / m, z / m)
    }

    public static func + (lhs: Vector3, rhs: Vector3) -> Vector3 {
        Vector3(lhs.x + rhs.x, lhs.y + rhs.y, lhs.z + rhs.z)
    }

    public static func - (lhs: Vector3, rhs: Vector3) -> Vector3 {
        Vector3(lhs.x - rhs.x, lhs.y - rhs.y, lhs.z - rhs.z)
    }

    public static func * (lhs: Vector3, rhs: Float) -> Vector3 {
        Vector3(lhs.x * rhs, lhs.y * rhs, lhs.z * rhs)
    }

    public static prefix func - (value: Vector3) -> Vector3 {
        Vector3(-value.x, -value.y, -value.z)
    }
}
