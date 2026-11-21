import os

/// Diagnostics: `log stream --predicate 'subsystem == "local.rasklad"' --level debug`.
/// Never logs typed characters, only event kinds, key codes of modifiers and counts.
let log = Logger(subsystem: "local.rasklad", category: "main")
