//
//  Math.swift
//  BezierKit
//
//  Created by Goodnotes on 4/24/26.
//

#if canImport(Darwin)
import Darwin

enum BezierMath {
    static func acos(_ x: Double) -> Double {
        Darwin.acos(x)
    }

    static func atan2(_ y: Double, _ x: Double) -> Double {
        Darwin.atan2(y, x)
    }

    static func cos(_ x: Double) -> Double {
        Darwin.cos(x)
    }

    static func pow(_ x: Double, _ y: Double) -> Double {
        Darwin.pow(x, y)
    }

    static func sqrt(_ x: Double) -> Double {
        Darwin.sqrt(x)
    }
}
#elseif canImport(WASILibc)
import WASILibc

enum BezierMath {
    static func acos(_ x: Double) -> Double {
        WASILibc.acos(x)
    }

    static func atan2(_ y: Double, _ x: Double) -> Double {
        WASILibc.atan2(y, x)
    }

    static func cos(_ x: Double) -> Double {
        WASILibc.cos(x)
    }

    static func pow(_ x: Double, _ y: Double) -> Double {
        WASILibc.pow(x, y)
    }

    static func sqrt(_ x: Double) -> Double {
        WASILibc.sqrt(x)
    }
}
#elseif canImport(Android)
import Android

enum BezierMath {
    static func acos(_ x: Double) -> Double {
        Android.acos(x)
    }

    static func atan2(_ y: Double, _ x: Double) -> Double {
        Android.atan2(y, x)
    }

    static func cos(_ x: Double) -> Double {
        Android.cos(x)
    }

    static func pow(_ x: Double, _ y: Double) -> Double {
        Android.pow(x, y)
    }

    static func sqrt(_ x: Double) -> Double {
        Android.sqrt(x)
    }
}
#elseif canImport(Glibc)
import Glibc

enum BezierMath {
    static func acos(_ x: Double) -> Double {
        Glibc.acos(x)
    }

    static func atan2(_ y: Double, _ x: Double) -> Double {
        Glibc.atan2(y, x)
    }

    static func cos(_ x: Double) -> Double {
        Glibc.cos(x)
    }

    static func pow(_ x: Double, _ y: Double) -> Double {
        Glibc.pow(x, y)
    }

    static func sqrt(_ x: Double) -> Double {
        Glibc.sqrt(x)
    }
}
#endif
