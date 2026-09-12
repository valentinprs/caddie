// swift-tools-version: 6.0
import PackageDescription
let package = Package(name: "CoursesCore", platforms: [.macOS(.v14)], products: [.library(name: "CoursesCore", targets: ["CoursesCore"])], targets: [.target(name: "CoursesCore", path: "Courses/Core"), .testTarget(name: "CoursesCoreTests", dependencies: ["CoursesCore"], path: "Tests/CoursesCoreTests")])
