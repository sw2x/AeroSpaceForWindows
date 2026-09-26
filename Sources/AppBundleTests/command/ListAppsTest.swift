@testable import AppBundle
import Common
import XCTest

final class ListAppsTest: XCTestCase {
    func testParse() {
        assertNotNil(parseCommand("list-apps --macos-native-hidden").errorOrNil)
        assertNotNil(parseCommand("list-apps --macos-native-hidden no").errorOrNil)
        assertNotNil(parseCommand("list-apps --format %{app-id}").cmdOrDie)
        assertNotNil(parseCommand("list-apps --count").cmdOrDie)
        assertEquals(parseCommand("list-apps --format %{app-id} --count").errorOrNil, "ERROR: Conflicting options: --count, --format")
    }
}
