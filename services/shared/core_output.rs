//! The stdout/stderr framing limit applies before a full line is allocated.

pub(crate) const MAX_CORE_LOG_BYTES: usize = 16 * 1024;

pub(crate) struct LogLine {
    bytes: Vec<u8>,
    seen: bool,
    truncated: bool,
}

impl LogLine {
    pub(crate) fn new() -> Self {
        Self {
            bytes: Vec::with_capacity(256),
            seen: false,
            truncated: false,
        }
    }

    /// Consumes at most the first newline. Excess content is drained rather than
    /// retained, so a noisy child can still make progress writing its pipe.
    pub(crate) fn consume(&mut self, available: &[u8]) -> (usize, bool) {
        let newline = available.iter().position(|byte| *byte == b'\n');
        let content = newline.unwrap_or(available.len());
        let retained = content.min(MAX_CORE_LOG_BYTES - self.bytes.len());
        let required = self.bytes.len() + retained;
        if required > self.bytes.capacity() {
            let target = required.next_power_of_two().min(MAX_CORE_LOG_BYTES);
            self.bytes.reserve_exact(target - self.bytes.len());
        }
        self.bytes.extend_from_slice(&available[..retained]);
        self.truncated |= retained != content;
        self.seen |= !available.is_empty();
        (content + usize::from(newline.is_some()), newline.is_some())
    }

    pub(crate) fn finish(mut self) -> Option<String> {
        if !self.seen {
            return None;
        }
        if self.bytes.last() == Some(&b'\r') {
            self.bytes.pop();
        }
        // Decode after framing so valid UTF-8 split across reader chunks is preserved.
        // A truncated codepoint/invalid byte is diagnostic data, not a reason to stop draining.
        let text = String::from_utf8_lossy(&self.bytes);
        Some(if self.truncated {
            format!("[truncated] {text}")
        } else {
            text.into_owned()
        })
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn resource_line_storage_stays_bounded_without_newline() {
        let mut line = LogLine::new();
        let block = [b'x'; 1003];
        for _ in 0..10_000 {
            assert_eq!(line.consume(&block), (block.len(), false));
            assert!(line.bytes.len() <= MAX_CORE_LOG_BYTES);
            assert!(line.bytes.capacity() <= MAX_CORE_LOG_BYTES);
        }
        assert_eq!(line.consume(b"\nnext"), (1, true));
        let output = line.finish().unwrap();
        assert_eq!(output.len(), MAX_CORE_LOG_BYTES + "[truncated] ".len());
    }

    #[test]
    fn resource_line_utf8_crlf_empty_and_eof_are_preserved() {
        let mut line = LogLine::new();
        for chunk in "日志🙂\r\n".as_bytes().chunks(1) {
            line.consume(chunk);
        }
        assert_eq!(line.finish().as_deref(), Some("日志🙂"));
        assert!(LogLine::new().finish().is_none());
        let mut empty = LogLine::new();
        empty.consume(b"\n");
        assert_eq!(empty.finish().as_deref(), Some(""));
        let mut eof = LogLine::new();
        eof.consume(b"last\xff");
        assert_eq!(eof.finish().as_deref(), Some("last\u{fffd}"));
    }
}
