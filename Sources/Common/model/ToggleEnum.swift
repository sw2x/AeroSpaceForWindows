public enum ToggleEnum: Sendable { case on, off, toggle }
func parseToggleEnum(i: PosArgParserInput) -> ParsedCliArgs<ToggleEnum> {
    switch i.arg {
        case "on": .succ(.on, advanceBy: 1)
        case "off": .succ(.off, advanceBy: 1)
        default: .fail("Can't parse '\(i.arg)'. Possible values: on|off", advanceBy: 1)
    }
}
