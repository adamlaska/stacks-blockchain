use crate::vm::diagnostic::{DiagnosableError, Level};
use crate::vm::representations::Span;

#[derive(Debug, PartialEq, Clone)]
pub enum LexerError {
    InvalidCharInt(char),
    InvalidCharUint(char),
    InvalidCharBuffer(char),
    InvalidCharIdent(char),
    InvalidCharTraitIdent(char),
    InvalidCharPrincipal(char),
    InvalidBufferLength(usize),
    UnknownEscapeChar(char),
    IllegalCharString(char),
    IllegalCharUTF8Encoding(char),
    UnterminatedUTF8Encoding,
    ExpectedClosing(char),
    ExpectedSeparator,
    EmptyUTF8Encoding,
    InvalidUTF8Encoding,
    SingleSemiColon,
    UnknownSymbol(char),
    NonASCIIChar(char),
    NoteToMatchThis(char),
    UnsupportedLineEnding,
    EditorCRLFMode,
}

#[derive(Debug)]
pub struct PlacedError {
    pub e: LexerError,
    pub span: Span,
}

impl DiagnosableError for LexerError {
    fn message(&self) -> String {
        use self::LexerError::*;
        match self {
            InvalidCharInt(c) => format!("invalid character, '{c}', in int literal"),
            InvalidCharUint(c) => format!("invalid character, '{c}', in uint literal"),
            InvalidCharBuffer(c) => format!("invalid character, '{c}', in buffer"),
            InvalidCharIdent(c) => format!("invalid character, '{c}', in identifier"),
            InvalidCharTraitIdent(c) => format!("invalid character, '{c}', in trait identifier"),
            InvalidCharPrincipal(c) => format!("invalid character, '{c}', in principal literal"),
            IllegalCharString(c) => format!("invalid character, '{c}', in string literal"),
            IllegalCharUTF8Encoding(c) => format!("invalid character, '{c}', in UTF8 encoding"),
            InvalidUTF8Encoding => "invalid UTF8 encoding".to_string(),
            EmptyUTF8Encoding => "empty UTF8 encoding".to_string(),
            UnterminatedUTF8Encoding => "unterminated UTF8 encoding, missing '}'".to_string(),
            InvalidBufferLength(size) => format!("invalid buffer length, {size}"),
            UnknownEscapeChar(c) => format!("unknown escape character, '{c}'"),
            ExpectedClosing(c) => format!("expected closing '{c}'"),
            ExpectedSeparator => "expected separator".to_string(),
            SingleSemiColon => "unexpected single ';' (comments begin with \";;\"".to_string(),
            UnknownSymbol(c) => format!("unknown symbol, '{c}'"),
            NonASCIIChar(c) => format!("illegal non-ASCII character, '{c}'"),
            NoteToMatchThis(c) => format!("to match this '{c}'"),
            UnsupportedLineEnding => {
                "unsupported line-ending '\\r', only '\\n' is supported".to_string()
            }
            EditorCRLFMode => {
                "you may need to change your editor from CRLF mode to LF mode".to_string()
            }
        }
    }

    fn suggestion(&self) -> Option<String> {
        None
    }

    fn level(&self) -> crate::vm::diagnostic::Level {
        use self::LexerError::*;
        match self {
            NoteToMatchThis(_) => Level::Note,
            EditorCRLFMode => Level::Note,
            _ => Level::Error,
        }
    }
}
