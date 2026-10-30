/// "1 window", "3 windows": `noun` takes an s past one.
public func counted(_ n: Int, _ noun: String) -> String {
    "\(n) \(noun)\(n == 1 ? "" : "s")"
}
